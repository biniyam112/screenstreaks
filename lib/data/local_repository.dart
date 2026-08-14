import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';

import '../config.dart';
import '../models/group.dart';
import '../models/models.dart';
import 'repository.dart';

/// In-memory demo backend so the full app is usable without Supabase.
/// Seeds "you" plus a few friends with realistic hit/miss histories.
class LocalRepository implements Repository {
  LocalRepository({int myLimit = 120}) : _myLimit = myLimit;

  bool _signedIn = true; // demo mode: treat as already signed in
  int _myLimit;

  late final Map<String, Profile> _people = _seed();

  @override
  bool get isSignedIn => _signedIn;

  @override
  Future<Profile> signInWithGoogle() async {
    _signedIn = true;
    return me();
  }

  @override
  Future<Profile> signInWithEmail(String email, String password) async {
    _signedIn = true;
    return me();
  }

  @override
  Future<void> signOut() async => _signedIn = false;

  @override
  Future<Profile> me() async => _people['me']!;

  @override
  Future<List<Profile>> friends() async => _people.values.where((p) => !p.isMe).toList();

  @override
  Future<Profile> friend(String id) async => _people[id]!;

  @override
  Future<void> checkIn({
    required DateTime day,
    required bool limitMet,
    int? usedMinutes,
    required int limitMinutes,
    String source = 'manual',
    bool partial = false,
  }) async {
    final me = _people['me']!;
    final d = dateOnly(day);
    me.records.removeWhere((r) => dateOnly(r.day) == d);
    me.records.add(
      DailyRecord(
        day: d,
        limitMet: limitMet,
        usedMinutes: usedMinutes,
        limitMinutes: limitMinutes,
        source: source,
      ),
    );
    me.records.sort((a, b) => a.day.compareTo(b.day));
  }

  @override
  Future<void> setDailyLimit(int minutes) async {
    _myLimit = minutes;
    final old = _people['me']!;
    _people['me'] = Profile(
      id: old.id,
      displayName: old.displayName,
      shareCode: old.shareCode,
      dailyLimitMinutes: minutes,
      records: old.records,
      avatarColor: old.avatarColor,
      isMe: true,
    );
  }

  @override
  Future<void> setDisplayName(String name) async {
    final old = _people['me']!;
    _people['me'] = Profile(
      id: old.id,
      displayName: name,
      shareCode: old.shareCode,
      dailyLimitMinutes: old.dailyLimitMinutes,
      records: old.records,
      avatarColor: old.avatarColor,
      isMe: true,
    );
  }

  @override
  Future<Profile> connectWithCode(String code) async {
    // Demo: pretend we found a new friend for any non-empty code.
    final trimmed = code.trim().toUpperCase();
    if (trimmed.isEmpty) throw Exception('Enter a valid code');
    final existing = _people.values.where((p) => p.shareCode == trimmed).toList();
    if (existing.isNotEmpty) return existing.first;

    final id = 'friend_${_people.length}';
    final p = _makeProfile(
      id: id,
      name: 'New Friend',
      code: trimmed,
      color: Colors.teal,
      seed: trimmed.hashCode,
      limit: 120,
    );
    _people[id] = p;
    return p;
  }

  @override
  String shareLink(String code) => '${AppConfig.shareLinkBase}$code';

  @override
  Future<List<FeedItem>> feed() async => _feedSeed
      .map((e) => e.copyWith(
            iCelebrated: _celebrated.contains(e.id),
            celebrateCount: e.celebrateCount + (_boost[e.id] ?? 0),
          ))
      .toList();

  final Set<String> _celebrated = {};
  final Map<String, int> _boost = {};

  late final List<FeedItem> _feedSeed = _makeFeed();

