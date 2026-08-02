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
import 'screens/groups_screen.dart';
import 'screens/probe_screen.dart';

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

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  bool? _signedIn;

  @override
  void initState() {
    super.initState();
    _checkSignIn();
  }

  void _checkSignIn() {
    final repo = RepoScope.of(context);
    setState(() => _signedIn = repo.isSignedIn);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Undr',
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
            // Clear the device onboarding flag so the next account (which may
            // be a different person on this device) sets up fresh.
            await Prefs.setOnboarded(false);
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
        onProfile: () => setState(() => _index = 3),
      ),
      const FeedScreen(),
      const GroupsScreen(),
      const AccountScreen(),
      const ProbeScreen(),
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
            _navItem(context, IconsaxPlusBold.people, 'Groups', AppColors.primary),
            _navItem(context, IconsaxPlusBold.user, 'Profile', const Color(0xFF8B5CF6)),
            _navItem(context, IconsaxPlusBold.code_1, 'Probe', AppColors.danger),
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
