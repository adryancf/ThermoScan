import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thermoscan/core/notifications/local_notification_service.dart';
import 'package:thermoscan/features/alerts/data/alerts_repository.dart';
import 'package:thermoscan/features/alerts/domain/alert_models.dart';

final alertsSummaryProvider =
    FutureProvider.autoDispose<AlertsSummary>((ref) async {
  final repo = ref.watch(alertsRepositoryProvider);
  final summary = await repo.listAlerts();
  if (summary.alerts.isNotEmpty) {
    unawaited(LocalNotificationService.instance.notifyNewAlerts(summary.alerts));
  }
  return summary;
});
