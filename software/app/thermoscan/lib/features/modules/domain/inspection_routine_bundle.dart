import 'dart:math' as math;

import 'package:thermoscan/features/modules/domain/module_models.dart';
import 'package:thermoscan/features/modules/presentation/widgets/thermal_panorama_painter.dart';

/// Per-hotspot before/after cleaning verification comparison summary.
class HotspotVerificationSummary {
  const HotspotVerificationSummary({
    required this.anomaly,
    this.cleaning,
    required this.beforeTempC,
    this.afterTempC,
    this.baselineTempC,
    required this.outcome,
  });

  final ConfirmedAnomaly anomaly;
  final ModuleCleaning? cleaning;
  final double beforeTempC;
  final double? afterTempC;
  final double? baselineTempC;

  /// One of: 'resolved', 'resolved_later', 'unresolved',
  /// 'pending_verification', 'unwashed'.
  final String outcome;

  double? get deltaChangeC =>
      afterTempC != null ? (afterTempC! - beforeTempC) : null;

  bool get isResolved => outcome == 'resolved';
  bool get isResolvedLater => outcome == 'resolved_later';
  bool get isCleared => isResolved || isResolvedLater;
  bool get isUnresolved => outcome == 'unresolved';
  bool get isPendingVerification => outcome == 'pending_verification';
  bool get isUnwashed => outcome == 'unwashed';
}

/// Represents a consolidated routine inspection session along with any
/// post-cleaning verification micro-inspections triggered by its anomalies.
class InspectionRoutineBundle {
  const InspectionRoutineBundle({
    required this.routineInspection,
    required this.verificationInspections,
    required this.routineMeasurements,
    required this.verificationMeasurements,
    required this.restoredMeasurements,
    this.primaryCleaning,
    this.cleanings = const [],
    List<HotspotVerificationSummary>? hotspotSummaries,
    // ignore: prefer_initializing_formals
  }) : _hotspotSummaries = hotspotSummaries;

  /// The root scheduled routine inspection that scanned the module or string.
  final ModuleInspection routineInspection;

  /// Post-cleaning micro-inspections (type == 'verification') attached to this routine,
  /// sorted chronologically descending so the latest verification appears first.
  final List<ModuleInspection> verificationInspections;

  /// Original pre-cleaning measurements recorded during the routine scan.
  final List<ModuleMeasurement> routineMeasurements;

  /// Post-cleaning verification measurements recorded after cleaning actuation.
  final List<ModuleMeasurement> verificationMeasurements;

  /// Spatially fused measurements: routine frames with verified hotspot areas healed.
  final List<ModuleMeasurement> restoredMeasurements;

  /// Latest / primary cleaning operation associated with this routine, if available.
  final ModuleCleaning? primaryCleaning;

  /// All cleaning operations associated with anomalies in this routine.
  final List<ModuleCleaning> cleanings;

  final List<HotspotVerificationSummary>? _hotspotSummaries;

  /// Per-hotspot before/after comparison summaries.
  List<HotspotVerificationSummary> get hotspotSummaries =>
      _hotspotSummaries ??
      computeHotspotSummaries(
        routineInspection: routineInspection,
        cleanings: cleanings,
        verificationInspections: verificationInspections,
        routineMeasurements: routineMeasurements,
        verificationMeasurements: verificationMeasurements,
      );

  int get resolvedCount =>
      hotspotSummaries.where((s) => s.outcome == 'resolved').length;

  int get resolvedLaterCount =>
      hotspotSummaries.where((s) => s.outcome == 'resolved_later').length;

  int get unresolvedCount =>
      hotspotSummaries.where((s) => s.outcome == 'unresolved').length;

  int get pendingCount =>
      hotspotSummaries.where((s) => s.outcome == 'pending_verification').length;

  /// Strict boolean: returns true ONLY when verified post-cleaning measurements exist.
  bool get hasPostCleaning => verificationMeasurements.isNotEmpty;

