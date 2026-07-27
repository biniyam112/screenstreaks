import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeProvider() : _isDark = true {
    _loadTheme();
  }

  bool _isDark;

  bool get isDark => _isDark;

  ThemeData get currentTheme => _isDark ? AppTheme.dark() : AppTheme.light();

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    _isDark = prefs.getBool('isDark') ?? true;
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    _isDark = !_isDark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDark', _isDark);
    notifyListeners();
  }

  Future<void> setDark(bool value) async {
    if (_isDark == value) return;
    _isDark = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDark', _isDark);
    notifyListeners();
  }
}

class ThemeScope extends InheritedNotifier<ThemeProvider> {
  const ThemeScope({
    required ThemeProvider theme,
    required super.child,
    super.key,
  }) : super(notifier: theme);

  static ThemeProvider of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ThemeScope>();
    assert(scope != null, 'ThemeScope not found in widget tree');
    return scope!.notifier!;
  }
}
