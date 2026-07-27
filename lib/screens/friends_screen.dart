import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../data/repo_scope.dart';
import '../models/models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'connect_screen.dart';
import 'profile_screen.dart' show FriendRow, showShareSheet;

/// List of accountability friends, ranked by current streak.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  List<Profile> _friends = [];
  Profile? _me;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = RepoScope.of(context);
    final friends = await repo.friends();
    final me = await repo.me();
    friends.sort((a, b) => b.currentStreak.compareTo(a.currentStreak));
    if (!mounted) return;
    setState(() {
      _friends = friends;
      _me = me;
      _loading = false;
    });
  }

  Future<void> _openConnect() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ConnectScreen()));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Friends'),
        actions: [
          if (_me != null)
            IconButton(
              icon: const Icon(IconsaxPlusLinear.share, size: 22),
              onPressed: () => showShareSheet(context, _me!),
            ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(IconsaxPlusBold.profile_add, size: 20),
        label: Text('Connect', style: appFont(fontWeight: FontWeight.w700)),
        onPressed: _openConnect,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _load,
                child: _friends.isEmpty
                    ? _EmptyState(onConnect: _openConnect)
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                        children: [
                          for (var i = 0; i < _friends.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 26,
                                    child: Text(
                                      '${i + 1}',
                                      style: appFont(
                                        fontWeight: FontWeight.w700,
                                        color: context.cTextTer,
                                      ),
                                    ),
                                  ),
                                  Expanded(child: FriendRow(friend: _friends[i])),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onConnect});
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 90, 24, 32),
      children: [
        Center(
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(IconsaxPlusBold.profile_2user, size: 38, color: AppColors.primary),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'No friends yet',
          textAlign: TextAlign.center,
          style: appFont(fontSize: 22, fontWeight: FontWeight.w800, color: context.cText),
        ),
        const SizedBox(height: 8),
        Text(
          'Accountability works better together. Connect with a friend to '
          'share streaks and keep each other honest.',
          textAlign: TextAlign.center,
          style: appFont(
            fontSize: 15,
            color: context.cTextSec,
            fontWeight: FontWeight.w500,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 28),
        ModernButton(
          label: 'Connect with a friend',
          icon: IconsaxPlusBold.profile_add,
          onPressed: onConnect,
        ),
      ],
    );
  }
}
