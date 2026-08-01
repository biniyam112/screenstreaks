import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:share_plus/share_plus.dart';

import '../app_events.dart';
import '../data/repo_scope.dart';
import '../data/repository.dart';
import '../models/models.dart';
import '../services/home_widget_service.dart';
import '../services/prefs.dart';
import '../services/usage_service.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/profile_view.dart';
import 'friend_detail_screen.dart';
import '../services/screen_time.dart';

/// The user's home page: streak, weekly chart, today check-in, share, friends.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.onSeeFriends, this.onProfile});

  final VoidCallback? onSeeFriends;
  final VoidCallback? onProfile;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with WidgetsBindingObserver {
  Profile? _me;
  List<Profile> _friends = [];
  bool _loading = true;
  bool _monitoring = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Refresh when the profile changes elsewhere (e.g. daily limit saved in
    // Settings), since this tab stays alive in the IndexedStack.
    profileRevision.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    profileRevision.removeListener(_load);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final repo = RepoScope.of(context);
    await _autoCheckInAndroid(repo);
    await _drainScreenTime(repo);
    try {
      final me = await repo.me();
      final friends = await repo.friends();
      final savedGoal = await Prefs.goalMinutes();
      final monitoring = await _ensureMonitoring(savedGoal);
      if (!mounted) return;
      setState(() {
        _monitoring = monitoring;
        _me = me.dailyLimitMinutes == savedGoal
            ? me
            : me.copyWith(dailyLimitMinutes: savedGoal);
        _friends = friends;
        _loading = false;
      });
      // Keep the home-screen widget in sync with the latest week/streak.
      HomeWidgetService.update(me);
    } catch (_) {
      // Only reachable on a first-ever launch with no connection and no cache;
      // otherwise the offline layer serves cached data. Show a retry instead
      // of an endless spinner.
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  /// Keeps the monitor watching the current goal — restarts it when the
  /// limit changed or monitoring was never started. Returns whether it's on.
  Future<bool> _ensureMonitoring(int goalMinutes) async {
    if (!ScreenTime.supported) return false;
    try {
      if (!await ScreenTime.hasSelection()) return false;
      final active = await ScreenTime.activeLimit();
      if (active == goalMinutes) return true;
      return await ScreenTime.startMonitoring(goalMinutes);
    } catch (_) {
      return false;
    }
  }

  /// Turns outcomes recorded by the iOS monitor extension into check-ins.
  /// Safe to re-run — checkIn replaces any record for the same day.
  Future<void> _drainScreenTime(Repository repo) async {
    if (!ScreenTime.supported) return;
    try {
      final pending = await ScreenTime.pendingOutcomes();
      if (pending.isEmpty) return;
      final limit = await Prefs.goalMinutes();
      final consumed = <String>[];
      for (final entry in pending.entries) {
        final day = ScreenTime.parseDay(entry.key);
        if (day == null) continue;
        await repo.checkIn(
          day: day,
          limitMet: entry.value,
          limitMinutes: limit,
          source: 'auto',
        );
        consumed.add(entry.key);
      }
      await ScreenTime.clearPending(consumed);
    } catch (_) {
      // Never let a drain failure block loading.
    }
  }

  /// Reads today's usage and records it. Uses the locally-stored goal (kept in
  /// sync by Settings) so it needs no network, and checkIn is local-first — so
  /// this is safe and lossless even fully offline.
  Future<void> _autoCheckInAndroid(Repository repo) async {
    if (!Platform.isAndroid) return;
    try {
      if (!await UsageService.hasPermission()) return;
      final limit = await Prefs.goalMinutes();
      final used = await UsageService.todayMinutes();
      await repo.checkIn(
        day: DateTime.now(),
        limitMet: used <= limit,
        usedMinutes: used,
        limitMinutes: limit,
        source: 'auto',
      );
    } catch (_) {
      // Never let a check-in failure block loading.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My streak'),
        actions: [
          if (_me != null)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: GestureDetector(
                onTap: widget.onProfile,
                child: Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: (_me!.avatarColor ?? AppColors.primary)
                        .withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    _me!.initials,
                    style: appFont(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: _me!.avatarColor ?? AppColors.primary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _me == null
            ? _LoadError(
                onRetry: () {
                  setState(() => _loading = true);
                  _load();
                },
              )
            : RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _load,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
                  child: ProfileView(
                    profile: _me!,
                    showIdentity: false,
                    showLiveUsage: Platform.isAndroid,
                    showProgress: false,
                    checkInControls: Platform.isAndroid || _monitoring
                        ? null
                        : _CheckInButtons(profile: _me!, onChanged: _load),
                  ),
                ),
              ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(IconsaxPlusLinear.cloud_cross, size: 44, color: context.cTextTer),
            const SizedBox(height: 16),
            Text(
              "Can't reach Undr",
              style: appFont(fontSize: 17, fontWeight: FontWeight.w800, color: context.cText),
            ),
            const SizedBox(height: 6),
            Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: appFont(fontSize: 13.5, fontWeight: FontWeight.w500, color: context.cTextSec),
            ),
            const SizedBox(height: 20),
            ModernButton(
              label: 'Retry',
              icon: IconsaxPlusLinear.refresh,
              expand: false,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckInButtons extends StatelessWidget {
  const _CheckInButtons({required this.profile, required this.onChanged});
  final Profile profile;
  final VoidCallback onChanged;

  Future<void> _log(BuildContext context, bool met) async {
    final repo = RepoScope.of(context);
    await repo.checkIn(
      day: DateTime.now(),
      limitMet: met,
      limitMinutes: profile.dailyLimitMinutes,
      source: 'manual',
    );
    HapticFeedback.selectionClick();
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RoundAction(
          icon: IconsaxPlusLinear.close_square,
          color: AppColors.danger,
          onTap: () => _log(context, false),
        ),
        const SizedBox(width: 8),
        _RoundAction(
          icon: IconsaxPlusLinear.tick_square,
          color: AppColors.primary,
          onTap: () => _log(context, true),
        ),
      ],
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, required this.color, required this.onTap});
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }
}

class _FriendsPreview extends StatelessWidget {
  const _FriendsPreview({required this.friends, this.onSeeAll});
  final List<Profile> friends;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Friends',
              style: appFont(fontSize: 17, fontWeight: FontWeight.w700, color: context.cText),
            ),
            const Spacer(),
            if (onSeeAll != null && friends.isNotEmpty)
              TextButton(
                onPressed: onSeeAll,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('See all'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (friends.isEmpty)
          _EmptyFriends(onShare: onSeeAll)
        else
          ...friends
              .take(3)
              .map(
                (f) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: FriendRow(friend: f),
                ),
              ),
      ],
    );
  }
}

class _EmptyFriends extends StatelessWidget {
  const _EmptyFriends({this.onShare});
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 18),
      decoration: BoxDecoration(
        color: context.cSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.cDivider),
      ),
      child: Column(
        children: [
          Icon(IconsaxPlusBold.profile_2user, size: 30, color: context.cTextTer),
          const SizedBox(height: 10),
          Text(
            'No friends yet',
            style: appFont(fontWeight: FontWeight.w700, fontSize: 15, color: context.cText),
          ),
          const SizedBox(height: 4),
          Text(
            'Share your code to keep each other accountable.',
            textAlign: TextAlign.center,
            style: appFont(fontSize: 13, color: context.cTextSec, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

/// Compact friend row with avatar, streak, and today's status chip.
class FriendRow extends StatelessWidget {
  const FriendRow({super.key, required this.friend});
  final Profile friend;

  @override
  Widget build(BuildContext context) {
    final color = friend.avatarColor ?? AppColors.primary;
    final todayStatus = friend.statusOn(DateTime.now());
    final streak = friend.currentStreak;

    return Material(
      color: context.cSurface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => FriendDetailScreen(friendId: friend.id))),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.cDivider),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  friend.initials,
                  style: appFont(fontWeight: FontWeight.w700, color: color),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      friend.displayName,
                      style: appFont(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: context.cText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          streak == 0 ? IconsaxPlusBold.moon : IconsaxPlusBold.flash_1,
                          size: 13,
                          color: streak == 0 ? context.cTextTer : AppColors.accent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          streak == 0 ? 'No streak' : '$streak day streak',
                          style: appFont(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: context.cTextSec,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _StatusDot(status: todayStatus),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});
  final DayStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      DayStatus.met => (AppColors.primary, 'Under'),
      DayStatus.missed => (AppColors.danger, 'Over'),
      DayStatus.none => (context.cTextTer, 'No log'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: appFont(fontSize: 12, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

/// Bottom sheet to share your invite link / code.
void showShareSheet(BuildContext context, Profile me) {
  final repo = RepoScope.of(context);
  final link = repo.shareLink(me.shareCode);
  final inviteMessage =
      "Let's keep each other under our screen-time limit on Undr 👀\n\n"
      'Connect with me: $link\n\n'
      'Or enter my code in the app: ${me.shareCode}';
  showModalBottomSheet(
    context: context,
    backgroundColor: context.cBg,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: sheetContext.cDivider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'Invite a friend',
            style: appFont(fontSize: 20, fontWeight: FontWeight.w800, color: sheetContext.cText),
          ),
          const SizedBox(height: 6),
          Text(
            'Share your code. When they enter it in Vero, '
            "you'll see each other's streaks.",
            style: appFont(
              fontSize: 13.5,
              color: sheetContext.cTextSec,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 22),
          // High-contrast code chip.
          Container(
            padding: const EdgeInsets.symmetric(vertical: 22),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
            ),
            child: Center(
              child: Text(
                me.shareCode,
                style: appMono(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 8,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Primary action: fire the OS share sheet straight into WhatsApp,
          // Messages, etc. with the link + code pre-written.
          ModernButton(
            label: 'Share invite',
            icon: IconsaxPlusBold.send_2,
            onPressed: () async {
              // Capture the anchor rect before awaiting (needed for the iPad
              // popover); keep the sheet open so the anchor stays valid.
              final box = sheetContext.findRenderObject() as RenderBox?;
              final origin = box != null ? box.localToGlobal(Offset.zero) & box.size : null;
              await SharePlus.instance.share(
                ShareParams(
                  text: inviteMessage,
                  subject: 'Join me on Vero',
                  sharePositionOrigin: origin,
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ModernButton(
                  label: 'Copy link',
                  icon: IconsaxPlusLinear.link_1,
                  outlined: true,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: link));
                    Navigator.pop(sheetContext);
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('Invite link copied')));
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ModernButton(
                  label: 'Copy code',
                  icon: IconsaxPlusBold.copy,
                  outlined: true,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: me.shareCode));
                    Navigator.pop(sheetContext);
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('Code copied')));
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
