import 'dart:async';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

class DeviceLocationReading {
  const DeviceLocationReading({
    required this.latitude,
    required this.longitude,
    required this.elevationM,
  });

  final double latitude;
  final double longitude;
  final double elevationM;
}

class SurfaceOrientationReading {
  const SurfaceOrientationReading({
    required this.azimuthDeg,
    required this.tiltDeg,
    required this.hasMagnetometer,
  });

  final double azimuthDeg;
  final double tiltDeg;
  final bool hasMagnetometer;

  String get cardinalDirection {
    const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final idx = ((azimuthDeg + 22.5) % 360 / 45).floor();
    return directions[idx % 8];
  }

  /// Radians representing the azimuth [0, 2*pi]
  double get azimuthRad => azimuthDeg * (math.pi / 180.0);
}

class DeviceSensorService {
  const DeviceSensorService();

  /// Acquires current GPS coordinates and altitude from the device hardware.
  Future<DeviceLocationReading> acquireGpsLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception(
        'Location services (GPS) are disabled on this device. Please enable GPS in device settings.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception(
          'Location permission was denied. Please grant permission to acquire GPS coordinates.',
        );
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permission is permanently denied. Please enable it in Android Settings > Apps > ThermoScan.',
      );
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 12),
      ),
    );

    return DeviceLocationReading(
      latitude: position.latitude,
      longitude: position.longitude,
      elevationM: position.altitude,
    );
  }

  /// Provides a high-frequency (50-60Hz) smoothed real-time stream of tilt
  /// and tilt-compensated compass azimuth from hardware sensors.
  Stream<SurfaceOrientationReading> watchSurfaceOrientation() {
    late StreamController<SurfaceOrientationReading> controller;
    StreamSubscription<AccelerometerEvent>? accelSub;
    StreamSubscription<MagnetometerEvent>? magSub;

    double? ax, ay, az;
    double? mx, my, mz;
    const double alpha = 0.18; // Low-pass filter factor at 50Hz for smooth, responsive movement

    void emitIfReady() {
      if (ax == null || ay == null || az == null) return;
      if (controller.isClosed) return;

      final reading = _computeOrientation(
        ax: ax!,
        ay: ay!,
        az: az!,
        mx: mx,
        my: my,
        mz: mz,
      );
      if (reading != null) {
        controller.add(reading);
      }
    }

    controller = StreamController<SurfaceOrientationReading>.broadcast(
      onListen: () {
        // High frequency sensor sampling for fluid 50-60 FPS UI
        accelSub = accelerometerEventStream(
          samplingPeriod: SensorInterval.gameInterval,
        ).listen(
          (event) {
            ax = ax == null ? event.x : (ax! * (1 - alpha) + event.x * alpha);
            ay = ay == null ? event.y : (ay! * (1 - alpha) + event.y * alpha);
            az = az == null ? event.z : (az! * (1 - alpha) + event.z * alpha);
            emitIfReady();
          },
          onError: (_) {},
        );

        magSub = magnetometerEventStream(
          samplingPeriod: SensorInterval.gameInterval,
        ).listen(
          (event) {
            mx = mx == null ? event.x : (mx! * (1 - alpha) + event.x * alpha);
            my = my == null ? event.y : (my! * (1 - alpha) + event.y * alpha);
            mz = mz == null ? event.z : (mz! * (1 - alpha) + event.z * alpha);
            emitIfReady();
          },
          onError: (_) {},
        );
      },
      onCancel: () async {
        await accelSub?.cancel();
        await magSub?.cancel();
      },
    );

    return controller.stream;
  }

  /// Captures a single smoothed orientation snapshot from hardware sensors.
  Future<SurfaceOrientationReading> captureSurfaceOrientation({
    Duration sampleWindow = const Duration(milliseconds: 300),
  }) async {
    SurfaceOrientationReading? latest;
    final sub = watchSurfaceOrientation().listen((reading) {
      latest = reading;
    });

    try {
      await Future<void>.delayed(sampleWindow);
    } finally {
      await sub.cancel();
    }

    if (latest == null) {
      throw Exception(
        'Motion sensors are unavailable on this device. Please enter Azimuth and Tilt manually.',
      );
    }

    return latest!;
  }

  static SurfaceOrientationReading? _computeOrientation({
    required double ax,
    required double ay,
    required double az,
    double? mx,
    double? my,
    double? mz,
  }) {
    final normA = math.sqrt(ax * ax + ay * ay + az * az);
    if (normA < 1e-4) return null;

    // Tilt angle [0°, 90°]: angle between panel surface normal (+Z axis of phone)
    // and the vertical gravity vector.
    final horizontalMag = math.sqrt(ax * ax + ay * ay);
    final rawTiltDeg = math.atan2(horizontalMag, az.abs()) * (180.0 / math.pi);
    final tiltDeg = rawTiltDeg.clamp(0.0, 90.0);

    // Tilt-compensated Azimuth [0°, 360°) using 3D cross-product
    double azimuthDeg = 0.0;
    bool hasMag = false;

    if (mx != null && my != null && mz != null) {
      // East vector H = m x a
      final hx = my * az - mz * ay;
      final hy = mz * ax - mx * az;
      final hz = mx * ay - my * ax;
      final normH = math.sqrt(hx * hx + hy * hy + hz * hz);

      if (normH >= 1e-4) {
        hasMag = true;
        final ex = hx / normH;
        final ey = hy / normH;
        final ez = hz / normH;

        final ux = ax / normA;
        final uz = az / normA;

        // North vector N = U x E (y-component)
        final ny = uz * ex - ux * ez;

        // Heading of phone top edge relative to Magnetic North
        var headingDeg = math.atan2(ey, ny) * (180.0 / math.pi);
        if (headingDeg < 0) {
          headingDeg += 360.0;
        }
        if (headingDeg >= 360.0) {
          headingDeg = headingDeg % 360.0;
        }
        azimuthDeg = headingDeg;
      }
    }

    return SurfaceOrientationReading(
      azimuthDeg: azimuthDeg,
      tiltDeg: tiltDeg,
      hasMagnetometer: hasMag,
    );
  }
}
