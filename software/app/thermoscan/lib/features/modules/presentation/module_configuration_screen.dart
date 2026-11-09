import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/core/widgets/app_buttons.dart';
import 'package:thermoscan/core/widgets/app_text_field.dart';
import 'package:thermoscan/core/widgets/status_chips.dart';
import 'package:thermoscan/core/widgets/top_app_bar.dart';
import 'package:thermoscan/features/auth/presentation/auth_controller.dart';
import 'package:thermoscan/features/modules/data/device_sensor_service.dart';
import 'package:thermoscan/features/modules/data/module_repository.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';
import 'package:thermoscan/features/modules/presentation/modules_controller.dart';
import 'package:thermoscan/features/modules/presentation/widgets/array_geometry_blueprint_widget.dart';
import 'package:thermoscan/features/modules/presentation/widgets/orientation_calibration_modal.dart';
import 'package:thermoscan/features/modules/presentation/widgets/scan_frequency_selector_widget.dart';
import 'package:thermoscan/features/modules/presentation/widgets/solar_angle_selector_widget.dart';

/// SCR-13: Module Configuration & Interval Change Log
class ModuleConfigurationScreen extends ConsumerStatefulWidget {
  const ModuleConfigurationScreen({
    super.key,
    required this.moduleId,
    this.showAppBar = true,
  });

  final String moduleId;
  final bool showAppBar;

  @override
  ConsumerState<ModuleConfigurationScreen> createState() =>
      _ModuleConfigurationScreenState();
}

class ModuleConfigurationView extends StatelessWidget {
  const ModuleConfigurationView({
    super.key,
    required this.moduleId,
  });

  final String moduleId;

  @override
  Widget build(BuildContext context) {
    return ModuleConfigurationScreen(
      moduleId: moduleId,
      showAppBar: false,
    );
  }
}

