import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/core/utils/date_formatter.dart';
import 'package:thermoscan/features/modules/data/module_repository.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';
import 'package:thermoscan/features/modules/presentation/modules_controller.dart';
import 'package:thermoscan/features/modules/presentation/widgets/electrical_series_chart.dart';
import 'package:thermoscan/features/modules/presentation/widgets/export_electrical_pdf_sheet.dart';

class ElectricalHistoryView extends ConsumerStatefulWidget {
  const ElectricalHistoryView({
    super.key,
    required this.moduleId,
    required this.module,
    this.refreshToken = 0,
  });

  final String moduleId;
  final PvModule? module;
  final int refreshToken;

  @override
  ConsumerState<ElectricalHistoryView> createState() =>
      _ElectricalHistoryViewState();
}

class _ElectricalHistoryViewState extends ConsumerState<ElectricalHistoryView> {
  static const _ranges = [
    ('1h', '1H'),
    ('24h', '24H'),
    ('7d', '7D'),
    ('30d', '30D'),
    ('all', 'All'),
  ];

  String _selectedRange = '24h';
  int? _selectedPanel;
  ElectricalChartMetric _selectedMetric = ElectricalChartMetric.power;

  // Paginated reading log state
  final List<PowerReadingItem> _logItems = <PowerReadingItem>[];
  int _logPage = 1;
  int _logTotalCount = 0;
  bool _logHasNext = false;
  bool _isLoadingLog = false;
  int _logRequestSeq = 0;
  String? _logError;
  Timer? _liveRefreshTimer;
  ({double? voltageV, double? currentA, double? powerW, bool hasData})?
      _lastValidLiveAgg;
  String? _lastValidPowerAt;

