import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/core/widgets/app_buttons.dart';
import 'package:thermoscan/features/auth/presentation/auth_controller.dart';
import 'package:thermoscan/features/modules/data/module_repository.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';
import 'package:thermoscan/features/modules/presentation/services/electrical_pdf_report_service.dart';

Future<void> showExportElectricalPdfSheet({
  required BuildContext context,
  required PvModule module,
  String initialRange = '24h',
  int? initialPanelIndex,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => ExportElectricalPdfSheet(
      module: module,
      initialRange: initialRange,
      initialPanelIndex: initialPanelIndex,
    ),
  );
}

class ExportElectricalPdfSheet extends ConsumerStatefulWidget {
  const ExportElectricalPdfSheet({
    super.key,
    required this.module,
    this.initialRange = '24h',
    this.initialPanelIndex,
  });

  final PvModule module;
  final String initialRange;
  final int? initialPanelIndex;

  @override
  ConsumerState<ExportElectricalPdfSheet> createState() =>
      _ExportElectricalPdfSheetState();
}

class _ExportElectricalPdfSheetState
    extends ConsumerState<ExportElectricalPdfSheet> {
  static const _ranges = [
    ('1h', '1H'),
    ('24h', '24H'),
    ('7d', '7D'),
    ('30d', '30D'),
    ('all', 'All Time'),
  ];

  late String _selectedRange;
  int? _selectedPanel;
  bool _isGenerating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedRange = widget.initialRange;
    _selectedPanel = widget.initialPanelIndex;
  }

  Future<void> _generatePdf() async {
    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });
    try {
      final repo = ref.read(moduleRepositoryProvider);
      final user = ref.read(authControllerProvider).user;

      final series = await repo.getPowerReadingsSeries(
        moduleId: widget.module.id,
        range: _selectedRange,
        panelIndex: _selectedPanel,
      );
      final page = await repo.listPowerReadings(
        moduleId: widget.module.id,
        range: _selectedRange,
        panelIndex: _selectedPanel,
        page: 1,
        limit: 60,
      );

      if (!mounted) return;
      await ElectricalPdfReportService.shareOrPrintReport(
        module: widget.module,
        series: series,
        recentReadings: page.items,
        generatedBy: user?.name,
      );

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (err) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to export electrical report: $err';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final panelCount = widget.module.panelCount ?? 1;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Export Electrical PDF Report', style: AppTypography.h2),
            const SizedBox(height: 4),
            Text(
              'Generate a dedicated electrical telemetry report (voltage, current, and power) separate from thermal scans.',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Time Range',
              style: AppTypography.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _ranges.map((r) {
                final selected = _selectedRange == r.$1;
                return ChoiceChip(
                  label: Text(r.$2),
                  selected: selected,
                  onSelected: _isGenerating
                      ? null
                      : (_) => setState(() => _selectedRange = r.$1),
                  selectedColor: AppColors.primary,
                  backgroundColor: AppColors.background,
                  labelStyle: AppTypography.caption.copyWith(
                    color: selected ? Colors.white : AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  side: BorderSide(
                    color: selected ? AppColors.primary : AppColors.border,
                  ),
                  showCheckmark: false,
                );
              }).toList(),
            ),
            if (panelCount > 1) ...[
              const SizedBox(height: 16),
              Text(
                'Panel Scope',
                style: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('All Panels'),
                    selected: _selectedPanel == null,
                    onSelected: _isGenerating
                        ? null
                        : (_) => setState(() => _selectedPanel = null),
                    selectedColor: AppColors.primary,
                    backgroundColor: AppColors.background,
                    labelStyle: AppTypography.caption.copyWith(
                      color: _selectedPanel == null
                          ? Colors.white
                          : AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    side: BorderSide(
                      color: _selectedPanel == null
                          ? AppColors.primary
                          : AppColors.border,
                    ),
                    showCheckmark: false,
                  ),
                  for (var p = 1; p <= panelCount; p++)
                    ChoiceChip(
                      label: Text('Panel $p'),
                      selected: _selectedPanel == p,
                      onSelected: _isGenerating
                          ? null
                          : (_) => setState(() => _selectedPanel = p),
                      selectedColor: AppColors.primary,
                      backgroundColor: AppColors.background,
                      labelStyle: AppTypography.caption.copyWith(
                        color: _selectedPanel == p
                            ? Colors.white
                            : AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                      side: BorderSide(
                        color: _selectedPanel == p
                            ? AppColors.primary
                            : AppColors.border,
                      ),
                      showCheckmark: false,
                    ),
                ],
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: AppTypography.caption.copyWith(color: AppColors.error),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: _isGenerating ? 'Generating PDF...' : 'Export PDF Report',
                icon: Icons.picture_as_pdf_rounded,
                isLoading: _isGenerating,
                onPressed: _isGenerating ? null : _generatePdf,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
