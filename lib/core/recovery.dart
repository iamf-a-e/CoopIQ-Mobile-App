import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Tracks whether the user arrived from a password-reset email link and still
/// has to choose a new password. AuthGate shows ResetPasswordScreen while true.
class RecoveryState {
  static final pending = ValueNotifier<bool>(false);
  static bool _listening = false;

  /// Call once in main(), straight after Supabase.initialize().
  static void listen() {
    if (_listening) return;
    _listening = true;
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) pending.value = true;
      if (data.event == AuthChangeEvent.signedOut) pending.value = false;
    });
  }
}
