import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/settings.dart';
import '../core/theme.dart';
import '../services/db.dart';
import 'coop_logo.dart';

/// Where the password-reset email link opens the app. This must also be added
/// under Authentication > URL Configuration > Redirect URLs in Supabase, and
/// to the Android manifest and iOS Info.plist (see the setup notes).
const resetRedirect = 'coopiq://reset-password';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _key = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _signUp = false;
  bool _busy = false;
  String? _msg;
  bool _isError = true;
  String? _pendingEmail;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_key.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final email = _email.text.trim();
      if (_signUp) {
        final started = await Db.i.signUp(email, _pass.text, {
          'full_name': _name.text.trim(),
          'phone': _phone.text.trim(),
          'language': Settings.instance.langName,
        });
        if (!started && mounted) {
          setState(() {
            _signUp = false;
            _isError = false;
            _pendingEmail = email;
            _msg = context.tr('account_created');
          });
        }
      } else {
        await Db.i.signIn(email, _pass.text);
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _isError = true;
          _msg = e.message;
          if (e.message.toLowerCase().contains('not confirmed')) _pendingEmail = _email.text.trim();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isError = true;
          _msg = context.tr('err_generic');
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    final email = _pendingEmail;
    if (email == null) return;
    setState(() => _busy = true);
    try {
      await Db.i.resendConfirmation(email);
      if (mounted) {
        setState(() {
          _isError = false;
          _msg = context.tr('resent', {'email': email});
        });
      }
    } on AuthException catch (e) {
      if (mounted) setState(() { _isError = true; _msg = e.message; });
    } catch (_) {
      if (mounted) {
        setState(() {
          _isError = true;
          _msg = context.tr('err_email');
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Sends a password reset email to the address typed in the email box.
  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() {
        _isError = true;
        _msg = context.tr('enter_email_first');
      });
      return;
    }
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email, redirectTo: resetRedirect);
      // Same message whether or not the account exists, so nobody can probe for accounts.
      if (mounted) {
        setState(() {
          _isError = false;
          _msg = context.tr('reset_sent', {'email': email});
        });
      }
    } on AuthException catch (e) {
      if (mounted) setState(() { _isError = true; _msg = e.message; });
    } catch (_) {
      if (mounted) {
        setState(() {
          _isError = true;
          _msg = context.tr('err_email');
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final linkStyle = TextButton.styleFrom(
      foregroundColor: context.link,
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    );
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _key,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Center(child: CoopLogo(height: 88)),
                  const SizedBox(height: 10),
                  Text(
                    context.tr('hero_title'),
                    textAlign: TextAlign.center,
                    style: t.bodyMedium?.copyWith(color: context.muted),
                  ),
                  const SizedBox(height: 28),
                  Text(_signUp ? context.tr('create_account_title') : context.tr('welcome_back'), style: t.titleLarge),
                  const SizedBox(height: 16),
                  if (_signUp) ...[
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(labelText: context.tr('full_name')),
                      validator: (v) => (v == null || v.trim().isEmpty) ? context.tr('required') : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(labelText: context.tr('phone_number')),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: InputDecoration(labelText: context.tr('email')),
                    validator: (v) => (v == null || !v.contains('@')) ? context.tr('valid_email') : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _pass,
                    obscureText: true,
                    decoration: InputDecoration(labelText: context.tr('password')),
                    validator: (v) => (v == null || v.length < 6) ? context.tr('pass_min') : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  if (!_signUp)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        style: linkStyle,
                        onPressed: _busy ? null : _forgot,
                        child: Text(context.tr('forgot_password')),
                      ),
                    ),
                  if (_msg != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _msg!,
                      style: t.bodyMedium?.copyWith(color: _isError ? Theme.of(context).colorScheme.error : context.brand),
                    ),
                  ],
                  if (_pendingEmail != null)
                    TextButton(
                      style: linkStyle,
                      onPressed: _busy ? null : _resend,
                      child: Text(context.tr('resend_confirm')),
                    ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(_signUp ? context.tr('create_account') : context.tr('sign_in')),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    style: linkStyle,
                    onPressed: _busy ? null : () => setState(() { _signUp = !_signUp; _msg = null; }),
                    child: Text(_signUp ? context.tr('have_account') : context.tr('new_here')),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
