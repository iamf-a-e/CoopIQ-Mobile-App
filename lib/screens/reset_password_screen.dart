import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/recovery.dart';
import '../core/settings.dart';
import '../core/theme.dart';
import 'coop_logo.dart';

// English, Nyanja, Bemba, Lozi, Tonga. Draft translations: have native speakers
// check them. An empty entry falls back to English.
const _tx = <String, List<String>>{
  'title': [
    'Set a new password',
    'Ikani mawu achinsinsi atsopano',
    'Beka password ipya',
    'Beya password ye nca',
    'Bikka password iipya',
  ],
  'subtitle': [
    'Choose a new password for your CoopIQ account.',
    'Sankhani mawu achinsinsi atsopano a akaunti yanu ya CoopIQ.',
    'Sala password ipya ku akaunti yobe ya CoopIQ.',
    'Mu fe password ye nca ya akaunti ya mina ya CoopIQ.',
    'Sala password iipya ya akkaunti yako ya CoopIQ.',
  ],
  'new_pw': [
    'New password',
    'Mawu achinsinsi atsopano',
    'Password ipya',
    'Password ye nca',
    'Password iipya',
  ],
  'confirm_pw': [
    'Confirm new password',
    'Bwerezani mawu achinsinsi atsopano',
    'Shininkisha password ipya',
    'Tiisa password ye nca',
    'Lemba alimwi password iipya',
  ],
  'mismatch': [
    'Passwords do not match',
    'Mawu achinsinsi sakufanana',
    'Ama password tayalingana',
    'Li password ha li swana',
    'Ma password tayyandani',
  ],
  'update': [
    'Update password',
    'Sinthani mawu achinsinsi',
    'Alula password',
    'Fetola password',
    'Cinca password',
  ],
  'done_title': [
    'Password updated',
    'Mawu achinsinsi asinthidwa',
    'Password yalulwa',
    'Password i fetotwe',
    'Password yacincwa',
  ],
  'done_body': [
    'You are all set. Your password has been updated.',
    'Zonse zili bwino. Mawu achinsinsi anu asinthidwa.',
    'Fyonse fili bwino. Password yobe yalulwa.',
    'Ku siame kaufela. Password ya mina i fetotwe.',
    'Zyoonse zili kabotu. Password yako yacincwa.',
  ],
  'continue': [
    'Continue',
    'Pitirizani',
    'Endelela',
    'Tswelela',
    'Zumanana',
  ],
  'cancel': [
    'Cancel',
    'Siyani',
    'Leka',
    '',
    '',
  ],
};

const _langIndex = {'English': 0, 'Nyanja': 1, 'Bemba': 2, 'Lozi': 3, 'Tonga': 4};

String _s(String key) {
  final v = _tx[key]!;
  final i = _langIndex[Settings.instance.langName] ?? 0;
  return v[i].isEmpty ? v[0] : v[i];
}

/// Shown after the user taps the reset link in the email and the app opens at
/// coopiq://reset-password. The link has already signed them in with a
/// short-lived recovery session, so all that is left is choosing the password.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});
  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _key = GlobalKey<FormState>();
  final _p1 = TextEditingController();
  final _p2 = TextEditingController();
  bool _busy = false;
  bool _done = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _p1.dispose();
    _p2.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.updateUser(UserAttributes(password: _p1.text));
      if (mounted) setState(() => _done = true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = context.tr('err_generic'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Leaving without choosing a password signs the recovery session out again.
  Future<void> _cancel() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    RecoveryState.pending.value = false;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final linkStyle = TextButton.styleFrom(
      foregroundColor: context.link,
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    );

    return PopScope(
      canPop: false, // no back gesture: choose a password, or tap Cancel
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: _done
                    ? Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        const Center(child: CoopLogo(height: 72)),
                        const SizedBox(height: 28),
                        Icon(Icons.check_circle_outline, size: 64, color: context.brand),
                        const SizedBox(height: 14),
                        Text(_s('done_title'), textAlign: TextAlign.center, style: t.titleLarge),
                        const SizedBox(height: 8),
                        Text(
                          _s('done_body'),
                          textAlign: TextAlign.center,
                          style: t.bodyMedium?.copyWith(color: context.muted),
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: () => RecoveryState.pending.value = false,
                          child: Text(_s('continue')),
                        ),
                      ])
                    : Form(
                        key: _key,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          const Center(child: CoopLogo(height: 72)),
                          const SizedBox(height: 28),
                          Text(_s('title'), style: t.titleLarge),
                          const SizedBox(height: 6),
                          Text(_s('subtitle'), style: t.bodyMedium?.copyWith(color: context.muted)),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: _p1,
                            obscureText: _hide,
                            autofocus: true,
                            decoration: InputDecoration(
                              labelText: _s('new_pw'),
                              suffixIcon: IconButton(
                                icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                onPressed: () => setState(() => _hide = !_hide),
                              ),
                            ),
                            validator: (v) => (v == null || v.length < 6) ? context.tr('pass_min') : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _p2,
                            obscureText: _hide,
                            decoration: InputDecoration(labelText: _s('confirm_pw')),
                            validator: (v) => v != _p1.text ? _s('mismatch') : null,
                            onFieldSubmitted: (_) => _save(),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Text(_error!, style: t.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error)),
                          ],
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: _busy ? null : _save,
                            child: _busy
                                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : Text(_s('update')),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            style: linkStyle,
                            onPressed: _busy ? null : _cancel,
                            child: Text(_s('cancel')),
                          ),
                        ]),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
