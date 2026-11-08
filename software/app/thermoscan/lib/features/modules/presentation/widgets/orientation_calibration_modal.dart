import 'dart:async';
import 'package:flutter/material.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/core/widgets/app_buttons.dart';
import 'package:thermoscan/features/modules/data/device_sensor_service.dart';
import 'package:thermoscan/features/modules/presentation/widgets/orientation_compass_widget.dart';

class SurfaceOrientationResult {
  const SurfaceOrientationResult({
    required this.azimuthDeg,
    required this.tiltDeg,
    required this.azimuthSource,
    required this.tiltSource,
  });

  final double azimuthDeg;
  final double tiltDeg;
  final String azimuthSource;
  final String tiltSource;
}

/// Modal bottom sheet for live sensor orientation calibration in SCR-13 (Module Configuration).
class OrientationCalibrationModal extends StatefulWidget {
  const OrientationCalibrationModal({
    super.key,
    this.initialAzimuth,
    this.initialTilt,
  });

  final double? initialAzimuth;
  final double? initialTilt;

  static Future<SurfaceOrientationResult?> show(
    BuildContext context, {
    double? initialAzimuth,
    double? initialTilt,
  }) {
    return showModalBottomSheet<SurfaceOrientationResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => OrientationCalibrationModal(
        initialAzimuth: initialAzimuth,
        initialTilt: initialTilt,
      ),
    );
  }

  @override
  State<OrientationCalibrationModal> createState() =>
      _OrientationCalibrationModalState();
}

class _OrientationCalibrationModalState
    extends State<OrientationCalibrationModal> {
  final _sensorService = const DeviceSensorService();
  StreamSubscription<SurfaceOrientationReading>? _sensorSub;

  SurfaceOrientationReading? _liveReading;
  bool _isCapturing = false;
  bool _isLocked = false;
  double? _lockedAzimuth;
  double? _lockedTilt;

  @override
  void initState() {
    super.initState();
    _sensorSub = _sensorService.watchSurfaceOrientation().listen(
      (reading) {
        if (!mounted) return;
        setState(() => _liveReading = reading);
      },
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    _sensorSub?.cancel();
    super.dispose();
  }

  Future<void> _handleCapture() async {
    setState(() => _isCapturing = true);
    try {
      final sample = await _sensorService.captureSurfaceOrientation();
      if (!mounted) return;
      setState(() {
        _isLocked = true;
        _lockedAzimuth = sample.azimuthDeg;
        _lockedTilt = sample.tiltDeg;
      });
    } catch (_) {
      // Fallback to live reading if snapshot times out
      if (_liveReading != null && mounted) {
        setState(() {
          _isLocked = true;
          _lockedAzimuth = _liveReading!.azimuthDeg;
          _lockedTilt = _liveReading!.tiltDeg;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isCapturing = false);
      }
    }
  }

  void _handleRecapture() {
    setState(() {
      _isLocked = false;
      _lockedAzimuth = null;
      _lockedTilt = null;
    });
  }

  void _applyResult() {
    if (_lockedAzimuth == null || _lockedTilt == null) return;
    Navigator.of(context).pop(
      SurfaceOrientationResult(
        azimuthDeg: _lockedAzimuth!,
        tiltDeg: _lockedTilt!,
        azimuthSource: 'compass',
        tiltSource: 'accelerometer',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.explore_outlined,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Measure Panel Angle', style: AppTypography.h3),
                        const SizedBox(height: 2),
                        Text(
                          'Place phone flat on panel to measure direction and tilt angle',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Close',
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Orientation Instrument
              OrientationCompassWidget(
                reading: _liveReading,
                isCapturing: _isCapturing,
                isLocked: _isLocked,
                lockedAzimuth: _lockedAzimuth,
                lockedTilt: _lockedTilt,
                onCapture: _handleCapture,
                onRecapture: _handleRecapture,
              ),

              // Confirmation Action when locked
              if (_isLocked) ...[
                const SizedBox(height: 16),
                PrimaryButton(
                  label:
                      'Apply (${_lockedAzimuth!.toStringAsFixed(1)}° / ${_lockedTilt!.toStringAsFixed(1)}°)',
                  icon: Icons.check_circle_outline,
                  onPressed: _applyResult,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
