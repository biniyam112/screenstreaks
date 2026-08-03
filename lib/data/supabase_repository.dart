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
    try {
      // v7 API: authenticate() throws GoogleSignInException on failure.
      final googleUser = await _googleSignIn.authenticate();
      final googleName = googleUser.displayName;
      final idToken = googleUser.authentication.idToken;

      if (idToken == null) throw Exception('No ID token from Google');

      final response = await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      );

      final user = response.user;
      if (user == null) throw Exception('Failed to sign in');

      // Adopt the real Google name if the profile is still on its default.
      var profile = await me();
      if (profile.displayName.trim().isEmpty ||
          profile.displayName == 'Friend') {
        final meta = user.userMetadata;
        final name = (googleName ??
                meta?['full_name'] as String? ??
                meta?['name'] as String?)
            ?.trim();
        if (name != null && name.isNotEmpty) {
          await setDisplayName(name);
          profile = await me();
        }
      }
      return profile;
    } catch (e) {
      throw Exception('Google sign-in failed: $e');
    }
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

    return _profileFromJson(profile, records);
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

    return _profileFromJson(profile, records);
  }

  @override
  Future<void> checkIn({
    required DateTime day,
    required bool limitMet,
    int? usedMinutes,
    required int limitMinutes,
    String source = 'manual',
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

  Profile _profileFromJson(Map<String, dynamic> json, List<Map<String, dynamic>> records) {
    return Profile(
      id: json['id'] as String,
      displayName: json['display_name'] as String? ?? 'Friend',
      shareCode: json['share_code'] as String? ?? '',
      dailyLimitMinutes: json['daily_limit_minutes'] as int? ?? 120,
      records: records
          .map(
            (r) => DailyRecord(
              day: DateTime.parse(r['day'] as String),
              limitMet: r['limit_met'] as bool,
              limitMinutes: r['limit_minutes'] as int,
              usedMinutes: r['used_minutes'] as int?,
              source: r['source'] as String? ?? 'auto',
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
    AuthResponse res;
    try {
      res = await _supabase.auth
          .signInWithPassword(email: email, password: password);
    } on AuthException {
      // No account yet — create one, then use the session it returns.
      res = await _supabase.auth.signUp(email: email, password: password);
    }
    if (res.session == null) {
      throw Exception(
          'Account created — confirm it from the email we sent, then sign in.');
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
}
