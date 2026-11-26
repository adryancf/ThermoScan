import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:thermoscan/features/alerts/domain/alert_models.dart';

/// Native OS local notification bridge fulfilling SNFR12.
///
/// Dispatches Android/iOS system notifications whenever newly detected active
/// alerts arrive (unresolved hotspots, depleted water reservoir, etc.), while
/// safely no-oping in headless unit/widget test environments.
class LocalNotificationService {
  LocalNotificationService._();

  static final LocalNotificationService instance = LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _permissionRequested = false;
  final Set<String> _notifiedAlertIds = <String>{};

  static const String _channelId = 'thermoscan_operational_alerts';
  static const String _channelName = 'ThermoScan Operational Alerts';
  static const String _channelDescription =
      'Critical hotspot, water reservoir, and inspection alerts from ThermoScan robots.';

  Future<void> ensureInitialized() async {
    if (_initialized || kIsWeb) return;
    try {
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const settings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      );
      await _plugin.initialize(settings);
      _initialized = true;

      if (!_permissionRequested) {
        _permissionRequested = true;
        final androidImpl = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        await androidImpl?.requestNotificationsPermission();
      }
    } catch (_) {
      // Safe fallback in unit/widget tests or unsupported desktop targets.
    }
  }

  /// Dispatches native OS notifications for any alert IDs in [alerts] that
  /// have not been notified yet during this app session.
  Future<void> notifyNewAlerts(List<FieldAlert> alerts) async {
    if (alerts.isEmpty || kIsWeb) return;

    final unseen = <FieldAlert>[];
    for (final alert in alerts) {
      final key = '${alert.type}:${alert.id}';
      if (!_notifiedAlertIds.contains(key)) {
        unseen.add(alert);
      }
    }
    if (unseen.isEmpty) return;

    await ensureInitialized();
    if (!_initialized) return;

    try {
      const androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );
      const darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      const details = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
        macOS: darwinDetails,
      );

      // Show up to 3 individual notifications or a consolidated summary if many
      if (unseen.length <= 3) {
        for (final alert in unseen) {
          final title = alert.isReservoirLow
              ? 'Low Water Alert · ${alert.moduleName}'
              : 'Hotspot Alert · ${alert.moduleName}';
          final body = alert.isReservoirLow
              ? 'Cleaning fluid reservoir is empty. Refill required to resume washing.'
              : '${alert.title}${alert.maxTemperatureC != null ? ' (${alert.maxTemperatureC!.toStringAsFixed(1)} °C)' : ''}';
          await _plugin.show(
            alert.id.hashCode & 0x7fffffff,
            title,
            body,
            details,
          );
          _notifiedAlertIds.add('${alert.type}:${alert.id}');
        }
      } else {
        await _plugin.show(
          unseen.first.id.hashCode & 0x7fffffff,
          'ThermoScan · ${unseen.length} Active Operational Alerts',
          'Open the Alerts tab to review active hotspots and robot reservoir warnings.',
          details,
        );
        for (final alert in unseen) {
          _notifiedAlertIds.add('${alert.type}:${alert.id}');
        }
      }
    } catch (_) {
      // Never crash app flow if native notification channel is unavailable.
    }
  }

  void clearNotifiedAlerts() {
    _notifiedAlertIds.clear();
  }

  @visibleForTesting
  void resetForTest() {
    _notifiedAlertIds.clear();
  }
}
