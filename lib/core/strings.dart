import 'strings_screens.dart';

/// All translatable text for the app.
///
/// English is the base. Any key missing in another language falls back to
/// English, so a half-translated language never shows blanks or raw keys.
/// Bemba, Tonga and Lozi are first drafts: have a native speaker review them.
class Lang {
  final String code, name;
  const Lang(this.code, this.name);
}

class Strings {
  static const languages = [
    Lang('en', 'English'),
    Lang('bem', 'Bemba'),
    Lang('nya', 'Nyanja'),
    Lang('tog', 'Tonga'),
    Lang('loz', 'Lozi'),
  ];

  static bool supports(String code) => languages.any((l) => l.code == code);

  static String nameOf(String code) =>
      languages.firstWhere((l) => l.code == code, orElse: () => languages.first).name;

  /// Looks up [key] in [lang], falling back to English, then to the key itself.
  /// Placeholders like {day} are replaced from [args].
  static String lookup(String lang, String key, [Map<String, String>? args]) {
    var s = _all[lang]?[key] ?? _all['en']![key] ?? key;
    if (args != null) {
      for (final e in args.entries) {
        s = s.replaceAll('{${e.key}}', e.value);
      }
    }
    return s;
  }

  static const Map<String, Map<String, String>> _all = {
    'en': {..._en, ...ScreenStrings.en},
    'bem': {..._bem, ...ScreenStrings.bem},
    'nya': {..._nya, ...ScreenStrings.nya},
    'tog': {..._tog, ...ScreenStrings.tog},
    'loz': {..._loz, ...ScreenStrings.loz},
  };

  // ───────────────────────── English (base) ─────────────────────────
  static const Map<String, String> _en = {
    // navigation
    'nav_home': 'Home',
    'nav_diagnose': 'Diagnose',
    'nav_flock': 'Flock',
    'nav_agrovet': 'Vet',
    'nav_profile': 'Profile',
    'ask_coopiq': 'Ask CoopIQ',
    // home
    'greet_morning': 'Good morning,',
    'greet_afternoon': 'Good afternoon,',
    'greet_evening': 'Good evening,',
    'farmer': 'Farmer',
    'hero_label': 'Photo diagnosis',
    'hero_title': 'A photo in. A diagnosis out.',
    'hero_sub': 'Catch disease in your flock or herd before it spreads.',
    'check_photo': 'Check a photo',
    'act_ask': 'Ask CoopIQ',
    'act_agrovet': 'Talk to a vet',
    'act_visit': 'Book farm visit',
    'act_library': 'Farm library',
    'track_batch': 'Track a broiler batch',
    'track_batch_sub': 'Add your chick arrival date to get vaccination reminders.',
    'batch_day': 'Batch day {day} of 42',
    'vax_done': 'All scheduled vaccinations are done.',
    'next_vax': 'Next: {vaccine} on day {day}',
    'today_farm': 'Today on the farm',
    // notifications
    'notifications': 'Notifications',
    'no_notifs': "You're all caught up.",
    'no_notifs_sub': 'New reminders will show up here.',
    'vax_reminder': 'Vaccination reminder',
    'notif_prefs': 'Notification preferences',
    'np_reminders': 'Vaccination reminders',
    'np_reminders_sub': 'Alerts when a batch vaccination is due',
    'np_tips': 'Daily farm tips',
    'np_tips_sub': 'A short health tip each day',
    'np_agrovet': 'Vet updates',
    'np_agrovet_sub': 'Updates on your visit and consultation requests',
    // auth
    'welcome_back': 'Welcome back',
    'create_account_title': 'Create your account',
    'full_name': 'Full name',
    'phone': 'Phone or WhatsApp',
    'email': 'Email',
    'password': 'Password',
    'required': 'Required',
    'valid_email': 'Enter a valid email',
    'pass_min': 'At least 6 characters',
    'resend_confirm': 'Resend confirmation email',
    'sign_in': 'Sign in',
    'create_account': 'Create account',
    'have_account': 'I already have an account',
    'new_here': 'New to CoopIQ? Create an account',
    'account_created': 'Account created. Check your email to confirm it, then sign in.',
    'resent': 'A new confirmation email is on its way to {email}.',
    'err_generic': 'Something went wrong. Check your connection and try again.',
    'err_email': 'Could not send the email. Check your connection.',
    // profile
    'language': 'Language',
    'choose_language': 'Choose language',
    'sec_prefs': 'Preferences',
    'sec_account': 'Account',
    'sec_help': 'Help and information',
    'dark_mode': 'Dark mode',
    'dark_mode_sub': 'Easier on the eyes at night',
    'change_password': 'Change password',
    'support': 'Support',
    'about': 'About CoopIQ',
    'privacy': 'Privacy',
    'sign_out': 'Sign out',
    'new_password': 'New password',
    'confirm_password': 'Confirm new password',
    'pass_mismatch': 'Passwords do not match',
    'update_password': 'Update password',
    'pass_updated': 'Password updated.',
    // support / about / privacy
    'support_intro': 'Need help? Reach the CoopIQ team.',
    'sup_email': 'Email us',
    'sup_whatsapp': 'Chat on WhatsApp',
    'sup_web': 'Visit our website',
    'couldnt_open': 'Could not open that link.',
    'version': 'Version',
    'about_body':
        'CoopIQ helps poultry and livestock farmers spot disease early, plan vaccinations and reach a vet. Advice in the app is guidance only and does not replace a veterinarian.',
    'privacy_body':
        'This page explains in plain language what CoopIQ collects and why.\n\n'
        'What we collect\n'
        'Your name, email and phone number when you sign up. The photos you upload for diagnosis. Your questions to CoopIQ and the answers you receive. Your batch and vaccination records.\n\n'
        'How we use it\n'
        'To give you diagnoses and answers, to remind you about vaccinations, to connect you with a vet when you ask, and to keep your account secure.\n\n'
        'Who can see it\n'
        'Your records are linked to your account and stored with our hosting provider. Photos and questions are sent to an AI service so it can produce a diagnosis or an answer.\n\n'
        'Your choices\n'
        'You can change your password, language and notification settings in Profile at any time. To have your account and data deleted, contact Support.\n\n'
        'AI advice is guidance only. For a sick or dying flock or herd, contact a veterinarian or vet.',
  };

