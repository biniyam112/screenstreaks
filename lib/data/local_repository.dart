import 'dart:math';
import 'package:flutter/material.dart';

import '../config.dart';
import '../models/models.dart';
import 'repository.dart';

/// In-memory demo backend so the full app is usable without Supabase.
/// Seeds "you" plus a few friends with realistic hit/miss histories.
class LocalRepository implements Repository {
  LocalRepository();

  bool _signedIn = true; // demo mode: treat as already signed in
  int _myLimit = 120;

  late final Map<String, Profile> _people = _seed();

  @override
  bool get isSignedIn => _signedIn;

  @override
  Future<Profile> signInWithGoogle() async {
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
  Future<List<FeedItem>> feed() async => const [];

  @override
  Future<bool> toggleCelebrate(String eventId) async => false;

  @override
  Future<List<FeedComment>> comments(String eventId) async => const [];

  @override
  Future<void> addComment(String eventId, String body) async {}

  @override
  Future<void> selectFriend(String targetId) async {}

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
      _makeProfile(
        id: 'maya',
        name: 'Maya Chen',
        code: 'MAYA42',
        color: const Color(0xFFFF6D3D),
        seed: 11,
        limit: 90,
        metBias: 0.85,
      ),
      _makeProfile(
        id: 'leo',
        name: 'Leo Martins',
        code: 'LEO777',
        color: const Color(0xFF2563EB),
        seed: 23,
        limit: 150,
        metBias: 0.55,
      ),
      _makeProfile(
        id: 'aisha',
        name: 'Aisha Bello',
        code: 'AISHA9',
        color: const Color(0xFF8B5CF6),
        seed: 31,
        limit: 120,
        metBias: 0.68,
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
            usedMinutes: (limit * 0.6).round(),
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
}
