import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/core/utils/date_formatter.dart';
import 'package:thermoscan/features/auth/presentation/auth_controller.dart';
import 'package:thermoscan/features/modules/data/module_repository.dart';
import 'package:thermoscan/features/modules/domain/inspection_routine_bundle.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';
import 'package:thermoscan/features/modules/presentation/modules_controller.dart';
import 'package:thermoscan/features/modules/presentation/services/thermal_pdf_report_service.dart';
import 'package:thermoscan/features/modules/presentation/widgets/thermal_panorama_painter.dart';

/// Opens SCR-15: Export Telemetry PDF Dialog & Multi-Inspection Selector.
Future<void> showExportPdfReportSheet({
  required BuildContext context,
  required PvModule module,
  String? preselectedInspectionId,
  int? focusedPanelIndex,
  bool defaultPostCleaningView = true,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) => ExportPdfReportSheet(
      module: module,
      preselectedInspectionId: preselectedInspectionId,
      focusedPanelIndex: focusedPanelIndex,
      defaultPostCleaningView: defaultPostCleaningView,
    ),
  );
}

/// SCR-15: Export Telemetry PDF Dialog & Preview with single or multi-inspection
/// selection and automatic historical frame loading.
class ExportPdfReportSheet extends ConsumerStatefulWidget {
  const ExportPdfReportSheet({
    super.key,
    required this.module,
    this.preselectedInspectionId,
    this.focusedPanelIndex,
    this.defaultPostCleaningView = true,
  });

  final PvModule module;
  final String? preselectedInspectionId;
  final int? focusedPanelIndex;
  final bool defaultPostCleaningView;

  @override
  ConsumerState<ExportPdfReportSheet> createState() =>
      _ExportPdfReportSheetState();
}

class _ExportPdfReportSheetState extends ConsumerState<ExportPdfReportSheet> {
  final Set<String> _selectedIds = <String>{};
  bool _initializedSelection = false;
  bool _isGenerating = false;
  String? _statusMessage;
  String? _errorMessage;

  List<InspectionRoutineBundle> _resolveBundles({
    required List<ModuleInspection> inspections,
    required List<ModuleCleaning> cleanings,
    required List<ModuleMeasurement> measurements,
    required LatestInspection? latestInspection,
  }) {
    final raw = InspectionRoutineBundle.buildBundles(
      allInspections: inspections,
      allCleanings: cleanings,
      allMeasurements: measurements,
      latestInspection: latestInspection,
    );
    return raw.where((b) {
      if (b.routineInspection.status == 'scheduled' &&
          b.routineMeasurements.isEmpty &&
          b.verificationMeasurements.isEmpty) {
        return false;
      }
      return true;
    }).toList();
  }

  void _ensureInitialSelection(List<InspectionRoutineBundle> bundles) {
    if (_initializedSelection || bundles.isEmpty) return;
    _initializedSelection = true;

    final targetId = widget.preselectedInspectionId;
    if (targetId != null &&
        bundles.any((b) => b.routineInspection.id == targetId)) {
      _selectedIds.add(targetId);
    } else {
      final latest = InspectionRoutineBundle.getLatestActiveBundle(bundles);
      if (latest != null) {
        _selectedIds.add(latest.routineInspection.id);
      } else {
        _selectedIds.add(bundles.first.routineInspection.id);
      }
    }
  }

  Future<List<ModuleMeasurement>> _fetchAllFramesForInspection(
    ModuleRepository repo,
    String inspectionId,
  ) async {
    final collected = <ModuleMeasurement>[];
    var page = 1;
    var hasNext = true;
    while (hasNext && page <= 15) {
      final res = await repo.listInspectionMeasurements(
        moduleId: widget.module.id,
        inspectionId: inspectionId,
        page: page,
        limit: 50,
      );
      collected.addAll(res.measurements);
      hasNext = res.hasNextPage && res.measurements.isNotEmpty;
      page++;
    }
    return collected;
  }

