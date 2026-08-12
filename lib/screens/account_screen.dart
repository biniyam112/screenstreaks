import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../app_events.dart';
import '../data/repo_scope.dart';
import '../main_app.dart' show AuthScope;
import '../models/models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'friends_screen.dart';
import 'settings_screen.dart';
import '../widgets/avatar.dart';
import 'package:image_picker/image_picker.dart';

/// The "Profile" tab: the user's own identity — avatar, editable display name,
/// share code — plus entry points to settings and sign-out.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  Profile? _me;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final me = await RepoScope.of(context).me();
    if (mounted) setState(() => _me = me);
  }

  Future<void> _pickAvatar() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
    if (file == null || !mounted) return;
    try {
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      await RepoScope.of(context).setAvatar(bytes);
      notifyProfileChanged();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _editName() async {
    final me = _me;
    if (me == null) return;
    final controller = TextEditingController(text: me.displayName);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.cSurface,
        title: Text(
          'Your name',
          style: appFont(fontWeight: FontWeight.w700, color: dialogContext.cText),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          maxLength: 40,
          style: appFont(color: dialogContext.cText, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: 'e.g. Alex Rivera',
            counterText: '',
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: dialogContext.cDivider),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
            ),
          ),
          onSubmitted: (v) => Navigator.pop(dialogContext, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              'Cancel',
              style: appFont(color: dialogContext.cTextSec, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: Text(
              'Save',
              style: appFont(color: AppColors.primary, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty || newName == me.displayName) return;
    if (!mounted) return;
    await RepoScope.of(context).setDisplayName(newName);
    notifyProfileChanged();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
        child: me == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                children: [
                  _Header(profile: me, onEdit: _editName, onPickPhoto: _pickAvatar),
                  const SizedBox(height: 24),
                  _ShareCodeCard(code: me.shareCode),
                  const SizedBox(height: 24),
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _Tile(
                          icon: IconsaxPlusBold.profile_2user,
                          iconColor: AppColors.info,
                          label: 'Friends',
                          subtitle: 'Your accountability circle',
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const FriendsScreen()),
                            );
                            _load();
                          },
                        ),
                        Divider(height: 1, color: context.cDivider),
                        _Tile(
                          icon: IconsaxPlusBold.setting_2,
                          iconColor: AppColors.info,
                          label: 'Settings',
                          subtitle: 'Daily limit, alerts, appearance',
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const SettingsScreen()),
                            );
                            _load();
                          },
                        ),
                        Divider(height: 1, color: context.cDivider),
                        _Tile(
                          icon: IconsaxPlusLinear.logout,
                          label: 'Sign out',
                          color: AppColors.danger,
                          onTap: () async {
                            final auth = AuthScope.of(context);
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                backgroundColor: c.cSurface,
                                title: Text(
                                  'Sign out?',
                                  style: appFont(
                                      fontWeight: FontWeight.w700,
                                      color: c.cText),
                                ),
                                content: Text(
                                  "Your streak and history are safe — you'll "
                                  'just need to sign back in.',
                                  style: appFont(
                                      fontWeight: FontWeight.w500,
                                      color: c.cTextSec),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(c, false),
                                    child: Text('Cancel',
                                        style: appFont(
                                            color: c.cTextSec,
                                            fontWeight: FontWeight.w600)),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(c, true),
                                    child: Text('Sign out',
                                        style: appFont(
                                            color: AppColors.danger,
                                            fontWeight: FontWeight.w700)),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true) await auth.signOut();
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.profile,
    required this.onEdit,
    required this.onPickPhoto,
  });
  final Profile profile;
  final VoidCallback onEdit;
  final VoidCallback onPickPhoto;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: onPickPhoto,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Avatar(profile: profile, size: 88),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(
                        AppColors.primary.withValues(alpha: 0.9),
                        context.cSurface),
                    shape: BoxShape.circle,
                    border: Border.all(color: context.cBg, width: 2),
                  ),
                  child: const Icon(IconsaxPlusBold.camera,
                      size: 14, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: onEdit,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  profile.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: appFont(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: context.cText,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  IconsaxPlusBold.edit_2,
                  size: 15,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ShareCodeCard extends StatelessWidget {
  const _ShareCodeCard({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'YOUR CODE',
                style: appFont(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: context.cTextTer,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                code,
                style: appMono(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 4,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(IconsaxPlusBold.copy, size: 20),
            color: context.cTextSec,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Code copied')),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.color,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final Color? color;
  final Color? iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.cText;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(icon, size: 22, color: iconColor ?? color ?? context.cTextSec),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: appFont(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: c,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: appFont(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: context.cTextSec,
                      ),
                    ),
                ],
              ),
            ),
            if (color == null)
              Icon(IconsaxPlusLinear.arrow_right_3,
                  size: 18, color: context.cTextTer),
          ],
        ),
      ),
    );
  }
}