  /// Milestones derived from the seeded histories, so the feed matches the
  /// streaks shown elsewhere instead of being invented separately.
  List<FeedItem> _makeFeed() {
    const runMarks = [3, 7, 14, 21, 30];
    const totalMarks = [25, 50, 100];
    final items = <FeedItem>[];
    var n = 0;

    FeedItem make(Profile p, String kind, int value, DateTime day) {
      n++;
      return FeedItem(
        id: 'demo-${p.id}-$kind-$value',
        userId: p.id,
        displayName: p.displayName,
        kind: kind,
        milestone: value,
        createdAt: day.add(Duration(hours: 9 + (n % 12))),
        celebrateCount: (value * 2 + n * 3) % 9,
        iCelebrated: false,
        commentCount: n % 4,
        viewerIsOwner: p.isMe,
        viewerIsParticipant: p.isMe,
      );
    }

    final monday = DateTime(2020, 1, 6);

    for (final p in _people.values) {
      final days = p.records.map((r) => dateOnly(r.day)).toList()..sort();
      final map = p.byDay;
      final weekMet = <int, int>{};
      final weekLast = <int, DateTime>{};

      var run = 0, best = 0, met = 0, prevRun = 0;
      var didComeback = false, didBest = false, didRare = false;
      DateTime? prev;

      for (final day in days) {
        final ok = map[day]?.limitMet == true;
        final wk = day.difference(monday).inDays ~/ 7;
        weekLast[wk] = day;
        if (ok) weekMet[wk] = (weekMet[wk] ?? 0) + 1;

        if (!ok) {
          prevRun = run;
          run = 0;
          prev = day;
          continue;
        }

        met++;
        run = (prev != null && day.difference(prev).inDays == 1) ? run + 1 : 1;
        prev = day;

        if (runMarks.contains(run)) items.add(make(p, 'streak', run, day));
        if (totalMarks.contains(met)) items.add(make(p, 'total_days', met, day));

        if (!didComeback && run == 3 && prevRun >= 3) {
          items.add(make(p, 'comeback', run, day));
          didComeback = true;
        }
        if (!didBest && best >= 7 && run == best + 1) {
          items.add(make(p, 'personal_best', run, day));
          didBest = true;
        }
        if (!didRare && run == 7) {
          final pct = (communityUnderRate(p.dailyLimitMinutes) * 100).round();
          if (pct <= 35) {
            items.add(make(p, 'rare_air', pct, day));
            didRare = true;
          }
        }
        if (run > best) best = run;
      }

      weekMet.forEach((wk, count) {
        if (count == 7) {
          items.add(make(p, 'perfect_week', 7, weekLast[wk]!));
        }
      });
    }

    // Weekend hold: both Saturday and Sunday met, most recent occurrence.
    for (final p in _people.values) {
      final map = p.byDay;
      final days = map.keys.toList()..sort();
      for (final day in days.reversed) {
        if (day.weekday != DateTime.sunday) continue;
        final sat = day.subtract(const Duration(days: 1));
        if (map[day]?.limitMet == true && map[sat]?.limitMet == true) {
          items.add(make(p, 'weekend', 2, day));
          break;
        }
      }
    }

    // Most improved: last 30 days versus the 30 before.
    for (final p in _people.values) {
      final now = (p.successRate(30) * 100).round();
      final before = (p.successRate(60) * 100).round();
      final gain = now - before;
      if (gain >= 8) {
        items.add(make(p, 'improved', gain, dateOnly(DateTime.now())));
      }
    }

    // Group day: every member of a group under on the same day.
    for (final g in _demoGroups) {
      final members =
          g.memberIds.map((id) => _people[id]).whereType<Profile>().toList();
      if (members.length < 2) continue;
      final days = members.first.byDay.keys.toList()..sort();
      for (final day in days.reversed) {
        if (members.every((m) => m.byDay[day]?.limitMet == true)) {
          final host = members.firstWhere((m) => m.isMe, orElse: () => members.first);
          items.add(make(host, 'group_day', members.length, day));
          break;
        }
      }
    }

    // Streak milestones vastly outnumber the rest, so let every special
    // through and fill the remainder with the newest streaks.
    final special = items.where((e) => e.kind != 'streak').toList()
      ..sort((x, y) => y.createdAt.compareTo(x.createdAt));
    final streaks = items.where((e) => e.kind == 'streak').toList()
      ..sort((x, y) => y.createdAt.compareTo(x.createdAt));
    final mixed = [...special.take(24), ...streaks.take(16)]
      ..sort((x, y) => y.createdAt.compareTo(x.createdAt));
    return mixed;
  }