  /// Aggregate verification outcome: 'resolved', 'unresolved', or null if pending/no verification.
  String? get verificationResult {
    final summaries = hotspotSummaries;
    if (summaries.isNotEmpty) {
      if (summaries.any((s) => s.isUnresolved)) {
        return 'unresolved';
      }
      if (summaries.any((s) => s.isPendingVerification)) {
        return 'pending';
      }
      if (summaries.every((s) => s.isCleared) &&
          summaries.any((s) => s.isResolved)) {
        return 'resolved';
      }
      if (summaries.every((s) => s.isResolvedLater)) {
        return 'unresolved';
      }
    }

    // Fallback when confirmedAnomalies is empty: group by cleaningOperationId
    // so the latest verification per cleaning operation wins.
    if (verificationInspections.isNotEmpty) {
      final latestPerCleaning = <String, String>{};
      final standaloneResults = <String>[];
      for (final v in verificationInspections) {
        final res = v.verificationResult;
        if (res == null || res.isEmpty) continue;
        final cid = v.cleaningOperationId;
        if (cid != null && cid.isNotEmpty) {
          latestPerCleaning.putIfAbsent(cid, () => res);
        } else {
          standaloneResults.add(res);
        }
      }
      final allResults = [...latestPerCleaning.values, ...standaloneResults];
      if (allResults.isNotEmpty) {
        if (allResults.any((r) => r == 'unresolved')) return 'unresolved';
        if (allResults.every((r) => r == 'resolved')) return 'resolved';
        return allResults.first;
      }
    }

    return primaryCleaning?.postCleaningResult;
  }

  /// True if all post-cleaning verifications resolved the hotspot anomalies.
  bool get isHotspotResolved => verificationResult == 'resolved';

  /// Confirmed anomalies identified during the routine scan.
  List<ConfirmedAnomaly> get confirmedAnomalies =>
      routineInspection.confirmedAnomalies;

  /// Baseline temperature of the routine inspection.
  double? get baselineTemperatureC => routineInspection.baselineTemperatureC;

  /// True if this routine has completed or contains valid measurement frames.
  bool get hasData =>
      routineMeasurements.isNotEmpty || routineInspection.status == 'completed';

  /// Builds a [LatestInspection] anchored on [routineInspection] so UI views
  /// never collapse onto a 2-frame verification micro-inspection and preserve
  /// per-panel baselines and confirmed anomalies.
  LatestInspection toEffectiveLatestInspection(LatestInspection? rawLatest) {
    final isSameInspection =
        rawLatest != null && rawLatest.inspection.id == routineInspection.id;
    final effectiveAnomalies = routineInspection.confirmedAnomalies.isNotEmpty
        ? routineInspection.confirmedAnomalies
        : (isSameInspection
            ? rawLatest.confirmedAnomalies
            : const <ConfirmedAnomaly>[]);

    final rawPanels = rawLatest?.panelResults;
    final canUseRawPanels = rawPanels != null &&
        rawPanels.isNotEmpty &&
        (isSameInspection ||
            rawPanels.every(
              (p) =>
                  p.inspectionId.isEmpty ||
                  p.inspectionId == routineInspection.id,
            ));
    final effectivePanelResults = (routineInspection.panelResults != null &&
            routineInspection.panelResults!.isNotEmpty)
        ? routineInspection.panelResults
        : (canUseRawPanels ? rawPanels : null);

    final effectiveTotalMeasurements = isSameInspection
        ? math.max(rawLatest.totalMeasurements, routineMeasurements.length)
        : routineMeasurements.length;

    return LatestInspection(
      inspection: routineInspection.copyWith(
        confirmedAnomalies: effectiveAnomalies,
        panelResults: effectivePanelResults,
      ),
      totalMeasurements: effectiveTotalMeasurements,
      confirmedAnomalies: effectiveAnomalies,
      panelResults: effectivePanelResults,
    );
  }

  /// Returns the latest completed routine bundle, falling back to a bundle with
  /// measurements only if no completed routine exists yet.
  static InspectionRoutineBundle? getLatestActiveBundle(
    List<InspectionRoutineBundle> bundles,
  ) {
    if (bundles.isEmpty) return null;
    for (final b in bundles) {
      if (b.routineInspection.status == 'completed') {
        return b;
      }
    }
    return bundles.firstWhere(
      (b) => b.routineMeasurements.isNotEmpty,
      orElse: () => bundles.first,
    );
  }

  static DateTime? _inspectionTimestamp(ModuleInspection insp) {
    return DateTime.tryParse(insp.finishedAt ?? '') ??
        DateTime.tryParse(insp.startedAt ?? '') ??
        DateTime.tryParse(insp.scheduledFor) ??
        DateTime.tryParse(insp.createdAt);
  }

