import 'package:thermoscan/features/modules/domain/module_models.dart';
import 'package:thermoscan/features/modules/presentation/widgets/thermal_panorama_painter.dart';

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
  });

  /// The root scheduled routine inspection that scanned the module or string.
  final ModuleInspection routineInspection;

  /// Post-cleaning micro-inspections (type == 'verification') attached to this routine.
  final List<ModuleInspection> verificationInspections;

  /// Original pre-cleaning measurements recorded during the routine scan.
  final List<ModuleMeasurement> routineMeasurements;

  /// Post-cleaning verification measurements recorded after cleaning actuation.
  final List<ModuleMeasurement> verificationMeasurements;

  /// Spatially fused measurements: routine frames with verified hotspot areas healed.
  final List<ModuleMeasurement> restoredMeasurements;

  /// Primary cleaning operation that triggered the verification, if available.
  final ModuleCleaning? primaryCleaning;

  /// Strict boolean: returns true ONLY when verified post-cleaning measurements exist.
  bool get hasPostCleaning => verificationMeasurements.isNotEmpty;

  /// Verification outcome: 'resolved', 'unresolved', or null if pending/no verification.
  String? get verificationResult {
    for (final v in verificationInspections) {
      if (v.verificationResult != null && v.verificationResult!.isNotEmpty) {
        return v.verificationResult;
      }
    }
    return primaryCleaning?.postCleaningResult;
  }

  /// True if the post-cleaning verification resolved the hotspot anomaly.
  bool get isHotspotResolved => verificationResult == 'resolved';

  /// Confirmed anomalies identified during the routine scan.
  List<ConfirmedAnomaly> get confirmedAnomalies =>
      routineInspection.confirmedAnomalies;

  /// Baseline temperature of the routine inspection.
  double? get baselineTemperatureC => routineInspection.baselineTemperatureC;

  /// True if this routine has completed or contains valid measurement frames.
  bool get hasData =>
      routineMeasurements.isNotEmpty || routineInspection.status == 'completed';

  /// Returns the latest active or completed routine bundle, avoiding empty pending scheduled scans.
  static InspectionRoutineBundle? getLatestActiveBundle(
      List<InspectionRoutineBundle> bundles) {
    if (bundles.isEmpty) return null;
    return bundles.firstWhere(
      (b) =>
          b.routineInspection.status == 'completed' ||
          b.routineMeasurements.isNotEmpty,
      orElse: () => bundles.first,
    );
  }

  /// Resolves bundles for all scheduled routine inspections from raw lists.
  static List<InspectionRoutineBundle> buildBundles({
    required List<ModuleInspection> allInspections,
    required List<ModuleCleaning> allCleanings,
    required List<ModuleMeasurement> allMeasurements,
    LatestInspection? latestInspection,
  }) {
    // 1. Ensure latest inspection model is merged if not present
    final inspectionPool = <String, ModuleInspection>{};
    for (final insp in allInspections) {
      inspectionPool[insp.id] = insp;
    }
    if (latestInspection != null &&
        latestInspection.inspection.id.isNotEmpty &&
        !inspectionPool.containsKey(latestInspection.inspection.id)) {
      inspectionPool[latestInspection.inspection.id] =
          latestInspection.inspection;
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
    final scheduledRoutines = <ModuleInspection>[];
    final verifications = <ModuleInspection>[];

    for (final insp in inspectionPool.values) {
      if (insp.type == 'verification' || insp.cleaningOperationId != null) {
        verifications.add(insp);
      } else {
        scheduledRoutines.add(insp);
      }
    }

    // Sort scheduled routines descending by scheduled_for / created_at
    scheduledRoutines.sort((a, b) {
      final dtA = DateTime.tryParse(a.scheduledFor) ?? DateTime.tryParse(a.createdAt);
      final dtB = DateTime.tryParse(b.scheduledFor) ?? DateTime.tryParse(b.createdAt);
      if (dtA != null && dtB != null) return dtB.compareTo(dtA);
      return b.createdAt.compareTo(a.createdAt);
    });

    // Cleanings indexed by id and by anomalyEventId
    final cleaningsById = {for (var c in allCleanings) c.id: c};
    final cleaningsByAnomaly = {for (var c in allCleanings) c.anomalyEventId: c};

    // Measurements grouped by inspectionId
    final measurementsByInsp = <String, List<ModuleMeasurement>>{};
    for (final m in allMeasurements) {
      if (m.inspectionId.isNotEmpty) {
        measurementsByInsp.putIfAbsent(m.inspectionId, () => []).add(m);
      }
    }

    final bundles = <InspectionRoutineBundle>[];

    for (var i = 0; i < scheduledRoutines.length; i++) {
      final routine = scheduledRoutines[i];
      final routineMeas = List<ModuleMeasurement>.from(
        measurementsByInsp[routine.id] ?? const <ModuleMeasurement>[],
      );

      // Find anomalies belonging to this routine
      final anomalyIds = routine.confirmedAnomalies.map((a) => a.id).toSet();

      // Find matching cleanings
      final matchingCleanings = <ModuleCleaning>[];
      for (final aId in anomalyIds) {
        final cln = cleaningsByAnomaly[aId];
        if (cln != null) matchingCleanings.add(cln);
      }
      final matchingCleanIds = matchingCleanings.map((c) => c.id).toSet();

      // Match verification inspections by cleaningOperationId or anomaly association
      final matchedVerifications = verifications.where((v) {
        if (v.cleaningOperationId != null &&
            matchingCleanIds.contains(v.cleaningOperationId)) {
          return true;
        }
        return false;
      }).toList();

      // Fallback: If verification is not linked through cleanings but occurred
      // immediately after routine before the next scheduled routine:
      if (matchedVerifications.isEmpty && routine.confirmedAnomalies.isNotEmpty) {
        final routineDt = DateTime.tryParse(routine.scheduledFor) ??
            DateTime.tryParse(routine.createdAt);
        final nextRoutineDt = (i > 0)
            ? (DateTime.tryParse(scheduledRoutines[i - 1].scheduledFor) ??
                DateTime.tryParse(scheduledRoutines[i - 1].createdAt))
            : null;

        for (final v in verifications) {
          final vDt = DateTime.tryParse(v.scheduledFor) ??
              DateTime.tryParse(v.createdAt);
          if (routineDt != null && vDt != null && vDt.isAfter(routineDt)) {
            if (nextRoutineDt == null || vDt.isBefore(nextRoutineDt)) {
              if (!matchedVerifications.contains(v)) {
                matchedVerifications.add(v);
              }
            }
          }
        }
      }

      // Gather verification measurements
      final verifMeas = <ModuleMeasurement>[];
      for (final v in matchedVerifications) {
        final list = measurementsByInsp[v.id];
        if (list != null) {
          verifMeas.addAll(list);
        }
      }

      // Sort measurements spatially
      final sortedRoutineMeas = sortMeasurementsSpatially(routineMeas);
      final sortedVerifMeas = sortMeasurementsSpatially(verifMeas);

      // Restored measurements = spatial fusion
      final restored = sortedVerifMeas.isNotEmpty
          ? deduplicateMeasurementsSpatially([
              ...sortedRoutineMeas,
              ...sortedVerifMeas,
            ])
          : sortedRoutineMeas;

      bundles.add(
        InspectionRoutineBundle(
          routineInspection: routine,
          verificationInspections: matchedVerifications,
          routineMeasurements: sortedRoutineMeas,
          verificationMeasurements: sortedVerifMeas,
          restoredMeasurements: restored,
          primaryCleaning: matchingCleanings.isNotEmpty
              ? matchingCleanings.first
              : null,
        ),
      );
    }

    // Edge case: If there are verifications without any scheduled routine found,
    // synthesize a bundle for them so measurements are never hidden.
    final matchedVerifIds = bundles
        .expand((b) => b.verificationInspections.map((v) => v.id))
        .toSet();
    final orphanVerifications =
        verifications.where((v) => !matchedVerifIds.contains(v.id)).toList();

    for (final orphan in orphanVerifications) {
      final meas = List<ModuleMeasurement>.from(
        measurementsByInsp[orphan.id] ?? const <ModuleMeasurement>[],
      );
      bundles.add(
        InspectionRoutineBundle(
          routineInspection: orphan,
          verificationInspections: [orphan],
          routineMeasurements: meas,
          verificationMeasurements: meas,
          restoredMeasurements: meas,
          primaryCleaning: orphan.cleaningOperationId != null
              ? cleaningsById[orphan.cleaningOperationId!]
              : null,
        ),
      );
    }

    return bundles;
  }
}