  @override
  Future<bool> toggleCelebrate(String eventId) async {
    final now = !_celebrated.contains(eventId);
    if (now) { _celebrated.add(eventId); } else { _celebrated.remove(eventId); }
    _boost[eventId] = (_boost[eventId] ?? 0) + (now ? 1 : -1);
    return now;
  }

  @override
  Future<List<FeedComment>> comments(String eventId) async => const [];

  @override
  Future<void> addComment(String eventId, String body) async {}

  @override
  Future<void> selectFriend(String targetId) async {}

  @override
  Future<List<Group>> groups() async => _demoGroups;

  static const _demoGroups = [
    Group(id: 'work', name: 'Work', memberIds: [
      'me', 'maya', 'omar', 'priya', 'dan', 'sofia']),
    Group(id: 'pickleball', name: 'Pickleball', memberIds: [
      'me', 'leo', 'theo', 'nina', 'marcus', 'yuki']),
    Group(id: 'family', name: 'Family', memberIds: [
      'me', 'aisha', 'grace', 'isaac', 'rosa', 'kofi']),
    Group(id: 'lifemaxxers', name: 'Lifemaxxers', memberIds: [
      'me', 'jonas', 'amara', 'felix', 'hana', 'tomas']),
  ];

  /// (id, name, code, colour, seed, limit, metBias)
  static const List<(String, String, String, int, int, int, double)> _roster = [
    ('maya', 'Maya Chen', 'MAYA42', 0xFFFF6D3D, 11, 90, 0.85),
    ('omar', 'Omar Haddad', 'OMAR15', 0xFF0EA5E9, 13, 120, 0.62),
    ('priya', 'Priya Nair', 'PRIYA8', 0xFFA855F7, 17, 105, 0.78),
    ('dan', 'Dan Kovacs', 'DANK21', 0xFF14B8A6, 19, 180, 0.44),
    ('sofia', 'Sofia Reyes', 'SOFIA3', 0xFFF43F5E, 23, 135, 0.71),
    ('leo', 'Leo Martins', 'LEO777', 0xFF2563EB, 29, 150, 0.55),
    ('theo', 'Theo Brandt', 'THEO44', 0xFFEAB308, 31, 90, 0.81),
    ('nina', 'Nina Okafor', 'NINA60', 0xFF22C55E, 37, 120, 0.9),
    ('marcus', 'Marcus Webb', 'MARC12', 0xFF8B5CF6, 41, 210, 0.38),
    ('yuki', 'Yuki Tanaka', 'YUKI55', 0xFFEC4899, 43, 75, 0.67),
    ('aisha', 'Aisha Bello', 'AISHA9', 0xFF8B5CF6, 47, 120, 0.68),
    ('grace', 'Grace Mensah', 'GRACE7', 0xFF06B6D4, 53, 100, 0.74),
    ('isaac', 'Isaac Cohen', 'ISAAC2', 0xFFF97316, 59, 160, 0.51),
    ('rosa', 'Rosa Delgado', 'ROSA88', 0xFF84CC16, 61, 110, 0.83),
    ('kofi', 'Kofi Boateng', 'KOFI30', 0xFF6366F1, 67, 145, 0.59),
    ('jonas', 'Jonas Lind', 'JONAS1', 0xFF10B981, 71, 60, 0.93),
    ('amara', 'Amara Diallo', 'AMARA4', 0xFFD946EF, 73, 85, 0.87),
    ('felix', 'Felix Wu', 'FELIX9', 0xFF3B82F6, 79, 95, 0.76),
    ('hana', 'Hana Yilmaz', 'HANA23', 0xFFF59E0B, 83, 70, 0.89),
    ('tomas', 'Tomas Silva', 'TOMAS6', 0xFFEF4444, 89, 200, 0.41),
  ];

