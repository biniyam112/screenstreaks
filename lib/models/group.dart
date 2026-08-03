/// An accountability group. Membership is by profile id and always includes
/// the current user; a person can belong to several groups.
class Group {
  const Group({
    required this.id,
    required this.name,
    required this.memberIds,
    this.adminId,
    this.limitMinutes,
  });

  final String id;
  final String name;
  final List<String> memberIds;

  /// Who can change the limit and the roster. Null on demo data.
  final String? adminId;

  /// The shared limit everyone must stay under. Null until the admin sets one.
  final int? limitMinutes;

  bool isAdmin(String userId) => adminId == userId;
}

/// A pending invitation to join a group.
class GroupInvite {
  const GroupInvite({
    required this.id,
    required this.groupId,
    required this.groupName,
    required this.invitedBy,
  });

  final String id;
  final String groupId;
  final String groupName;

  /// Display name of the admin who sent it.
  final String invitedBy;
}
