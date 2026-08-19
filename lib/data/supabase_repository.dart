import 'dart:typed_data';
import 'dart:async';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/group.dart';
import '../models/models.dart';
import 'repository.dart';

class SupabaseRepository implements Repository {
  SupabaseRepository(this._supabase, this._googleSignIn);

  final SupabaseClient _supabase;
  final GoogleSignIn _googleSignIn;

  @override
  bool get isSignedIn => _supabase.auth.currentSession != null;

  @override
  Future<Profile> signInWithGoogle() async {
    // Browser-based OAuth rather than an ID token. google_sign_in 7.x embeds
    // a nonce we can't read, which Supabase rejects — this flow has none.
    final completer = Completer<Profile>();
    late final StreamSubscription<AuthState> sub;

    sub = _supabase.auth.onAuthStateChange.listen((event) async {
      if (event.session == null) return;
      await sub.cancel();
      try {
        completer.complete(await me());
      } catch (e) {
        completer.completeError(e);
      }
    });

    final started = await _supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'undr://login-callback',
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
    if (!started) {
      await sub.cancel();
      throw Exception("Couldn't open Google sign-in.");
    }

    // Don't hang forever if they close the browser without finishing.
    return completer.future.timeout(
      const Duration(minutes: 3),
      onTimeout: () async {
        await sub.cancel();
        throw Exception('Sign-in was cancelled.');
      },
    );
  }