  Future<void> _generateAndShare(List<InspectionRoutineBundle> bundles) async {
    final selectedBundles = bundles
        .where((b) => _selectedIds.contains(b.routineInspection.id))
        .toList();
    if (selectedBundles.isEmpty) return;

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
      _statusMessage = 'Preparing inspection data...';
    });

    try {
      final repo = ref.read(moduleRepositoryProvider);
      final user = ref.read(authControllerProvider).user;
      final entries = <PdfInspectionEntry>[];

      for (var i = 0; i < selectedBundles.length; i++) {
        final bundle = selectedBundles[i];
        final inspId = bundle.routineInspection.id;

        var routineMeas = bundle.routineMeasurements;
        final hasValidMatrices =
            routineMeas.any(ThermalPanoramaData.hasValidThermalMatrix);
        if ((!hasValidMatrices || routineMeas.length < 4) &&
            inspId.isNotEmpty) {
          if (mounted) {
            setState(() {
              _statusMessage =
                  'Loading thermal frames (${i + 1}/${selectedBundles.length})...';
            });
          }
          try {
            final fetched = await _fetchAllFramesForInspection(repo, inspId);
            if (fetched.isNotEmpty) {
              routineMeas = fetched;
            }
          } catch (_) {
            // Keep existing list if backend page fetch fails
          }
        }

        var verifMeas = bundle.verificationMeasurements;
        if (verifMeas.isEmpty && bundle.verificationInspections.isNotEmpty) {
          final fetchedVerif = <ModuleMeasurement>[];
          for (final v in bundle.verificationInspections) {
            try {
              fetchedVerif.addAll(await _fetchAllFramesForInspection(repo, v.id));
            } catch (_) {
              // Ignore individual verification fetch failure
            }
          }
          if (fetchedVerif.isNotEmpty) {
            verifMeas = fetchedVerif;
          }
        }

        final sortedRoutine = sortMeasurementsSpatially(routineMeas);
        final sortedVerif = sortMeasurementsSpatially(verifMeas);
        final restored = sortedVerif.isNotEmpty
            ? fuseRoutineWithVerificationMeasurements(
                routineMeasurements: sortedRoutine,
                verificationMeasurements: sortedVerif,
              )
            : sortedRoutine;

        entries.add(
          PdfInspectionEntry(
            bundle: bundle,
            routineMeasurements: sortedRoutine,
            verificationMeasurements: sortedVerif,
            restoredMeasurements: restored,
            usePostCleaningView: widget.defaultPostCleaningView,
            focusedPanelIndex:
                selectedBundles.length == 1 ? widget.focusedPanelIndex : null,
          ),
        );
      }

      if (mounted) {
        setState(() {
          _statusMessage = 'Rendering thermal maps & building PDF...';
        });
      }

      await ThermalPdfReportService.shareOrSavePdf(
        module: widget.module,
        entries: entries,
        generatedByName: user?.name,
        generatedByRole: user?.role,
      );

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _statusMessage = null;
          _errorMessage = 'Failed to generate PDF report: $e';
        });
      }
    }
  }

  ({String label, Color bg, Color fg}) _resolveBundleBadge(
    InspectionRoutineBundle bundle,
  ) {
    final summaries = bundle.hotspotSummaries;
    if (summaries.isNotEmpty) {
      final total = summaries.length;
      final cleared = bundle.resolvedCount + bundle.resolvedLaterCount;
      if (bundle.resolvedLaterCount > 0 &&
          bundle.unresolvedCount == 0 &&
          bundle.resolvedCount == 0 &&
          bundle.pendingCount == 0) {
        return (
          label: 'Cleared Later',
          bg: AppColors.primarySoft,
          fg: AppColors.primary,
        );
      }
      if (cleared == total && total > 0) {
        return (
          label: '$total/$total Resolved',
          bg: AppColors.successBackground,
          fg: AppColors.success,
        );
      }
      if (bundle.unresolvedCount > 0) {
        return (
          label: '${bundle.unresolvedCount} Unresolved',
          bg: AppColors.errorBackground,
          fg: AppColors.error,
        );
      }
      return (
        label: '$total Hotspot${total > 1 ? 's' : ''}',
        bg: AppColors.warningBackground,
        fg: AppColors.warning,
      );
    }

    if (bundle.confirmedAnomalies.isNotEmpty) {
      final n = bundle.confirmedAnomalies.length;
      return (
        label: '$n Hotspot${n > 1 ? 's' : ''}',
        bg: AppColors.errorBackground,
        fg: AppColors.error,
      );
    }

    final status = bundle.routineInspection.status.toUpperCase();
    if (status == 'CANCELLED') {
      return (
        label: 'Aborted',
        bg: AppColors.warningBackground,
        fg: AppColors.warning,
      );
    }
    if (status == 'FAILED') {
      return (
        label: 'Failed',
        bg: AppColors.errorBackground,
        fg: AppColors.error,
      );
    }
    return (
      label: 'Healthy',
      bg: AppColors.successBackground,
      fg: AppColors.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final inspectionsAsync =
        ref.watch(moduleInspectionsProvider(widget.module.id));
    final cleaningsAsync = ref.watch(moduleCleaningsProvider(widget.module.id));
    final measurementsAsync =
        ref.watch(moduleMeasurementsProvider(widget.module.id));
    final latestAsync = ref.watch(latestInspectionProvider(widget.module.id));

    final isLoading = inspectionsAsync.isLoading &&
        latestAsync.isLoading &&
        measurementsAsync.isLoading;

    final bundles = _resolveBundles(
      inspections: inspectionsAsync.valueOrNull ?? const [],
      cleanings: cleaningsAsync.valueOrNull ?? const [],
      measurements: measurementsAsync.valueOrNull ?? const [],
      latestInspection: latestAsync.valueOrNull,
    );
    _ensureInitialSelection(bundles);

    final hotspotBundles = bundles
        .where(
          (b) =>
              b.confirmedAnomalies.isNotEmpty ||
              b.hotspotSummaries.isNotEmpty ||
              b.hasPostCleaning,
        )
        .toList();

    final selectedCount =
        bundles.where((b) => _selectedIds.contains(b.routineInspection.id)).length;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.86,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          child: Column(
            key: const Key('export_pdf_report_sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.picture_as_pdf_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Export Telemetry PDF',
                          style: AppTypography.h3.copyWith(fontSize: 16),
                        ),
                        Text(
                          widget.module.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: AppColors.textSecondary,
                    tooltip: 'Close',
                    onPressed:
                        _isGenerating ? null : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Report Preview Summary Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.description_outlined,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selectedCount > 1
                                ? 'Consolidated Report ($selectedCount Inspections)'
                                : selectedCount == 1
                                    ? 'Single Inspection Technical Report'
                                    : 'Select at least 1 inspection',
                            style: AppTypography.bodySmall.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            selectedCount > 1
                                ? 'Includes executive summary + full thermal map, per-panel V/A/W & hotspot breakdown for each selected scan.'
                                : 'Includes asset specs, high-res thermal panorama, per-panel telemetry (V/A/W) & hotspot verification.',
                            style: AppTypography.caption.copyWith(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Quick Selection Presets
              if (bundles.isNotEmpty) ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _QuickSelectChip(
                        key: const Key('pdf_preset_latest'),
                        label: 'Latest',
                        onTap: _isGenerating
                            ? null
                            : () {
                                final latest =
                                    InspectionRoutineBundle.getLatestActiveBundle(
                                  bundles,
                                );
                                setState(() {
                                  _selectedIds.clear();
                                  if (latest != null) {
                                    _selectedIds.add(latest.routineInspection.id);
                                  }
                                });
                              },
                      ),
                      const SizedBox(width: 8),
                      if (hotspotBundles.isNotEmpty) ...[
                        _QuickSelectChip(
                          key: const Key('pdf_preset_hotspots'),
                          label: 'With Hotspots (${hotspotBundles.length})',
                          onTap: _isGenerating
                              ? null
                              : () {
                                  setState(() {
                                    _selectedIds
                                      ..clear()
                                      ..addAll(
                                        hotspotBundles
                                            .map((b) => b.routineInspection.id),
                                      );
                                  });
                                },
                        ),
                        const SizedBox(width: 8),
                      ],
                      _QuickSelectChip(
                        key: const Key('pdf_preset_all'),
                        label: 'Select All (${bundles.length})',
                        onTap: _isGenerating
                            ? null
                            : () {
                                setState(() {
                                  _selectedIds
                                    ..clear()
                                    ..addAll(
                                      bundles.map((b) => b.routineInspection.id),
                                    );
                                });
                              },
                      ),
                      if (_selectedIds.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        _QuickSelectChip(
                          key: const Key('pdf_preset_clear'),
                          label: 'Clear',
                          onTap: _isGenerating
                              ? null
                              : () => setState(_selectedIds.clear),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],

              // Inspection Multi-Select List
              if (isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                )
              else if (bundles.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    'No completed inspections available to export yet.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: bundles.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final b = bundles[index];
                      final insp = b.routineInspection;
                      final isSelected = _selectedIds.contains(insp.id);
                      final dateIso = insp.finishedAt ??
                          insp.startedAt ??
                          (insp.scheduledFor.isNotEmpty
                              ? insp.scheduledFor
                              : insp.createdAt);
                      final dateLabel = AppDateFormatter.formatDateTime(
                        DateTime.tryParse(dateIso),
                        includeYear: true,
                        fallback: dateIso,
                      );
                      final badge = _resolveBundleBadge(b);
                      final baseStr = insp.baselineTemperatureC != null
                          ? 'Base ${insp.baselineTemperatureC!.toStringAsFixed(1)}°C'
                          : null;
                      final frameStr = b.routineMeasurements.isNotEmpty
                          ? '${b.routineMeasurements.length} frames'
                          : 'History scan';

                      return Material(
                        color: isSelected
                            ? AppColors.primarySoft.withValues(alpha: 0.45)
                            : AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          key: Key('pdf_inspection_item_${insp.id}'),
                          borderRadius: BorderRadius.circular(12),
                          onTap: _isGenerating
                              ? null
                              : () {
                                  setState(() {
                                    if (isSelected) {
                                      _selectedIds.remove(insp.id);
                                    } else {
                                      _selectedIds.add(insp.id);
                                    }
                                  });
                                },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.border,
                                width: isSelected ? 1.4 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: isSelected,
                                  activeColor: AppColors.primary,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                  onChanged: _isGenerating
                                      ? null
                                      : (val) {
                                          setState(() {
                                            if (val == true) {
                                              _selectedIds.add(insp.id);
                                            } else {
                                              _selectedIds.remove(insp.id);
                                            }
                                          });
                                        },
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        dateLabel,
                                        style: AppTypography.bodySmall.copyWith(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12.5,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        [
                                          frameStr,
                                          ?baseStr,
                                          if (b.cleanings.isNotEmpty)
                                            '${b.cleanings.length} wash${b.cleanings.length > 1 ? 'es' : ''}',
                                        ].join(' · '),
                                        style: AppTypography.caption.copyWith(
                                          fontSize: 10.5,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: badge.bg,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    badge.label,
                                    style: AppTypography.caption.copyWith(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: badge.fg,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

              if (_statusMessage != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _statusMessage!,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              if (_errorMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  _errorMessage!,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],

              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isGenerating
                          ? null
                          : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      key: const Key('export_pdf_confirm_button'),
                      onPressed: (_isGenerating || selectedCount == 0)
                          ? null
                          : () => _generateAndShare(bundles),
                      icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                      label: Text(
                        _isGenerating
                            ? 'Generating...'
                            : (selectedCount > 1
                                ? 'Export PDF ($selectedCount)'
                                : 'Export PDF'),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickSelectChip extends StatelessWidget {
  const _QuickSelectChip({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            label,
            style: AppTypography.caption.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 11,
              color: AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }
}
