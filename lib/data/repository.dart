import '../models/group.dart';
import '../models/models.dart';

/// Backend abstraction. Two implementations:
///  - LocalRepository  (in-memory demo — used when no Supabase keys)
///  - SupabaseRepository (real backend — used when configured)
///
/// Screens only ever talk to this interface.
abstract class Repository {
  /// Whether a user is signed in.
  bool get isSignedIn;

  /// Sign in with Google. Returns the signed-in profile.
  Future<Profile> signInWithGoogle();

  /// Email + password. Creates the account if it doesn't exist yet.
  Future<Profile> signInWithEmail(String email, String password) =>
      throw UnimplementedError('Email sign-in not supported by this backend');

  Future<void> signOut();

  /// Fires whenever a day's outcome changes for you or a friend. Backends
  /// without live updates return an empty stream and screens just refresh
  /// on resume instead.
  Stream<void> recordChanges() => const Stream.empty();

  /// The current user's full profile (with history).
  Future<Profile> me();

  /// The current user's accountability friends (with history).
  Future<List<Profile>> friends();

  /// Create a group. The caller becomes its admin. Returns the new group.
  Future<Group> createGroup(String name) =>
      throw UnimplementedError('Groups not supported by this backend');

  /// Add a friend to a group you administer.
  Future<void> addToGroup(String groupId, String userId) =>
      throw UnimplementedError('Groups not supported by this backend');

  /// Invite a friend to a group you administer.
  Future<void> inviteToGroup(String groupId, String userId) =>
      throw UnimplementedError('Groups not supported by this backend');

  /// Invitations waiting on your answer.
  Future<List<GroupInvite>> pendingInvites() async => const [];

  /// Accept or decline an invitation.
  Future<void> respondToInvite(String inviteId, bool accept) =>
      throw UnimplementedError('Groups not supported by this backend');

  /// Leave a group you're a member of.
  Future<void> leaveGroup(String groupId) =>
      throw UnimplementedError('Groups not supported by this backend');

  /// Delete a group you administer.
  Future<void> deleteGroup(String groupId) =>
      throw UnimplementedError('Groups not supported by this backend');

  /// Set the shared limit. Admin only.
  Future<void> setGroupLimit(String groupId, int minutes) =>
      throw UnimplementedError('Groups not supported by this backend');

  /// Groups the user belongs to. Backends without group support fall back to
  /// a single group holding everyone, so screens work either way.
  Future<List<Group>> groups() async {
    final all = [await me(), ...await friends()];
    return [
      Group(id: 'all', name: 'Friends', memberIds: all.map((p) => p.id).toList())
    ];
  }

  /// A single friend's profile with history.
  Future<Profile> friend(String id);

  /// One stretch where Screen Time monitoring was running.
  /// [endedAt] is null while it's still live.
  Future<List<({DateTime startedAt, DateTime? endedAt, String? reason})>>
      monitoringSessions() async => const [];

  /// Record that monitoring just started.
  Future<void> logMonitoringOn() async {}

  /// Close the open session. [reason] is 'manual' when the user switched it
  /// off, 'detected' when we found it already stopped.
  Future<void> logMonitoringOff(String reason) async {}

  /// Days you've recovered with a pass, personal and per-group.
  /// Keys are 'yyyy-MM-dd'; the value is the group id, or null if personal.
  Future<List<({DateTime day, String? groupId})>> spentPasses() async => const [];

  /// Spend a pass to recover [day]. Pass a group id to save that group's
  /// streak, or null for your own. Throws if none are left.
  Future<void> spendPass(DateTime day, {String? groupId}) =>
      throw UnimplementedError('Passes not supported by this backend');

  /// Record today's outcome (manual check-in on iOS, or an automated write).
  Future<void> checkIn({
    required DateTime day,
    required bool limitMet,
    int? usedMinutes,
    required int limitMinutes,
    String source = 'manual',
    bool partial = false,
  });

  /// Update the daily limit goal.
  Future<void> setDailyLimit(int minutes);

  /// Update the current user's display name.
  Future<void> setDisplayName(String name);

  /// Connect to another user via their share code.
  Future<Profile> connectWithCode(String code);

  /// Shareable link for the given code.
  String shareLink(String code);

  /// The social feed: your + your friends' milestones, newest first.
  Future<List<FeedItem>> feed();

  /// Toggle a "celebrate" reaction on a feed event. Returns the new state
  /// (true = now celebrated).
  Future<bool> toggleCelebrate(String eventId);

  /// Comments on a feed event, oldest first.
  Future<List<FeedComment>> comments(String eventId);

  /// Add a comment to a feed event.
  Future<void> addComment(String eventId, String body);

  /// Request to be matched with [targetId] for the upcoming week's friend
  /// streak. A one-sided request is enough to form the match.
  Future<void> selectFriend(String targetId);
}
