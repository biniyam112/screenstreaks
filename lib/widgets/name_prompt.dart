import 'package:flutter/material.dart';

import '../app_events.dart';
import '../data/repo_scope.dart';
import '../models/models.dart';
import '../theme.dart';

/// Asks for a first and last name once, for accounts created before those
/// fields existed. The nickname is optional.
Future<void> showNamePrompt(BuildContext context, Profile me) async {
  final first = TextEditingController(text: me.firstName ?? '');
  final last = TextEditingController(text: me.lastName ?? '');
  final nick = TextEditingController(text: me.nickname ?? '');

  // Seed from the display name so it's a confirmation rather than retyping.
  if (first.text.isEmpty && me.displayName.trim().isNotEmpty &&
      me.displayName != 'Friend') {
    final parts = me.displayName.trim().split(RegExp(r'\s+'));
    first.text = parts.first;
    if (parts.length > 1) last.text = parts.last;
  }

  final repo = RepoScope.of(context);

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      backgroundColor: c.cSurface,
      title: Text('What should we call you?',
          style: appFont(fontWeight: FontWeight.w800, color: c.cText)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Your first name shows in groups and lists. The nickname is for '
            "the widget, where there's only room for a few characters.",
            style: appFont(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: c.cTextSec,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          _Field(controller: first, hint: 'First name'),
          const SizedBox(height: 10),
          _Field(controller: last, hint: 'Last name'),
          const SizedBox(height: 10),
          _Field(controller: nick, hint: 'Nickname (optional)', maxLength: 4),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            // Both names are required — the widget builds initials from them.
            if (first.text.trim().isEmpty || last.text.trim().isEmpty) return;
            await repo.setNames(
              firstName: first.text.trim(),
              lastName: last.text.trim(),
              nickname: nick.text.trim(),
            );
            notifyProfileChanged();
            if (c.mounted) Navigator.pop(c);
          },
          child: Text('Save',
              style: appFont(
                  color: AppColors.primary, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
}

class _Field extends StatelessWidget {
  const _Field({required this.controller, required this.hint, this.maxLength});

  final TextEditingController controller;
  final String hint;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textCapitalization: TextCapitalization.words,
      maxLength: maxLength,
      style: appFont(
          fontSize: 15, fontWeight: FontWeight.w600, color: context.cText),
      decoration: InputDecoration(
        hintText: hint,
        counterText: '',
        isDense: true,
        hintStyle: appFont(
            fontSize: 15, fontWeight: FontWeight.w500, color: context.cTextTer),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: context.cDivider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }
}
