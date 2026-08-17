import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/firebase_providers.dart';
import '../core/services/notification_phone_bridge.dart';
import '../features/auth/data/auth_repository.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

class FixNowApp extends ConsumerWidget {
  const FixNowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    ref.listen(currentUserProvider, (_, next) {
      unawaited(NotificationPhoneBridge.instance.sync(
        user: next.valueOrNull,
        firestore: ref.read(firebaseRefsProvider).firestore,
      ));
    });
    return MaterialApp.router(
      title: 'FixNow | Home Appliance Repair & Service Booking',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.light,
      themeMode: ThemeMode.light,
      routerConfig: router,
    );
  }
}