  static int _compareInspectionsDesc(ModuleInspection a, ModuleInspection b) {
    final dtA = _inspectionTimestamp(a);
    final dtB = _inspectionTimestamp(b);
    if (dtA != null && dtB != null) {
      final cmp = dtB.compareTo(dtA);
      if (cmp != 0) return cmp;
    } else if (dtA != null || dtB != null) {
      return dtB != null ? 1 : -1;
    }
    final createdCmp = b.createdAt.compareTo(a.createdAt);
    if (createdCmp != 0) return createdCmp;
    return b.id.compareTo(a.id);
  }

  static int _compareCleaningsDesc(ModuleCleaning a, ModuleCleaning b) {
    final attA = a.attemptNumber ?? 0;
    final attB = b.attemptNumber ?? 0;
    if (attA != attB) return attB.compareTo(attA);
    final dtA = DateTime.tryParse(a.endedAt ?? '') ??
        DateTime.tryParse(a.startedAt ?? '') ??
        DateTime.tryParse(a.createdAt);
    final dtB = DateTime.tryParse(b.endedAt ?? '') ??
        DateTime.tryParse(b.startedAt ?? '') ??
        DateTime.tryParse(b.createdAt);
    if (dtA != null && dtB != null) {
      final cmp = dtB.compareTo(dtA);
      if (cmp != 0) return cmp;
    }
    return b.createdAt.compareTo(a.createdAt);
  }

  static bool _isSamePanel(int? panelA, int? panelB) {
    if (panelA == null || panelA <= 0 || panelB == null || panelB <= 0) {
      return true;
    }
    return panelA == panelB;
  }

