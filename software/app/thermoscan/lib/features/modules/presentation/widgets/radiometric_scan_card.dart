import 'package:flutter/material.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';

/// SCR-10: 2D Interpolated Thermal Matrix Canvas & Radiometric Telemetry Metrics
class RadiometricScanCard extends StatelessWidget {
  const RadiometricScanCard({
    super.key,
    required this.module,
    this.latestMeasurement,
    this.latestInspection,
    this.thermalMap,
  });

  final PvModule module;
  final ModuleMeasurement? latestMeasurement;
  final LatestInspection? latestInspection;
  final ModuleThermalMap? thermalMap;

  @override
  Widget build(BuildContext context) {
    final m = latestMeasurement;
    final insp = latestInspection;
    final tm = thermalMap;

    if (m == null && insp == null && tm == null) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.grid_view_rounded,
                color: AppColors.primary,
                size: 28,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Awaiting Radiometric Telemetry',
              style: AppTypography.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'No thermal frames or electrical readings recorded yet by the ESP32. Real telemetry and 2D radiometric heatmap will appear here upon the first hardware inspection scan.',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final peakTemp = m?.maxTemperatureC ?? 0.0;
    final baselineTemp = insp?.inspection.baselineTemperatureC ?? m?.baselineTemperatureC ?? 0.0;
    final voltage = m?.voltageV ?? 0.0;
    final current = m?.currentA ?? 0.0;
    final power = m?.powerW ?? (voltage * current);
    final xPos = m?.xPositionCm ?? 0.0;
    final isHotspot = (insp?.confirmedAnomalies.isNotEmpty == true) || (m?.hotspotDetected ?? false);
    final delta = (peakTemp > 0 && baselineTemp > 0) ? (peakTemp - baselineTemp) : 0.0;

    // Calculate 5 cm bands strictly based on module length (e.g. 10cm -> 2 bands, 20cm -> 4 bands)
    final panelLength = (module.panelLengthCm != null && module.panelLengthCm! > 0)
        ? module.panelLengthCm!
        : 20.0;
    final totalExpectedBands = (panelLength / 5.0).ceil().clamp(1, 40);

    List<ThermalBand> bands = [];
    for (int i = 0; i < totalExpectedBands; i++) {
      final startX = i * 5.0;
      final endX = ((i + 1) * 5.0 > panelLength) ? panelLength : (i + 1) * 5.0;
      final hasMeasurementInBand = (m != null && xPos >= startX && xPos <= endX);
      final hasAnomalyInBand = insp?.confirmedAnomalies.any(
            (a) => a.xPositionCm >= startX && a.xPositionCm <= endX,
          ) ?? false;
      final bandHasHotspot = hasAnomalyInBand || (hasMeasurementInBand && isHotspot);
      final bandMaxTemp = hasMeasurementInBand ? peakTemp : 0.0;
      final bandAvgTemp = hasMeasurementInBand ? baselineTemp : 0.0;

      bands.add(
        ThermalBand(
          bandIndex: i + 1,
          startXCm: startX,
          endXCm: endX,
          maxTemperatureC: bandMaxTemp,
          avgTemperatureC: bandAvgTemp,
          hasHotspot: bandHasHotspot,
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(
                      Icons.grid_view_rounded,
                      color: AppColors.secondary,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '32×24 Sensor Interpolation',
                        style: AppTypography.caption.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isHotspot
                      ? AppColors.errorBackground
                      : AppColors.successBackground,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isHotspot
                        ? AppColors.errorBorder
                        : AppColors.successBorder,
                  ),
                ),
                child: Text(
                  isHotspot
                      ? 'Delta: +${delta.toStringAsFixed(1)}°C (Hotspot)'
                      : 'Delta: ${delta.toStringAsFixed(1)}°C (Normal)',
                  style: AppTypography.caption.copyWith(
                    color: isHotspot ? AppColors.error : AppColors.success,
                    fontWeight: FontWeight.w800,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 2D Thermal Viewport Canvas with Prominent 5 cm Bands Overlay
          Container(
            height: 190,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
              gradient: RadialGradient(
                center: const Alignment(0.3, -0.2),
                radius: 0.85,
                colors: isHotspot
                    ? const [
                        AppColors.thermalHot,
                        AppColors.thermalWarm,
                        AppColors.thermalMid,
                        AppColors.thermalCool,
                        AppColors.thermalCold,
                      ]
                    : const [
                        Color(0xFFFF8A1F),
                        Color(0xFFFFD43B),
                        Color(0xFF19B5D6),
                        Color(0xFF1E4FD8),
                        Color(0xFF0F1B2D),
                      ],
                stops: const [0.0, 0.28, 0.50, 0.75, 1.0],
              ),
            ),
            child: Stack(
              children: [
                // Prominent 5 cm Band Vertical Divider Lines
                Row(
                  children: List.generate(bands.length, (idx) {
                    final b = bands[idx];
                    return Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border(
                            right: idx < bands.length - 1
                                ? BorderSide(
                                    color: Colors.white.withValues(alpha: 0.45),
                                    width: 1.5,
                                  )
                                : BorderSide.none,
                            top: b.hasHotspot
                                ? const BorderSide(color: AppColors.error, width: 3)
                                : BorderSide.none,
                            bottom: b.hasHotspot
                                ? const BorderSide(color: AppColors.error, width: 3)
                                : BorderSide.none,
                          ),
                          color: b.hasHotspot
                              ? AppColors.error.withValues(alpha: 0.18)
                              : Colors.transparent,
                        ),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: b.hasHotspot
                                    ? AppColors.error.withValues(alpha: 0.85)
                                    : Colors.black.withValues(alpha: 0.60),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                b.label,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9.0,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),

                // Live Metadata Badges
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: _buildBadge('X: ${xPos.toStringAsFixed(1)} cm (Step 2cm)'),
                ),
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: _buildBadge(
                    'T_max: ${peakTemp.toStringAsFixed(1)}°C',
                    highlight: isHotspot,
                  ),
                ),

                // Hotspot Target Pin
                if (isHotspot)
                  Positioned(
                    top: 50,
                    right: 60,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.error,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: const [
                              BoxShadow(
                                color: AppColors.error,
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Container(
                              width: 4,
                              height: 4,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Hotspot Detected',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 9,
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Calibrated Thermal Scale Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              height: 10,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: AppColors.thermalSpectrum,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '30.0°C (Ambient)',
                style: AppTypography.caption.copyWith(fontSize: 10),
              ),
              Text(
                '45.0°C',
                style: AppTypography.caption.copyWith(fontSize: 10),
              ),
              Text(
                '≥60.0°C (Threshold)',
                style: AppTypography.caption.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 5 cm Thermal Sectors Breakdown
          Text(
            'Thermal Zones (5 cm Sectors)',
            style: AppTypography.caption.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: bands.map((b) {
                return Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: b.hasHotspot
                        ? AppColors.errorBackground
                        : AppColors.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: b.hasHotspot
                          ? AppColors.error
                          : AppColors.border,
                      width: b.hasHotspot ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            b.hasHotspot
                                ? Icons.warning_amber_rounded
                                : Icons.check_circle_outline_rounded,
                            size: 14,
                            color: b.hasHotspot
                                ? AppColors.error
                                : AppColors.success,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            b.label,
                            style: AppTypography.caption.copyWith(
                              fontWeight: FontWeight.w700,
                              color: b.hasHotspot
                                  ? AppColors.error
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        (b.maxTemperatureC <= 0.0 && b.avgTemperatureC <= 0.0)
                            ? 'No readings in sector'
                            : 'Peak: ${b.maxTemperatureC.toStringAsFixed(1)}°C • Avg: ${b.avgTemperatureC.toStringAsFixed(1)}°C',
                        style: AppTypography.caption.copyWith(
                          fontSize: 9.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),

          // 4 Key Telemetry Metrics Grid with Baseline Temperature
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  label: 'Peak Temperature',
                  value: '${peakTemp.toStringAsFixed(1)}°C',
                  subtext: isHotspot
                      ? 'Delta: +${delta.toStringAsFixed(1)}°C'
                      : (peakTemp < 60.0 ? 'Normal curve' : 'Exceeds 60°C'),
                  isWarning: isHotspot || peakTemp >= 60.0,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricTile(
                  label: 'Baseline Temperature',
                  value: baselineTemp > 0 ? '${baselineTemp.toStringAsFixed(1)}°C' : 'N/A',
                  subtext: 'Inspection median reference',
                  isWarning: false,
                  valueColor: AppColors.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  label: 'DC Voltage & Current',
                  value: '${voltage.toStringAsFixed(1)} V · ${current.toStringAsFixed(2)} A',
                  subtext: 'Array electrical output',
                  isWarning: false,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricTile(
                  label: 'Active Power',
                  value: '${power.toStringAsFixed(1)} W',
                  subtext: 'Calculated (V × I)',
                  isWarning: false,
                  valueColor: AppColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String text, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.error.withValues(alpha: 0.85)
            : Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required String subtext,
    bool isWarning = false,
    Color? valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isWarning ? AppColors.errorBackground : AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isWarning ? AppColors.errorBorder : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: isWarning ? AppColors.error : AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTypography.h3.copyWith(
              color: isWarning
                  ? AppColors.error
                  : (valueColor ?? AppColors.textPrimary),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtext,
            style: AppTypography.caption.copyWith(
              color: isWarning ? AppColors.error : AppColors.textSecondary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
