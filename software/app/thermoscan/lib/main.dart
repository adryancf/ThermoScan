import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thermoscan/core/config/app_config.dart';
import 'package:thermoscan/core/notifications/local_notification_service.dart';
import 'package:thermoscan/core/router/app_router.dart';
import 'package:thermoscan/core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.init();
  unawaited(LocalNotificationService.instance.ensureInitialized());
  runApp(
    const ProviderScope(
      child: ThermoScanApp(),
    ),
  );
}

class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.unknown,
      };
}

class ThermoScanApp extends ConsumerWidget {
  const ThermoScanApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'ThermoScan',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      scrollBehavior: const _AppScrollBehavior(),
      routerConfig: router,
    );
  }
}