  @override
  void initState() {
    super.initState();
    unawaited(_fetchLogPage(reset: true));
    _liveRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      ref.invalidate(moduleDeviceStatusProvider(widget.moduleId));
      if (_selectedRange == '1h' || _selectedRange == '24h') {
        ref.invalidate(
          powerReadingsSeriesProvider((
            moduleId: widget.moduleId,
            range: _selectedRange,
            panelIndex: _selectedPanel,
          )),
        );
        if (_logPage == 1 && !_isLoadingLog) {
          unawaited(_fetchLogPage(reset: true, silent: true));
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant ElectricalHistoryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      unawaited(_fetchLogPage(reset: true));
    }
  }

  @override
  void dispose() {
    _liveRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchLogPage({required bool reset, bool silent = false}) async {
    if (!reset && _isLoadingLog) return;
    final seq = ++_logRequestSeq;
    final nextPage = reset ? 1 : _logPage + 1;
    if (!silent) {
      setState(() {
        _isLoadingLog = true;
        _logError = null;
        if (reset) {
          _logItems.clear();
          _logPage = 1;
          _logHasNext = false;
        }
      });
    }
    try {
      final res = await ref.read(moduleRepositoryProvider).listPowerReadings(
            moduleId: widget.moduleId,
            range: _selectedRange,
            panelIndex: _selectedPanel,
            page: nextPage,
            limit: 20,
          );
      if (!mounted || seq != _logRequestSeq) return;
      setState(() {
        if (reset) {
          _logItems
            ..clear()
            ..addAll(res.items);
        } else {
          _logItems.addAll(res.items);
        }
        _logPage = res.page;
        _logTotalCount = res.totalCount;
        _logHasNext = res.hasNextPage;
      });
    } catch (err) {
      if (!mounted || seq != _logRequestSeq) return;
      if (!silent) {
        setState(() => _logError = '$err');
      }
    } finally {
      if (mounted && seq == _logRequestSeq && !silent) {
        setState(() => _isLoadingLog = false);
      }
    }
  }

  void _onRangeChanged(String newRange) {
    if (_selectedRange == newRange) return;
    setState(() => _selectedRange = newRange);
    unawaited(_fetchLogPage(reset: true));
  }

  void _onPanelChanged(int? newPanel) {
    if (_selectedPanel == newPanel) return;
    setState(() => _selectedPanel = newPanel);
    unawaited(_fetchLogPage(reset: true));
  }

  String _formatRelativeTime(String? iso) {
    if (iso == null || iso.isEmpty) return 'No live readings yet';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return 'Updated recently';
    final diff = DateTime.now().toUtc().difference(dt.toUtc());
    if (diff.inSeconds < 5) return 'Updated just now';
    if (diff.inSeconds < 60) return 'Updated ${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return 'Updated ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Updated ${diff.inHours}h ago';
    return 'Updated ${AppDateFormatter.formatDateTimeShort(iso)}';
  }

  ({double? voltageV, double? currentA, double? powerW, bool hasData})
      _aggregateLive(List<LivePowerReading> readings) {
    final filtered = _selectedPanel == null
        ? readings
        : readings.where((r) => r.panelIndex == _selectedPanel).toList();
    if (filtered.isEmpty) {
      return (voltageV: null, currentA: null, powerW: null, hasData: false);
    }
    if (filtered.length == 1) {
      final r = filtered.first;
      return (
        voltageV: r.voltageV,
        currentA: r.currentA,
        powerW: r.powerW,
        hasData: r.hasAnyValue,
      );
    }

    double sumV = 0;
    int cntV = 0;
    double sumA = 0;
    int cntA = 0;
    double sumW = 0;
    int cntW = 0;
    for (final r in filtered) {
      if (r.voltageV != null) {
        sumV += r.voltageV!;
        cntV++;
      }
      if (r.currentA != null) {
        sumA += r.currentA!;
        cntA++;
      }
      if (r.powerW != null) {
        sumW += r.powerW!;
        cntW++;
      }
    }
    return (
      voltageV: cntV > 0 ? sumV / cntV : null,
      currentA: cntA > 0 ? sumA : null,
      powerW: cntW > 0 ? sumW : null,
      hasData: cntV > 0 || cntA > 0 || cntW > 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final deviceStatusAsync =
        ref.watch(moduleDeviceStatusProvider(widget.moduleId));
    final deviceStatus = deviceStatusAsync.valueOrNull;
    final seriesAsync = ref.watch(
      powerReadingsSeriesProvider((
        moduleId: widget.moduleId,
        range: _selectedRange,
        panelIndex: _selectedPanel,
      )),
    );

    final panelCount = widget.module?.panelCount ?? 1;
    final liveReadings = deviceStatus?.latestPowerReadings ?? const [];
    final liveAgg = _aggregateLive(liveReadings);
    if (liveAgg.hasData) {
      _lastValidLiveAgg = liveAgg;
      _lastValidPowerAt = deviceStatus?.latestPowerAt;
    }
    final displayLiveAgg =
        liveAgg.hasData ? liveAgg : (_lastValidLiveAgg ?? liveAgg);
    final displayPowerAt = liveAgg.hasData
        ? deviceStatus?.latestPowerAt
        : (_lastValidPowerAt ?? deviceStatus?.latestPowerAt);
    final isOnline = deviceStatus?.isOnline ?? false;
    final isLive = isOnline && displayLiveAgg.hasData;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Live Electrical Monitor Card
        _buildLiveMonitorCard(
          isLive: isLive,
          isOnline: isOnline,
          latestPowerAt: displayPowerAt,
          liveAgg: displayLiveAgg,
          panelCount: panelCount,
        ),
        const SizedBox(height: 14),

        // 2. Power History Chart Card
        _buildChartCard(seriesAsync),
        const SizedBox(height: 14),

        // 3. Period Summary KPIs
        if (seriesAsync.valueOrNull != null) ...[
          _buildSummaryStrip(seriesAsync.valueOrNull!.summary),
          const SizedBox(height: 14),
        ],

        // 4. Paginated Reading Log
        _buildReadingLogCard(showPanelColumn: _selectedPanel == null && panelCount > 1),
      ],
    );
  }

  Widget _buildLiveMonitorCard({
    required bool isLive,
    required bool isOnline,
    required String? latestPowerAt,
    required ({
      double? voltageV,
      double? currentA,
      double? powerW,
      bool hasData
    }) liveAgg,
    required int panelCount,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Live Electrical Monitor',
                          style: AppTypography.h3.copyWith(fontSize: 15),
                        ),
                        _buildStatusPill(isLive: isLive, isOnline: isOnline),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatRelativeTime(latestPowerAt),
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.module != null)
                TextButton.icon(
                  onPressed: () => showExportElectricalPdfSheet(
                    context: context,
                    module: widget.module!,
                    initialRange: _selectedRange,
                    initialPanelIndex: _selectedPanel,
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: AppColors.border),
                    ),
                  ),
                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                  label: Text(
                    'Export PDF',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildLiveMetricColumn(
                    label: 'Power',
                    value: formatElectricalPower(liveAgg.powerW),
                    valueColor: AppColors.primary,
                  ),
                ),
                Container(width: 1, height: 32, color: AppColors.border),
                Expanded(
                  child: _buildLiveMetricColumn(
                    label: 'Voltage',
                    value: formatElectricalVoltage(liveAgg.voltageV),
                    valueColor: AppColors.textPrimary,
                  ),
                ),
                Container(width: 1, height: 32, color: AppColors.border),
                Expanded(
                  child: _buildLiveMetricColumn(
                    label: 'Current',
                    value: formatElectricalCurrent(liveAgg.currentA),
                    valueColor: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          if (panelCount > 1) ...[
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterPill(
                    label: 'All Panels',
                    selected: _selectedPanel == null,
                    onTap: () => _onPanelChanged(null),
                  ),
                  for (var p = 1; p <= panelCount; p++) ...[
                    const SizedBox(width: 6),
                    _buildFilterPill(
                      label: 'Panel $p',
                      selected: _selectedPanel == p,
                      onTap: () => _onPanelChanged(p),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusPill({required bool isLive, required bool isOnline}) {
    final label = isLive ? 'LIVE' : (isOnline ? 'NO DATA' : 'OFFLINE');
    final bgColor = isLive
        ? AppColors.successBackground
        : (isOnline ? AppColors.warningBackground : AppColors.background);
    final borderColor = isLive
        ? AppColors.successBorder
        : (isOnline ? AppColors.warningBorder : AppColors.border);
    final fgColor = isLive
        ? AppColors.success
        : (isOnline ? AppColors.warning : AppColors.textSecondary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: fgColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppTypography.caption.copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: fgColor,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveMetricColumn({
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: AppTypography.caption.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTypography.h3.copyWith(
            fontSize: 16,
            color: value == 'N/A' ? AppColors.textSecondary : valueColor,
          ),
        ),
      ],
    );
  }

  Widget _buildFilterPill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.caption.copyWith(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildChartCard(AsyncValue<PowerReadingsSeries> seriesAsync) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Text(
                'Electrical History',
                style: AppTypography.h3.copyWith(fontSize: 15),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildMetricMiniTab(
                    label: 'Power',
                    metric: ElectricalChartMetric.power,
                  ),
                  const SizedBox(width: 4),
                  _buildMetricMiniTab(
                    label: 'Voltage',
                    metric: ElectricalChartMetric.voltage,
                  ),
                  const SizedBox(width: 4),
                  _buildMetricMiniTab(
                    label: 'Current',
                    metric: ElectricalChartMetric.current,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: _ranges.map((r) {
              final selected = _selectedRange == r.$1;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: InkWell(
                    onTap: () => _onRangeChanged(r.$1),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primary
                            : AppColors.background,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected
                              ? AppColors.primary
                              : AppColors.border,
                        ),
                      ),
                      child: Text(
                        r.$2,
                        style: AppTypography.caption.copyWith(
                          color: selected
                              ? Colors.white
                              : AppColors.textSecondary,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          seriesAsync.when(
            loading: () => const SizedBox(
              height: 200,
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            ),
            error: (err, _) => Container(
              height: 120,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.errorBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.errorBorder),
              ),
              child: Text(
                'Failed to load electrical history: $err',
                style: AppTypography.caption.copyWith(color: AppColors.error),
                textAlign: TextAlign.center,
              ),
            ),
            data: (series) => ElectricalSeriesChart(
              points: series.points,
              metric: _selectedMetric,
              range: _selectedRange,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricMiniTab({
    required String label,
    required ElectricalChartMetric metric,
  }) {
    final selected = _selectedMetric == metric;
    return InkWell(
      onTap: () => setState(() => _selectedMetric = metric),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: AppTypography.caption.copyWith(
            fontSize: 11,
            color: selected ? AppColors.primary : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryStrip(PowerSeriesSummary summary) {
    return Row(
      children: [
        Expanded(
          child: _buildKpiTile(
            label: 'Peak Power',
            value: formatElectricalPower(summary.peakPowerW),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildKpiTile(
            label: 'Average Power',
            value: formatElectricalPower(summary.avgPowerW),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildKpiTile(
            label: 'Samples',
            value: summary.totalReadings.toString(),
          ),
        ),
      ],
    );
  }

  Widget _buildKpiTile({required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTypography.h3.copyWith(
              fontSize: 15,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadingLogCard({required bool showPanelColumn}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Reading Log',
                style: AppTypography.h3.copyWith(fontSize: 15),
              ),
              Text(
                '$_logTotalCount total',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_logError != null)
            Text(
              'Failed to load log: $_logError',
              style: AppTypography.caption.copyWith(color: AppColors.error),
            )
          else if (_logItems.isEmpty && _isLoadingLog)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (_logItems.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'No readings recorded in this period.',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            )
          else ...[
            for (var i = 0; i < _logItems.length; i++) ...[
              if (i > 0)
                const Divider(height: 12, thickness: 1, color: AppColors.border),
              _buildLogRow(_logItems[i], showPanelColumn: showPanelColumn),
            ],
            if (_logHasNext) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed:
                      _isLoadingLog ? null : () => _fetchLogPage(reset: false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    _isLoadingLog ? 'Loading...' : 'Load more readings',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildLogRow(PowerReadingItem item, {required bool showPanelColumn}) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppDateFormatter.formatDateTimeShort(item.measuredAt),
                style: AppTypography.caption.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (showPanelColumn)
                Text(
                  'Panel ${item.panelIndex}',
                  style: AppTypography.caption.copyWith(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            formatElectricalVoltage(item.voltageV),
            textAlign: TextAlign.right,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            formatElectricalCurrent(item.currentA),
            textAlign: TextAlign.right,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            formatElectricalPower(item.powerW),
            textAlign: TextAlign.right,
            style: AppTypography.caption.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
