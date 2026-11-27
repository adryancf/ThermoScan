import 'dart:math' as math;

/// One sampled point along a 24-hour local solar curve.
class SolarCurvePoint {
  const SolarCurvePoint({
    required this.localTime,
    required this.hourFraction,
    required this.elevationDeg,
    required this.cosineScore,
    required this.isAllowed,
  });

  final DateTime localTime;
  final double hourFraction; // 0.0 .. 24.0
  final double elevationDeg;
  final double cosineScore; // 0.0 .. 1.0
  final bool isAllowed;
}

/// Consolidated daily solar scan window calculated with the exact same NOAA
/// solar geometry equations used by the ESP32 firmware (`solar_geometry.cpp`).
class DailySolarWindow {
  const DailySolarWindow({
    required this.dateLocal,
    required this.minSolarAngleDeg,
    required this.points,
    this.windowStart,
    this.windowEnd,
    required this.duration,
    required this.peakElevationDeg,
    this.peakElevationTime,
    required this.bestCosineScore,
    this.bestAlignmentTime,
    required this.isOpenNow,
    required this.currentElevationDeg,
    required this.nowHourFraction,
  });

  final DateTime dateLocal;
  final double minSolarAngleDeg;
  final List<SolarCurvePoint> points;
  final DateTime? windowStart;
  final DateTime? windowEnd;
  final Duration duration;
  final double peakElevationDeg;
  final DateTime? peakElevationTime;
  final double bestCosineScore;
  final DateTime? bestAlignmentTime;
  final bool isOpenNow;
  final double currentElevationDeg;
  final double nowHourFraction;

  bool get hasWindow => windowStart != null && windowEnd != null && duration.inMinutes > 0;

  String get windowRangeLabel {
    if (!hasWindow) return 'None';
    return '${formatHm(windowStart!)} – ${formatHm(windowEnd!)}';
  }

  String get durationLabel {
    if (!hasWindow) return '0m';
    final hours = duration.inHours;
    final mins = duration.inMinutes % 60;
    if (hours == 0) return '${mins}m';
    if (mins == 0) return '${hours}h';
    return '${hours}h ${mins}m';
  }

  String get peakLabel {
    final t = bestAlignmentTime ?? peakElevationTime;
    if (t == null) return 'N/A';
    final pct = (bestCosineScore * 100).round().clamp(0, 100);
    return pct > 0 ? '${formatHm(t)} · $pct%' : formatHm(t);
  }

