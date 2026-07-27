import 'dart:io';
import 'dart:ui' show DartPluginRegistrant;
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../config.dart';
import '../data/local_store.dart';
import '../models/models.dart';
import 'notifications.dart';
import 'prefs.dart';
import 'usage_service.dart';

const _kTaskName = 'checkScreenTime';
const _kUniqueName = 'screen-time-periodic';

/// Runs in a background isolate on WorkManager's schedule. Records today's
/// usage locally, pushes it (and anything queued) to Supabase, then fires any
/// threshold alerts that are due.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    // Register plugins for this isolate.
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();

    try {
      if (!await UsageService.hasPermission()) return true;

      final goal = await Prefs.goalMinutes();
      final used = await UsageService.todayMinutes();

      // 1) Record today's outcome durably. This shares the exact same outbox
      //    (SharedPreferences) the UI isolate uses, so the two coordinate.
      const store = LocalStore();
      await store.enqueue(
        DailyRecord(
          day: dateOnly(DateTime.now()),
          limitMet: used <= goal,
          usedMinutes: used,
          limitMinutes: goal,
          source: 'auto',
        ),
      );

      // 2) Push to Supabase so accountability friends see fresh data even if
      //    this user never opens the app. Anything not pushed stays queued.
      await _pushOutbox(store);

      // 3) Fire "approaching your limit" alerts.
      await Notifications.init();
      await Notifications.evaluate(usedMinutes: used, goalMinutes: goal);
    } catch (_) {
      // Never crash the worker; it will simply retry next cycle.
    }
    return true;
  });
}

/// Best-effort push of queued check-ins directly to Supabase from the isolate.
///
/// Restores the persisted session (shared via SharedPreferences), refreshes it
/// if the access token has expired, then upserts each queued day. If we're
/// offline or not signed in, everything stays queued for the next cycle / the
/// next time the app is foregrounded.
Future<void> _pushOutbox(LocalStore store) async {
  if (!AppConfig.hasBackend) return;

  final pending = await store.outbox();
  if (pending.isEmpty) return;

  try {
    // Idempotent — returns the existing instance if already initialized in this
    // isolate. detectSessionInUri:false avoids starting a deep-link observer
    // (there's no UI here to receive one).
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
    );
  } catch (_) {
    return;
  }

  final client = Supabase.instance.client;
  final userId = client.auth.currentUser?.id;
  if (userId == null) return; // no persisted session in this isolate

  final session = client.auth.currentSession;
  if (session != null && session.isExpired) {
    try {
      await client.auth.refreshSession();
    } catch (_) {
      return; // offline or refresh failed — keep everything queued
    }
  }

  for (final r in pending) {
    try {
      await client.from('daily_records').upsert({
        'user_id': userId,
        'day': r.day.toIso8601String().split('T').first,
        'limit_met': r.limitMet,
        'used_minutes': r.usedMinutes,
        'limit_minutes': r.limitMinutes,
        'source': r.source,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,day');
      await store.dequeueDay(r.day);
    } catch (_) {
      break; // network died mid-flush; retry the rest next cycle
    }
  }
}

/// One-time WorkManager setup + registration of the recurring check.
class Background {
  Background._();

  static Future<void> start() async {
    if (!Platform.isAndroid) return;

    await Workmanager().initialize(callbackDispatcher);
    // Android's minimum periodic interval is 15 minutes. networkType.notRequired
    // so we still *record* usage offline; the push inside simply no-ops until
    // a connection is available.
    await Workmanager().registerPeriodicTask(
      _kUniqueName,
      _kTaskName,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.notRequired),
    );
  }
}
