import 'package:flutter/foundation.dart';

import '../data/app_database.dart';

class ThemePreference extends ChangeNotifier {
  ThemePreference(this._database, {required bool startsDark})
    : _isDark = startsDark;

  static Future<ThemePreference> load(AppDatabase database) async {
    final saved = await database.setting('dark_mode');
    return ThemePreference(database, startsDark: saved == 'true');
  }

  final AppDatabase _database;
  bool _isDark;

  bool get isDark => _isDark;

  Future<void> setDark(bool value) async {
    if (_isDark == value) return;
    _isDark = value;
    notifyListeners();
    await _database.setSetting('dark_mode', value.toString());
  }
}