  static String formatHm(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

enum SolarSeasonPreset {
  today,
  summer,
  winter,
}

/// Pure-Dart port of `firmware/src/domain/solar_geometry.cpp` so the mobile app
/// renders the exact same scan window boundaries evaluated on the ESP32.
class SolarWindowCalculator {
  SolarWindowCalculator._();

  static const double _degToRad = math.pi / 180.0;
  static const double _radToDeg = 180.0 / math.pi;

  static int _dayOfYearZeroBased(DateTime utc) {
    final jan1 = DateTime.utc(utc.year, 1, 1);
    return utc.difference(jan1).inDays;
  }

  static double calculateSolarElevationDeg({
    required double latitude,
    required double longitude,
    required DateTime utcTime,
  }) {
    final utc = utcTime.toUtc();
    final doy = _dayOfYearZeroBased(utc);
    final hour = utc.hour + utc.minute / 60.0 + utc.second / 3600.0;

    final gamma = (2.0 * math.pi / 365.25) * (doy + (hour - 12.0) / 24.0);

    final eot = 229.18 *
        (0.000075 +
            0.001868 * math.cos(gamma) -
            0.032077 * math.sin(gamma) -
            0.014615 * math.cos(2.0 * gamma) -
            0.040849 * math.sin(2.0 * gamma));

    final decl = 0.006918 -
        0.399912 * math.cos(gamma) +
        0.070257 * math.sin(gamma) -
        0.006758 * math.cos(2.0 * gamma) +
        0.000907 * math.sin(2.0 * gamma) -
        0.002697 * math.cos(3.0 * gamma) +
        0.00148 * math.sin(3.0 * gamma);

    final timeOffset = eot + 4.0 * longitude;
    final tst = hour * 60.0 + timeOffset;

    var haDeg = (tst / 4.0) - 180.0;
    while (haDeg > 180.0) {
      haDeg -= 360.0;
    }
    while (haDeg < -180.0) {
      haDeg += 360.0;
    }

    final haRad = haDeg * _degToRad;
    final latRad = latitude * _degToRad;

    final sinElevation = (math.sin(latRad) * math.sin(decl) +
            math.cos(latRad) * math.cos(decl) * math.cos(haRad))
        .clamp(-1.0, 1.0);

    return math.asin(sinElevation) * _radToDeg;
  }

  static double calculateCosineScore({
    required double latitude,
    required double longitude,
    required double azimuthDeg,
    required double tiltDeg,
    required DateTime utcTime,
  }) {
    final elevationDeg = calculateSolarElevationDeg(
      latitude: latitude,
      longitude: longitude,
      utcTime: utcTime,
    );
    if (elevationDeg <= 0.0) return 0.0;

    final elevationRad = elevationDeg * _degToRad;
    final tiltRad = tiltDeg * _degToRad;

    final utc = utcTime.toUtc();
    final doy = _dayOfYearZeroBased(utc);
    final hour = utc.hour + utc.minute / 60.0 + utc.second / 3600.0;

    final gamma = (2.0 * math.pi / 365.25) * (doy + (hour - 12.0) / 24.0);
    final decl = 0.006918 -
        0.399912 * math.cos(gamma) +
        0.070257 * math.sin(gamma);
    final eot = 229.18 *
        (0.000075 +
            0.001868 * math.cos(gamma) -
            0.032077 * math.sin(gamma));

    final timeOffset = eot + 4.0 * longitude;
    final tst = hour * 60.0 + timeOffset;

    var haDeg = (tst / 4.0) - 180.0;
    while (haDeg > 180.0) {
      haDeg -= 360.0;
    }
    while (haDeg < -180.0) {
      haDeg += 360.0;
    }

    final haRad = haDeg * _degToRad;
    final latRad = latitude * _degToRad;

    final sinZenith = math.max(0.001, math.cos(elevationRad));
    final cosAzimuth = ((math.sin(decl) * math.cos(latRad) -
                math.cos(decl) * math.sin(latRad) * math.cos(haRad)) /
            sinZenith)
        .clamp(-1.0, 1.0);

    var solarAzimuthRad = math.acos(cosAzimuth);
    if (haRad > 0.0) {
      solarAzimuthRad = 2.0 * math.pi - solarAzimuthRad;
    }

    final panelAzimuthRad = azimuthDeg * _degToRad;
    final cosInc = math.sin(elevationRad) * math.cos(tiltRad) +
        math.cos(elevationRad) *
            math.sin(tiltRad) *
            math.cos(solarAzimuthRad - panelAzimuthRad);

    return cosInc.clamp(0.0, 1.0);
  }

  /// Resolves hemisphere-aware solstice dates for seasonal comparison.
  static DateTime dateForSeason({
    required SolarSeasonPreset season,
    required double latitude,
    DateTime? referenceLocal,
  }) {
    final now = referenceLocal ?? DateTime.now();
    switch (season) {
      case SolarSeasonPreset.today:
        return DateTime(now.year, now.month, now.day);
      case SolarSeasonPreset.summer:
        return latitude < 0
            ? DateTime(now.year, 12, 21)
            : DateTime(now.year, 6, 21);
      case SolarSeasonPreset.winter:
        return latitude < 0
            ? DateTime(now.year, 6, 21)
            : DateTime(now.year, 12, 21);
    }
  }

  static DailySolarWindow computeDailyWindow({
    required double latitude,
    required double longitude,
    required double minSolarAngleDeg,
    double? azimuthDeg,
    double? tiltDeg,
    DateTime? dateLocal,
    DateTime? nowLocal,
    int stepMinutes = 5,
  }) {
    final now = nowLocal ?? DateTime.now();
    final day = dateLocal ?? DateTime(now.year, now.month, now.day);
    final dayStart = DateTime(day.year, day.month, day.day);
    final effAzimuth = azimuthDeg ?? (latitude < 0 ? 0.0 : 180.0);
    final effTilt = tiltDeg ?? latitude.abs().clamp(0.0, 45.0);

    final points = <SolarCurvePoint>[];
    DateTime? firstAllowed;
    DateTime? lastAllowed;
    double peakElev = -90.0;
    DateTime? peakElevTime;
    double bestCos = 0.0;
    DateTime? bestCosTime;

    for (var mins = 0; mins <= 24 * 60; mins += stepMinutes) {
      final tLocal = dayStart.add(Duration(minutes: mins));
      final tUtc = tLocal.toUtc();
      final elev = calculateSolarElevationDeg(
        latitude: latitude,
        longitude: longitude,
        utcTime: tUtc,
      );
      final cosScore = calculateCosineScore(
        latitude: latitude,
        longitude: longitude,
        azimuthDeg: effAzimuth,
        tiltDeg: effTilt,
        utcTime: tUtc,
      );
      final allowed = elev >= minSolarAngleDeg;

      if (allowed) {
        firstAllowed ??= tLocal;
        lastAllowed = tLocal;
      }
      if (elev > peakElev) {
        peakElev = elev;
        peakElevTime = tLocal;
      }
      if (allowed && cosScore > bestCos) {
        bestCos = cosScore;
        bestCosTime = tLocal;
      }

      points.add(
        SolarCurvePoint(
          localTime: tLocal,
          hourFraction: mins / 60.0,
          elevationDeg: elev,
          cosineScore: cosScore,
          isAllowed: allowed,
        ),
      );
    }

    final currentElev = calculateSolarElevationDeg(
      latitude: latitude,
      longitude: longitude,
      utcTime: now.toUtc(),
    );

    final duration = (firstAllowed != null && lastAllowed != null)
        ? lastAllowed.difference(firstAllowed)
        : Duration.zero;

    return DailySolarWindow(
      dateLocal: dayStart,
      minSolarAngleDeg: minSolarAngleDeg,
      points: points,
      windowStart: firstAllowed,
      windowEnd: lastAllowed,
      duration: duration,
      peakElevationDeg: peakElev,
      peakElevationTime: peakElevTime,
      bestCosineScore: bestCos,
      bestAlignmentTime: bestCosTime ?? peakElevTime,
      isOpenNow: currentElev >= minSolarAngleDeg,
      currentElevationDeg: currentElev,
      nowHourFraction: now.hour + now.minute / 60.0,
    );
  }
}
