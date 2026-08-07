import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../data/repo_scope.dart';
import '../models/group.dart';
import '../models/group_streak.dart';
import '../models/models.dart';
import '../services/prefs.dart';
import '../theme.dart';
import '../widgets.dart';
import 'friend_detail_screen.dart';
import '../widgets/aurora_header.dart';

String fmtLimit(int m) {
  final h = m ~/ 60, r = m % 60;
  if (h == 0) return '${r}m';
  return r == 0 ? '${h}h' : '${h}h ${r}m';
}

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen>
    with WidgetsBindingObserver {
  StreamSubscription<void>? _records;
  List<Group> _groups = const [];
  Map<String, Profile> _people = const {};
  Map<String, int?> _limits = const {};
  String? _pinned;
  List<GroupInvite> _invites = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _records = RepoScope.of(context).recordChanges().listen((_) {
        if (mounted) _load();
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _records = RepoScope.of(context).recordChanges().listen((_) {
        if (mounted) _load();
      });
    });
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _records?.cancel();
    _records?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final repo = RepoScope.of(context);
    try {
      final me = await repo.me();
      final friends = await repo.friends();
      final groups = await repo.groups();
      final invites = await repo.pendingInvites();
      final people = {me.id: me, for (final f in friends) f.id: f};
      final limits = {for (final g in groups) g.id: g.limitMinutes};
      final pinned = await Prefs.widgetGroupId() ??
          (groups.isNotEmpty ? groups.first.id : null);
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _invites = invites;
        _people = people;
        _limits = limits;
        _pinned = pinned;
        _loading = false;
      });
      _pushWidget();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Profile> membersOf(Group g) {
    return g.memberIds.map((id) => _people[id]).whereType<Profile>().toList()
      ..sort((a, b) {
        final s = b.currentStreak.compareTo(a.currentStreak);
        return s != 0 ? s : b.longestStreak.compareTo(a.longestStreak);
      });
  }

  Future<void> _pushWidget() async {
    final id = _pinned;
    if (id == null) return;
    Group? g;
    for (final x in _groups) {
      if (x.id == id) g = x;
    }
    if (g == null) return;
    try {
      final members = membersOf(g);
      final limit = _limits[id];
      await HomeWidget.setAppGroupId('group.com.screenstreaks.screenstreaks');
      await HomeWidget.saveWidgetData<String>(
        'leaderboard',
        jsonEncode(members
            .take(6)
            .map((p) => {
                  'name': p.displayName,
                  'streak': p.currentStreak,
                  'isMe': p.isMe,
                  'limit': p.dailyLimitMinutes,
                })
            .toList()),
      );
      await HomeWidget.saveWidgetData<String>(
        'group',
        jsonEncode({
          'name': g.name,
          'streak': limit == null ? 0 : groupStreak(members, limit),
          'limit': limit ?? 0,
        }),
      );
      await HomeWidget.updateWidget(iOSName: 'StreaksWidget');
    } catch (_) {}
  }

  Future<void> _pin(Group g) async {
    await Prefs.setWidgetGroupId(g.id);
    if (!mounted) return;
    setState(() => _pinned = g.id);
    await _pushWidget();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Widget now shows ${g.name}')),
    );
  }

  Future<void> _respond(GroupInvite invite, bool accept) async {
    try {
      await RepoScope.of(context).respondToInvite(invite.id, accept);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
      return;
    }
    await _load();
  }

  Future<void> _createGroup() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.cSurface,
        title: Text(
          'New group',
          style: appFont(fontWeight: FontWeight.w700, color: dialogContext.cText),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          maxLength: 30,
          style: appFont(color: dialogContext.cText, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: 'e.g. Work, Family, Roommates',
            counterText: '',
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: dialogContext.cDivider),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
            ),
          ),
          onSubmitted: (v) => Navigator.pop(dialogContext, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              'Cancel',
              style: appFont(
                  color: dialogContext.cTextSec, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: Text(
              'Create',
              style: appFont(
                  color: AppColors.primary, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;
    if (!mounted) return;
    try {
      await RepoScope.of(context).createGroup(name);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _open(Group g) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GroupDetailScreen(group: g, members: membersOf(g)),
    ));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          AuroraHeader(
            title: 'Groups',
            tint: AppColors.info,
            trailing: GestureDetector(
              onTap: _createGroup,
              child: Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.22),
                  shape: BoxShape.circle,
                ),
                child: const Icon(IconsaxPlusLinear.add,
                    size: 18, color: AppColors.info),
              ),
            ),
          ),
          Expanded(
            child: SafeArea(
              top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _groups.isEmpty && _invites.isEmpty
                ? _EmptyGroups(onCreate: _createGroup)
                : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                itemCount: _groups.length + _invites.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  if (i < _invites.length) {
                    final inv = _invites[i];
                    return _InviteCard(
                      invite: inv,
                      onAccept: () => _respond(inv, true),
                      onDecline: () => _respond(inv, false),
                    );
                  }
                  final g = _groups[i - _invites.length];
                  return Dismissible(
                    key: ValueKey(g.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 22),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(IconsaxPlusLinear.trash,
                          color: AppColors.danger),
                    ),
                    confirmDismiss: (_) => showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        backgroundColor: c.cSurface,
                        title: Text('Delete ${g.name}?',
                            style: appFont(
                                fontWeight: FontWeight.w700, color: c.cText)),
                        content: Text(
                          'This removes the group for everyone in it.',
                          style: appFont(
                              fontWeight: FontWeight.w500, color: c.cTextSec),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c, false),
                            child: Text('Cancel',
                                style: appFont(
                                    color: c.cTextSec,
                                    fontWeight: FontWeight.w600)),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(c, true),
                            child: Text('Delete',
                                style: appFont(
                                    color: AppColors.danger,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ),
                    onDismissed: (_) async {
                      try {
                        await RepoScope.of(context).deleteGroup(g.id);
                      } catch (_) {}
                      await _load();
                    },
                    child: GroupCard(
                    group: g,
                    members: membersOf(g),
                    limit: _limits[g.id],
                    pinned: _pinned == g.id,
                    onTap: () => _open(g),
                    onPin: () => _pin(g),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({
    required this.invite,
    required this.onAccept,
    required this.onDecline,
  });

  final GroupInvite invite;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.info, width: 1.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Join ${invite.groupName}?',
            style: appFont(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: context.cText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${invite.invitedBy} invited you.',
            style: appFont(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: context.cTextSec,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: ModernButton(label: 'Join', onPressed: onAccept)),
              const SizedBox(width: 10),
              TextButton(
                onPressed: onDecline,
                child: Text(
                  'Decline',
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

class _EmptyGroups extends StatelessWidget {
  const _EmptyGroups({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 90, 28, 32),
      children: [
        Icon(IconsaxPlusLinear.people, size: 46, color: context.cTextTer),
        const SizedBox(height: 18),
        Text(
          'No groups yet',
          textAlign: TextAlign.center,
          style: appFont(
              fontSize: 18, fontWeight: FontWeight.w800, color: context.cText),
        ),
        const SizedBox(height: 8),
        Text(
          'Make a group with friends, agree a limit everyone can live with, '
          'and keep the streak alive together.',
          textAlign: TextAlign.center,
          style: appFont(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.45,
            color: context.cTextSec,
          ),
        ),
        const SizedBox(height: 22),
        ModernButton(label: 'Create a group', onPressed: onCreate),
      ],
    );
  }
}

class GroupCard extends StatelessWidget {
  const GroupCard({
    super.key,
    required this.group,
    required this.members,
    required this.limit,
    required this.pinned,
    required this.onTap,
    required this.onPin,
  });

  final Group group;
  final List<Profile> members;
  final int? limit;
  final bool pinned;
  final VoidCallback onTap;
  final VoidCallback onPin;

  @override
  Widget build(BuildContext context) {
    final l = limit;
    final streak = l == null ? 0 : groupStreak(members, l);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: BoxDecoration(
          color: context.cSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: pinned ? AppColors.primary : context.cDivider,
            width: pinned ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    group.name,
                    style: appFont(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: context.cText,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Show on widget',
                  icon: Icon(
                    pinned ? IconsaxPlusBold.star : IconsaxPlusLinear.star,
                    size: 20,
                    color: pinned ? AppColors.primary : context.cTextTer,
                  ),
                  onPressed: onPin,
                ),
              ],
            ),
            Row(
              children: [
                Text(
                  '$streak',
                  style: appFont(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: context.cText,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 5),
                Icon(
                  Icons.local_fire_department,
                  size: 22,
                  color: streak > 0 ? AppColors.accent : context.cTextTer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l == null
                        ? 'No limit set yet'
                        : 'days · everyone under ${fmtLimit(l)}',
                    style: appFont(
                      fontSize: 13,
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
                for (final m in members.take(6))
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: (m.avatarColor ?? AppColors.primary)
                            .withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        m.initials,
                        style: appFont(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: m.avatarColor ?? AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
                Text(
                  '${members.length} people',
                  style: appFont(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: context.cTextTer,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class GroupDetailScreen extends StatefulWidget {
  const GroupDetailScreen({
    super.key,
    required this.group,
    required this.members,
  });

  final Group group;
  final List<Profile> members;

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  int? _limit;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _limit = widget.group.limitMinutes;
    _loading = false;
  }

  Future<void> _leave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: c.cSurface,
        title: Text('Leave ${widget.group.name}?',
            style: appFont(fontWeight: FontWeight.w700, color: c.cText)),
        content: Text(
          "You'll stop counting toward this group's streak.",
          style: appFont(fontWeight: FontWeight.w500, color: c.cTextSec),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text('Cancel',
                style: appFont(
                    color: c.cTextSec, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text('Leave',
                style: appFont(
                    color: AppColors.danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await RepoScope.of(context).leaveGroup(widget.group.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _addMembers() async {
    final repo = RepoScope.of(context);
    final friends = await repo.friends();
    if (!mounted) return;

    final existing = widget.members.map((m) => m.id).toSet();
    final candidates =
        friends.where((f) => !existing.contains(f.id)).toList();

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Everyone you know is already in.')),
      );
      return;
    }

    final picked = <String>{};
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Invite to ${widget.group.name}',
                style: appFont(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: context.cText,
                ),
              ),
              const SizedBox(height: 16),
              ...candidates.map((f) {
                final on = picked.contains(f.id);
                return CheckboxListTile(
                  value: on,
                  activeColor: AppColors.primary,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    f.displayName,
                    style: appFont(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: context.cText,
                    ),
                  ),
                  subtitle: Text(
                    'Limit ${fmtLimit(f.dailyLimitMinutes)}',
                    style: appFont(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: context.cTextSec,
                    ),
                  ),
                  onChanged: (v) => setSheet(() {
                    if (v == true) {
                      picked.add(f.id);
                    } else {
                      picked.remove(f.id);
                    }
                  }),
                );
              }),
              const SizedBox(height: 18),
              ModernButton(
                label: picked.isEmpty
                    ? 'Select someone'
                    : 'Invite ${picked.length}',
                onPressed: picked.isEmpty
                    ? null
                    : () => Navigator.pop(sheetContext, true),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true || picked.isEmpty) return;
    if (!mounted) return;
    try {
      for (final id in picked) {
        await repo.inviteToGroup(widget.group.id, id);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _editLimit() async {
    final floor = minGroupLimit(widget.members);
    var value = _limit ?? (floor + 30);
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
                  '${widget.group.name} limit',
                  style: appFont(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: context.cText,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'At least ${fmtLimit(floor)} — the highest personal limit '
                  'here. Everyone stays under it to keep the streak.',
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
                  onPressed:
                      tooLow ? null : () => Navigator.pop(sheetContext, value),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (saved == null) return;
    if (!mounted) return;
    await RepoScope.of(context).setGroupLimit(widget.group.id, saved);
    if (!mounted) return;
    setState(() => _limit = saved);
  }

  @override
  Widget build(BuildContext context) {
    final members = widget.members;
    final l = _limit;
    final streak = l == null ? 0 : groupStreak(members, l);
    final over = l == null
        ? const <Profile>[]
        : membersOverOn(members, dateOnly(DateTime.now()), l);

    return Scaffold(
      body: Column(
        children: [
          AuroraHeader(
            title: widget.group.name,
            tint: AppColors.info,
            trailing: PopupMenuButton<String>(
              icon: Icon(IconsaxPlusLinear.more, color: context.cText),
              color: context.cSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              onSelected: (v) {
                if (v == 'limit') _editLimit();
                if (v == 'add') _addMembers();
                if (v == 'leave') _leave();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'limit',
                  child: Text(l == null ? 'Set limit' : 'Change limit',
                      style: appFont(color: context.cText)),
                ),
                PopupMenuItem(
                  value: 'add',
                  child: Text('Add members',
                      style: appFont(color: context.cText)),
                ),
                PopupMenuItem(
                  value: 'leave',
                  child: Text('Leave group',
                      style: appFont(color: AppColors.danger)),
                ),
              ],
            ),
          ),
          Expanded(
            child: SafeArea(
              top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                itemCount: members.length + 1,
                separatorBuilder: (_, i) => SizedBox(height: i == 0 ? 18 : 10),
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return _Banner(
                      streak: streak,
                      limit: l,
                      over: over,
                      onSet: _editLimit,
                    );
                  }
                  return _MemberRow(person: members[i - 1], rank: i);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.streak,
    required this.limit,
    required this.over,
    required this.onSet,
  });

  final int streak;
  final int? limit;
  final List<Profile> over;
  final VoidCallback onSet;

  @override
  Widget build(BuildContext context) {
    final l = limit;
    if (l == null) {
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
              'Pick a limit everyone can live with. Stay under it together '
              'and the group streak starts counting.',
              style: appFont(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: context.cTextSec,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            ModernButton(label: 'Set group limit', onPressed: onSet),
          ],
        ),
      );
    }

    final status = over.isEmpty
        ? 'Everyone under today'
        : over.length == 1
            ? '${over.first.displayName} is over today'
            : '${over.length} people over today';

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
          Text(
            'GROUP STREAK',
            style: appFont(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: context.cTextSec,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '$streak',
                style: appFont(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  color: context.cText,
                  height: 1,
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
          Text(
            '$status · everyone under ${fmtLimit(l)}',
            style: appFont(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.cTextSec,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.person, required this.rank});

  final Profile person;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final isMe = person.isMe;
    final color = person.avatarColor ?? AppColors.primary;

    return GestureDetector(
      onTap: isMe
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => FriendDetailScreen(friendId: person.id),
              )),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color:
              isMe ? AppColors.primary.withValues(alpha: 0.10) : context.cSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isMe ? AppColors.primary : context.cDivider,
            width: isMe ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Text(
                '$rank',
                style: appFont(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: rank <= 3 ? AppColors.primary : context.cTextTer,
                ),
              ),
            ),
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Text(
                person.initials,
                style: appFont(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    person.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: appFont(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: context.cText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Limit ${fmtLimit(person.dailyLimitMinutes)} · '
                    'best ${person.longestStreak}',
                    style: appFont(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: context.cTextSec,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${person.currentStreak}',
              style: appFont(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: context.cText,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.local_fire_department,
              size: 19,
              color:
                  person.currentStreak > 0 ? AppColors.accent : context.cTextTer,
            ),
          ],
        ),
      ),
    );
  }
}
