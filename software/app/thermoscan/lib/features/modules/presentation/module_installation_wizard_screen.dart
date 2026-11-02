import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:go_router/go_router.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/core/utils/mac_address_formatter.dart';
import 'package:thermoscan/core/widgets/app_buttons.dart';
import 'package:thermoscan/core/widgets/app_text_field.dart';
import 'package:thermoscan/core/widgets/top_app_bar.dart';
import 'package:thermoscan/features/auth/presentation/auth_controller.dart';
import 'package:thermoscan/features/modules/data/device_sensor_service.dart';
import 'package:thermoscan/features/modules/data/module_repository.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';
import 'package:thermoscan/features/modules/presentation/modules_controller.dart';
import 'package:thermoscan/features/modules/presentation/widgets/mac_qr_scanner_modal.dart';
import 'package:thermoscan/features/modules/presentation/widgets/orientation_compass_widget.dart';

/// SCR-16 to SCR-20: Technician 5-Step Module Installation Wizard
class ModuleInstallationWizardScreen extends ConsumerStatefulWidget {
  const ModuleInstallationWizardScreen({
    super.key,
    this.existingModuleId,
  });

  final String? existingModuleId;

  @override
  ConsumerState<ModuleInstallationWizardScreen> createState() =>
      _ModuleInstallationWizardScreenState();
}

