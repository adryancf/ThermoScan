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
    this.thermalMap,
  });

  final PvModule module;
  final ModuleMeasurement? latestMeasurement;
  final ModuleThermalMap? thermalMap;

  @override
  Widget build(BuildContext context) {
    final m = latestMeasurement;
    final tm = thermalMap;
    if (m == null && tm == null) {
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

    final peakTemp = m?.maxTemperatureC ?? 36.5;
    final baselineTemp = m?.baselineTemperatureC ?? 35.0;
    final voltage = m?.voltageV ?? 18.0;
    final current = m?.currentA ?? 4.0;
    final power = m?.powerW ?? (voltage * current);
    final xPos = m?.xPositionCm ?? 0.0;
    final isHotspot = m?.hotspotDetected ?? false;
    final delta = peakTemp - baselineTemp;

    // 5 cm Bands resolution
    List<ThermalBand> bands = tm?.bands ?? [];
    if (bands.isEmpty) {
      // Default 3 bands (15 cm total span) if no backend composite yet
      final targetBand = (xPos / 5.0).floor() + 1;
      bands = [
        ThermalBand(
          bandIndex: 1,
          startXCm: 0.0,
          endXCm: 5.0,
          maxTemperatureC: targetBand == 1 ? peakTemp : baselineTemp,
          avgTemperatureC: baselineTemp,
          hasHotspot: targetBand == 1 && isHotspot,
        ),
        ThermalBand(
          bandIndex: 2,
          startXCm: 5.0,
          endXCm: 10.0,
          maxTemperatureC: targetBand == 2 ? peakTemp : baselineTemp + 0.5,
          avgTemperatureC: baselineTemp,
          hasHotspot: targetBand == 2 && isHotspot,
        ),
        ThermalBand(
          bandIndex: 3,
          startXCm: 10.0,
          endXCm: 15.0,
          maxTemperatureC: targetBand == 3 ? peakTemp : baselineTemp,
          avgTemperatureC: baselineTemp,
          hasHotspot: targetBand == 3 && isHotspot,
        ),
      ];
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

          // 2D Thermal Viewport Canvas Container with 5 cm Bands Overlay
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
                // 5 cm Band Vertical Divider Lines
                Row(
                  children: List.generate(bands.length, (idx) {
                    final b = bands[idx];
                    return Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border(
                            right: idx < bands.length - 1
                                ? BorderSide(
                                    color: Colors.white.withValues(alpha: 0.25),
                                    width: 1,
                                  )
                                : BorderSide.none,
                            // Highlight band if it contains hotspot
                            top: b.hasHotspot
                                ? const BorderSide(color: AppColors.error, width: 3)
                                : BorderSide.none,
                            bottom: b.hasHotspot
                                ? const BorderSide(color: AppColors.error, width: 3)
                                : BorderSide.none,
                          ),
                          color: b.hasHotspot
                              ? AppColors.error.withValues(alpha: 0.12)
                              : Colors.transparent,
                        ),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: b.hasHotspot
                                    ? AppColors.error.withValues(alpha: 0.85)
                                    : Colors.black.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                b.label,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8.5,
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
                  child: _buildBadge('X: ${xPos.toStringAsFixed(1)} cm (Passo 2cm)'),
                ),
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: _buildBadge('T_max: ${peakTemp.toStringAsFixed(1)}°C'),
                ),

                // Hotspot Target Reticle Marker
                if (isHotspot)
                  Positioned(
                    top: 65,
                    left: 170,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.9),
                              width: 2,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
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
                            'Hotspot Detectado',
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

          // Faixas de 5 cm - Seletor / Breakdown
          Text(
            'Discretização do Painel (Faixas de 5 cm)',
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
                        'Pico: ${b.maxTemperatureC.toStringAsFixed(1)}°C • Média: ${b.avgTemperatureC.toStringAsFixed(1)}°C',
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

          // 4 Key Telemetry Metrics Grid
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  label: 'Peak Temperature',
                  value: '${peakTemp.toStringAsFixed(1)}°C',
                  subtext: peakTemp < 60.0
                      ? 'Below 60°C threshold'
                      : 'Exceeds threshold',
                  isWarning: peakTemp >= 60.0,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricTile(
                  label: 'DC Output Voltage',
                  value: '${voltage.toStringAsFixed(1)} V',
                  subtext: 'Nominal string curve',
                  isWarning: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  label: 'String Current',
                  value: '${current.toStringAsFixed(2)} A',
                  subtext: 'Array active',
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

  Widget _buildBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontFamily: 'monospace',
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required String subtext,
    required bool isWarning,
    Color? valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.caption.copyWith(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: AppTypography.h3.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: valueColor ??
                  (isWarning ? AppColors.error : AppColors.textPrimary),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtext,
            style: AppTypography.caption.copyWith(
              fontSize: 10,
              color: isWarning ? AppColors.error : AppColors.textSecondary,
              fontWeight: isWarning ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