  static List<HotspotVerificationSummary> computeHotspotSummaries({
    required ModuleInspection routineInspection,
    required List<ModuleCleaning> cleanings,
    required List<ModuleInspection> verificationInspections,
    required List<ModuleMeasurement> routineMeasurements,
    required List<ModuleMeasurement> verificationMeasurements,
  }) {
    final anomalies = routineInspection.confirmedAnomalies;
    if (anomalies.isEmpty) return const [];

    final sortedCleanings = List<ModuleCleaning>.from(cleanings)
      ..sort(_compareCleaningsDesc);
    final sortedVerifs = List<ModuleInspection>.from(verificationInspections)
      ..sort(_compareInspectionsDesc);
    final panelBaselines = buildPanelBaselineMap(routineInspection.panelResults);

    final summaries = <HotspotVerificationSummary>[];
    for (final anomaly in anomalies) {
      // 1. Cleanings for this anomaly (newest / highest attempt first)
      final anomalyCleanings = sortedCleanings
          .where((c) => c.anomalyEventId == anomaly.id)
          .toList();
      final latestCleaning =
          anomalyCleanings.isNotEmpty ? anomalyCleanings.first : null;
      final anomalyCleaningIds = anomalyCleanings.map((c) => c.id).toSet();

      // 2. Latest verification inspection for this anomaly's cleanings
      ModuleInspection? matchedVerif;
      for (final v in sortedVerifs) {
        if (v.cleaningOperationId != null &&
            anomalyCleaningIds.contains(v.cleaningOperationId)) {
          matchedVerif = v;
          break;
        }
      }
      if (matchedVerif == null &&
          anomalies.length == 1 &&
          sortedVerifs.isNotEmpty) {
        matchedVerif = sortedVerifs.first;
      }

      // 3. Before temperature from routine frames
      var beforeFrames = routineMeasurements
          .where((m) => isFrameAssociatedWithAnomaly(m, anomaly))
          .toList();
      if (beforeFrames.isEmpty) {
        beforeFrames = routineMeasurements
            .where(
              (m) =>
                  _isSamePanel(m.panelIndex, anomaly.panelIndex) &&
                  (m.xPositionCm - anomaly.xPositionCm).abs() <= 2.5,
            )
            .toList();
      }
      if (beforeFrames.isEmpty) {
        beforeFrames = routineMeasurements
            .where(
              (m) =>
                  _isSamePanel(m.panelIndex, anomaly.panelIndex) &&
                  (m.xPositionCm - anomaly.xPositionCm).abs() <= 5.0,
            )
            .toList();
      }

      final baselineTemp = (anomaly.panelIndex != null &&
              anomaly.panelIndex! > 0
          ? panelBaselines[anomaly.panelIndex!]
          : null) ??
          routineInspection.baselineTemperatureC;

      final beforeTempC = beforeFrames.isNotEmpty
          ? beforeFrames.map((m) => m.maxTemperatureC).reduce(math.max)
          : (baselineTemp ?? 0.0);

      // 4. After temperature from verification frames
      List<ModuleMeasurement> afterFrames = const [];
      if (matchedVerif != null) {
        final verifSpecific = verificationMeasurements
            .where((m) => m.inspectionId == matchedVerif!.id)
            .toList();
        final nearbySpecific = verifSpecific
            .where(
              (m) =>
                  _isSamePanel(m.panelIndex, anomaly.panelIndex) &&
                  (m.xPositionCm - anomaly.xPositionCm).abs() <= 5.0,
            )
            .toList();
        afterFrames =
            nearbySpecific.isNotEmpty ? nearbySpecific : verifSpecific;
      } else if (verificationMeasurements.isNotEmpty) {
        final nearbyAll = verificationMeasurements
            .where(
              (m) =>
                  _isSamePanel(m.panelIndex, anomaly.panelIndex) &&
                  (m.xPositionCm - anomaly.xPositionCm).abs() <= 2.5,
            )
            .toList();
        afterFrames = nearbyAll.isNotEmpty
            ? nearbyAll
            : verificationMeasurements
                .where(
                  (m) =>
                      _isSamePanel(m.panelIndex, anomaly.panelIndex) &&
                      (m.xPositionCm - anomaly.xPositionCm).abs() <= 5.0,
                )
                .toList();
      }

      final double? afterTempC = afterFrames.isNotEmpty
          ? afterFrames.map((m) => m.maxTemperatureC).reduce(math.max)
          : null;

      // 5. Determine outcome
      final String outcome;
      final postRes = latestCleaning?.postCleaningResult ?? '';
      final verifRes = matchedVerif?.verificationResult ?? '';
      if (anomaly.isResolvedLater) {
        outcome = 'resolved_later';
      } else if (anomaly.isResolved ||
          verifRes == 'resolved' ||
          postRes == 'resolved' ||
          postRes == 'verified_resolved') {
        outcome = 'resolved';
      } else if (verifRes == 'unresolved' ||
          postRes == 'unresolved' ||
          postRes == 'verified_unresolved' ||
          anomaly.status == 'unresolved') {
        outcome = 'unresolved';
      } else if (latestCleaning != null) {
        if ((latestCleaning.status == 'refused' ||
                latestCleaning.status == 'failed') &&
            !latestCleaning.pumpActuated) {
          outcome = 'unwashed';
        } else {
          outcome = 'pending_verification';
        }
      } else if (matchedVerif != null) {
        outcome = 'pending_verification';
      } else {
        outcome = 'unwashed';
      }

      summaries.add(
        HotspotVerificationSummary(
          anomaly: anomaly,
          cleaning: latestCleaning,
          beforeTempC: beforeTempC,
          afterTempC: afterTempC,
          baselineTempC: baselineTemp,
          outcome: outcome,
        ),
      );
    }

    return summaries;
  }

