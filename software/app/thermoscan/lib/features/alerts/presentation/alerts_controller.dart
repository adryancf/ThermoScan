import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thermoscan/features/alerts/data/alerts_repository.dart';
import 'package:thermoscan/features/alerts/domain/alert_models.dart';

final alertsSummaryProvider = FutureProvider.autoDispose<AlertsSummary>((ref) {
  final repo = ref.watch(alertsRepositoryProvider);
  return repo.listAlerts();
});
