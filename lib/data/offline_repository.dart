import '../models/group.dart';
import '../models/models.dart';
import 'local_store.dart';
import 'repository.dart';

/// Wraps a real [Repository] (Supabase) with offline resilience.
///
///  • Writes are **local-first**: a check-in is saved to the outbox and applied
///    to the cached profile immediately, then pushed to the server best-effort.
///    If there's no connection it stays queued and is retried on the next read.
///  • Reads fall back to the on-device cache when the network is unavailable,
///    so the UI never hangs and always shows the latest known state.
class OfflineRepository implements Repository {
  OfflineRepository(this._inner, [this._store = const LocalStore()]);

  final Repository _inner;
  final LocalStore _store;

  bool _syncing = false;

  // --- auth (pass-through) --------------------------------------------------

  @override
  bool get isSignedIn => _inner.isSignedIn;

  @override
  Future<Profile> signInWithGoogle() => _inner.signInWithGoogle();

  @override
  Future<void> signOut() async {
    await _store.clearAll();
    await _inner.signOut();
  }

  // --- reads (cache fallback) -----------------------------------------------

  @override
  Future<Profile> me() async {
    await _sync(); // opportunistically flush anything queued
    try {
      final remote = await _inner.me();
      final merged = await _applyPending(remote);
      await _store.cacheMe(merged);
      return merged;
    } catch (_) {
      final cached = await _store.cachedMe();
      if (cached != null) return _applyPending(cached);
      rethrow; // first launch, offline, nothing cached — let the UI decide
    }
  }

  @override
  Future<List<Profile>> friends() async {
    try {
      final remote = await _inner.friends();
      await _store.cacheFriends(remote);
      return remote;
    } catch (_) {
      return await _store.cachedFriends() ?? const [];
    }
  }

  @override
  Future<Profile> friend(String id) async {
    try {
      return await _inner.friend(id);
    } catch (_) {
      final cached = await _store.cachedFriends();
      final match = cached?.where((p) => p.id == id);
      if (match != null && match.isNotEmpty) return match.first;
      rethrow;
    }
  }

  // --- writes (local-first) -------------------------------------------------

  @override
  Future<void> checkIn({
    required DateTime day,
    required bool limitMet,
    int? usedMinutes,
    required int limitMinutes,
    String source = 'manual',
  }) async {
    final record = DailyRecord(
      day: dateOnly(day),
      limitMet: limitMet,
      usedMinutes: usedMinutes,
      limitMinutes: limitMinutes,
      source: source,
    );
    // 1) durable local record  2) reflect in cache now  3) push best-effort.
    await _store.enqueue(record);
    final cached = await _store.cachedMe();
    if (cached != null) await _store.cacheMe(_mergeRecord(cached, record));
    await _sync();
  }

  @override
  Future<void> setDailyLimit(int minutes) async {
    final cached = await _store.cachedMe();
    if (cached != null) {
      await _store.cacheMe(cached.copyWith(dailyLimitMinutes: minutes));
    }
    try {
      await _inner.setDailyLimit(minutes);
    } catch (_) {
      await _store.mergePendingProfile({'dailyLimitMinutes': minutes});
    }
  }

  @override
  Future<void> setDisplayName(String name) async {
    final cached = await _store.cachedMe();
    if (cached != null) {
      await _store.cacheMe(cached.copyWith(displayName: name));
    }
    try {
      await _inner.setDisplayName(name);
    } catch (_) {
      await _store.mergePendingProfile({'displayName': name});
    }
  }

  // Connecting inherently needs the network; no useful offline behaviour.
  @override
  Future<Profile> connectWithCode(String code) => _inner.connectWithCode(code);

  @override
  String shareLink(String code) => _inner.shareLink(code);

  // The social feed is inherently live; delegate straight through. The Feed
  // screen handles connectivity failures with a retry.
  @override
  Future<List<FeedItem>> feed() => _inner.feed();

  @override
  Future<bool> toggleCelebrate(String eventId) => _inner.toggleCelebrate(eventId);

  @override
  Future<List<FeedComment>> comments(String eventId) => _inner.comments(eventId);

  @override
  Future<void> addComment(String eventId, String body) => _inner.addComment(eventId, body);

  @override
  Future<void> selectFriend(String targetId) => _inner.selectFriend(targetId);

  // --- sync engine ----------------------------------------------------------

  /// Push any queued profile patch + check-ins. Never throws; stops early when
  /// the network is unavailable and leaves the queue intact for next time.
  Future<void> _sync() async {
    if (_syncing) return;
    _syncing = true;
    try {
      final patch = await _store.pendingProfile();
      if (patch.isNotEmpty) {
        try {
          if (patch['dailyLimitMinutes'] is int) {
            await _inner.setDailyLimit(patch['dailyLimitMinutes'] as int);
          }
          if (patch['displayName'] is String) {
            await _inner.setDisplayName(patch['displayName'] as String);
          }
          await _store.clearPendingProfile();
        } catch (_) {
          // still offline — keep the patch
        }
      }

      for (final r in await _store.outbox()) {
        try {
          await _inner.checkIn(
            day: r.day,
            limitMet: r.limitMet,
            usedMinutes: r.usedMinutes,
            limitMinutes: r.limitMinutes,
            source: r.source,
          );
          await _store.dequeueDay(r.day);
        } catch (_) {
          break; // offline; retry the rest later
        }
      }
    } finally {
      _syncing = false;
    }
  }

  /// Overlay queued (un-synced) check-ins onto a profile's history.
  Future<Profile> _applyPending(Profile p) async {
    final pending = await _store.outbox();
    var result = p;
    for (final r in pending) {
      result = _mergeRecord(result, r);
    }
    return result;
  }

  Profile _mergeRecord(Profile p, DailyRecord r) {
    final records = [...p.records]
      ..removeWhere((x) => dateOnly(x.day) == dateOnly(r.day))
      ..add(r)
      ..sort((a, b) => a.day.compareTo(b.day));
    return p.copyWith(records: records);
  }

  @override
  Future<List<Group>> groups() => _inner.groups();
}
