import 'dart:async';

import 'package:flutter/material.dart';

import 'data/repo_scope.dart';
import 'data/repository.dart';
import 'main_app.dart';
import 'services/background.dart';
import 'theme_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final repository = await createRepository();
    runApp(ScreenStreaksBootstrap(repository: repository));
    // Schedule the recurring background usage sync (Android only; no-op
    // elsewhere). Fire-and-forget so it never blocks or crashes startup.
    unawaited(Background.start().catchError((_) {}));
  } catch (e) {
    runApp(ErrorApp(error: e.toString()));
  }
}

/// Error screen when Supabase isn't configured.
class ErrorApp extends StatelessWidget {
  const ErrorApp({super.key, required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('⚠️', style: TextStyle(fontSize: 72)),
                const SizedBox(height: 20),
                const Text(
                  'Supabase not configured',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(error, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 20),
                const Text('Run the app with:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text(
                    'flutter run --dart-define=SUPABASE_URL=... '
                    '--dart-define=SUPABASE_ANON_KEY=... '
                    '--dart-define=GOOGLE_WEB_CLIENT_ID=...',
                    style: TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bootstrap the app with Supabase + theme.
class ScreenStreaksBootstrap extends StatefulWidget {
  const ScreenStreaksBootstrap({super.key, required this.repository});

  final Repository repository;

  @override
  State<ScreenStreaksBootstrap> createState() => _ScreenStreaksBootstrapState();
}

class _ScreenStreaksBootstrapState extends State<ScreenStreaksBootstrap> {
  late final ThemeProvider _themeProvider = ThemeProvider();

  @override
  void dispose() {
    _themeProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // MainApp owns the MaterialApp so it can inject AuthScope above the
    // Navigator (see main_app.dart). Theme changes propagate through
    // ThemeScope + this ListenableBuilder.
    return ThemeScope(
      theme: _themeProvider,
      child: ListenableBuilder(
        listenable: _themeProvider,
        builder: (context, _) => RepoScope(
          repository: widget.repository,
          child: const MainApp(),
        ),
      ),
    );
  }
}
