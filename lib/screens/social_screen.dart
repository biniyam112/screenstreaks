import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../data/repo_scope.dart';
import '../models/models.dart';
import '../theme.dart';
import 'connect_screen.dart';
import 'friend_detail_screen.dart';
import 'groups_screen.dart';
import '../widgets/avatar.dart';

/// Friends as a row of faces, groups as cards beneath. One tab for everyone
/// you're accountable to.
class SocialScreen extends StatefulWidget {
  const SocialScreen({super.key});

  @override
  State<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<SocialScreen> {
  List<Profile> _friends = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final friends = await RepoScope.of(context).friends();
      friends.sort((a, b) => b.currentStreak.compareTo(a.currentStreak));
      if (!mounted) return;
      setState(() {
        _friends = friends;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _connect() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ConnectScreen()));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Social')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 84,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        for (final f in _friends) _FriendChip(friend: f),
                        _AddChip(onTap: _connect),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  // The groups list already handles invites, creation and
                  // its own loading, so it drops straight in.
                  const Expanded(child: GroupsScreen(embedded: true)),
                ],
              ),
      ),
    );
  }
}

class _FriendChip extends StatelessWidget {
  const _FriendChip({required this.friend});
  final Profile friend;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FriendDetailScreen(friendId: friend.id),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Avatar(profile: friend, size: 46),
            const SizedBox(height: 5),
            Text(
              '${friend.currentStreak} 🔥',
              style: appFont(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: context.cTextSec,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddChip extends StatelessWidget {
  const _AddChip({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: context.cDivider),
            ),
            child: Icon(IconsaxPlusLinear.add,
                size: 20, color: context.cTextTer),
          ),
          const SizedBox(height: 5),
          Text(
            'add',
            style: appFont(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: context.cTextTer,
            ),
          ),
        ],
      ),
    );
  }
}
