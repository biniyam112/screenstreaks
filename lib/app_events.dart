import 'package:flutter/foundation.dart';

/// Bumped whenever the signed-in user's own profile changes (daily limit or
/// display name saved). Live tabs kept alive in the bottom-nav IndexedStack
/// (e.g. the home screen) listen to this and re-fetch, so an edit made on one
/// tab shows up on the others without a manual refresh.
final ValueNotifier<int> profileRevision = ValueNotifier<int>(0);

void notifyProfileChanged() => profileRevision.value++;
