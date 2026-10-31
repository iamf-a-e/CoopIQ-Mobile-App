import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/app_state.dart';
import '../core/settings.dart';
import '../core/theme.dart';
import 'language_sheet.dart';
import 'profile_pages.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  void _go(BuildContext context, Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final s = AppState.instance;
    final t = Theme.of(context).textTheme;

    return ListenableBuilder(
      listenable: Listenable.merge([s, Settings.instance]),
      builder: (context, _) {
        final user = Supabase.instance.client.auth.currentUser;
        final meta = user?.userMetadata ?? const <String, dynamic>{};
        final fullName = (meta['full_name'] ?? '').toString().trim();
        final name = fullName.isNotEmpty ? fullName : s.firstName;
        final email = user?.email ?? '';

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            // Header
            Center(
              child: Container(
                width: 84,
                height: 84,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.brand.withAlpha(24),
                  border: Border.all(color: CoopColors.leaf, width: 2.5),
                ),
                child: Text(s.initials,
                    style: t.headlineSmall?.copyWith(color: context.brand, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 12),
            if (name.isNotEmpty)
              Center(child: Text(name, style: t.titleLarge, textAlign: TextAlign.center)),
            if (email.isNotEmpty)
              Center(child: Text(email, style: t.bodyMedium?.copyWith(color: context.muted))),
            const SizedBox(height: 24),

            // Preferences
            _Section(context.tr('sec_prefs')),
            Card(
              child: Column(children: [
                ListTile(
                  leading: Icon(Icons.language, color: context.brand),
                  title: Text(context.tr('language')),
                  subtitle: Text(Settings.instance.langName),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showLanguageSheet(context),
                ),
                const Divider(),
                SwitchListTile(
                  secondary: Icon(Icons.dark_mode_outlined, color: context.brand),
                  title: Text(context.tr('dark_mode')),
                  subtitle: Text(context.tr('dark_mode_sub')),
                  value: context.isDark,
                  onChanged: Settings.instance.setDark,
                ),
                const Divider(),
                ListTile(
                  leading: Icon(Icons.notifications_none_rounded, color: context.brand),
                  title: Text(context.tr('notif_prefs')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _go(context, const NotificationPrefsScreen()),
                ),
              ]),
            ),
            const SizedBox(height: 20),

            // Account
            _Section(context.tr('sec_account')),
            Card(
              child: ListTile(
                leading: Icon(Icons.lock_outline, color: context.brand),
                title: Text(context.tr('change_password')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _go(context, const ChangePasswordScreen()),
              ),
            ),
            const SizedBox(height: 20),

            // Help and information
            _Section(context.tr('sec_help')),
            Card(
              child: Column(children: [
                ListTile(
                  leading: Icon(Icons.support_agent, color: context.brand),
                  title: Text(context.tr('support')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _go(context, const SupportScreen()),
                ),
                const Divider(),
                ListTile(
                  leading: Icon(Icons.info_outline, color: context.brand),
                  title: Text(context.tr('about')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _go(context, const AboutScreen()),
                ),
                const Divider(),
                ListTile(
                  leading: Icon(Icons.privacy_tip_outlined, color: context.brand),
                  title: Text(context.tr('privacy')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _go(context, const PrivacyScreen()),
                ),
              ]),
            ),
            const SizedBox(height: 28),

            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: context.danger,
                side: BorderSide(color: context.danger),
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Supabase.instance.client.auth.signOut(),
              icon: const Icon(Icons.logout),
              label: Text(context.tr('sign_out')),
            ),
          ],
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  final String label;
  const _Section(this.label);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: context.muted,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w700,
              ),
        ),
      );
}