class _ModuleInstallationWizardScreenState
    extends ConsumerState<ModuleInstallationWizardScreen> {
  final _step1FormKey = GlobalKey<FormState>();
  final _step2FormKey = GlobalKey<FormState>();
  final _step3FormKey = GlobalKey<FormState>();
  final _step4FormKey = GlobalKey<FormState>();

  int _currentStep = 0; // 0..4 (SCR-16..SCR-20)
  String? _persistedModuleId;
  bool _hydratedExisting = false;

  // Step 1 (SCR-16): Module & Device
  final _nameCtrl = TextEditingController();
  final _macCtrl = TextEditingController();
  final Set<String> _selectedManagerIds = {};

  final _sensorService = const DeviceSensorService();

  // Step 2 (SCR-17): Location
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();
  final _elevCtrl = TextEditingController();
  String? _locationNotice;
  String? _resolvedAddress;
  bool _acquiringLocation = false;
  bool _resolvingAddress = false;

  // Step 3 (SCR-18): Orientation
  final _azimuthCtrl = TextEditingController();
  final _tiltCtrl = TextEditingController();
  String _azimuthSource = 'manual';
  String _tiltSource = 'manual';
  String? _orientationNotice;
  bool _capturingOrientation = false;
  bool _showManualOrientationFields = false;
  bool _isOrientationLocked = false;
  SurfaceOrientationReading? _liveOrientation;
  StreamSubscription<SurfaceOrientationReading>? _orientationSub;

  // Step 4 (SCR-19): Array Configuration
  final _lengthCtrl = TextEditingController();
  final _widthCtrl = TextEditingController();
  final _countCtrl = TextEditingController(text: '1');
  final _spacingCtrl = TextEditingController(text: '0');
  final _solarAngleCtrl = TextEditingController(text: '15');
  String _solarAngleSource = 'default (15°)';
  final _intervalCtrl = TextEditingController(text: '7');
  final _reservoirCtrl = TextEditingController(text: '2000');

  // Step 5 (SCR-19B): Client Access Assignment (Optional)
  final Set<String> _selectedClientIds = {};
  final _clientSearchCtrl = TextEditingController();

  bool _saving = false;
  String? _errorMsg;

  static final _macRegex = RegExp(
    r'^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$',
  );

  @override
  void initState() {
    super.initState();
    _persistedModuleId = widget.existingModuleId;
    _orientationSub = _sensorService.watchSurfaceOrientation().listen(
      (reading) {
        if (!mounted) return;
        if (_currentStep == 2) {
          setState(() => _liveOrientation = reading);
        } else {
          _liveOrientation = reading;
        }
      },
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    _orientationSub?.cancel();
    _nameCtrl.dispose();
    _macCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _elevCtrl.dispose();
    _azimuthCtrl.dispose();
    _tiltCtrl.dispose();
    _lengthCtrl.dispose();
    _widthCtrl.dispose();
    _countCtrl.dispose();
    _spacingCtrl.dispose();
    _solarAngleCtrl.dispose();
    _intervalCtrl.dispose();
    _reservoirCtrl.dispose();
    _clientSearchCtrl.dispose();
    super.dispose();
  }

  void _hydrateFromExistingDetails(ModuleDetails details) {
    if (_hydratedExisting) return;
    _hydratedExisting = true;
    final mod = details.module;
    _persistedModuleId = mod.id;
    _nameCtrl.text = mod.name;
    _macCtrl.text = mod.macAddress;
    _selectedManagerIds
      ..clear()
      ..addAll(details.responsibleManagers.map((m) => m.id));
    _selectedClientIds
      ..clear()
      ..addAll(
        details.companyClients.where((c) => c.isAssigned).map((c) => c.id),
      );

    if (mod.latitude != null) _latCtrl.text = mod.latitude.toString();
    if (mod.longitude != null) _lngCtrl.text = mod.longitude.toString();
    if (mod.elevationM != null) _elevCtrl.text = mod.elevationM.toString();
    if (mod.azimuthDeg != null) _azimuthCtrl.text = mod.azimuthDeg.toString();
    if (mod.tiltDeg != null) _tiltCtrl.text = mod.tiltDeg.toString();
    if (mod.azimuthDeg != null && mod.tiltDeg != null) {
      _isOrientationLocked = true;
    }
    _azimuthSource = mod.azimuthSource ?? 'manual';
    _tiltSource = mod.tiltSource ?? 'manual';

    if (mod.panelLengthCm != null) {
      _lengthCtrl.text = mod.panelLengthCm.toString();
    }
    if (mod.panelWidthCm != null) {
      _widthCtrl.text = mod.panelWidthCm.toString();
    }
    if (mod.panelCount != null) _countCtrl.text = mod.panelCount.toString();
    if (mod.panelSpacingCm != null) {
      _spacingCtrl.text = mod.panelSpacingCm.toString();
    }
    if (mod.minimumSolarAngleDeg != null) {
      _solarAngleCtrl.text = mod.minimumSolarAngleDeg.toString();
    }
    _intervalCtrl.text = mod.inspectionIntervalDays.toString();
    if (mod.reservoirNominalCapacityMl != null) {
      _reservoirCtrl.text = mod.reservoirNominalCapacityMl.toString();
    }

    // Start on Step 2 (Location) when resuming a saved draft
    _currentStep = 1;
  }

  Future<void> _saveDraftAndExit() async {
    setState(() => _errorMsg = null);
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _errorMsg = 'Module name is required to save a draft.');
      return;
    }
    if (_macCtrl.text.trim().isEmpty || !_macRegex.hasMatch(_macCtrl.text.trim())) {
      setState(() => _errorMsg = 'A valid MAC address (e.g. AA:BB:CC:DD:EE:FF) is required to save a draft.');
      return;
    }
    if (_selectedManagerIds.isEmpty) {
      setState(() {
        _errorMsg = 'Select at least one active responsible Manager.';
      });
      return;
    }

    setState(() => _saving = true);
    try {
      final repo = ref.read(moduleRepositoryProvider);

      // Collect whatever fields are currently available to persist into the draft
      final length = double.tryParse(_lengthCtrl.text.trim());
      final width = double.tryParse(_widthCtrl.text.trim());
      final count = int.tryParse(_countCtrl.text.trim());
      final spacing = double.tryParse(_spacingCtrl.text.trim());
      final lat = double.tryParse(_latCtrl.text.trim());
      final lng = double.tryParse(_lngCtrl.text.trim());
      final elev = double.tryParse(_elevCtrl.text.trim());
      final azimuth = double.tryParse(_azimuthCtrl.text.trim());
      final tilt = double.tryParse(_tiltCtrl.text.trim());
      final solarAngle = double.tryParse(_solarAngleCtrl.text.trim());
      final interval = int.tryParse(_intervalCtrl.text.trim());
      final reservoir = double.tryParse(_reservoirCtrl.text.trim());

      if (_persistedModuleId == null) {
        final created = await repo.createModule(
          name: _nameCtrl.text.trim(),
          macAddress: _macCtrl.text.trim(),
          managerIds: _selectedManagerIds.toList(),
          clientIds: _selectedClientIds.toList(),
          panelLengthCm: length,
          panelWidthCm: width,
          panelCount: count,
          panelSpacingCm: spacing,
          latitude: lat,
          longitude: lng,
          elevationM: elev,
          azimuthDeg: azimuth,
          tiltDeg: tilt,
          azimuthSource: azimuth != null ? _azimuthSource : null,
          tiltSource: tilt != null ? _tiltSource : null,
          minimumSolarAngleDeg: solarAngle,
          inspectionIntervalDays: interval,
          reservoirNominalCapacityMl: reservoir,
        );
        _persistedModuleId = created.module.id;
      } else {
        await repo.updateConfiguration(
          moduleId: _persistedModuleId!,
          payload: {
            'name': _nameCtrl.text.trim(),
            'panel_length_cm': ?length,
            'panel_width_cm': ?width,
            'panel_count': ?count,
            'panel_spacing_cm': ?spacing,
            'latitude': ?lat,
            'longitude': ?lng,
            'elevation_m': ?elev,
            'azimuth_deg': ?azimuth,
            'tilt_deg': ?tilt,
            if (azimuth != null) 'azimuth_source': _azimuthSource,
            if (tilt != null) 'tilt_source': _tiltSource,
            'minimum_solar_angle_deg': ?solarAngle,
            'inspection_interval_days': ?interval,
            'reservoir_nominal_capacity_ml': ?reservoir,
            'client_ids': _selectedClientIds.toList(),
          },
        );
      }

      ref.invalidate(modulesListProvider);
      if (_persistedModuleId != null) {
        ref.invalidate(moduleDetailsProvider(_persistedModuleId!));
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Draft saved (Pending Configuration). You can resume configuration anytime.',
          ),
          backgroundColor: AppColors.success,
        ),
      );
      context.pushReplacement('/modules/${_persistedModuleId!}');
    } catch (err) {
      if (!mounted) return;
      setState(() => _errorMsg = err.toString());
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _nextFromStep1() {
    setState(() => _errorMsg = null);
    if (!(_step1FormKey.currentState?.validate() ?? false)) return;
    if (_selectedManagerIds.isEmpty) {
      setState(() {
        _errorMsg = 'Select at least one active responsible Manager.';
      });
      return;
    }
    setState(() => _currentStep = 1);
  }

  void _nextFromStep2() {
    setState(() => _errorMsg = null);
    if (!(_step2FormKey.currentState?.validate() ?? false)) return;
    setState(() => _currentStep = 2);
  }

  void _nextFromStep3() {
    setState(() => _errorMsg = null);
    if (_azimuthCtrl.text.trim().isEmpty || _tiltCtrl.text.trim().isEmpty) {
      setState(() {
        _errorMsg =
            'Capture orientation with the sensors or enter Azimuth and Tilt manually below.';
        _showManualOrientationFields = true;
      });
      return;
    }
    if (!(_step3FormKey.currentState?.validate() ?? false)) return;
    setState(() => _currentStep = 3);
  }

  void _nextFromStep4() {
    setState(() => _errorMsg = null);
    if (!(_step4FormKey.currentState?.validate() ?? false)) return;
    setState(() => _currentStep = 4);
  }

  void _nextFromStep5() {
    setState(() {
      _errorMsg = null;
      _currentStep = 5;
    });
  }

  Future<void> _acquireDeviceLocationSample() async {
    setState(() {
      _acquiringLocation = true;
      _locationNotice = null;
    });
    try {
      final loc = await _sensorService.acquireGpsLocation();
      if (!mounted) return;
      setState(() {
        _latCtrl.text = loc.latitude.toStringAsFixed(6);
        _lngCtrl.text = loc.longitude.toStringAsFixed(6);
        _elevCtrl.text = loc.elevationM.toStringAsFixed(1);
        _locationNotice =
            'Coordinates acquired from GPS hardware. Review and adjust any value manually if needed.';
      });
      _reverseGeocode(loc.latitude, loc.longitude);
      _autoEstimateSolarAngle(loc.latitude);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _locationNotice =
            'GPS Notice: ${e.toString().replaceAll('Exception: ', '')}';
      });
    } finally {
      if (mounted) {
        setState(() => _acquiringLocation = false);
      }
    }
  }

  Future<void> _reverseGeocode(double lat, double lng) async {
    setState(() => _resolvingAddress = true);
    try {
      final geocoding = Geocoding();
      final placemarks = await geocoding.placemarkFromCoordinates(lat, lng);
      if (!mounted) return;
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        String address = '';

        // On Android, geocoding maps `Address.getAddressLine(0)` to `p.street`.
        // When it already contains a complete formatted address line, use it directly.
        if (p.street != null && p.street!.isNotEmpty) {
          final s = p.street!.trim();
          if (s.contains(',') &&
              (s.contains('-') ||
                  (p.country != null && p.country!.isNotEmpty && s.contains(p.country!)) ||
                  (p.administrativeArea != null && p.administrativeArea!.isNotEmpty && s.contains(p.administrativeArea!)))) {
            address = s;
          }
        }

        if (address.isEmpty) {
          final parts = <String>[];
          final streetName = (p.thoroughfare != null && p.thoroughfare!.isNotEmpty)
              ? p.thoroughfare!.trim()
              : (p.street?.trim() ?? '');
          final number = p.subThoroughfare?.trim() ?? '';
          final streetWithNum = [
            if (streetName.isNotEmpty) streetName,
            if (number.isNotEmpty && !streetName.contains(number)) number,
          ].join(', ');

          if (streetWithNum.isNotEmpty) parts.add(streetWithNum);
          if (p.subLocality != null && p.subLocality!.isNotEmpty) {
            parts.add(p.subLocality!.trim());
          }

          final city = (p.locality != null && p.locality!.isNotEmpty)
              ? p.locality!.trim()
              : (p.subAdministrativeArea?.trim() ?? '');
          final state = p.administrativeArea?.trim() ?? '';
          if (city.isNotEmpty && state.isNotEmpty) {
            parts.add('$city - $state');
          } else if (city.isNotEmpty) {
            parts.add(city);
          } else if (state.isNotEmpty) {
            parts.add(state);
          }

          if (p.country != null && p.country!.isNotEmpty) {
            parts.add(p.country!.trim());
          }

          address = parts.join(', ');
        }

        if (address.isEmpty && p.street != null && p.street!.isNotEmpty) {
          address = p.street!.trim();
        }

        setState(() {
          _resolvedAddress = address.isNotEmpty
              ? address
              : '${p.locality ?? ''}, ${p.administrativeArea ?? ''}';
        });
      }
    } catch (_) {
      // Non-blocking: Geocoding is for operator convenience
    } finally {
      if (mounted) {
        setState(() => _resolvingAddress = false);
      }
    }
  }

  void _autoEstimateSolarAngle(double latitude) {
    // Estimativa solar regional/geométrica:
    // Em baixas latitudes (equador/tropicais), ângulo solar mínimo útil de corte costuma ficar em 10°-12°.
    // Em latitudes médias/altas, 15°-18° evita sombreamentos de inverno no início da manhã.
    final absLat = latitude.abs();
    double estimated;
    if (absLat < 15.0) {
      estimated = 10.0;
    } else if (absLat < 30.0) {
      estimated = 15.0;
    } else {
      estimated = 18.0;
    }

    // Se o usuário ainda não editou manualmente ou está no default inicial
    if (_solarAngleSource.startsWith('default') || _solarAngleSource.startsWith('estimated')) {
      _solarAngleCtrl.text = estimated.toStringAsFixed(1);
      _solarAngleSource = 'estimated from latitude ($absLat° S/N)';
    }
  }

  Future<void> _acquireDeviceOrientationSample() async {
    setState(() {
      _capturingOrientation = true;
      _orientationNotice = null;
    });
    try {
      final reading = _liveOrientation ??
          await _sensorService.captureSurfaceOrientation();
      if (!mounted) return;
      setState(() {
        _azimuthCtrl.text = reading.azimuthDeg.toStringAsFixed(1);
        _tiltCtrl.text = reading.tiltDeg.toStringAsFixed(1);
        _azimuthSource = reading.hasMagnetometer ? 'sensor' : 'manual';
        _tiltSource = 'sensor';
        _isOrientationLocked = true;
        _orientationNotice = reading.hasMagnetometer
            ? 'Surface alignment captured from device motion & compass (Source: SENSOR).'
            : 'Tilt captured from accelerometer (Source: SENSOR). Compass unavailable on this device: verify Azimuth manually.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _orientationNotice =
            'Sensor Notice: ${e.toString().replaceAll('Exception: ', '')}';
      });
    } finally {
      if (mounted) {
        setState(() => _capturingOrientation = false);
      }
    }
  }

  void _onManualAzimuthChanged(String v) {
    setState(() {
      if (v.trim().isEmpty) {
        _azimuthSource = 'sensor';
      } else {
        _azimuthSource = 'manual';
      }
      _isOrientationLocked = _azimuthCtrl.text.trim().isNotEmpty && _tiltCtrl.text.trim().isNotEmpty;
    });
  }

  void _onManualTiltChanged(String v) {
    setState(() {
      if (v.trim().isEmpty) {
        _tiltSource = 'sensor';
      } else {
        _tiltSource = 'manual';
      }
      _isOrientationLocked = _azimuthCtrl.text.trim().isNotEmpty && _tiltCtrl.text.trim().isNotEmpty;
    });
  }

  Future<void> _submitFullInstallation() async {
    setState(() {
      _errorMsg = null;
      _saving = true;
    });

    try {
      final repo = ref.read(moduleRepositoryProvider);
      final name = _nameCtrl.text.trim();
      final mac = _macCtrl.text.trim();
      final lat = double.parse(_latCtrl.text.trim());
      final lng = double.parse(_lngCtrl.text.trim());
      final elev = double.parse(_elevCtrl.text.trim());
      final azimuth = double.parse(_azimuthCtrl.text.trim());
      final tilt = double.parse(_tiltCtrl.text.trim());
      final length = double.parse(_lengthCtrl.text.trim());
      final width = double.parse(_widthCtrl.text.trim());
      final count = int.parse(_countCtrl.text.trim());
      final spacing = double.parse(_spacingCtrl.text.trim());
      final solarAngle = double.parse(_solarAngleCtrl.text.trim());
      final interval = int.parse(_intervalCtrl.text.trim());
      final reservoir = _reservoirCtrl.text.trim().isEmpty
          ? null
          : double.parse(_reservoirCtrl.text.trim());

      String targetModuleId;
      if (_persistedModuleId == null) {
        final created = await repo.createModule(
          name: name,
          macAddress: mac,
          managerIds: _selectedManagerIds.toList(),
          clientIds: _selectedClientIds.toList(),
          panelLengthCm: length,
          panelWidthCm: width,
          panelCount: count,
          panelSpacingCm: spacing,
          latitude: lat,
          longitude: lng,
          elevationM: elev,
          azimuthDeg: azimuth,
          tiltDeg: tilt,
          azimuthSource: _azimuthSource,
          tiltSource: _tiltSource,
          minimumSolarAngleDeg: solarAngle,
          inspectionIntervalDays: interval,
          reservoirNominalCapacityMl: reservoir,
        );
        targetModuleId = created.module.id;
      } else {
        final updated = await repo.updateConfiguration(
          moduleId: _persistedModuleId!,
          payload: {
            'name': name,
            'panel_length_cm': length,
            'panel_width_cm': width,
            'panel_count': count,
            'panel_spacing_cm': spacing,
            'latitude': lat,
            'longitude': lng,
            'elevation_m': elev,
            'azimuth_deg': azimuth,
            'tilt_deg': tilt,
            'azimuth_source': _azimuthSource,
            'tilt_source': _tiltSource,
            'minimum_solar_angle_deg': solarAngle,
            'inspection_interval_days': interval,
            'reservoir_nominal_capacity_ml': reservoir,
            'client_ids': _selectedClientIds.toList(),
          },
        );
        targetModuleId = updated.module.id;
      }

      ref.invalidate(modulesListProvider);
      ref.invalidate(moduleDetailsProvider(targetModuleId));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Module configuration saved. The embedded device remains offline until it connects and syncs.',
          ),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 4),
        ),
      );
      context.pushReplacement('/modules/$targetModuleId');
    } catch (err) {
      if (!mounted) return;
      setState(() => _errorMsg = err.toString());
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final managersAsync = ref.watch(companyManagersOptionsProvider);
    final clientsAsync = ref.watch(companyClientsOptionsProvider);

    if (widget.existingModuleId != null && !_hydratedExisting) {
      final existingAsync =
          ref.watch(moduleDetailsProvider(widget.existingModuleId!));
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: ThermoScanAppBar(
          title: 'Resume Installation',
          role: user?.role ?? 'technician',
          showBack: true,
        ),
        body: existingAsync.when(
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
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() => _hydrateFromExistingDetails(details));
              }
            });
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          },
        ),
      );
    }

    final stepTitles = [
      'Step 1 of 6 · Module & Device',
      'Step 2 of 6 · Site Location',
      'Step 3 of 6 · Surface Orientation',
      'Step 4 of 6 · Array Configuration',
      'Step 5 of 6 · Client Access',
      'Step 6 of 6 · Review & Save',
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: ThermoScanAppBar(
        title: _persistedModuleId != null
            ? 'Complete Installation'
            : 'Install Module',
        role: user?.role ?? 'technician',
        showBack: true,
        onBack: () {
          if (_currentStep > 0) {
            setState(() => _currentStep--);
          } else {
            context.pop();
          }
        },
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Step Progress Header
              Text(
                stepTitles[_currentStep].toUpperCase(),
                style: AppTypography.caption.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: List.generate(6, (index) {
                  final active = index <= _currentStep;
                  return Expanded(
                    child: Container(
                      height: 6,
                      margin: EdgeInsets.only(right: index < 5 ? 6 : 0),
                      decoration: BoxDecoration(
                        color: active ? AppColors.primary : AppColors.border,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 20),

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

              if (_currentStep == 0) _buildStep1(managersAsync),
              if (_currentStep == 1) _buildStep2(),
              if (_currentStep == 2) _buildStep3(),
              if (_currentStep == 3) _buildStep4(),
              if (_currentStep == 4) _buildStep5ClientAccess(clientsAsync),
              if (_currentStep == 5)
                _buildStep6Review(
                  managersAsync.valueOrNull ?? [],
                  clientsAsync.valueOrNull ?? [],
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// SCR-16: Module Name, MAC Address & Responsible Managers
  Widget _buildStep1(AsyncValue<List<ModuleManagerItem>> managersAsync) {
    final isMacLocked = _persistedModuleId != null;

    return Form(
      key: _step1FormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Module & Embedded Device',
            style: AppTypography.h2,
          ),
          const SizedBox(height: 4),
          Text(
            'Register the photovoltaic module label, embedded ESP32 MAC address, and responsible company Managers.',
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextField(
                  label: 'Module Name',
                  hintText: 'e.g. PV-001 — Roof Array North',
                  controller: _nameCtrl,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Module name is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label: 'Device MAC Address',
                  hintText: 'AA:BB:CC:DD:EE:FF',
                  controller: _macCtrl,
                  readOnly: isMacLocked,
                  enabled: !isMacLocked,
                  inputFormatters: [MacAddressInputFormatter()],
                  suffixIcon: isMacLocked
                      ? null
                      : IconButton(
                          icon: const Icon(
                            Icons.qr_code_scanner,
                            color: AppColors.primary,
                          ),
                          tooltip: 'Scan QR Code / Barcode',
                          onPressed: () async {
                            final scanned = await Navigator.of(context).push<String>(
                              MaterialPageRoute(
                                builder: (_) => const MacQrScannerModal(),
                              ),
                            );
                            if (scanned != null && mounted) {
                              setState(() {
                                _macCtrl.text = scanned;
                              });
                            }
                          },
                        ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'MAC address is required';
                    }
                    if (!_macRegex.hasMatch(v.trim())) {
                      return 'Enter a valid 6-byte MAC (e.g. AA:BB:CC:DD:EE:FF)';
                    }
                    return null;
                  },
                ),
                if (isMacLocked) ...[
                  const SizedBox(height: 6),
                  Text(
                    'MAC address is locked to the persisted draft module.',
                    style: AppTypography.caption,
                  ),
                ],
                const SizedBox(height: 20),
                Text(
                  'Responsible Managers (Select at least 1)',
                  style: AppTypography.h3.copyWith(fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  'Select from all active Managers in your company.',
                  style: AppTypography.bodySmall,
                ),
                const SizedBox(height: 10),
                managersAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary),
                    ),
                  ),
                  error: (err, _) => Text(
                    err.toString(),
                    style:
                        AppTypography.caption.copyWith(color: AppColors.error),
                  ),
                  data: (managers) {
                    if (_selectedManagerIds.isEmpty && managers.isNotEmpty) {
                      // Pre-select default manager for convenience if none chosen yet
                      final defaultMgr = managers
                          .where((m) => m.isDefaultManager)
                          .firstOrNull;
                      if (defaultMgr != null) {
                        _selectedManagerIds.add(defaultMgr.id);
                      }
                    }
                    return Column(
                      children: managers.map((mgr) {
                        final selected = _selectedManagerIds.contains(mgr.id);
                        return CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          activeColor: AppColors.primary,
                          value: selected,
                          onChanged: isMacLocked
                              ? null
                              : (val) {
                                  setState(() {
                                    if (val ?? false) {
                                      _selectedManagerIds.add(mgr.id);
                                    } else {
                                      _selectedManagerIds.remove(mgr.id);
                                    }
                                  });
                                },
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  mgr.name,
                                  style: AppTypography.body.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (mgr.isDefaultManager) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primarySoft,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    'Default',
                                    style: AppTypography.chip.copyWith(
                                      fontSize: 10,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text(
                            mgr.email,
                            style: AppTypography.caption,
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          PrimaryButton(
            label: 'Continue to Site Location',
            icon: Icons.arrow_forward,
            isLoading: _saving,
            onPressed: _nextFromStep1,
          ),
          const SizedBox(height: 10),
          SecondaryButton(
            label: 'Save as Draft (Pending Configuration)',
            icon: Icons.save_outlined,
            isLoading: _saving,
            onPressed: _saveDraftAndExit,
          ),
        ],
      ),
    );
  }

  /// SCR-17: Installation Site Location
  Widget _buildStep2() {
    return Form(
      key: _step2FormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Installation Site Location',
            style: AppTypography.h2,
          ),
          const SizedBox(height: 4),
          Text(
            'Acquire or enter the installation latitude, longitude, and elevation above sea level.',
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SecondaryButton(
                  label: 'Acquire Location from Device GPS',
                  icon: Icons.my_location_outlined,
                  isLoading: _acquiringLocation,
                  onPressed: _acquireDeviceLocationSample,
                ),
                if (_locationNotice != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _locationNotice!,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
                if (_resolvingAddress || _resolvedAddress != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 18,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Estimated Physical Address (Verification Only)',
                                style: AppTypography.caption.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              if (_resolvingAddress)
                                Text(
                                  'Resolving address from coordinates...',
                                  style: AppTypography.caption.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                )
                              else
                                Text(
                                  _resolvedAddress!,
                                  style: AppTypography.bodySmall.copyWith(
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                AppTextField(
                  label: 'Latitude (Decimal Degrees, -90° to 90°)',
                  hintText: 'e.g. -25.43950',
                  controller: _latCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Latitude is required';
                    }
                    final n = double.tryParse(v.trim());
                    if (n == null || n < -90 || n > 90) {
                      return 'Enter a valid latitude between -90 and 90';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                AppTextField(
                  label: 'Longitude (Decimal Degrees, -180° to 180°)',
                  hintText: 'e.g. -49.26870',
                  controller: _lngCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Longitude is required';
                    }
                    final n = double.tryParse(v.trim());
                    if (n == null || n < -180 || n > 180) {
                      return 'Enter a valid longitude between -180 and 180';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                AppTextField(
                  label: 'Elevation (Meters relative to sea level)',
                  hintText: 'e.g. 934.0',
                  controller: _elevCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Elevation is required';
                    }
                    if (double.tryParse(v.trim()) == null) {
                      return 'Enter a valid elevation in meters';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          PrimaryButton(
            label: 'Continue to Surface Orientation',
            icon: Icons.arrow_forward,
            onPressed: _nextFromStep2,
          ),
        ],
      ),
    );
  }

  /// SCR-18: Panel Surface Orientation (Azimuth & Tilt)
  Widget _buildStep3() {
    final hasRecordedOrientation = _isOrientationLocked &&
        _azimuthCtrl.text.trim().isNotEmpty &&
        _tiltCtrl.text.trim().isNotEmpty;
    final lockedAzimuth = double.tryParse(_azimuthCtrl.text.trim());
    final lockedTilt = double.tryParse(_tiltCtrl.text.trim());

    return Form(
      key: _step3FormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Surface Orientation',
            style: AppTypography.h2,
          ),
          const SizedBox(height: 4),
          Text(
            'Place your phone flat and aligned with the panel surface to capture azimuth and tilt in real time.',
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: 16),
          OrientationCompassWidget(
            reading: _liveOrientation,
            isCapturing: _capturingOrientation,
            isLocked: hasRecordedOrientation,
            lockedAzimuth: lockedAzimuth,
            lockedTilt: lockedTilt,
            onCapture: _acquireDeviceOrientationSample,
            onRecapture: () {
              setState(() {
                _azimuthCtrl.clear();
                _tiltCtrl.clear();
                _azimuthSource = 'sensor';
                _tiltSource = 'sensor';
                _isOrientationLocked = false;
                _orientationNotice = null;
              });
            },
          ),
          const SizedBox(height: 14),

          // Recorded Confirmation Card
          if (hasRecordedOrientation) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.successBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.successBorder),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: AppColors.success,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Alignment Recorded',
                          style: AppTypography.h3.copyWith(
                            fontSize: 13,
                            color: AppColors.success,
                          ),
                        ),
                        Text(
                          'Azimuth: ${_azimuthCtrl.text}° (${_azimuthSource.toUpperCase()}) • Tilt: ${_tiltCtrl.text}° (${_tiltSource.toUpperCase()})',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _showManualOrientationFields =
                            !_showManualOrientationFields;
                      });
                    },
                    child: Text(
                      _showManualOrientationFields ? 'Hide' : 'Edit',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ] else ...[
            Center(
              child: TextButton.icon(
                icon: Icon(
                  _showManualOrientationFields
                      ? Icons.keyboard_arrow_up
                      : Icons.tune_outlined,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                label: Text(
                  _showManualOrientationFields
                      ? 'Hide manual adjustment fields'
                      : 'Or enter / adjust angles manually',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: () {
                  setState(() {
                    _showManualOrientationFields =
                        !_showManualOrientationFields;
                  });
                },
              ),
            ),
            const SizedBox(height: 6),
          ],

          // Collapsible Manual Input Container
          if (_showManualOrientationFields) ...[
            Container(
              padding: const EdgeInsets.all(18),
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
                        'Manual Adjustments',
                        style: AppTypography.h3.copyWith(fontSize: 14),
                      ),
                      Row(
                        children: [
                          Text(
                            'Az: ${_azimuthSource.toUpperCase()}',
                            style: AppTypography.caption.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Tilt: ${_tiltSource.toUpperCase()}',
                            style: AppTypography.caption.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    label: 'Panel Azimuth (0° to <360° relative to True North)',
                    hintText: 'e.g. 15.0',
                    controller: _azimuthCtrl,
                    onChanged: _onManualAzimuthChanged,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Azimuth angle is required';
                      }
                      final n = double.tryParse(v.trim());
                      if (n == null || n < 0 || n >= 360) {
                        return 'Enter an angle from 0° to less than 360°';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    label: 'Panel Tilt Angle (0° to 90°)',
                    hintText: 'e.g. 23.5',
                    controller: _tiltCtrl,
                    onChanged: _onManualTiltChanged,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Tilt angle is required';
                      }
                      final n = double.tryParse(v.trim());
                      if (n == null || n < 0 || n > 90) {
                        return 'Enter an angle between 0° and 90°';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          if (_orientationNotice != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.primarySoft.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _orientationNotice!,
                style: AppTypography.caption.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          PrimaryButton(
            label: 'Continue to Array Configuration',
            icon: Icons.arrow_forward,
            onPressed: _nextFromStep3,
          ),
        ],
      ),
    );
  }

  /// SCR-19: Photovoltaic Array Configuration
  Widget _buildStep4() {
    return Form(
      key: _step4FormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Array Configuration',
            style: AppTypography.h2,
          ),
          const SizedBox(height: 4),
          Text(
            'Enter panel dimensions in centimeters, string count, minimum solar angle, and inspection interval.',
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: 16),
          Container(
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
                  children: [
                    Expanded(
                      child: AppTextField(
                        label: 'Panel Length (cm)',
                        hintText: '195.5',
                        controller: _lengthCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Required';
                          }
                          final n = double.tryParse(v.trim());
                          if (n == null || n <= 0) return 'Must be > 0';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppTextField(
                        label: 'Panel Width (cm)',
                        hintText: '99.2',
                        controller: _widthCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Required';
                          }
                          final n = double.tryParse(v.trim());
                          if (n == null || n <= 0) return 'Must be > 0';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Panels in Series',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            height: 48,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove, size: 18),
                                  splashRadius: 18,
                                  onPressed: () {
                                    final current = int.tryParse(_countCtrl.text.trim()) ?? 1;
                                    if (current > 1) {
                                      setState(() => _countCtrl.text = '${current - 1}');
                                    }
                                  },
                                ),
                                Expanded(
                                  child: TextFormField(
                                    controller: _countCtrl,
                                    textAlign: TextAlign.center,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.zero,
                                      isDense: true,
                                    ),
                                    style: AppTypography.body.copyWith(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    validator: (v) {
                                      if (v == null || v.trim().isEmpty) return 'Req';
                                      final n = int.tryParse(v.trim());
                                      if (n == null || n < 1) return '>=1';
                                      return null;
                                    },
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add, size: 18),
                                  splashRadius: 18,
                                  onPressed: () {
                                    final current = int.tryParse(_countCtrl.text.trim()) ?? 1;
                                    setState(() => _countCtrl.text = '${current + 1}');
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppTextField(
                        label: 'Inter-Panel Spacing (cm)',
                        hintText: '2.5',
                        controller: _spacingCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Required';
                          }
                          final n = double.tryParse(v.trim());
                          if (n == null || n < 0) return 'Must be >= 0';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                AppTextField(
                  label: 'Minimum Solar Angle Threshold (0° to 90°)',
                  hintText: '15.0',
                  controller: _solarAngleCtrl,
                  onChanged: (_) => setState(() => _solarAngleSource = 'manual'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Minimum solar angle is required';
                    }
                    final n = double.tryParse(v.trim());
                    if (n == null || n < 0 || n > 90) {
                      return 'Enter an angle between 0° and 90°';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 4),
                Text(
                  'Source: $_solarAngleSource • Tap to edit anytime.',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.primary,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Inspection Interval Presets',
                  style: AppTypography.caption.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [1, 7, 15].map((days) {
                    final selected = _intervalCtrl.text.trim() == '$days';
                    return ChoiceChip(
                      label: Text('$days ${days == 1 ? 'Day' : 'Days'}'),
                      selected: selected,
                      selectedColor: AppColors.primarySoft,
                      onSelected: (_) {
                        setState(() => _intervalCtrl.text = '$days');
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                AppTextField(
                  label: 'Inspection Interval (Days >= 1)',
                  controller: _intervalCtrl,
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Inspection interval is required';
                    }
                    final n = int.tryParse(v.trim());
                    if (n == null || n < 1) {
                      return 'Must be an integer >= 1';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                AppTextField(
                  label: 'Nominal Reservoir Capacity (mL)',
                  hintText: '2000',
                  controller: _reservoirCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Reservoir nominal capacity is required';
                    }
                    final n = double.tryParse(v.trim());
                    if (n == null || n <= 0) return 'Must be a positive number';
                    return null;
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          PrimaryButton(
            label: 'Continue to Client Access',
            icon: Icons.arrow_forward,
            onPressed: _nextFromStep4,
          ),
        ],
      ),
    );
  }

  /// SCR-19B: Client Access Assignment (Optional)
  Widget _buildStep5ClientAccess(
    AsyncValue<List<ModuleClientItem>> clientsAsync,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Client Access Assignment',
          style: AppTypography.h2,
        ),
        const SizedBox(height: 4),
        Text(
          'Optionally link active company clients to grant them read-only monitoring access to this module. (A Manager can also assign or modify clients later).',
          style: AppTypography.bodySmall,
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              clientsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                ),
                error: (err, _) => Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.errorBackground,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.errorBorder),
                  ),
                  child: Text(
                    err.toString(),
                    style:
                        AppTypography.caption.copyWith(color: AppColors.error),
                  ),
                ),
                data: (clients) {
                  if (clients.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: AppColors.textSecondary,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'No clients available. A Manager can assign clients later.',
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final query = _clientSearchCtrl.text.trim().toLowerCase();
                  final filtered = query.isEmpty
                      ? clients
                      : clients.where((c) {
                          return c.name.toLowerCase().contains(query) ||
                              c.email.toLowerCase().contains(query);
                        }).toList();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppTextField(
                        label: 'Search Company Clients',
                        hintText: 'Search by client name or email...',
                        controller: _clientSearchCtrl,
                        onChanged: (_) => setState(() {}),
                        prefixIcon: Icons.search,
                        suffixIcon: _clientSearchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _clientSearchCtrl.clear();
                                  setState(() {});
                                },
                              )
                            : null,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${_selectedClientIds.length} of ${clients.length} client(s) selected',
                            style: AppTypography.caption.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (_selectedClientIds.isNotEmpty)
                            TextButton(
                              onPressed: () {
                                setState(() => _selectedClientIds.clear());
                              },
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text('Clear all'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Divider(height: 1),
                      if (filtered.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: Text(
                              'No clients match "$query".',
                              style: AppTypography.caption,
                            ),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final client = filtered[index];
                            final isChecked =
                                _selectedClientIds.contains(client.id);
                            return CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              activeColor: AppColors.primary,
                              value: isChecked,
                              onChanged: (val) {
                                setState(() {
                                  if (val ?? false) {
                                    _selectedClientIds.add(client.id);
                                  } else {
                                    _selectedClientIds.remove(client.id);
                                  }
                                });
                              },
                              title: Text(
                                client.name,
                                style: AppTypography.body.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                client.email,
                                style: AppTypography.caption,
                              ),
                            );
                          },
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        PrimaryButton(
          label: 'Continue to Review',
          icon: Icons.fact_check_outlined,
          onPressed: _nextFromStep5,
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _saving ? null : _saveDraftAndExit,
            icon: const Icon(Icons.bookmark_outline, size: 18),
            label: const Text('Save Draft & Exit'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// SCR-20: Review and Save
  Widget _buildStep6Review(
    List<ModuleManagerItem> managers,
    List<ModuleClientItem> clients,
  ) {
    final chosenManagers = managers
        .where((m) => _selectedManagerIds.contains(m.id))
        .map((m) => m.name)
        .join(', ');

    final chosenClients = clients
        .where((c) => _selectedClientIds.contains(c.id))
        .map((c) => c.name)
        .join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Review & Confirm Installation',
          style: AppTypography.h2,
        ),
        const SizedBox(height: 4),
        Text(
          'Verify all acquired and manually entered properties before saving to the cloud.',
          style: AppTypography.bodySmall,
        ),
        const SizedBox(height: 16),

        _ReviewSectionCard(
          title: 'Module & Device',
          onEdit: () => setState(() => _currentStep = 0),
          items: {
            'Name': _nameCtrl.text.trim(),
            'MAC Address': _macCtrl.text.trim().toUpperCase(),
            'Managers': chosenManagers.isEmpty
                ? '${_selectedManagerIds.length} selected'
                : chosenManagers,
          },
        ),
        const SizedBox(height: 12),

        _ReviewSectionCard(
          title: 'Site Location',
          onEdit: () => setState(() => _currentStep = 1),
          items: {
            'Latitude': '${_latCtrl.text.trim()}°',
            'Longitude': '${_lngCtrl.text.trim()}°',
            'Elevation': '${_elevCtrl.text.trim()} m',
          },
        ),
        const SizedBox(height: 12),

        _ReviewSectionCard(
          title: 'Surface Orientation',
          onEdit: () => setState(() => _currentStep = 2),
          items: {
            'Azimuth':
                '${_azimuthCtrl.text.trim()}° (${_azimuthSource.toUpperCase()})',
            'Tilt Angle':
                '${_tiltCtrl.text.trim()}° (${_tiltSource.toUpperCase()})',
          },
        ),
        const SizedBox(height: 12),

        _ReviewSectionCard(
          title: 'Array & Schedule',
          onEdit: () => setState(() => _currentStep = 3),
          items: {
            'Dimensions':
                '${_lengthCtrl.text.trim()} × ${_widthCtrl.text.trim()} cm',
            'Panels in Series': _countCtrl.text.trim(),
            'Panel Spacing': '${_spacingCtrl.text.trim()} cm',
            'Min Solar Angle': '${_solarAngleCtrl.text.trim()}°',
            'Scan Interval': 'Every ${_intervalCtrl.text.trim()} day(s)',
          },
        ),
        const SizedBox(height: 12),

        _ReviewSectionCard(
          title: 'Client Access Assignment',
          onEdit: () => setState(() => _currentStep = 4),
          items: {
            'Assigned Clients': chosenClients.isEmpty
                ? 'None (Can be assigned later by Manager)'
                : chosenClients,
          },
        ),
        const SizedBox(height: 20),

        PrimaryButton(
          label: 'Save Module Configuration',
          icon: Icons.cloud_upload_outlined,
          isLoading: _saving,
          onPressed: _submitFullInstallation,
        ),
      ],
    );
  }
}

class _ReviewSectionCard extends StatelessWidget {
  const _ReviewSectionCard({
    required this.title,
    required this.onEdit,
    required this.items,
  });

  final String title;
  final VoidCallback onEdit;
  final Map<String, String> items;

  @override
  Widget build(BuildContext context) {
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
                title,
                style: AppTypography.h3.copyWith(fontSize: 16),
              ),
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit'),
              ),
            ],
          ),
          const Divider(height: 12),
          ...items.entries.map(
            (e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      e.key,
                      style: AppTypography.bodySmall,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      e.value,
                      style: AppTypography.dataValue.copyWith(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
