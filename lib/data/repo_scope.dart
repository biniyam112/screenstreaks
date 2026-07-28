import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'local_store.dart';
import 'local_repository.dart';
import 'offline_repository.dart';
import 'repository.dart';
import 'supabase_repository.dart';

/// Initializes and returns the real Supabase repository.
/// Requires SUPABASE_URL and SUPABASE_ANON_KEY to be set via --dart-define.
/// Throws if backend is not configured.
Future<Repository> createRepository() async {
  if (!AppConfig.hasBackend) {
    return LocalRepository();
  }

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
  );

  // v7: singleton, must be initialized before use.
  await GoogleSignIn.instance.initialize(
    serverClientId: AppConfig.googleWebClientId.isNotEmpty
        ? AppConfig.googleWebClientId
        : null,
  );

  final backend =
      SupabaseRepository(Supabase.instance.client, GoogleSignIn.instance);
  // Wrap with the offline layer: local-first writes + cache-fallback reads.
  return OfflineRepository(backend, const LocalStore());
}

/// Provides the [Repository] to the widget tree.
class RepoScope extends InheritedWidget {
  const RepoScope({
    super.key,
    required this.repository,
    required super.child,
  });

  final Repository repository;

  static Repository of(BuildContext context) {
    // getInheritedWidgetOfExactType (no dependency) so this is safe to call
    // from initState. The repository instance is stable for the app's life.
    final scope = context.getInheritedWidgetOfExactType<RepoScope>();
    assert(scope != null, 'RepoScope not found in widget tree');
    return scope!.repository;
  }

  @override
  bool updateShouldNotify(RepoScope oldWidget) =>
      oldWidget.repository != repository;
}
