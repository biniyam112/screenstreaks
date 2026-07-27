import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../data/repo_scope.dart';
import '../theme.dart';
import '../widgets.dart';

/// Connect with a friend by entering their share code (or pasting their link).
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _extractCode(String input) {
    var s = input.trim();
    if (s.contains('/')) s = s.split('/').last;
    if (s.contains('?')) s = s.split('?').first;
    return s.toUpperCase();
  }

  Future<void> _connect() async {
    final code = _extractCode(_controller.text);
    if (code.isEmpty) {
      setState(() => _error = 'Enter a code or paste a link.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final friend = await RepoScope.of(context).connectWithCode(code);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Connected with ${friend.displayName} 🎉')));
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connect')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: const Icon(IconsaxPlusBold.link_1, color: AppColors.primary, size: 32),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              "Enter your friend's code",
              textAlign: TextAlign.center,
              style: appFont(fontSize: 21, fontWeight: FontWeight.w800, color: context.cText),
            ),
            const SizedBox(height: 8),
            Text(
              'Paste their invite link or type the code they shared with you.',
              textAlign: TextAlign.center,
              style: appFont(
                fontSize: 14,
                color: context.cTextSec,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: _controller,
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              style: appMono(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: 6,
                color: context.cText,
              ),
              decoration: InputDecoration(
                hintText: 'ABC123',
                hintStyle: appMono(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 6,
                  color: context.cTextTer,
                ),
                filled: true,
                fillColor: context.cSurface,
                contentPadding: const EdgeInsets.symmetric(vertical: 18),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: _error != null ? AppColors.danger : context.cDivider,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: _error != null ? AppColors.danger : AppColors.primary,
                    width: 1.6,
                  ),
                ),
              ),
              onSubmitted: (_) => _connect(),
            ),
            // Full, wrapping error message (no truncation).
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(IconsaxPlusBold.info_circle, color: AppColors.danger, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: appFont(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.center,
              child: TextButton.icon(
                onPressed: () async {
                  final data = await Clipboard.getData('text/plain');
                  if (data?.text != null) {
                    _controller.text = _extractCode(data!.text!);
                  }
                },
                style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                icon: const Icon(IconsaxPlusLinear.clipboard_text, size: 18),
                label: const Text('Paste from clipboard'),
              ),
            ),
            const SizedBox(height: 12),
            ModernButton(
              label: _busy ? 'Connecting…' : 'Connect',
              icon: _busy ? null : IconsaxPlusBold.link_1,
              onPressed: _busy ? null : _connect,
            ),
          ],
        ),
      ),
    );
  }
}