class _ModuleConfigurationScreenState
    extends ConsumerState<ModuleConfigurationScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _lengthCtrl = TextEditingController();
  final _widthCtrl = TextEditingController();
  final _countCtrl = TextEditingController();
  final _spacingCtrl = TextEditingController();
  final _reservoirCtrl = TextEditingController();

  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();
  final _elevCtrl = TextEditingController();
  final _azimuthCtrl = TextEditingController();
  final _tiltCtrl = TextEditingController();
  String _azimuthSource = 'manual';
  String _tiltSource = 'manual';

  final _solarAngleCtrl = TextEditingController();
  final _intervalCtrl = TextEditingController();

  String? _populatedForUpdatedAt;
  bool _saving = false;
  String? _errorMsg;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _lengthCtrl.dispose();
    _widthCtrl.dispose();
    _countCtrl.dispose();
    _spacingCtrl.dispose();
    _reservoirCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _elevCtrl.dispose();
    _azimuthCtrl.dispose();
    _tiltCtrl.dispose();
    _solarAngleCtrl.dispose();
    _intervalCtrl.dispose();
    super.dispose();
  }

  void _populateFields(PvModule mod) {
    if (_populatedForUpdatedAt == mod.updatedAt) return;
    _populatedForUpdatedAt = mod.updatedAt;

    _nameCtrl.text = mod.name;
    _lengthCtrl.text = mod.panelLengthCm?.toString() ?? '';
    _widthCtrl.text = mod.panelWidthCm?.toString() ?? '';
    _countCtrl.text = mod.panelCount?.toString() ?? '';
    _spacingCtrl.text = mod.panelSpacingCm?.toString() ?? '';
    _reservoirCtrl.text = mod.reservoirNominalCapacityMl?.toString() ?? '';

    _latCtrl.text = mod.latitude?.toString() ?? '';
    _lngCtrl.text = mod.longitude?.toString() ?? '';
    _elevCtrl.text = mod.elevationM?.toString() ?? '';
    _azimuthCtrl.text = mod.azimuthDeg?.toString() ?? '';
    _tiltCtrl.text = mod.tiltDeg?.toString() ?? '';
    _azimuthSource = mod.azimuthSource ?? 'manual';
    _tiltSource = mod.tiltSource ?? 'manual';

    _solarAngleCtrl.text = mod.minimumSolarAngleDeg?.toString() ?? '';
    _intervalCtrl.text = mod.inspectionIntervalDays.toString();
  }

  Future<void> _handleSave(PvModule mod) async {
    setState(() => _errorMsg = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final perms = mod.permissions;
    final payload = <String, dynamic>{};

    if (perms.canEditGeometryAndLocation) {
      payload['name'] = _nameCtrl.text.trim();
      final length = double.tryParse(_lengthCtrl.text.trim());
      final width = double.tryParse(_widthCtrl.text.trim());
      final count = int.tryParse(_countCtrl.text.trim());
      final spacing = double.tryParse(_spacingCtrl.text.trim());
      final lat = double.tryParse(_latCtrl.text.trim());
      final lng = double.tryParse(_lngCtrl.text.trim());
      final elev = double.tryParse(_elevCtrl.text.trim());
      final az = double.tryParse(_azimuthCtrl.text.trim());
      final tilt = double.tryParse(_tiltCtrl.text.trim());
      final resCap = double.tryParse(_reservoirCtrl.text.trim());

      if (length != null) payload['panel_length_cm'] = length;
      if (width != null) payload['panel_width_cm'] = width;
      if (count != null) payload['panel_count'] = count;
      if (spacing != null) payload['panel_spacing_cm'] = spacing;
      if (lat != null) payload['latitude'] = lat;
      if (lng != null) payload['longitude'] = lng;
      if (elev != null) payload['elevation_m'] = elev;
      if (az != null) {
        payload['azimuth_deg'] = az;
        payload['azimuth_source'] = _azimuthSource;
      }
      if (tilt != null) {
        payload['tilt_deg'] = tilt;
        payload['tilt_source'] = _tiltSource;
      }
      if (resCap != null) {
        payload['reservoir_nominal_capacity_ml'] = resCap;
      }
    }

    if (perms.canEditSolarAngle) {
      final solar = double.tryParse(_solarAngleCtrl.text.trim());
      if (solar != null) {
        payload['minimum_solar_angle_deg'] = solar;
      }
    }

    if (perms.canEditInterval) {
      final interval = int.tryParse(_intervalCtrl.text.trim());
      if (interval != null) {
        payload['inspection_interval_days'] = interval;
      }
    }

    if (payload.isEmpty) {
      setState(() => _errorMsg = 'No configuration values to update.');
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(moduleRepositoryProvider).updateConfiguration(
            moduleId: widget.moduleId,
            payload: payload,
          );
      ref.invalidate(moduleDetailsProvider(widget.moduleId));
      ref.invalidate(moduleIntervalLogsProvider(widget.moduleId));
      ref.invalidate(modulesListProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Configuration updated. The next inspection will be recalculated without starting an immediate scan.',
          ),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 4),
        ),
      );
    } catch (err) {
      if (!mounted) return;
      setState(() => _errorMsg = err.toString());
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  bool _acquiringGps = false;
  final _sensorService = const DeviceSensorService();

  Future<void> _acquireGpsCoordinates() async {
    setState(() => _acquiringGps = true);
    try {
      final loc = await _sensorService.acquireGpsLocation();
      if (!mounted) return;
      setState(() {
        _latCtrl.text = loc.latitude.toStringAsFixed(6);
        _lngCtrl.text = loc.longitude.toStringAsFixed(6);
        _elevCtrl.text = loc.elevationM.toStringAsFixed(1);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Coordinates updated from device GPS.'),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err.toString()),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _acquiringGps = false);
      }
    }
  }

  Future<void> _openOrientationCalibration() async {
    final curAz = double.tryParse(_azimuthCtrl.text.trim());
    final curTilt = double.tryParse(_tiltCtrl.text.trim());

    final result = await OrientationCalibrationModal.show(
      context,
      initialAzimuth: curAz,
      initialTilt: curTilt,
    );

    if (result != null && mounted) {
      setState(() {
        _azimuthCtrl.text = result.azimuthDeg.toStringAsFixed(1);
        _tiltCtrl.text = result.tiltDeg.toStringAsFixed(1);
        _azimuthSource = result.azimuthSource;
        _tiltSource = result.tiltSource;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Orientation angles updated from device sensors.'),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  String _formatDateTime(String iso) {
    if (iso.isEmpty) return '';
    return iso.replaceFirst('T', ' ').split('.').first;
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final detailsAsync = ref.watch(moduleDetailsProvider(widget.moduleId));
    final logsAsync = ref.watch(moduleIntervalLogsProvider(widget.moduleId));

    final body = detailsAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
      error: (err, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(err.toString(), style: AppTypography.body),
        ),
      ),
      data: (details) {
            final mod = details.module;
            final perms = mod.permissions;
            _populateFields(mod);

            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mod.name,
                      style: AppTypography.h2,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Role access: ${mod.relationshipLabel} · MAC ${mod.macAddress}',
                      style: AppTypography.bodySmall,
                    ),
                    const SizedBox(height: 16),

                    if (_errorMsg != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.errorBackground,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.errorBorder),
                        ),
                        child: Text(
                          _errorMsg!,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.error,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Section 1: Array Dimensions & Geometry
                    _SectionCard(
                      title: 'Panel Dimensions & Array',
                      subtitle:
                          'Physical panel dimensions in centimeters and number of panels in row.',
                      editable: perms.canEditGeometryAndLocation,
                      children: [
                        ArrayGeometryBlueprintWidget(
                          panelLengthCm:
                              double.tryParse(_lengthCtrl.text.trim()) ?? 100.0,
                          panelWidthCm:
                              double.tryParse(_widthCtrl.text.trim()) ?? 100.0,
                          panelCount:
                              int.tryParse(_countCtrl.text.trim()) ?? 1,
                          panelSpacingCm:
                              double.tryParse(_spacingCtrl.text.trim()) ?? 0.0,
                          onSwapDimensions: perms.canEditGeometryAndLocation
                              ? () {
                                  setState(() {
                                    final temp = _lengthCtrl.text;
                                    _lengthCtrl.text = _widthCtrl.text;
                                    _widthCtrl.text = temp;
                                  });
                                }
                              : null,
                          onOpenMeasureGuide: () =>
                              showHowToMeasureModal(context),
                        ),
                        const SizedBox(height: 16),
                        AppTextField(
                          label: 'Module Name',
                          controller: _nameCtrl,
                          readOnly: !perms.canEditGeometryAndLocation,
                          validator: (v) {
                            if (!perms.canEditGeometryAndLocation) return null;
                            if (v == null || v.trim().isEmpty) {
                              return 'Module name is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  AppTextField(
                                    label: 'Length along Track (cm)',
                                    controller: _lengthCtrl,
                                    onChanged: (_) => setState(() {}),
                                    readOnly: !perms.canEditGeometryAndLocation,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                    validator: (v) {
                                      if (!perms.canEditGeometryAndLocation) {
                                        return null;
                                      }
                                      if (v == null || v.trim().isEmpty) {
                                        return 'Required';
                                      }
                                      final n = double.tryParse(v.trim());
                                      if (n == null || n <= 0) {
                                        return 'Must be > 0';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Parallel to robot rail',
                                    style: AppTypography.caption.copyWith(
                                      color: AppColors.textSecondary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  AppTextField(
                                    label: 'Width across (cm)',
                                    controller: _widthCtrl,
                                    onChanged: (_) => setState(() {}),
                                    readOnly: !perms.canEditGeometryAndLocation,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                    validator: (v) {
                                      if (!perms.canEditGeometryAndLocation) {
                                        return null;
                                      }
                                      if (v == null || v.trim().isEmpty) {
                                        return 'Required';
                                      }
                                      final n = double.tryParse(v.trim());
                                      if (n == null || n <= 0) {
                                        return 'Must be > 0';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Perpendicular to rail',
                                    style: AppTypography.caption.copyWith(
                                      color: AppColors.textSecondary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  AppTextField(
                                    label: 'Panel Count',
                                    controller: _countCtrl,
                                    onChanged: (_) => setState(() {}),
                                    readOnly: !perms.canEditGeometryAndLocation,
                                    keyboardType: TextInputType.number,
                                    validator: (v) {
                                      if (!perms.canEditGeometryAndLocation) {
                                        return null;
                                      }
                                      if (v == null || v.trim().isEmpty) {
                                        return 'Required';
                                      }
                                      final n = int.tryParse(v.trim());
                                      if (n == null || n < 1) {
                                        return 'Must be >= 1';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Panels along rail',
                                    style: AppTypography.caption.copyWith(
                                      color: AppColors.textSecondary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  AppTextField(
                                    label: 'Gap Between Panels (cm)',
                                    controller: _spacingCtrl,
                                    onChanged: (_) => setState(() {}),
                                    readOnly: !perms.canEditGeometryAndLocation,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                    validator: (v) {
                                      if (!perms.canEditGeometryAndLocation) {
                                        return null;
                                      }
                                      if (v == null || v.trim().isEmpty) {
                                        return 'Required';
                                      }
                                      final n = double.tryParse(v.trim());
                                      if (n == null || n < 0) {
                                        return 'Must be >= 0';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Spacing along rail',
                                    style: AppTypography.caption.copyWith(
                                      color: AppColors.textSecondary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AppTextField(
                              label: 'Water Tank Capacity (mL, optional)',
                              hintText: 'e.g. 1000',
                              controller: _reservoirCtrl,
                              readOnly: !perms.canEditGeometryAndLocation,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              validator: (v) {
                                if (!perms.canEditGeometryAndLocation ||
                                    v == null ||
                                    v.trim().isEmpty) {
                                  return null;
                                }
                                final n = double.tryParse(v.trim());
                                if (n == null || n <= 0) {
                                  return 'Must be > 0';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Robot reservoir volume (e.g. 2000 mL = 2 Liters)',
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Section 2: Installation Location & Orientation
                    _SectionCard(
                      title: 'Installation Location & Orientation',
                      subtitle:
                          'Decimal degree coordinates, elevation, and panel alignment.',
                      editable: perms.canEditGeometryAndLocation,
                      children: [
                        if (perms.canEditGeometryAndLocation) ...[
                          SecondaryButton(
                            label: _acquiringGps
                                ? 'Getting Phone Location...'
                                : 'Use Current Phone Location (GPS)',
                            icon: Icons.my_location,
                            onPressed:
                                _acquiringGps ? null : _acquireGpsCoordinates,
                          ),
                          const SizedBox(height: 12),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: AppTextField(
                                label: 'Latitude (°)',
                                controller: _latCtrl,
                                readOnly: !perms.canEditGeometryAndLocation,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                  signed: true,
                                ),
                                validator: (v) {
                                  if (!perms.canEditGeometryAndLocation) {
                                    return null;
                                  }
                                  if (v == null || v.trim().isEmpty) {
                                    return 'Required';
                                  }
                                  final n = double.tryParse(v.trim());
                                  if (n == null || n < -90 || n > 90) {
                                    return '-90 to 90';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: AppTextField(
                                label: 'Longitude (°)',
                                controller: _lngCtrl,
                                readOnly: !perms.canEditGeometryAndLocation,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                  signed: true,
                                ),
                                validator: (v) {
                                  if (!perms.canEditGeometryAndLocation) {
                                    return null;
                                  }
                                  if (v == null || v.trim().isEmpty) {
                                    return 'Required';
                                  }
                                  final n = double.tryParse(v.trim());
                                  if (n == null || n < -180 || n > 180) {
                                    return '-180 to 180';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        AppTextField(
                          label: 'Elevation (m above sea level)',
                          controller: _elevCtrl,
                          readOnly: !perms.canEditGeometryAndLocation,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          validator: (v) {
                            if (!perms.canEditGeometryAndLocation) return null;
                            if (v == null || v.trim().isEmpty) {
                              return 'Elevation is required';
                            }
                            if (double.tryParse(v.trim()) == null) {
                              return 'Invalid elevation';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        const Divider(height: 1),
                        const SizedBox(height: 14),
                        if (perms.canEditGeometryAndLocation) ...[
                          SecondaryButton(
                            label: 'Measure Angle with Phone',
                            icon: Icons.explore_outlined,
                            onPressed: _openOrientationCalibration,
                          ),
                          const SizedBox(height: 12),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: AppTextField(
                                label: 'Compass Direction / Azimuth (0°–360°)',
                                controller: _azimuthCtrl,
                                readOnly: !perms.canEditGeometryAndLocation,
                                onChanged: (_) {
                                  if (perms.canEditGeometryAndLocation) {
                                    setState(() => _azimuthSource = 'manual');
                                  }
                                },
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                validator: (v) {
                                  if (!perms.canEditGeometryAndLocation) {
                                    return null;
                                  }
                                  if (v == null || v.trim().isEmpty) {
                                    return 'Required';
                                  }
                                  final n = double.tryParse(v.trim());
                                  if (n == null || n < 0 || n >= 360) {
                                    return '0 to <360';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: AppTextField(
                                label: 'Tilt Angle (0°–90°)',
                                controller: _tiltCtrl,
                                readOnly: !perms.canEditGeometryAndLocation,
                                onChanged: (_) {
                                  if (perms.canEditGeometryAndLocation) {
                                    setState(() => _tiltSource = 'manual');
                                  }
                                },
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                validator: (v) {
                                  if (!perms.canEditGeometryAndLocation) {
                                    return null;
                                  }
                                  if (v == null || v.trim().isEmpty) {
                                    return 'Required';
                                  }
                                  final n = double.tryParse(v.trim());
                                  if (n == null || n < 0 || n > 90) {
                                    return '0 to 90';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Orientation sources: Azimuth (${_azimuthSource.toUpperCase()}) · Tilt (${_tiltSource.toUpperCase()})',
                          style: AppTypography.caption,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Section 3: Minimum Solar Angle
                    _SectionCard(
                      title: 'Minimum Sun Height',
                      subtitle:
                          'Minimum sun height required for valid thermal scans.',
                      editable: perms.canEditSolarAngle,
                      children: [
                        SolarAngleSelectorWidget(
                          selectedAngle:
                              double.tryParse(_solarAngleCtrl.text.trim()) ??
                                  15.0,
                          recommendedAngle: () {
                            final lat = mod.latitude?.abs();
                            if (lat == null) return 15.0;
                            if (lat < 15.0) return 10.0;
                            if (lat < 30.0) return 15.0;
                            return 20.0;
                          }(),
                          readOnly: !perms.canEditSolarAngle,
                          onChanged: (angle) {
                            setState(() {
                              _solarAngleCtrl.text = angle.toStringAsFixed(1);
                            });
                          },
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(
                              Icons.lock_outline,
                              size: 15,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Overheating alert rule: 10 °C above normal panel temperature.',
                                style: AppTypography.caption,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Section 4: Inspection Interval
                    _SectionCard(
                      title: 'Inspection Interval',
                      subtitle:
                          'Days between scheduled thermal inspections (Daily, Weekly, Bi-Weekly, or Custom).',
                      editable: perms.canEditInterval,
                      children: [
                        ScanFrequencySelectorWidget(
                          selectedDays:
                              int.tryParse(_intervalCtrl.text.trim()) ?? 7,
                          readOnly: !perms.canEditInterval,
                          onChanged: (days) {
                            setState(() => _intervalCtrl.text = '$days');
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    if (perms.canEditAnyField) ...[
                      PrimaryButton(
                        label: 'Save Configuration',
                        icon: Icons.check_circle_outline,
                        isLoading: _saving,
                        onPressed: () => _handleSave(mod),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Section 5: Interval Change History Log (readable by all users with module access)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Interval Change History',
                            style: AppTypography.h3,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Audit log of inspection interval updates for this module.',
                            style: AppTypography.bodySmall,
                          ),
                          const SizedBox(height: 14),
                          logsAsync.when(
                            loading: () => const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: CircularProgressIndicator(
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            error: (err, _) => Text(
                              err.toString(),
                              style: AppTypography.caption.copyWith(
                                color: AppColors.error,
                              ),
                            ),
                            data: (logs) {
                              if (logs.isEmpty) {
                                return Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: AppColors.background,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: AppColors.border),
                                  ),
                                  child: Text(
                                    'No interval changes recorded yet.',
                                    style: AppTypography.bodySmall,
                                  ),
                                );
                              }

                              return Column(
                                children: logs
                                    .map(
                                      (log) => Container(
                                        margin:
                                            const EdgeInsets.only(bottom: 10),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: AppColors.background,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                              color: AppColors.border),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  '${log.previousIntervalDays}d → ${log.newIntervalDays}d',
                                                  style: AppTypography.dataValue
                                                      .copyWith(
                                                    color: AppColors.primary,
                                                  ),
                                                ),
                                                RoleChip(
                                                  role: log.authorRole,
                                                  compact: true,
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              '${log.authorName} (${log.authorEmail})',
                                              style: AppTypography.bodySmall
                                                  .copyWith(
                                                color: AppColors.textPrimary,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              _formatDateTime(log.changedAt),
                                              style: AppTypography.caption,
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                    .toList(),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );

    if (!widget.showAppBar) {
      return body;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: ThermoScanAppBar(
        title: 'Configuration',
        role: user?.role ?? 'technician',
        showBack: true,
      ),
      body: SafeArea(child: body),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.editable,
    required this.children,
  });

  final String title;
  final String subtitle;
  final bool editable;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.h3,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: editable
                      ? AppColors.primarySoft.withValues(alpha: 0.5)
                      : AppColors.background,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  editable ? 'Editable' : 'Read-Only',
                  style: AppTypography.caption.copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color:
                        editable ? AppColors.primary : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}
