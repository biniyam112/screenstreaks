import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/prefs.dart';
import '../theme.dart';
import '../services/screen_time.dart';

/// Temporary diagnostic: does iOS fire eventDidReachThreshold honestly on
/// this OS version, or immediately? Delete once that question is settled.
class ProbeScreen extends StatefulWidget {
  const ProbeScreen({super.key});

  @override
  State<ProbeScreen> createState() => _ProbeScreenState();
}

class _ProbeScreenState extends State<ProbeScreen> {
  static const _channel = MethodChannel('screenstreaks/screentime');

  String _status = 'Not started';
  List<String> _log = const [];
  DateTime? _since;
  Timer? _tick;

  Future<void> _call(String method, [dynamic args]) async {
    setState(() => _status = 'Calling $method…');
    try {
      final result = await _channel.invokeMethod(method, args);
      setState(() => _status = '$method → $result');
    } on PlatformException catch (e) {
      setState(() => _status = '$method failed: ${e.code} ${e.message}');
    }
  }

  Future<void> _startWithMyLimit() async {
    final minutes = await Prefs.goalMinutes();
    await _call('startProbe', minutes);
  }

  /// Ask iOS what's actually registered, rather than showing whatever the
  /// last button press reported.
  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _loadSince() async {
    final d = await ScreenTime.monitoringSince();
    if (mounted) setState(() => _since = d);
  }

  String get _elapsed {
    final start = _since;
    if (start == null) return '—';
    final d = DateTime.now().difference(start);
    final h = d.inHours.toString();
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final sec = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h + 'h ' + m + 'm ' + sec + 's';
  }

  Future<void> _refreshStatus() async {
    try {
      final active = await _channel.invokeMethod('activeLimit') as int? ?? 0;
      if (!mounted) return;
      setState(() => _status = active > 0
          ? 'monitoring — threshold ${active}m'
          : 'Not started');
    } on PlatformException {
      // Keep the last message.
    }
  }

  Future<void> _refreshLog() async {
    try {
      final entries = await _channel.invokeMethod('readLog');
      setState(() => _log = (entries as List).cast<String>());
    } on PlatformException catch (e) {
      setState(() => _status = 'readLog failed: ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Text(
              'Screen Time probe',
              style: appFont(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: context.cText,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Run these in order. Then use a selected app for 2+ minutes and '
              'check whether the threshold fires honestly.',
              style: appFont(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: context.cTextSec,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            _btn('1 · Request authorization', () => _call('authorize')),
            _btn('2 · Pick apps to count', () => _call('pickApps')),
            _btn('3 · Start monitoring (my limit)', _startWithMyLimit),
            _btn('TEST · Start at 2 min', () => _call('startProbe', 2)),
            _btn('Refresh log', () async {
              await _loadSince();
              await _refreshStatus();
              await _refreshLog();
            }),
            _btn('Clear log', () async {
              await _call('clearLog');
              await _refreshLog();
            }),
            _btn('Stop monitoring', () => _call('stop')),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: context.cSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.cDivider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MONITORING FOR',
                    style: appFont(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: context.cTextTer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _elapsed,
                    style: appMono(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.cSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.cDivider),
              ),
              child: Text(
                _status,
                style: appFont(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.cText,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'CALLBACK LOG',
              style: appFont(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: context.cTextSec,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            if (_log.isEmpty)
              Text(
                'Nothing yet.',
                style: appFont(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: context.cTextTer,
                ),
              )
            else
              ..._log.reversed.map(
                (line) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    line,
                    style: appFont(
                      fontSize: 13,
                      fontWeight: line.contains('THRESHOLD')
                          ? FontWeight.w800
                          : FontWeight.w500,
                      color: line.contains('THRESHOLD')
                          ? AppColors.danger
                          : context.cTextSec,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _btn(String label, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: onTap,
            child: Text(label, style: appFont(fontWeight: FontWeight.w700)),
          ),
        ),
      );
}
