import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../data/repo_scope.dart';
import '../models/models.dart';
import '../theme.dart';
import 'friend_detail_screen.dart';
import '../widgets/aurora_header.dart';

/// Social feed: your + your friends' streak milestones, with celebrate
/// reactions. Backed by Supabase (see supabase/feed.sql).
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  List<FeedItem> _items = [];
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await RepoScope.of(context).feed();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _celebrate(FeedItem item) async {
    final idx = _items.indexWhere((e) => e.id == item.id);
    if (idx < 0) return;
    final was = item.iCelebrated;
    HapticFeedback.lightImpact();
    // Optimistic toggle.
    setState(() {
      _items[idx] = item.copyWith(
        iCelebrated: !was,
        celebrateCount: item.celebrateCount + (was ? -1 : 1),
      );
    });
    try {
      final now = await RepoScope.of(context).toggleCelebrate(item.id);
      if (mounted && now == was) {
        // Server disagreed — reconcile to the truth.
        setState(() => _items[idx] = _items[idx].copyWith(iCelebrated: now));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _items[idx] = item); // revert
    }
  }

  /// Open a feed user's profile. No-op for your own events (that's you).
  void _openProfile(FeedItem item) {
    if (item.viewerIsOwner) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FriendDetailScreen(friendId: item.userId),
      ),
    );
  }

  void _openComments(FeedItem item) {
    final idx = _items.indexWhere((e) => e.id == item.id);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _CommentsSheet(
        eventId: item.id,
        onAdded: () {
          if (idx >= 0 && mounted) {
            setState(
              () => _items[idx] = _items[idx].copyWith(commentCount: _items[idx].commentCount + 1),
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const AuroraHeader(title: 'Feed', tint: AppColors.accent),
          Expanded(
            child: SafeArea(
              top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _failed
            ? _FeedMessage(
                icon: IconsaxPlusLinear.cloud_cross,
                title: "Couldn't load the feed",
                subtitle: 'Check your connection and try again.',
                onRetry: () {
                  setState(() => _loading = true);
                  _load();
                },
              )
            : RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _load,
                child: _items.isEmpty
                    ? const _FeedMessage(
                        icon: IconsaxPlusLinear.cup,
                        title: 'No activity yet',
                        subtitle:
                            'When you and your friends hit streak milestones, '
                            "they'll show up here to celebrate.",
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 20),
                        itemBuilder: (_, i) => _FeedCard(
                          item: _items[i],
                          onCelebrate: () => _celebrate(_items[i]),
                          onComment: () => _openComments(_items[i]),
                          onOpenProfile: () => _openProfile(_items[i]),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedCard extends StatelessWidget {
  const _FeedCard({
    required this.item,
    required this.onCelebrate,
    required this.onComment,
    required this.onOpenProfile,
  });
  final FeedItem item;
  final VoidCallback onCelebrate;
  final VoidCallback onComment;
  final VoidCallback onOpenProfile;

  static const _palette = [
    AppColors.primary,
    AppColors.info,
    AppColors.accent,
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
  ];

  static Color _colorFor(String id) => _palette[id.hashCode.abs() % _palette.length];

  Color get _color => _colorFor(item.userId);

  String get _title => switch (item.kind) {
    'streak' => 'Reached a ${item.milestone}-day streak!',
    'friend_streak' => 'Reached a ${item.milestone}-day friend streak!',
    'perfect_week' => 'A perfect week — seven for seven.',
    'comeback' => 'Back on it. ${item.milestone} days since the reset.',
    'personal_best' => 'New personal best: ${item.milestone} days.',
    'total_days' => '${item.milestone}th day under the limit, all time.',
    'rare_air' => 'Held a limit only ${item.milestone}% of people keep.',
    'weekend' => 'Held the line all weekend.',
    'improved' => 'Up ${item.milestone} points on last month.',
    'group_day' => 'Whole group stayed under on the same day.',
    _ => 'Hit a new milestone!',
  };

  String get _badge => switch (item.kind) {
    'perfect_week' => '\u2705',
    'comeback' => '\u267B\uFE0F',
    'personal_best' => '\uD83C\uDFC6',
    'total_days' => '\uD83D\uDCAF',
    'rare_air' => '\uD83D\uDC8E',
    'weekend' => '\uD83D\uDEE1\uFE0F',
    'improved' => '\uD83D\uDCC8',
    'group_day' => '\uD83E\uDD1D',
    _ => '\uD83D\uDD25',
  };

  Color get _badgeTint => switch (item.kind) {
    'perfect_week' => AppColors.primary,
    'personal_best' => AppColors.info,
    'rare_air' => const Color(0xFF8B5CF6),
    'weekend' => AppColors.info,
    'improved' => AppColors.primary,
    'group_day' => const Color(0xFFEC4899),
    _ => AppColors.accent,
  };

  /// Header line: for a friend streak it names both people ("You & Maya").
  String get _headline {
    if (!item.isFriendStreak) return item.displayName;
    final ownerLabel = item.viewerIsOwner ? 'You' : item.displayName;
    final viewerIsFriend = item.viewerIsParticipant && !item.viewerIsOwner;
    final friendLabel = viewerIsFriend ? 'You' : (item.friendName ?? 'Friend');
    return '$ownerLabel & $friendLabel';
  }

  String get _ago {
    final d = DateTime.now().difference(item.createdAt);
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    if (d.inDays < 7) return '${d.inDays}d';
    return '${(d.inDays / 7).floor()}w';
  }

  /// One avatar for a solo event, two overlapping avatars for a friend streak.
  Widget _leading(BuildContext context) {
    if (!item.isFriendStreak) {
      return _avatarCircle(context, item.initials, _color, 42);
    }
    final friendColor = _colorFor(item.friendId ?? item.id);
    return SizedBox(
      width: 60,
      height: 42,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 2,
            child: _avatarCircle(context, item.initials, _color, 38, ring: true),
          ),
          Positioned(
            left: 22,
            top: 2,
            child: _avatarCircle(context, item.friendInitials, friendColor, 38, ring: true),
          ),
        ],
      ),
    );
  }

  Widget _avatarCircle(
    BuildContext context,
    String initials,
    Color color,
    double size, {
    bool ring = false,
  }) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // Opaque fill for the overlapping (ring) case so the back avatar
        // doesn't bleed through the front one.
        color: ring
            ? Color.alphaBlend(color.withValues(alpha: 0.18), context.cSurface)
            : color.withValues(alpha: 0.16),
        shape: BoxShape.circle,
        border: ring ? Border.all(color: context.cSurface, width: 2) : null,
      ),
      child: Text(
        initials,
        style: appFont(fontWeight: FontWeight.w700, color: color, fontSize: size * 0.33),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.cSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: context.cDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: item.viewerIsOwner ? null : onOpenProfile,
                  child: Row(
                    children: [
                      _leading(context),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _headline,
                              style: appFont(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: context.cText,
                              ),
                            ),
                            Text(
                              _ago,
                              style: appFont(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: context.cTextTer,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _badgeTint.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Text(_badge, style: const TextStyle(fontSize: 22)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _title,
            style: appFont(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              height: 1.25,
              color: context.cText,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _CelebrateButton(celebrated: item.iCelebrated, onTap: onCelebrate),
              const Spacer(),
              if (item.celebrateCount > 0) ...[
                const Text('🎉', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 5),
                Text(
                  '${item.celebrateCount}',
                  style: appFont(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: context.cTextSec,
                  ),
                ),
              ],
              if (item.commentCount > 0) ...[
                const SizedBox(width: 14),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onComment,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(IconsaxPlusLinear.message,
                          size: 15, color: context.cTextSec),
                      const SizedBox(width: 5),
                      Text(
                        '${item.commentCount}',
                        style: appFont(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: context.cTextSec,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: context.cDivider),
          const SizedBox(height: 10),
          InkWell(
            onTap: onComment,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(IconsaxPlusLinear.message_text, size: 17, color: context.cTextTer),
                  const SizedBox(width: 8),
                  Text(
                    'Add a comment…',
                    style: appFont(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: context.cTextTer,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CelebrateButton extends StatelessWidget {
  const _CelebrateButton({required this.celebrated, required this.onTap});
  final bool celebrated;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.primary;
    return Material(
      color: celebrated ? color.withValues(alpha: 0.14) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: celebrated ? color : context.cDivider, width: 1.4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🎉', style: TextStyle(fontSize: 15)),
              const SizedBox(width: 8),
              Text(
                celebrated ? 'CELEBRATED' : 'CELEBRATE',
                style: appFont(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: celebrated ? color : context.cTextSec,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommentsSheet extends StatefulWidget {
  const _CommentsSheet({required this.eventId, required this.onAdded});
  final String eventId;
  final VoidCallback onAdded;

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _controller = TextEditingController();
  List<FeedComment> _comments = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  // Accumulated downward pull while the list is at its top; past a threshold
  // (on release) we close the sheet. Lets a short, non-scrollable list be
  // swiped away, while a long list still scrolls normally.
  double _pullDown = 0;

  bool _onListScroll(ScrollNotification n) {
    if (n is ScrollStartNotification) {
      _pullDown = 0;
    } else if (n is OverscrollNotification && n.overscroll < 0) {
      _pullDown += -n.overscroll;
    } else if (n is ScrollUpdateNotification &&
        n.metrics.pixels <= n.metrics.minScrollExtent &&
        (n.scrollDelta ?? 0) < 0) {
      _pullDown += -(n.scrollDelta ?? 0);
    } else if (n is ScrollEndNotification) {
      if (_pullDown > 90) {
        _pullDown = 0;
        Navigator.of(context).maybePop();
      }
      _pullDown = 0;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final c = await RepoScope.of(context).comments(widget.eventId);
      if (!mounted) return;
      setState(() {
        _comments = c;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await RepoScope.of(context).addComment(widget.eventId, text);
      _controller.clear();
      // Show it immediately; _load() then reconciles with the server (which
      // fills in the real author name / id).
      setState(
        () => _comments = [
          ..._comments,
          FeedComment(
            id: 'temp-${DateTime.now().microsecondsSinceEpoch}',
            userId: 'me',
            displayName: 'You',
            body: text,
            createdAt: DateTime.now(),
          ),
        ],
      );
      widget.onAdded();
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', '').trim());
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.cDivider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Comments',
              style: appFont(fontSize: 16, fontWeight: FontWeight.w800, color: context.cText),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _comments.isEmpty
                  ? NotificationListener<ScrollNotification>(
                      onNotification: _onListScroll,
                      child: ListView(
                        // Scrollable so a downward pull dismisses the sheet.
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 60),
                            child: Text(
                              'No comments yet. Be the first!',
                              textAlign: TextAlign.center,
                              style: appFont(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: context.cTextTer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : NotificationListener<ScrollNotification>(
                      onNotification: _onListScroll,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                        itemCount: _comments.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 16),
                        itemBuilder: (_, i) =>
                            _CommentTile(comment: _comments[i]),
                      ),
                    ),
            ),
            if (_error != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _error!,
                  style: appFont(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.danger,
                  ),
                ),
              ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: context.cDivider)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 300,
                      textCapitalization: TextCapitalization.sentences,
                      style: appFont(fontSize: 14, color: context.cText),
                      decoration: InputDecoration(
                        hintText: 'Add a comment…',
                        counterText: '',
                        hintStyle: appFont(
                          fontSize: 14,
                          color: context.cTextTer,
                          fontWeight: FontWeight.w500,
                        ),
                        filled: true,
                        fillColor: context.cSurface,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: context.cDivider),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: context.cDivider),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(IconsaxPlusBold.send_2, color: AppColors.primary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});
  final FeedComment comment;

  String get _ago {
    final d = DateTime.now().difference(comment.createdAt);
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    if (d.inDays < 7) return '${d.inDays}d';
    return '${(d.inDays / 7).floor()}w';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: Text(
            comment.initials,
            style: appFont(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    comment.displayName,
                    style: appFont(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: context.cText,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _ago,
                    style: appFont(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: context.cTextTer,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                comment.body,
                style: appFont(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                  color: context.cTextSec,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FeedMessage extends StatelessWidget {
  const _FeedMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 100, 28, 32),
      children: [
        Icon(icon, size: 46, color: context.cTextTer),
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: appFont(fontSize: 18, fontWeight: FontWeight.w800, color: context.cText),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: appFont(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.45,
            color: context.cTextSec,
          ),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 22),
          Center(
            child: TextButton.icon(
              onPressed: onRetry,
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
              icon: const Icon(IconsaxPlusLinear.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ),
        ],
      ],
    );
  }
}