  // ───────────────────────── Nyanja ─────────────────────────
  static const Map<String, String> _nya = {
    'nav_home': 'Kunyumba',
    'nav_diagnose': 'Kuyeza',
    'nav_flock': 'Nkhuku',
    'nav_profile': 'Za ine',
    'ask_coopiq': 'Funsani CoopIQ',
    'greet_morning': 'Mwauka bwanji,',
    'greet_afternoon': 'Masana abwino,',
    'greet_evening': 'Madzulo abwino,',
    'farmer': 'Mlimi',
    'hero_label': 'Kuzindikira matenda ndi chithunzi',
    'hero_title': 'Chithunzi chimodzi. Yankho la matenda.',
    'hero_sub': 'Dziwani matenda mu nkhuku kapena ziweto zanu asanafalikire.',
    'check_photo': 'Yeza chithunzi',
    'act_ask': 'Funsani CoopIQ',
    'act_agrovet': 'Lankhulani ndi vet',
    'act_visit': 'Pemphani kuyendera famu',
    'act_library': 'Laibulale ya famu',
    'track_batch': 'Tsatirani gulu la nkhuku',
    'track_batch_sub': 'Lowetsani tsiku lomwe ana a nkhuku anafika kuti mulandire zikumbutso za katemera.',
    'batch_day': 'Tsiku {day} mwa 42',
    'vax_done': 'Katemera yense wachitika.',
    'next_vax': 'Wotsatira: {vaccine} pa tsiku {day}',
    'today_farm': 'Lero pa famu',
    'notifications': 'Zidziwitso',
    'no_notifs': 'Palibe chatsopano.',
    'no_notifs_sub': 'Zikumbutso zatsopano zidzaoneka pano.',
    'vax_reminder': 'Chikumbutso cha katemera',
    'notif_prefs': 'Zokonda za zidziwitso',
    'np_reminders': 'Zikumbutso za katemera',
    'np_reminders_sub': 'Chenjezo katemera wa gulu akayandikira',
    'np_tips': 'Malangizo a tsiku ndi tsiku',
    'np_tips_sub': 'Langizo lalifupi la thanzi tsiku lililonse',
    'np_agrovet': 'Nkhani za vet',
    'np_agrovet_sub': 'Zosintha pa pempho lanu la kuyendera ndi uphungu',
    'welcome_back': 'Takulandirani kubwerera',
    'create_account_title': 'Tsegulani akaunti yanu',
    'full_name': 'Dzina lonse',
    'phone': 'Foni kapena WhatsApp',
    'email': 'Imelo',
    'password': 'Chinsinsi',
    'required': 'Zofunika',
    'valid_email': 'Lowetsani imelo yolondola',
    'pass_min': 'Zilembo zosachepera 6',
    'resend_confirm': 'Tumizaninso imelo yotsimikizira',
    'sign_in': 'Lowani',
    'create_account': 'Tsegulani akaunti',
    'have_account': 'Ndili kale ndi akaunti',
    'new_here': 'Mwatsopano pa CoopIQ? Tsegulani akaunti',
    'account_created': 'Akaunti yatsegulidwa. Onani imelo yanu kuti mutsimikizire, kenako lowani.',
    'resent': 'Imelo yatsopano yotsimikizira ikupita ku {email}.',
    'err_generic': 'Pali vuto. Onani intaneti yanu ndipo yesaninso.',
    'err_email': 'Imelo siinatumizidwe. Onani intaneti yanu.',
    'language': 'Chilankhulo',
    'choose_language': 'Sankhani chilankhulo',
    'sec_prefs': 'Zokonda',
    'sec_account': 'Akaunti',
    'sec_help': 'Thandizo ndi zambiri',
    'dark_mode': 'Njira ya mdima',
    'dark_mode_sub': 'Yabwino kwa maso usiku',
    'change_password': 'Sinthani chinsinsi',
    'support': 'Thandizo',
    'about': 'Za CoopIQ',
    'privacy': 'Zinsinsi',
    'sign_out': 'Tulukani',
    'new_password': 'Chinsinsi chatsopano',
    'confirm_password': 'Tsimikizirani chinsinsi chatsopano',
    'pass_mismatch': 'Zinsinsi sizikufanana',
    'update_password': 'Sinthani chinsinsi',
    'pass_updated': 'Chinsinsi chasinthidwa.',
    'support_intro': 'Mukufuna thandizo? Lankhulani ndi gulu la CoopIQ.',
    'sup_email': 'Titumizireni imelo',
    'sup_whatsapp': 'Lankhulani nafe pa WhatsApp',
    'sup_web': 'Pitani patsamba lathu',
    'couldnt_open': 'Sitinathe kutsegula ulalo umenewo.',
    'version': 'Mtundu',
    'about_body':
        "CoopIQ imathandiza alimi a nkhuku ndi ziweto kuzindikira matenda msanga, kukonza katemera ndi kulumikizana ndi vet. Malangizo a mu pulogalamuyi ndi chithandizo chokha ndipo salowa m'malo mwa dokotala wa ziweto.",
  };

