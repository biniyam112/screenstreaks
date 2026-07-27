import 'package:flutter/material.dart';

import '../config.dart';
import '../data/repo_scope.dart';
import '../theme.dart';

/// Sign-in gate. Uses Google auth via the repository.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.onSignedIn});

  final VoidCallback onSignedIn;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await RepoScope.of(context).signInWithGoogle();
      widget.onSignedIn();
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(flex: 3),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primary, AppColors.primaryDim],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.4),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Center(
                  child: Text('🔥', style: TextStyle(fontSize: 44)),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Vero',
                style: appFont(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: context.cText,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Stay under your screen-time limit, build a streak, '
                'and keep each other accountable.',
                textAlign: TextAlign.center,
                style: appFont(
                  fontSize: 15.5,
                  color: context.cTextSec,
                  fontWeight: FontWeight.w500,
                  height: 1.5,
                ),
              ),
              const Spacer(flex: 4),
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: appFont(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              _GoogleButton(busy: _busy, onTap: _busy ? null : _signIn),
              if (!AppConfig.hasBackend) ...[
                const SizedBox(height: 12),
                Text(
                  'Demo mode — Google sign-in activates once Supabase is set up.',
                  textAlign: TextAlign.center,
                  style: appFont(
                    fontSize: 12,
                    color: context.cTextTer,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              const SizedBox(height: 36),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.busy, required this.onTap});
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.cSurface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.cDivider, width: 1.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else ...[
                const _GoogleLogo(size: 20),
                const SizedBox(width: 12),
                Text(
                  'Continue with Google',
                  style: appFont(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: context.cText,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The Google "G" drawn in its four brand colors (no asset needed).
class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo({this.size = 20});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;
    final r = w / 2;
    final stroke = w * 0.22;

    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r - stroke / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    // Arcs approximating the Google "G".
    p.color = const Color(0xFF4285F4); // blue
    canvas.drawArc(rect, -0.4, 1.4, false, p);
    p.color = const Color(0xFF34A853); // green
    canvas.drawArc(rect, 1.0, 1.4, false, p);
    p.color = const Color(0xFFFBBC05); // yellow
    canvas.drawArc(rect, 2.4, 1.2, false, p);
    p.color = const Color(0xFFEA4335); // red
    canvas.drawArc(rect, 3.55, 1.5, false, p);

    // Horizontal bar of the "G".
    final bar = Paint()..color = const Color(0xFF4285F4);
    canvas.drawRect(
      Rect.fromLTWH(cx, cy - stroke / 2, r, stroke),
      bar,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
