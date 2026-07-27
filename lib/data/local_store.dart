import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// On-device cache + outbox that makes the app work offline.
///
///  • Caches "me" and the friends list so the UI renders instantly and still
///    works with no connection.
///  • Holds an outbox of un-synced check-ins (one per day, latest wins) and a
///    pending profile patch, so nothing the user does offline is ever lost.
///
/// Follows the same "fresh SharedPreferences per call" pattern as [Prefs] so it
/// is safe to use from any isolate.
class LocalStore {
  const LocalStore();

  static const _kMe = 'cache_me';
  static const _kFriends = 'cache_friends';
  static const _kOutbox = 'sync_outbox';
  static const _kPendingProfile = 'sync_pending_profile';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  // --- cached profiles ------------------------------------------------------

  Future<Profile?> cachedMe() async {
    final raw = (await _prefs).getString(_kMe);
    if (raw == null) return null;
    try {
      return Profile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> cacheMe(Profile me) async =>
      (await _prefs).setString(_kMe, jsonEncode(me.toJson()));

  Future<List<Profile>?> cachedFriends() async {
    final raw = (await _prefs).getString(_kFriends);
    if (raw == null) return null;
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Profile.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> cacheFriends(List<Profile> friends) async => (await _prefs)
      .setString(_kFriends, jsonEncode(friends.map((f) => f.toJson()).toList()));

  // --- check-in outbox ------------------------------------------------------

  Future<List<DailyRecord>> outbox() async {
    final raw = (await _prefs).getString(_kOutbox);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => DailyRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeOutbox(List<DailyRecord> items) async => (await _prefs)
      .setString(_kOutbox, jsonEncode(items.map((r) => r.toJson()).toList()));

  /// Queue a check-in, replacing any earlier one for the same day.
  Future<void> enqueue(DailyRecord record) async {
    final items = await outbox()
      ..removeWhere((r) => dateOnly(r.day) == dateOnly(record.day));
    items.add(record);
    await _writeOutbox(items);
  }

  Future<void> dequeueDay(DateTime day) async {
    final items = await outbox()
      ..removeWhere((r) => dateOnly(r.day) == dateOnly(day));
    await _writeOutbox(items);
  }

  // --- pending profile patch (name / limit changed while offline) -----------

  Future<Map<String, dynamic>> pendingProfile() async {
    final raw = (await _prefs).getString(_kPendingProfile);
    if (raw == null) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> mergePendingProfile(Map<String, dynamic> patch) async {
    final merged = await pendingProfile()
      ..addAll(patch);
    await (await _prefs).setString(_kPendingProfile, jsonEncode(merged));
  }

  Future<void> clearPendingProfile() async =>
      (await _prefs).remove(_kPendingProfile);

  // --- lifecycle ------------------------------------------------------------

  /// Wipe everything (call on sign-out so the next user starts clean).
  Future<void> clearAll() async {
    final p = await _prefs;
    await p.remove(_kMe);
    await p.remove(_kFriends);
    await p.remove(_kOutbox);
    await p.remove(_kPendingProfile);
  }
}
