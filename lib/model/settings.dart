import 'package:shared_preferences/shared_preferences.dart';

class Settings {
  static final String _RECENT_FILES        = "_RECENT_FILES";
  static final String _SHOW_ARCHIVE        = "_SHOW_ARCHIVE";
  static final String _WEBDAV_URI          = "_WEBDAV_URI";
  static final String _WEBDAV_LOGIN        = "_WEBDAV_LOGIN";
  static final String _WEBDAV_PASSWORD     = "_WEBDAV_PASSWORD";
  static final String _WEBDAV_INITIAL_PATH = "_WEBDAV_INITIAL_PATH";

  Settings._();
  static final Settings _instance = Settings._();
  static SharedPreferences? _preferences;
  static Future<void> init() async => _preferences = await SharedPreferences.getInstance();
  static Settings get local {
    if (_preferences != null) return _instance;
    else throw Exception("Settings are not initialized. Call Settings.local.init() first");
  }

  // show archives
  bool get showArchive => _preferences!.getBool(_SHOW_ARCHIVE) ?? false;
  Future<void> setShowArchive(bool v) async {
    if (v != showArchive)
      await _preferences!.setBool(_SHOW_ARCHIVE, v);
  }

  // recent files
  List<String> get recentFiles => _preferences!.getStringList(_RECENT_FILES) ?? [];

  Future<void> addToRecentFiles(String path) async {
    final list = _preferences!.getStringList(_RECENT_FILES) ?? [];
    if (list.firstOrNull == path) return; // no changes needed
    if (list.contains(path))              // remove possible duplicates
      list.remove(path);
    list.insert(0, path);                 // prepend to the list
    await _preferences!.setStringList(_RECENT_FILES, list);
  }

  Future<void> removeFromRecentFiles(String path) async {
    final list = _preferences!.getStringList(_RECENT_FILES) ?? [];
    list.remove(path);
    await _preferences!.setStringList(_RECENT_FILES, list);
  }

  // WebDAV settings
  String get webdavUri => _preferences!.getString(_WEBDAV_URI) ?? "";
  String get webdavLogin => _preferences!.getString(_WEBDAV_LOGIN) ?? "";
  String get webdavPass => _preferences!.getString(_WEBDAV_PASSWORD) ?? "";
  String get webdavInitPath => _preferences!.getString(_WEBDAV_INITIAL_PATH) ?? "/";
  Future<void> setWebdavConnection(String uri, String login, String pass) async {
    if (uri != webdavUri)
      await _preferences!.setString(_WEBDAV_URI, uri);
    if (login != webdavLogin)
      await _preferences!.setString(_WEBDAV_LOGIN, login);
    if (pass != webdavPass)
      await _preferences!.setString(_WEBDAV_PASSWORD, pass);
  }
  Future<void> setWebdavInitDir(String initDir) async {
    if (initDir != webdavInitPath)
      await _preferences!.setString(_WEBDAV_INITIAL_PATH, initDir);
  }
}
