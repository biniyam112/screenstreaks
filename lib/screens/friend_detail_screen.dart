import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../data/repo_scope.dart';
import '../models/models.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/profile_view.dart';
import '../widgets/streak_compare.dart';
import 'history_screen.dart';

/// A friend's full profile: their limit, weekly strip, progress grid, and a
/// side-by-side day-by-day comparison against you.
class FriendDetailScreen extends StatefulWidget {
  const FriendDetailScreen({super.key, required this.friendId});

  final String friendId;

  @override
  State<FriendDetailScreen> createState() => _FriendDetailScreenState();
}

class _FriendDetailScreenState extends State<FriendDetailScreen> {
  Profile? _friend;
  Profile? _me;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = RepoScope.of(context);
    final friend = await repo.friend(widget.friendId);
    final me = await repo.me();
    if (mounted) {
      setState(() {
        _friend = friend;
        _me = me;
      });
    }
  }

  Future<void> _match() async {
    final friend = _friend;
    if (friend == null) return;
    try {
      await RepoScope.of(context).selectFriend(friend.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "You'll be matched with ${friend.displayName.split(' ').first} "
            'next week 🤝',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _friend != null && _me != null;
    return Scaffold(
      appBar: AppBar(title: Text(_friend?.displayName ?? 'Friend')),
      body: SafeArea(
        child: !ready
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ProfileView(
                      profile: _friend!,
                      showIdentity: false,
                      // Match the home tab: month calendar, no week strip.
                      // Passes and the tracking pill stay personal.
                      showWeek: false,
                      showProgress: false,
                      onOpenHistory: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => HistoryScreen(profile: _friend!),
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    _MatchCard(name: _friend!.displayName.split(' ').first, onMatch: _match),
                    const SizedBox(height: 12),
                    _CompareCard(me: _me!, friend: _friend!),
                  ],
                ),
              ),
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.name, required this.onMatch});
  final String name;
  final VoidCallback onMatch;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.cSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.cDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🤝', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text(
                'Friend streak',
                style: appFont(fontSize: 15, fontWeight: FontWeight.w700, color: context.cText),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Team up with $name next week. If you both stay under your limits, '
            'your friend streak grows together.',
            style: appFont(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              height: 1.4,
              color: context.cTextSec,
            ),
          ),
          const SizedBox(height: 14),
          ModernButton(
            label: 'Match with $name next week',
            icon: IconsaxPlusBold.profile_2user,
            onPressed: onMatch,
          ),
        ],
      ),
    );
  }
}

class _CompareCard extends StatelessWidget {
  const _CompareCard({required this.me, required this.friend});
  final Profile me;
  final Profile friend;

  @override
  Widget build(BuildContext context) {
    final name = friend.displayName.split(' ').first;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.cSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.cDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You vs $name',
            style: appFont(fontSize: 15, fontWeight: FontWeight.w700, color: context.cText),
          ),
          const SizedBox(height: 4),
          Text(
            'Last 30 days — green means under the limit, red means over.',
            style: appFont(fontSize: 12.5, fontWeight: FontWeight.w500, color: context.cTextSec),
          ),
          const SizedBox(height: 18),
          StreakCompare(me: me, friend: friend),
        ],
      ),
    );
  }
}
