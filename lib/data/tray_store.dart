import 'package:shared_preferences/shared_preferences.dart';

abstract interface class TrayStore {
  Future<String?> read();
  Future<void> write(String value);
}

class PreferencesTrayStore implements TrayStore {
  final _preferences = SharedPreferencesAsync();
  static const _key = 'easy_dice_thrower.tray.v1';

  @override
  Future<String?> read() => _preferences.getString(_key);

  @override
  Future<void> write(String value) => _preferences.setString(_key, value);
}