  // ───────────────────────── Bemba (draft, partial) ─────────────────────────
  static const Map<String, String> _bem = {
    'nav_home': "Ing'anda",
    'nav_diagnose': 'Pima',
    'nav_flock': 'Inkoko',
    'nav_profile': 'Ine',
    'ask_coopiq': 'Ipusha CoopIQ',
    'greet_morning': 'Mwashibukeni,',
    'greet_afternoon': 'Mwapoleni,',
    'greet_evening': 'Mwapoleni,',
    'farmer': 'Umulimi',
    'check_photo': 'Pima photo',
    'act_ask': 'Ipusha CoopIQ',
    'act_agrovet': 'Lanshanya na vet',
    'welcome_back': 'Mwaiseni',
    'create_account_title': 'Panga akaunti yobe',
    'sign_in': 'Ingila',
    'create_account': 'Panga akaunti',
    'language': 'Ululimi',
    'choose_language': 'Sala ululimi',
    'sec_account': 'Akaunti',
    'dark_mode': 'Mode ya bushiku',
    'change_password': 'Cinja password',
    'support': 'Ubwafwilisho',
    'about': 'Pa CoopIQ',
    'sign_out': 'Fuma',
    'new_password': 'Password ipya',
    'update_password': 'Cinja password',
    'pass_updated': 'Password yacinjiwa.',
  };

  // ───────────────────────── Tonga (draft, partial) ─────────────────────────
  static const Map<String, String> _tog = {
    'nav_home': "Ng'anda",
    'nav_diagnose': 'Linga',
    'nav_flock': 'Nkuku',
    'nav_profile': 'Ndime',
    'ask_coopiq': 'Buzya CoopIQ',
    'greet_morning': 'Mwabuka buti,',
    'greet_afternoon': 'Mwalibizya buti,',
    'greet_evening': 'Mwalibizya buti,',
    'farmer': 'Mulimi',
    'check_photo': 'Linga foto',
    'act_ask': 'Buzya CoopIQ',
    'act_agrovet': 'Amba a vet',
    'create_account_title': 'Panga akaunti',
    'sign_in': 'Ingila',
    'create_account': 'Panga akaunti',
    'language': 'Mwaambo',
    'choose_language': 'Sala mwaambo',
    'sec_account': 'Akaunti',
    'dark_mode': 'Mode ya mudima',
    'change_password': 'Cinca password',
    'support': 'Lugwasyo',
    'about': 'Aa CoopIQ',
    'sign_out': 'Zwa',
    'update_password': 'Cinca password',
  };

  // ───────────────────────── Lozi (draft, partial) ─────────────────────────
  static const Map<String, String> _loz = {
    'nav_home': 'Ndu',
    'nav_diagnose': 'Lekanya',
    'nav_flock': 'Kuku',
    'nav_profile': 'Nna',
    'ask_coopiq': 'Buza CoopIQ',
    'greet_morning': 'Mwa zuhile,',
    'greet_afternoon': 'Mwa shapile,',
    'greet_evening': 'Mwa shapile,',
    'farmer': 'Mulimi',
    'check_photo': 'Lekanya foto',
    'act_ask': 'Buza CoopIQ',
    'act_agrovet': 'Bulelela ni vet',
    'create_account_title': 'Bupa akaunti',
    'sign_in': 'Kena',
    'create_account': 'Bupa akaunti',
    'language': 'Puo',
    'choose_language': 'Keta puo',
    'sec_account': 'Akaunti',
    'change_password': 'Fetola password',
    'support': 'Tuso',
    'about': 'Ka za CoopIQ',
    'sign_out': 'Zwa',
    'update_password': 'Fetola password',
  };
}