  /// Resolves bundles for all scheduled routine inspections from raw lists.
  static List<InspectionRoutineBundle> buildBundles({
    required List<ModuleInspection> allInspections,
    required List<ModuleCleaning> allCleanings,
    required List<ModuleMeasurement> allMeasurements,
    LatestInspection? latestInspection,
  }) {
    // 1. Merge latest inspection metadata (anomalies + panel_results) into pool
    final inspectionPool = <String, ModuleInspection>{};
    for (final insp in allInspections) {
      inspectionPool[insp.id] = insp;
    }
    if (latestInspection != null && latestInspection.inspection.id.isNotEmpty) {
      final existing = inspectionPool[latestInspection.inspection.id];
      final base = existing ?? latestInspection.inspection;
      final mergedAnomalies = base.confirmedAnomalies.isNotEmpty
          ? base.confirmedAnomalies
          : latestInspection.confirmedAnomalies;
      final mergedPanels =
          (base.panelResults != null && base.panelResults!.isNotEmpty)
              ? base.panelResults
              : latestInspection.panelResults;
      inspectionPool[latestInspection.inspection.id] = base.copyWith(
        confirmedAnomalies: mergedAnomalies,
        panelResults: mergedPanels,
      );
    }

    // Synthesize any inspection referenced by measurements if missing from pool
    for (final m in allMeasurements) {
      if (m.inspectionId.isNotEmpty &&
          !inspectionPool.containsKey(m.inspectionId)) {
        inspectionPool[m.inspectionId] = ModuleInspection(
          id: m.inspectionId,
          moduleId: m.moduleId,
          sourceEventId: m.sourceEventId,
          type: 'scheduled',
          scheduledFor: m.measuredAt,
          status: 'completed',
          createdAt: m.measuredAt,
          updatedAt: m.measuredAt,
        );
      }
    }

    // 2. Separate into scheduled routines and verification micro-inspections
    final rawScheduledRoutines = <ModuleInspection>[];
    final verifications = <ModuleInspection>[];

    for (final insp in inspectionPool.values) {
      final isVerif = insp.type == 'verification' ||
          insp.type == 'post_cleaning' ||
          insp.type == 'post_cleaning_verification' ||
          insp.cleaningOperationId != null;
      if (isVerif) {
        verifications.add(insp);
      } else {
        rawScheduledRoutines.add(insp);
      }
    }

    // Measurements grouped by inspectionId
    final measurementsByInsp = <String, List<ModuleMeasurement>>{};
    for (final m in allMeasurements) {
      if (m.inspectionId.isNotEmpty) {
        measurementsByInsp.putIfAbsent(m.inspectionId, () => []).add(m);
      }
    }

    // Drop cluttering empty 'scheduled' placeholders (0 measurements)
    final scheduledRoutines = rawScheduledRoutines.where((insp) {
      if (insp.status == 'scheduled' &&
          (measurementsByInsp[insp.id]?.isEmpty ?? true)) {
        return false;
      }
      return true;
    }).toList();

    // Sort scheduled routines descending by timestamp
    scheduledRoutines.sort(_compareInspectionsDesc);

    // Cleanings indexed by id and grouped by anomalyEventId (sorted newest first)
    final cleaningsById = {for (var c in allCleanings) c.id: c};
    final cleaningsByAnomaly = <String, List<ModuleCleaning>>{};
    for (final c in allCleanings) {
      cleaningsByAnomaly.putIfAbsent(c.anomalyEventId, () => []).add(c);
    }
    for (final list in cleaningsByAnomaly.values) {
      list.sort(_compareCleaningsDesc);
    }

    final bundles = <InspectionRoutineBundle>[];
    final matchedVerifIds = <String>{};

    for (var i = 0; i < scheduledRoutines.length; i++) {
      final routine = scheduledRoutines[i];
      final routineMeas = List<ModuleMeasurement>.from(
        measurementsByInsp[routine.id] ?? const <ModuleMeasurement>[],
      );

      // Find anomalies belonging to this routine
      final anomalyIds = routine.confirmedAnomalies.map((a) => a.id).toSet();

      // Find all matching cleanings for this routine's anomalies
      final matchingCleanings = <ModuleCleaning>[];
      for (final aId in anomalyIds) {
        final list = cleaningsByAnomaly[aId];
        if (list != null) {
          for (final cln in list) {
            if (!matchingCleanings.contains(cln)) {
              matchingCleanings.add(cln);
            }
          }
        }
      }
      final matchingCleanIds = matchingCleanings.map((c) => c.id).toSet();

      // 1. Match verification inspections by cleaningOperationId
      final matchedVerifications = verifications.where((v) {
        if (matchedVerifIds.contains(v.id)) return false;
        if (v.cleaningOperationId != null &&
            matchingCleanIds.contains(v.cleaningOperationId)) {
          return true;
        }
        return false;
      }).toList();

      // 2. Chronological window match:
      // Verification occurred during or after this routine, before the next routine (if any)
      final routineDt = _inspectionTimestamp(routine);
      final nextRoutineDt = (i > 0)
          ? (DateTime.tryParse(scheduledRoutines[i - 1].startedAt ?? '') ??
              DateTime.tryParse(scheduledRoutines[i - 1].scheduledFor) ??
              DateTime.tryParse(scheduledRoutines[i - 1].createdAt))
          : null;

      for (final v in verifications) {
        if (matchedVerifIds.contains(v.id) || matchedVerifications.contains(v)) {
          continue;
        }
        final vDt = _inspectionTimestamp(v);
        if (routineDt != null && vDt != null) {
          final routineBoundary = routineDt.subtract(const Duration(minutes: 10));
          if (!vDt.isBefore(routineBoundary)) {
            if (nextRoutineDt == null || vDt.isBefore(nextRoutineDt)) {
              matchedVerifications.add(v);
            }
          }
        }
      }

      // Sort matchedVerifications chronologically descending so latest verification wins
      matchedVerifications.sort(_compareInspectionsDesc);

      // Mark these verifications as matched and gather their cleaning operations
      for (final v in matchedVerifications) {
        matchedVerifIds.add(v.id);
        if (v.cleaningOperationId != null) {
          final cln = cleaningsById[v.cleaningOperationId!];
          if (cln != null && !matchingCleanings.contains(cln)) {
            matchingCleanings.add(cln);
          }
        }
      }
      matchingCleanings.sort(_compareCleaningsDesc);

      // Gather verification measurements
      final verifMeas = <ModuleMeasurement>[];
      for (final v in matchedVerifications) {
        final list = measurementsByInsp[v.id];
        if (list != null) {
          verifMeas.addAll(list);
        }
      }

      // Sort measurements spatially and fuse using 2.5 cm optical half-FOV window
      final sortedRoutineMeas = sortMeasurementsSpatially(routineMeas);
      final sortedVerifMeas = sortMeasurementsSpatially(verifMeas);
      final restored = sortedVerifMeas.isNotEmpty
          ? fuseRoutineWithVerificationMeasurements(
              routineMeasurements: sortedRoutineMeas,
              verificationMeasurements: sortedVerifMeas,
            )
          : sortedRoutineMeas;

      final summaries = computeHotspotSummaries(
        routineInspection: routine,
        cleanings: matchingCleanings,
        verificationInspections: matchedVerifications,
        routineMeasurements: sortedRoutineMeas,
        verificationMeasurements: sortedVerifMeas,
      );

      bundles.add(
        InspectionRoutineBundle(
          routineInspection: routine,
          verificationInspections: matchedVerifications,
          routineMeasurements: sortedRoutineMeas,
          verificationMeasurements: sortedVerifMeas,
          restoredMeasurements: restored,
          primaryCleaning:
              matchingCleanings.isNotEmpty ? matchingCleanings.first : null,
          cleanings: matchingCleanings,
          hotspotSummaries: summaries,
        ),
      );
    }

    // Edge case: verifications not matched to any routine (e.g. stand-alone cleaning verification sessions).
    // Skip empty scheduled placeholders and group remaining verifications within 30 minutes.
    final orphanVerifications = verifications
        .where(
          (v) =>
              !matchedVerifIds.contains(v.id) &&
              !(v.status == 'scheduled' &&
                  (measurementsByInsp[v.id]?.isEmpty ?? true)),
        )
        .toList()
      ..sort(_compareInspectionsDesc);

    final orphanSessionGroups = <List<ModuleInspection>>[];
    for (final orphan in orphanVerifications) {
      final oDt = _inspectionTimestamp(orphan);

      bool placed = false;
      for (final grp in orphanSessionGroups) {
        final grpDt = _inspectionTimestamp(grp.first);
        if (oDt != null &&
            grpDt != null &&
            (oDt.difference(grpDt).abs().inMinutes <= 30)) {
          grp.add(orphan);
          placed = true;
          break;
        }
      }
      if (!placed) {
        orphanSessionGroups.add([orphan]);
      }
    }

    for (final sessionVerifs in orphanSessionGroups) {
      sessionVerifs.sort(_compareInspectionsDesc);
      final rootInsp = sessionVerifs.first;
      final sessionMeas = <ModuleMeasurement>[];
      for (final v in sessionVerifs) {
        sessionMeas.addAll(measurementsByInsp[v.id] ?? const []);
      }
      final sortedMeas = sortMeasurementsSpatially(sessionMeas);
      final sessionCleanings = <ModuleCleaning>[];
      for (final v in sessionVerifs) {
        if (v.cleaningOperationId != null) {
          final cln = cleaningsById[v.cleaningOperationId!];
          if (cln != null && !sessionCleanings.contains(cln)) {
            sessionCleanings.add(cln);
          }
        }
      }
      sessionCleanings.sort(_compareCleaningsDesc);

      bundles.add(
        InspectionRoutineBundle(
          routineInspection: rootInsp,
          verificationInspections: sessionVerifs,
          routineMeasurements: sortedMeas,
          verificationMeasurements: sortedMeas,
          restoredMeasurements: sortedMeas,
          primaryCleaning:
              sessionCleanings.isNotEmpty ? sessionCleanings.first : null,
          cleanings: sessionCleanings,
        ),
      );
    }

    return bundles;
  }
}
