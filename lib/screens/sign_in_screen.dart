import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Separate sheet so signing in can't quietly create an account.
  Future<void> _signUp() async {
    final email = TextEditingController();
    final password = TextEditingController();
    final confirm = TextEditingController();
    String? error;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            22,
            24,
            MediaQuery.of(sheetContext).viewInsets.bottom + 28,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Create an account',
                style: appFont(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: context.cText,
                ),
              ),
              const SizedBox(height: 16),
              _Field(controller: email, hint: 'Email',
                  keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 10),
              _Field(controller: password, hint: 'Password', obscure: true),
              const SizedBox(height: 10),
              _Field(
                  controller: confirm, hint: 'Confirm password', obscure: true),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  style: appFont(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.danger,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () async {
                  final e = email.text.trim();
                  final p1 = password.text;
                  if (e.isEmpty || p1.length < 6) {
                    setSheet(() => error =
                        'Enter an email and a password of 6+ characters.');
                    return;
                  }
                  if (p1 != confirm.text) {
                    setSheet(() => error = "Passwords don't match.");
                    return;
                  }
                  try {
                    await RepoScope.of(context).signUpWithEmail(e, p1);
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                    widget.onSignedIn();
                  } catch (err) {
                    setSheet(() => error =
                        err.toString().replaceFirst('Exception: ', ''));
                  }
                },
                child: Text(
                  'Sign up',
                  style: appFont(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _signInEmail() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.length < 6) {
      setState(() => _error = 'Enter an email and a password of 6+ characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await RepoScope.of(context).signInWithEmail(email, password);
      // Tells iOS the credential worked, which is what prompts the save.
      TextInput.finishAutofillContext();
      widget.onSignedIn();
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
      backgroundColor: Colors.transparent,
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
                'Undr',
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
              AutofillGroup(
                child: Column(
                  children: [
                    _Field(
                      controller: _email,
                      hint: 'Email',
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.username],
                    ),
                    const SizedBox(height: 10),
                    _Field(
                      controller: _password,
                      hint: 'Password',
                      obscure: true,
                      onSubmitted: (_) => _signInEmail(),
                      autofillHints: const [AutofillHints.password],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _busy ? null : _signInEmail,
                  child: Text(
                    _busy ? 'Signing in…' : 'Continue with email',
                    style: appFont(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _GoogleButton(busy: _busy, onTap: _busy ? null : _signIn),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: _busy ? null : _signUp,
                child: Text(
                  'New here? Create an account',
                  textAlign: TextAlign.center,
                  style: appFont(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
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

/// Plain themed text field for the sign-in form.
class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.keyboardType,
    this.onSubmitted,
    this.autofillHints,
  });

  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted;

  /// Marks the field as a credential so iOS offers to save it in Keychain
  /// and fill it back in with Face ID.
  final List<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofillHints: autofillHints,
      obscureText: obscure,
      keyboardType: keyboardType,
      autocorrect: false,
      textCapitalization: TextCapitalization.none,
      onSubmitted: onSubmitted,
      style: appFont(fontSize: 15, color: context.cText),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: appFont(fontSize: 15, color: context.cTextTer),
        filled: true,
        fillColor: context.cSurface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: context.cDivider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }
}
