import 'dart:async';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'colors.dart';
import 'data/repo_scope.dart';
import 'screens/account_screen.dart';
import 'screens/feed_screen.dart';
import 'screens/friends_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/sign_in_screen.dart';
import 'services/prefs.dart';
import 'theme_provider.dart';
import 'screens/social_screen.dart';

/// Exposes sign-out to descendant screens (e.g. SettingsScreen).
class AuthScope extends InheritedWidget {
  const AuthScope({super.key, required this.onSignOut, required super.child});

  final Future<void> Function() onSignOut;

  Future<void> signOut() => onSignOut();

  static AuthScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AuthScope>();
    assert(scope != null, 'AuthScope not found — wrap with AuthScope');
    return scope!;
  }

  @override
  bool updateShouldNotify(AuthScope old) => false;
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  /// So the auth listener can clear pushed routes when the session ends.
  static final navigatorKey = GlobalKey<NavigatorState>();

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  bool? _signedIn;

  @override
  void initState() {
    super.initState();
    _checkSignIn();
    // Watch the session rather than polling it — signing out anywhere in the
    // app swaps straight back to the sign-in screen.
    _auth = RepoScope.of(context).authChanges().listen((signedIn) {
      if (!mounted) return;
      setState(() => _signedIn = signedIn);
      // home swaps to the sign-in screen, but Account and Settings are still
      // stacked on top of it — clear them or nothing looks like it happened.
      if (!signedIn) {
        MainApp.navigatorKey.currentState?.popUntil((r) => r.isFirst);
      }
    });
  }

  StreamSubscription<bool>? _auth;

  @override
  void dispose() {
    _auth?.cancel();
    super.dispose();
  }

  void _checkSignIn() {
    final repo = RepoScope.of(context);
    setState(() => _signedIn = repo.isSignedIn);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Undr',
      navigatorKey: MainApp.navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeScope.of(context).currentTheme,
      // AuthScope is injected here — *above* the Navigator — so it's an
      // ancestor of every pushed route (e.g. SettingsScreen), not just the
      // home page. Wrapping `home` directly left pushed routes unable to find
      // it, which crashed sign-out with "AuthScope not found".
      builder: (context, child) {
        if (_signedIn != true) return child!;
        return AuthScope(
          onSignOut: () async {
            await RepoScope.of(context).signOut();
            // Don't clear the onboarding flag — signing out and back in
            // shouldn't re-run setup, and re-running it resets the day's
            // count and lets the limit be changed again.
            // Give Supabase a moment to clear the session before we ask,
            // or isSignedIn still reports true and the tree doesn't swap.
            await Future<void>.delayed(const Duration(milliseconds: 150));
            if (!mounted) return;
            _checkSignIn();
          },
          child: child!,
        );
      },
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    if (_signedIn == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_signedIn!) {
      return SignInScreen(onSignedIn: _checkSignIn);
    }
    return const _OnboardingGate();
  }
}

/// After sign-in, decides between first-run onboarding and the main shell.
class _OnboardingGate extends StatefulWidget {
  const _OnboardingGate();

  @override
  State<_OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<_OnboardingGate> {
  bool? _onboarded;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    // Ask the account, not the device — a second person signing in on this
    // phone needs their own setup, and Prefs can't tell them apart.
    if (!mounted) return;
    try {
      final me = await RepoScope.of(context).me();
      final done = (me.firstName ?? '').trim().isNotEmpty;
      if (done) await Prefs.setOnboarded(true);
      if (mounted) setState(() => _onboarded = done);
      return;
    } catch (_) {
      // Offline or no profile yet — fall back to the device flag.
    }
    final done = await Prefs.isOnboarded();
    if (mounted) setState(() => _onboarded = done);
  }

  @override
  Widget build(BuildContext context) {
    if (_onboarded == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_onboarded!) {
      return OnboardingScreen(
        onDone: () => setState(() => _onboarded = true),
      );
    }
    return const RootShell();
  }
}

/// Bottom-nav shell: My streak, Feed, Groups, Profile.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      ProfileScreen(
        onSeeFriends: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const FriendsScreen()),
        ),
        // Profile lives behind the avatar on My Streak, not in the bar.
        onProfile: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AccountScreen()),
        ),
      ),
      const FeedScreen(),
      const SocialScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: context.cDivider)),
        ),
        child: NavigationBar(
          height: 64,
          backgroundColor: context.cSurface,
          // No pill — the filled icon lights up in its own colour when active.
          indicatorColor: Colors.transparent,
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            _navItem(context, IconsaxPlusBold.flash_1, 'My streak', AppColors.accent),
            _navItem(context, IconsaxPlusBold.heart, 'Feed', const Color(0xFFEC4899)),
            _navItem(context, IconsaxPlusBold.people, 'Social', AppColors.primary),
          ],
        ),
      ),
    );
  }

  /// A filled (Bold) tab icon — muted when inactive, its own colour when active.
  NavigationDestination _navItem(
    BuildContext context,
    IconData icon,
    String label,
    Color color,
  ) {
    return NavigationDestination(
      icon: Icon(icon, color: context.cTextTer),
      selectedIcon: Icon(icon, color: color),
      label: label,
    );
  }
}
