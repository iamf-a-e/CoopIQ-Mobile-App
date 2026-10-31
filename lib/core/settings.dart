import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'strings.dart';

/// App-level settings saved on the device: language, dark mode and
/// notification preferences. Call [load] once in main() before runApp.
class Settings extends ChangeNotifier {
  Settings._();
  static final Settings instance = Settings._();

  SharedPreferences? _prefs;
  String _lang = 'en';
  ThemeMode _mode = ThemeMode.system;
  bool _reminders = true;
  bool _tips = true;
  bool _agrovet = true;

  String get lang => _lang;
  String get langName => Strings.nameOf(_lang);
  ThemeMode get themeMode => _mode;
  bool get remindersOn => _reminders;
  bool get tipsOn => _tips;
  bool get agrovetOn => _agrovet;

  Future<void> load() async {
    final p = _prefs = await SharedPreferences.getInstance();
    final l = p.getString('settings.lang');
    if (l != null && Strings.supports(l)) _lang = l;
    switch (p.getString('settings.theme')) {
      case 'dark':
        _mode = ThemeMode.dark;
        break;
      case 'light':
        _mode = ThemeMode.light;
        break;
      default:
        _mode = ThemeMode.system;
    }
    _reminders = p.getBool('settings.notif.reminders') ?? true;
    _tips = p.getBool('settings.notif.tips') ?? true;
    _agrovet = p.getBool('settings.notif.vet') ?? true;
  }

  Future<void> setLang(String code) async {
    if (!Strings.supports(code) || code == _lang) return;
    _lang = code;
    notifyListeners();
    await _prefs?.setString('settings.lang', code);
  }

  Future<void> setDark(bool dark) async {
    _mode = dark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    await _prefs?.setString('settings.theme', dark ? 'dark' : 'light');
  }

  Future<void> setReminders(bool v) async {
    _reminders = v;
    notifyListeners();
    await _prefs?.setBool('settings.notif.reminders', v);
  }

  Future<void> setTips(bool v) async {
    _tips = v;
    notifyListeners();
    await _prefs?.setBool('settings.notif.tips', v);
  }

  Future<void> setAgrovet(bool v) async {
    _agrovet = v;
    notifyListeners();
    await _prefs?.setBool('settings.notif.vet', v);
  }
}

/// Makes every widget that calls context.tr(...) rebuild when the language
/// changes, even if the widget itself is const.
class SettingsScope extends InheritedNotifier<Settings> {
  const SettingsScope({super.key, required Settings settings, required super.child})
      : super(notifier: settings);

  static Settings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsScope>()?.notifier ?? Settings.instance;
}

extension Tr on BuildContext {
  /// Translated text for [key] in the current app language. Placeholders
  /// like {day} are filled from [args].
  String tr(String key, [Map<String, String>? args]) =>
      Strings.lookup(SettingsScope.of(this).lang, key, args);
}
