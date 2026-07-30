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

  Future<void> signOut();

  /// The current user's full profile (with history).
  Future<Profile> me();

  /// The current user's accountability friends (with history).
  Future<List<Profile>> friends();

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

  /// Record today's outcome (manual check-in on iOS, or an automated write).
  Future<void> checkIn({
    required DateTime day,
    required bool limitMet,
    int? usedMinutes,
    required int limitMinutes,
    String source = 'manual',
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
