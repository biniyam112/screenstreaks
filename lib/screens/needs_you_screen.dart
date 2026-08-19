import 'package:flutter/material.dart';

import '../data/repo_scope.dart';
import '../models/group.dart';
import '../models/models.dart';
import '../services/screen_time.dart';
import '../theme.dart';
import '../widgets.dart';

/// Everything waiting on the user, gathered from wherever it would otherwise
/// be scattered. Cards clear when acted on, so there's no read state.
class NeedsYouScreen extends StatefulWidget {
  const NeedsYouScreen({super.key});

  @override
  State<NeedsYouScreen> createState() => _NeedsYouScreenState();
}

class _NeedsYouScreenState extends State<NeedsYouScreen> {
  List<GroupInvite> _invites = const [];
  List<({String id, String groupId, String groupName, String proposedName})>
      _proposals = const [];
  DateTime? _sleepDay;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = RepoScope.of(context);
    try {
      final invites = await repo.pendingInvites();
      final proposals = await repo.pendingProposals();

      // A day the overnight watcher flagged that hasn't been recovered yet.
      DateTime? sleepDay;
      final flagged = await ScreenTime.sleepFlags();
      if (flagged.isNotEmpty) {
        final me = await repo.me();
        final spent = await repo.spentPasses();
        final claimed = spent.map((p) => dateOnly(p.day)).toSet();
        final weekAgo = DateTime.now().subtract(const Duration(days: 7));
        final usedSleep =
            spent.any((p) => p.kind == 'sleep' && p.day.isAfter(weekAgo));

        if (!usedSleep) {
          for (final key in flagged) {
            final day = ScreenTime.parseDay(key);
            if (day == null) continue;
            final d = dateOnly(day);
            if (claimed.contains(d)) continue;
            final record = me.byDay[d];
            if (record == null || record.limitMet || record.partial) continue;
            if (sleepDay == null || d.isAfter(sleepDay)) sleepDay = d;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _invites = invites;
        _proposals = proposals;
        _sleepDay = sleepDay;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _act(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final repo = RepoScope.of(context);
    final nothing = _invites.isEmpty && _proposals.isEmpty && _sleepDay == null;

    return Scaffold(
      appBar: AppBar(title: const Text('Needs you')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : nothing
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        "Nothing waiting on you.",
                        textAlign: TextAlign.center,
                        style: appFont(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: context.cTextSec,
                        ),
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      for (final p in _proposals) ...[
                        _Card(
                          accent: AppColors.warning,
                          title: 'Add ${p.proposedName} to ${p.groupName}?',
                          detail: 'Someone in the group suggested them.',
                          primary: 'Add',
                          secondary: 'No',
                          onPrimary: () => _act(
                              () => repo.decideProposal(p.id, true)),
                          onSecondary: () => _act(
                              () => repo.decideProposal(p.id, false)),
                        ),
                        const SizedBox(height: 12),
                      ],
                      for (final inv in _invites) ...[
                        _Card(
                          accent: AppColors.info,
                          title: 'Join ${inv.groupName}?',
                          detail: '${inv.invitedBy} invited you.',
                          primary: 'Join',
                          secondary: 'Later',
                          onPrimary: () => _act(
                              () => repo.respondToInvite(inv.id, true)),
                          onSecondary: () => _act(
                              () => repo.respondToInvite(inv.id, false)),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_sleepDay != null)
                        _Card(
                          accent: AppColors.accent,
                          title: 'Screen left on?',
                          detail:
                              'Your phone was in use for over an hour between '
                              '2 and 5am. Claim your sleep pass to recover '
                              'that day — one a week.',
                          primary: 'Claim it',
                          secondary: 'It was me',
                          onPrimary: () => _act(() =>
                              repo.spendPass(_sleepDay!, kind: 'sleep')),
                          onSecondary: () async {
                            if (mounted) setState(() => _sleepDay = null);
                          },
                        ),
                    ],
                  ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.accent,
    required this.title,
    required this.detail,
    required this.primary,
    required this.secondary,
    required this.onPrimary,
    required this.onSecondary,
  });

  final Color accent;
  final String title;
  final String detail;
  final String primary;
  final String secondary;
  final VoidCallback onPrimary;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: context.cSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: appFont(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: context.cText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            style: appFont(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: context.cTextSec,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: ModernButton(label: primary, onPressed: onPrimary)),
              const SizedBox(width: 10),
              TextButton(
                onPressed: onSecondary,
                child: Text(
                  secondary,
                  style: appFont(
                    fontWeight: FontWeight.w700,
                    color: context.cTextSec,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
