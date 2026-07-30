/// An accountability group. Membership is by profile id and always includes
/// 'me'; a person can belong to several groups.
class Group {
  const Group({
    required this.id,
    required this.name,
    required this.memberIds,
  });

  final String id;
  final String name;
  final List<String> memberIds;
}