  @override
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _supabase.auth.signOut();
  }

  @override
  Future<Profile> me() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not signed in');

    final profile = await _supabase.from('profiles').select().eq('id', userId).single();

    final records = await _supabase
        .from('daily_records')
        .select()
        .eq('user_id', userId)
        .order('day', ascending: true);

    return _profileFromJson(profile, records,
        passedDays: await _passedDays(userId));
  }

  /// Days this user has recovered with a personal pass.
  Future<Set<String>> _passedDays(String userId) async {
    try {
      final rows = await _supabase
          .from('streak_passes')
          .select('day')
          .eq('user_id', userId)
          .isFilter('group_id', null);
      return {for (final r in rows) r['day'] as String};
    } catch (_) {
      return const {};
    }
  }

  @override
  Future<List<Profile>> friends() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];

    // Get all connections where I'm either requester or addressee.
    final connections = await _supabase
        .from('connections')
        .select()
        .eq('status', 'accepted')
        .or('requester_id.eq.$userId,addressee_id.eq.$userId');

    final friendIds = <String>{};
    for (final conn in connections) {
      final reqId = conn['requester_id'] as String;
      final addId = conn['addressee_id'] as String;
      if (reqId == userId) {
        friendIds.add(addId);
      } else {
        friendIds.add(reqId);
      }
    }

    final profiles = <Profile>[];
    for (final fid in friendIds) {
      final p = await friend(fid);
      profiles.add(p);
    }

    return profiles;
  }

  @override
  Future<Profile> friend(String id) async {
    final profile = await _supabase.from('profiles').select().eq('id', id).single();

    final records = await _supabase
        .from('daily_records')
        .select()
        .eq('user_id', id)
        .order('day', ascending: true);

    return _profileFromJson(profile, records,
        passedDays: await _passedDays(id));
  }

  @override
  Future<void> checkIn({
    required DateTime day,
    required bool limitMet,
    int? usedMinutes,
    required int limitMinutes,
    String source = 'manual',
    bool partial = false,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not signed in');

    await _supabase.from('daily_records').upsert({
      'user_id': userId,
      'day': day.toIso8601String().split('T')[0],
      'limit_met': limitMet,
      'used_minutes': usedMinutes,
      'limit_minutes': limitMinutes,
      'source': source,
      'partial': partial,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id,day');
  }

  @override
  Future<void> setDailyLimit(int minutes) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not signed in');

    await _supabase.from('profiles').update({'daily_limit_minutes': minutes}).eq('id', userId);
  }

  @override
  Future<void> setDisplayName(String name) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not signed in');

    await _supabase.from('profiles').update({'display_name': name}).eq('id', userId);
  }

  @override
  Future<Profile> connectWithCode(String code) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not signed in');

    try {
      final result =
          await _supabase.rpc('redeem_share_code', params: {'code': code.toUpperCase()})
              as Map<String, dynamic>;

      return _profileFromJson(result, []);
    } on PostgrestException catch (e) {
      // Surface the RPC's own message (e.g. "Invalid share code").
      throw Exception(e.message);
    } catch (_) {
      throw Exception("That code didn't match anyone. Double-check it.");
    }
  }

  @override
  String shareLink(String code) => '$_shareLinkBase$code';

  static const _shareLinkBase = 'https://screenstreaks.app/c/';

  @override
  Future<List<FeedItem>> feed() async {
    final rows = await _supabase.rpc('get_feed') as List;
    return rows.map((r) => FeedItem.fromJson(Map<String, dynamic>.from(r as Map))).toList();
  }

  @override
  Future<bool> toggleCelebrate(String eventId) async {
    final res = await _supabase.rpc('toggle_celebrate', params: {'event': eventId});
    return res as bool;
  }

  @override
  Future<List<FeedComment>> comments(String eventId) async {
    final rows = await _supabase.rpc('get_comments', params: {'event': eventId}) as List;
    return rows.map((r) => FeedComment.fromJson(Map<String, dynamic>.from(r as Map))).toList();
  }

  @override
  Future<void> addComment(String eventId, String body) async {
    await _supabase.rpc('add_comment', params: {'event': eventId, 'body': body});
  }

  @override
  Future<void> selectFriend(String targetId) async {
    await _supabase.rpc('select_friend', params: {'target': targetId});
  }

  Profile _profileFromJson(
    Map<String, dynamic> json,
    List<Map<String, dynamic>> records, {
    Set<String> passedDays = const {},
  }) {
    return Profile(
      id: json['id'] as String,
      displayName: json['display_name'] as String? ?? 'Friend',
      shareCode: json['share_code'] as String? ?? '',
      dailyLimitMinutes: json['daily_limit_minutes'] as int? ?? 120,
      avatarUrl: json['avatar_url'] as String?,
      firstName: json['first_name'] as String?,
      lastName: json['last_name'] as String?,
      nickname: json['nickname'] as String?,
      records: records
          .map(
            (r) => DailyRecord(
              day: DateTime.parse(r['day'] as String),
              // A day recovered with a pass counts as met, so streaks and
              // the calendar don't need to know passes exist.
              limitMet: (r['limit_met'] as bool) ||
                  passedDays.contains(r['day'] as String),
              limitMinutes: r['limit_minutes'] as int,
              usedMinutes: r['used_minutes'] as int?,
              source: r['source'] as String? ?? 'auto',
              partial: r['partial'] as bool? ?? false,
            ),
          )
          .toList(),
    );
  }

  @override
  Future<List<Group>> groups() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];

    final mine = await _supabase
        .from('group_members')
        .select('group_id')
        .eq('user_id', userId);
    final ids = [for (final r in mine) r['group_id'] as String];
    if (ids.isEmpty) return [];

    final rows = await _supabase
        .from('groups')
        .select('id, name, admin_id, limit_minutes')
        .inFilter('id', ids);

    final members = await _supabase
        .from('group_members')
        .select('group_id, user_id')
        .inFilter('group_id', ids);

    final byGroup = <String, List<String>>{};
    for (final m in members) {
      byGroup
          .putIfAbsent(m['group_id'] as String, () => [])
          .add(m['user_id'] as String);
    }

    return [
      for (final g in rows)
        Group(
          id: g['id'] as String,
          name: g['name'] as String,
          adminId: g['admin_id'] as String?,
          limitMinutes: g['limit_minutes'] as int?,
          memberIds: byGroup[g['id']] ?? const [],
        ),
    ];
  }

  @override
  Future<Group> createGroup(String name) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not signed in');

    final row = await _supabase
        .from('groups')
        .insert({'name': name, 'admin_id': userId})
        .select()
        .single();

    final id = row['id'] as String;
    // The creator is a member too.
    await _supabase
        .from('group_members')
        .insert({'group_id': id, 'user_id': userId});

    return Group(
      id: id,
      name: name,
      adminId: userId,
      limitMinutes: null,
      memberIds: [userId],
    );
  }

  @override
  Future<void> addToGroup(String groupId, String userId) async {
    await _supabase
        .from('group_members')
        .insert({'group_id': groupId, 'user_id': userId});
  }

  @override
  Future<void> setGroupLimit(String groupId, int minutes) async {
    await _supabase
        .from('groups')
        .update({'limit_minutes': minutes}).eq('id', groupId);
  }

  @override
  Future<Profile> signInWithEmail(String email, String password) async {
    final AuthResponse res;
    try {
      res = await _supabase.auth
          .signInWithPassword(email: email, password: password);
    } on AuthException catch (e) {
      // Don't quietly create an account here — a typo'd password would make
      // a second one and lose their streak. Show what Supabase said, though,
      // or an unconfirmed account looks the same as a wrong password.
      throw Exception('Login failed: ' + e.message);
    }
    if (res.session == null) {
      throw Exception('Login failed. Check your email and password.');
    }
    return me();
  }

  @override
  Future<void> deleteGroup(String groupId) async {
    await _supabase.from('groups').delete().eq('id', groupId);
  }

  @override
  Future<void> leaveGroup(String groupId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not signed in');
    await _supabase
        .from('group_members')
        .delete()
        .eq('group_id', groupId)
        .eq('user_id', userId);
  }

  @override
  Future<void> inviteToGroup(String groupId, String userId) async {
    await _supabase.from('group_requests').upsert({
      'group_id': groupId,
      'user_id': userId,
      'status': 'pending',
    }, onConflict: 'group_id,user_id');
  }

  @override
  Future<List<GroupInvite>> pendingInvites() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];

    final rows = await _supabase
        .from('group_requests')
        .select('id, group_id, groups(name, admin_id)')
        .eq('user_id', userId)
        .eq('status', 'pending');

    final invites = <GroupInvite>[];
    for (final r in rows) {
      final g = r['groups'] as Map<String, dynamic>?;
      if (g == null) continue;
      var admin = 'A friend';
      final adminId = g['admin_id'] as String?;
      if (adminId != null) {
        final p = await _supabase
            .from('profiles')
            .select('display_name')
            .eq('id', adminId)
            .maybeSingle();
        admin = (p?['display_name'] as String?) ?? admin;
      }
      invites.add(GroupInvite(
        id: r['id'] as String,
        groupId: r['group_id'] as String,
        groupName: g['name'] as String? ?? 'a group',
        invitedBy: admin,
      ));
    }
    return invites;
  }

  @override
  Future<void> respondToInvite(String inviteId, bool accept) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not signed in');

    final row = await _supabase
        .from('group_requests')
        .update({'status': accept ? 'accepted' : 'declined'})
        .eq('id', inviteId)
        .select('group_id')
        .single();

    if (accept) {
      await _supabase.from('group_members').insert({
        'group_id': row['group_id'],
        'user_id': userId,
      });
    }
  }

  @override
  Stream<void> recordChanges() {
    final controller = StreamController<void>.broadcast();
    final channel = _supabase.channel('daily_records_changes');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'daily_records',
          callback: (_) => controller.add(null),
        )
        .subscribe();
    controller.onCancel = () => _supabase.removeChannel(channel);
    return controller.stream;
  }

  @override
  Future<List<({DateTime day, String? groupId, String kind})>>
      spentPasses() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];
    final rows = await _supabase
        .from('streak_passes')
        .select('day, group_id, kind')
        .eq('user_id', userId);
    return [
      for (final r in rows)
        (
          day: DateTime.parse(r['day'] as String),
          groupId: r['group_id'] as String?,
          kind: r['kind'] as String? ?? 'personal',
        ),
    ];
  }

  @override
  Future<void> spendPass(DateTime day,
      {String? groupId, String kind = 'personal'}) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not signed in');

    final now = DateTime.now();
    // Personal: one a week. Group: one a month, per group.
    final since = groupId == null
        ? now.subtract(const Duration(days: 7))
        : DateTime(now.year, now.month, 1);

    var q = _supabase
        .from('streak_passes')
        .select('id')
        .eq('user_id', userId)
        .gte('created_at', since.toIso8601String());
    q = groupId == null ? q.isFilter('group_id', null) : q.eq('group_id', groupId);
    // Sleep passes have their own weekly allowance.
    q = q.eq('kind', kind);

    final recent = await q;
    if (recent.isNotEmpty) {
      throw Exception(groupId != null
          ? 'This group has used its pass this month'
          : (kind == 'sleep'
              ? 'No sleep pass left this week'
              : 'No personal pass left this week'));
    }

    await _supabase.from('streak_passes').insert({
      'user_id': userId,
      'group_id': groupId,
      'day': day.toIso8601String().split('T').first,
      'kind': kind,
    });
  }

  @override
  Future<List<({DateTime startedAt, DateTime? endedAt, String? reason})>>
      monitoringSessions() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return const [];
    try {
      final rows = await _supabase
          .from('monitoring_sessions')
          .select('started_at, ended_at, ended_reason')
          .eq('user_id', userId)
          .order('started_at', ascending: false)
          .limit(50);
      return [
        for (final r in rows)
          (
            startedAt: DateTime.parse(r['started_at'] as String),
            endedAt: r['ended_at'] == null
                ? null
                : DateTime.parse(r['ended_at'] as String),
            reason: r['ended_reason'] as String?,
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> logMonitoringOn() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      // Don't stack sessions if one is already open.
      final open = await _supabase
          .from('monitoring_sessions')
          .select('id')
          .eq('user_id', userId)
          .isFilter('ended_at', null)
          .limit(1);
      if (open.isNotEmpty) return;
      await _supabase.from('monitoring_sessions').insert({'user_id': userId});
    } catch (_) {}
  }

  @override
  Future<void> logMonitoringOff(String reason) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await _supabase
          .from('monitoring_sessions')
          .update({
            'ended_at': DateTime.now().toIso8601String(),
            'ended_reason': reason,
          })
          .eq('user_id', userId)
          .isFilter('ended_at', null);
    } catch (_) {}
  }

  @override
  Future<void> setAvatar(List<int> bytes, {String ext = 'jpg'}) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not signed in');

    // Folder must be the user id — the storage policy checks it.
    final path = userId + '/avatar.' + ext;
    await _supabase.storage.from('Avatars').uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: const FileOptions(upsert: true),
        );

    // Cache-bust so a replaced picture actually shows.
    final base = _supabase.storage.from('Avatars').getPublicUrl(path);
    final url = base + '?v=' + DateTime.now().millisecondsSinceEpoch.toString();
    await _supabase.from('profiles').update({'avatar_url': url}).eq('id', userId);
  }

  @override
  Future<void> setNames({
    String? firstName,
    String? lastName,
    String? nickname,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not signed in');

    final patch = <String, dynamic>{};
    if (firstName != null) patch['first_name'] = firstName;
    if (lastName != null) patch['last_name'] = lastName;
    if (nickname != null) patch['nickname'] = nickname.isEmpty ? null : nickname;
    // Keep display_name in step so the rest of the app is unchanged.
    if (firstName != null || lastName != null) {
      patch['display_name'] =
          [firstName ?? '', lastName ?? ''].where((x) => x.isNotEmpty).join(' ');
    }
    if (patch.isEmpty) return;
    await _supabase.from('profiles').update(patch).eq('id', userId);
  }

  @override
  Stream<bool> authChanges() => _supabase.auth.onAuthStateChange
      .map((event) => event.session != null);

  @override
  Future<Profile> signUpWithEmail(String email, String password) async {
    final AuthResponse res;
    try {
      res = await _supabase.auth.signUp(email: email, password: password);
    } on AuthException catch (e) {
      throw Exception(e.message);
    }
    if (res.session == null) {
      throw Exception(
          'Account created — confirm it from the email we sent, then sign in.');
    }
    return me();
  }

  @override
  String? get currentEmail => _supabase.auth.currentUser?.email;

  @override
  Future<void> proposeForGroup(String groupId, String userId) async {
    // 'proposed' waits on the moderator; only then does it become an invite.
    await _supabase.from('group_requests').upsert({
      'group_id': groupId,
      'user_id': userId,
      'status': 'proposed',
    }, onConflict: 'group_id,user_id');
  }

  @override
  Future<List<({String id, String groupId, String groupName, String proposedName})>>
      pendingProposals() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return const [];
    try {
      final rows = await _supabase
          .from('group_requests')
          .select('id, group_id, user_id, groups(name, admin_id)')
          .eq('status', 'proposed');

      final out = <({String id, String groupId, String groupName, String proposedName})>[];
      for (final r in rows) {
        final g = r['groups'] as Map<String, dynamic>?;
        if (g == null || g['admin_id'] != userId) continue;
        final p = await _supabase
            .from('profiles')
            .select('display_name')
            .eq('id', r['user_id'] as String)
            .maybeSingle();
        out.add((
          id: r['id'] as String,
          groupId: r['group_id'] as String,
          groupName: g['name'] as String? ?? 'a group',
          proposedName: (p?['display_name'] as String?) ?? 'Someone',
        ));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> decideProposal(String requestId, bool approve) async {
    await _supabase
        .from('group_requests')
        .update({'status': approve ? 'pending' : 'declined'})
        .eq('id', requestId);
  }

  @override
  Future<Map<String, Set<DateTime>>> groupRecoveredDays() async {
    try {
      final rows = await _supabase
          .from('streak_passes')
          .select('group_id, day')
          .not('group_id', 'is', null);

      final out = <String, Set<DateTime>>{};
      for (final r in rows) {
        final gid = r['group_id'] as String;
        out.putIfAbsent(gid, () => <DateTime>{})
            .add(dateOnly(DateTime.parse(r['day'] as String)));
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  @override
  Future<void> renameGroup(String groupId, String name) async {
    await _supabase.from('groups').update({'name': name}).eq('id', groupId);
  }
}
