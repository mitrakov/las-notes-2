// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:shared_preferences/shared_preferences.dart';

class Settings {
  Settings._();
  static final Settings _instance = Settings._();
  static SharedPreferences? _preferences;
  static Future<void> init() async => _preferences = await SharedPreferences.getInstance();
  static Settings get local {
    if (_preferences != null) return _instance;
    else throw Exception("Settings are not initialized. Call Settings.local.init() first");
  }

  // show archives
  bool get showArchive    => _preferences!.getBool("_SHOW_ARCHIVE") ?? false;
  set showArchive(bool v) => _preferences!.setBool("_SHOW_ARCHIVE", v);

  // recent files
  List<String> get recentFiles => _preferences!.getStringList("_RECENT_FILES") ?? [];

  void addToRecentFiles(String path) {
    final list = _preferences!.getStringList("_RECENT_FILES") ?? [];
    if (list.firstOrNull == path) return; // no changes needed
    if (list.contains(path))              // remove possible duplicates
      list.remove(path);
    list.insert(0, path);                 // prepend to the list
    _preferences!.setStringList("_RECENT_FILES", list);
  }

  void removeFromRecentFiles(String path) {
    final list = _preferences!.getStringList("_RECENT_FILES") ?? [];
    list.remove(path);
    _preferences!.setStringList("_RECENT_FILES", list);
  }
}
