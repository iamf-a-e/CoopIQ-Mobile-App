import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/config.dart';
import '../core/settings.dart';
import '../core/theme.dart';
import 'coop_logo.dart';

const websiteUrl = 'https://www.urbanmunda.com';
const appVersion = '1.0.0'; // keep in step with pubspec.yaml

Future<void> _open(BuildContext context, Uri uri) async {
  var ok = false;
  try {
    ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('couldnt_open'))));
  }
}

// ───────────────────────── Change password ─────────────────────────
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _key = GlobalKey<FormState>();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.updateUser(UserAttributes(password: _new.text));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('pass_updated'))));
      Navigator.pop(context);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = context.tr('err_generic'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final eye = IconButton(
      icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
      onPressed: () => setState(() => _hide = !_hide),
    );
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('change_password'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _key,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextFormField(
              controller: _new,
              obscureText: _hide,
              decoration: InputDecoration(labelText: context.tr('new_password'), suffixIcon: eye),
              validator: (v) => (v == null || v.length < 6) ? context.tr('pass_min') : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirm,
              obscureText: _hide,
              decoration: InputDecoration(labelText: context.tr('confirm_password')),
              validator: (v) => v != _new.text ? context.tr('pass_mismatch') : null,
              onFieldSubmitted: (_) => _save(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(context.tr('update_password')),
            ),
          ]),
        ),
      ),
    );
  }
}

// ───────────────────────── Notification preferences ─────────────────────────
class NotificationPrefsScreen extends StatelessWidget {
  const NotificationPrefsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = Settings.instance;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('notif_prefs'))),
      body: ListenableBuilder(
        listenable: st,
        builder: (context, _) => ListView(padding: const EdgeInsets.all(20), children: [
          Card(
            child: Column(children: [
              SwitchListTile(
                value: st.remindersOn,
                onChanged: st.setReminders,
                title: Text(context.tr('np_reminders')),
                subtitle: Text(context.tr('np_reminders_sub')),
              ),
              const Divider(),
              SwitchListTile(
                value: st.tipsOn,
                onChanged: st.setTips,
                title: Text(context.tr('np_tips')),
                subtitle: Text(context.tr('np_tips_sub')),
              ),
              const Divider(),
              SwitchListTile(
                value: st.agrovetOn,
                onChanged: st.setAgrovet,
                title: Text(context.tr('np_agrovet')),
                subtitle: Text(context.tr('np_agrovet_sub')),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ───────────────────────── Support ─────────────────────────
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  Widget _tile(BuildContext context, IconData icon, String label, Uri uri) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: Icon(icon, color: context.brand),
            title: Text(label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(context, uri),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('support'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(context.tr('support_intro'), style: Theme.of(context).textTheme.bodyLarge),
        ),
        if (AppConfig.agrovetWhatsApp.isNotEmpty)
          _tile(context, Icons.chat_outlined, context.tr('sup_whatsapp'), Uri.parse('https://wa.me/${AppConfig.agrovetWhatsApp}')),
        if (AppConfig.supportEmail.isNotEmpty)
          _tile(context, Icons.mail_outline, context.tr('sup_email'), Uri(scheme: 'mailto', path: AppConfig.supportEmail)),
        _tile(context, Icons.public, context.tr('sup_web'), Uri.parse(websiteUrl)),
      ]),
    );
  }
}

// ───────────────────────── About ─────────────────────────
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('about'))),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        const Center(child: CoopLogo(height: 80)),
        const SizedBox(height: 14),
        Center(child: Text('CoopIQ', style: t.headlineSmall)),
        const SizedBox(height: 4),
        Center(
          child: Text('${context.tr('version')} $appVersion', style: t.bodyMedium?.copyWith(color: context.muted)),
        ),
        const SizedBox(height: 20),
        Text(context.tr('about_body'), style: t.bodyLarge),
        const SizedBox(height: 20),
        Card(
          child: ListTile(
            leading: Icon(Icons.public, color: context.brand),
            title: Text(context.tr('sup_web')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(context, Uri.parse(websiteUrl)),
          ),
        ),
      ]),
    );
  }
}

// ───────────────────────── Privacy ─────────────────────────
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('privacy'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Text(context.tr('privacy_body'), style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5)),
      ),
    );
  }
}
