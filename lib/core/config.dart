class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL',
      defaultValue: 'https://bpimmhuezwuiobctzygd.supabase.co');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY',
      defaultValue: 'PASTE_YOUR_ANON_KEY_HERE');

  static const authRedirectUrl = String.fromEnvironment('AUTH_REDIRECT_URL',
      defaultValue: 'https://www.urbanmunda.com/auth/confirm');

  static const agrovetWhatsApp =
      String.fromEnvironment('AGROVET_WHATSAPP', defaultValue: '260000000000');

  static const supportEmail = 'hello@coopiq.africa';
  static const languages = ['English', 'Nyanja', 'Bemba', 'Lozi', 'Tonga'];
  static const diagnosisBucket = 'diagnosis-images';
}
