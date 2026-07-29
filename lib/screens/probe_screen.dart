import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

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

  Future<void> _call(String method, [dynamic args]) async {
    setState(() => _status = 'Calling $method…');
    try {
      final result = await _channel.invokeMethod(method, args);
      setState(() => _status = '$method → $result');
    } on PlatformException catch (e) {
      setState(() => _status = '$method failed: ${e.code} ${e.message}');
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
            _btn('3 · Start probe (2 min)', () => _call('startProbe', 2)),
            _btn('Refresh log', _refreshLog),
            _btn('Clear log', () async {
              await _call('clearLog');
              await _refreshLog();
            }),
            _btn('Stop monitoring', () => _call('stop')),
            const SizedBox(height: 18),
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
