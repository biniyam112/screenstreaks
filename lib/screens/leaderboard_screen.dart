import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import '../data/repo_scope.dart';
import '../models/group_streak.dart';
import '../models/models.dart';
import '../services/prefs.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/avatar.dart';

String _fmtLimit(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

/// Your group: the shared streak on top, individual standings below.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  /// Days the group recovered with its weekly pass — they count as held.
  Set<DateTime> _recovered = const {};
  List<Profile> _people = const [];
  int? _groupLimit;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = RepoScope.of(context);
    try {
      final results = await Future.wait([repo.me(), repo.friends()]);
      final me = results[0] as Profile;
      final friends = results[1] as List<Profile>;
      final savedLimit = await Prefs.groupLimitMinutes();

      final all = [me, ...friends]
        ..sort((a, b) {
          final byStreak = b.currentStreak.compareTo(a.currentStreak);
          if (byStreak != 0) return byStreak;
          return b.longestStreak.compareTo(a.longestStreak);
        });

      if (!mounted) return;
      setState(() {
        _people = all;
        _groupLimit = savedLimit;
        _loading = false;
        _error = null;
      });
      _pushToWidget(all, savedLimit);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load the leaderboard.';
      });
    }
  }

  /// Mirror the board and the group streak into the home-screen widget.
  Future<void> _pushToWidget(List<Profile> people, int? limit) async {
    try {
      await HomeWidget.setAppGroupId('group.com.screenstreaks.screenstreaks');
      final payload = people
          .take(5)
          .map((p) => {
                'name': p.displayName,
                'streak': p.currentStreak,
                'isMe': p.isMe,
              })
          .toList();
      await HomeWidget.saveWidgetData<String>('leaderboard', jsonEncode(payload));
      await HomeWidget.saveWidgetData<String>(
        'group',
        jsonEncode({
          'streak': limit == null
              ? 0
              : groupStreak(people, limit, recovered: _recovered),
          'limit': limit ?? 0,
        }),
      );
      await HomeWidget.updateWidget(iOSName: 'StreaksWidget');
    } catch (_) {
      // Widget sync is best-effort; never break the screen over it.
    }
  }

  Future<void> _editGroupLimit() async {
    final floor = minGroupLimit(_people);
    var value = _groupLimit ?? (floor + 30);
    if (value < floor) value = floor;

    final saved = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          final tooLow = value < floor;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Group limit',
                  style: appFont(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: context.cText,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'At least ${_fmtLimit(floor)} — the highest personal limit in '
                  'the group. Everyone has to stay under it to keep the streak.',
                  textAlign: TextAlign.center,
                  style: appFont(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: context.cTextSec,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 26),
                GoalPicker(
                  minutes: value,
                  onChanged: (v) => setSheet(() => value = v),
                ),
                const SizedBox(height: 22),
                ModernButton(
                  label: tooLow ? 'Too low' : 'Save',
                  onPressed: tooLow
                      ? null
                      : () => Navigator.pop(sheetContext, value),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (saved == null) return;
    await Prefs.setGroupLimitMinutes(saved);
    if (!mounted) return;
    setState(() => _groupLimit = saved);
    _pushToWidget(_people, saved);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _buildBody(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Center(
            child: Text(
              _error!,
              style: appFont(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: context.cTextSec,
              ),
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      itemCount: _people.length + 2,
      separatorBuilder: (_, index) => SizedBox(height: index <= 1 ? 16 : 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your group',
                style: appFont(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: context.cText,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${_people.length} people · ranked by current streak',
                style: appFont(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: context.cTextSec,
                ),
              ),
            ],
          );
        }

        if (index == 1) {
          return _GroupCard(
            recovered: _recovered,
            members: _people,
            limit: _groupLimit,
            onEdit: _editGroupLimit,
          );
        }

        final rank = index - 1;
        return _LeaderRow(person: _people[index - 2], rank: rank);
      },
    );
  }
}

/// The shared streak: everyone under the group limit, every day.
class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.members,
    required this.limit,
    required this.onEdit,
    this.recovered = const {},
  });

  final List<Profile> members;
  final int? limit;
  final VoidCallback onEdit;

  /// Days the group recovered with its weekly pass.
  final Set<DateTime> recovered;

  @override
  Widget build(BuildContext context) {
    if (limit == null) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: context.cSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.cDivider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No group limit yet',
              style: appFont(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: context.cText,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Pick a limit everyone can live with. Stay under it together and '
              'the group streak starts counting.',
              style: appFont(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: context.cTextSec,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            ModernButton(label: 'Set group limit', onPressed: onEdit),
          ],
        ),
      );
    }

    final l = limit!;
    final streak = groupStreak(members, l, recovered: recovered);
    final today = dateOnly(DateTime.now());
    final loggedToday = members.any((m) => m.byDay[today] != null);
    final over = membersOverOn(members, today, l);

    final String status;
    if (!loggedToday) {
      status = 'Waiting on today';
    } else if (over.isEmpty) {
      status = 'Everyone under today';
    } else if (over.length == 1) {
      status = '${over.first.listName} is over today';
    } else {
      status = '${over.length} people over today';
    }

    final good = loggedToday && over.isEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary, width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'GROUP STREAK',
                style: appFont(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: context.cTextSec,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onEdit,
                child: Text(
                  'Change',
                  style: appFont(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '$streak',
                style: appFont(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  color: context.cText,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.local_fire_department,
                size: 30,
                color: streak > 0 ? AppColors.accent : context.cTextTer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  streak == 1 ? 'day together' : 'days together',
                  style: appFont(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.cTextSec,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                good ? Icons.check_circle : Icons.schedule,
                size: 15,
                color: good ? AppColors.primary : context.cTextTer,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '$status · everyone under ${_fmtLimit(l)}',
                  style: appFont(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
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

class _LeaderRow extends StatelessWidget {
  const _LeaderRow({required this.person, required this.rank});

  final Profile person;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final isMe = person.isMe;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: isMe
            ? AppColors.primary.withValues(alpha: 0.10)
            : context.cSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isMe ? AppColors.primary : context.cDivider,
          width: isMe ? 1.4 : 1,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              '$rank',
              textAlign: TextAlign.center,
              style: appFont(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: rank <= 3 ? AppColors.primary : context.cTextTer,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Avatar(profile: person, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  person.listName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: appFont(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: context.cText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Limit ${_fmtLimit(person.dailyLimitMinutes)} · '
                  'best ${person.longestStreak}',
                  style: appFont(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: context.cTextSec,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Row(
            children: [
              Text(
                '${person.currentStreak}',
                style: appFont(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: context.cText,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.local_fire_department,
                size: 20,
                color: person.currentStreak > 0
                    ? AppColors.accent
                    : context.cTextTer,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