  // --------------------------------------------------------------------------
  Map<String, Profile> _seed() {
    final me = _makeProfile(
      id: 'me',
      name: 'You',
      code: 'YOU123',
      color: const Color(0xFF00A86B),
      seed: 7,
      limit: _myLimit,
      isMe: true,
      metBias: 0.72,
    );
    final friends = [
      for (final f in _roster)
        _makeProfile(
          id: f.$1,
          name: f.$2,
          code: f.$3,
          color: Color(f.$4),
          seed: f.$5,
          limit: f.$6,
          metBias: f.$7,
        ),
    ];
    return {'me': me, for (final f in friends) f.id: f};
  }

  Profile _makeProfile({
    required String id,
    required String name,
    required String code,
    required Color color,
    required int seed,
    required int limit,
    bool isMe = false,
    double metBias = 0.7,
  }) {
    final rng = Random(seed);
    final records = <DailyRecord>[];
    final today = dateOnly(DateTime.now());
    // ~18 weeks of history for the contribution graph.
    for (var i = 125; i >= 0; i--) {
      final day = today.subtract(Duration(days: i));
      // Occasionally leave a gap (no data) to look realistic.
      if (rng.nextDouble() < 0.06) continue;
      final met = rng.nextDouble() < metBias;
      final used = met
          ? (limit * (0.4 + rng.nextDouble() * 0.55)).round()
          : (limit * (1.02 + rng.nextDouble() * 0.5)).round();
      records.add(
        DailyRecord(
          day: day,
          limitMet: met,
          usedMinutes: used,
          limitMinutes: limit,
          source: 'auto',
        ),
      );
    }
    // Give "me" a satisfying active streak.
    if (isMe) {
      for (var i = 4; i >= 1; i--) {
        final day = today.subtract(Duration(days: i));
        records.removeWhere((r) => dateOnly(r.day) == day);
        records.add(
          DailyRecord(
            day: day,
            limitMet: true,
            usedMinutes: Platform.isAndroid ? (limit * 0.6).round() : null,
            limitMinutes: limit,
          ),
        );
      }
      records.sort((a, b) => a.day.compareTo(b.day));
    }
    return Profile(
      id: id,
      displayName: name,
      shareCode: code,
      dailyLimitMinutes: limit,
      records: records,
      avatarColor: color,
      isMe: isMe,
    );
  }

  @override
  Future<Group> createGroup(String name) async =>
      Group(id: 'demo', name: name, memberIds: const ['me']);

  @override
  Future<void> addToGroup(String groupId, String userId) async {}

  @override
  Future<void> setGroupLimit(String groupId, int minutes) async {}

  @override
  Future<void> deleteGroup(String groupId) async {}

  @override
  Future<void> leaveGroup(String groupId) async {}

  @override
  Future<void> inviteToGroup(String groupId, String userId) async {}

  @override
  Future<List<GroupInvite>> pendingInvites() async => const [];

  @override
  Future<void> respondToInvite(String inviteId, bool accept) async {}

  @override
  Stream<void> recordChanges() => const Stream.empty();

  @override
  Future<List<({DateTime day, String? groupId, String kind})>>
      spentPasses() async => const [];

  @override
  Future<void> spendPass(DateTime day,
      {String? groupId, String kind = 'personal'}) async {}

  @override
  Future<List<({DateTime startedAt, DateTime? endedAt, String? reason})>>
      monitoringSessions() async => const [];

  @override
  Future<void> logMonitoringOn() async {}

  @override
  Future<void> logMonitoringOff(String reason) async {}

  @override
  Future<void> setAvatar(List<int> bytes, {String ext = 'jpg'}) async {}

  @override
  Future<void> setNames({
    String? firstName,
    String? lastName,
    String? nickname,
  }) async {}

  @override
  Stream<bool> authChanges() => const Stream.empty();

  @override
  Future<Profile> signUpWithEmail(String email, String password) async =>
      me();

  @override
  String? get currentEmail => null;
}
