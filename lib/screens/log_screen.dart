import 'package:flutter/material.dart';

import '../services/screen_time.dart';
import '../theme.dart';

/// What the Screen Time extension has recorded. Diagnostic, but the only
/// window into whether iOS is actually watching.
class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  List<String> _lines = const [];
  String _status = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final lines = (await ScreenTime.readLog()).reversed.toList();
    final active = await ScreenTime.activeLimit();
    if (!mounted) return;
    setState(() {
      _lines = lines;
      _status = active > 0
          ? 'Watching ${active ~/ 60}h ${active % 60}m'
          : 'Not tracking';
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity log'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: context.cSurface,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      _status,
                      style: appFont(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: context.cText,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _lines.isEmpty
                        ? Center(
                            child: Text(
                              'Nothing recorded yet',
                              style: appFont(color: context.cTextSec),
                            ),
                          )
                        : ListView.builder(
                            padding:
                                const EdgeInsets.fromLTRB(16, 4, 16, 32),
                            itemCount: _lines.length,
                            itemBuilder: (context, i) => Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 5),
                              child: Text(
                                _lines[i],
                                style: appFont(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  color: context.cTextSec,
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}
