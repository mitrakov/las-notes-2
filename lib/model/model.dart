import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:scoped_model/scoped_model.dart';
import 'package:lasnotes/model/db.dart';
import 'package:lasnotes/model/note.dart';
import 'package:lasnotes/model/settings.dart';
import 'package:lasnotes/widgets/webdavview.dart';
import 'package:lasnotes/utils.dart';
import 'package:path/path.dart' show extension;

final class TheModel extends Model {
  final _db = SQLiteDatabase();
  final _webDav = WebDavController();
  String? _currentPath;

  String? get currentPath => _currentPath;
  List<String> get recentFiles => Settings.local.recentFiles;
  bool get showArchive => Settings.local.showArchive;
  WebDavController get webDav => _webDav;
  Future<void> setShowArchive(bool v) => Settings.local.setShowArchive(v);

  Future<bool> openFile
      (String path, ValueSetter<String> onError, AsyncValueGetter<String?> askPasswd, {String? removeMe}) async {
    if (File(path).existsSync()) {
      final ext = extension(path);
      switch (ext) {
        case ".db":                              // regular
          await _db.openDb(path);
          break;
        case ".dbx":                             // encrypted
          final password = removeMe ?? await askPasswd();
          if (password == null) return false;
          try {
            await _db.openDb(path, password: password);
          } catch (e) {
            // note that messages differ on iOS/MacOS and Windows
            if (e.toString().contains("file is not a database") || e.toString().startsWith("DatabaseException(open_failed"))
              onError("Cannot open encrypted DB file. Wrong password?");
            else if (e.toString().startsWith('DatabaseException(Error Domain=FMDatabase Code=7 "out of memory"')) {
              // BUG in sqflite_sqlcipher: https://github.com/davidmartos96/sqflite_sqlcipher/issues/115. Once fixed, rm recursion
              openFile(path, onError, askPasswd, removeMe: password);
            } else onError(e.toString());
            return true;
          }
          break;
        default:
          onError("File extension not supported: $ext\n Supported types: *.db (Regular DB), *.dbx (Encrypted DB)");
          return false;
      }

      _currentPath = path;
      notifyListeners();
      Settings.local.addToRecentFiles(path);
      return true;
    } else {
      onError("File not found:\n$path");
      Settings.local.removeFromRecentFiles(path);
      return false;
    }
  }

  Future<void> openFileWithDialog(ValueSetter<String> onError, AsyncValueGetter<String?> askPasswd) async {
    // 1) on iOS/macOS, also update ios/Runner/Info.plist & macos/Runner/Info.plist
    // 2) since FilePicker v10.3.7, you must add to macos/Runner/DebugProfile.entitlements and Release.entitlements:
    // <key>com.apple.security.files.user-selected.read-write</key><true/>
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: "Open a DB file",
      type: Platform.isAndroid ? FileType.any : FileType.custom,    // TODO: For Android, need to register "db" and "dbx" mime-types
      allowedExtensions: Platform.isAndroid ? null : ["db", "dbx"], // TODO: For Android, need to register "db" and "dbx" mime-types
      lockParentWindow: true,
    );
    final path = result?.files.firstOrNull?.path;
    if (path != null)
      openFile(path, onError, askPasswd);
  }

  Future<void> newFile(AsyncCallback passwdWarning, AsyncValueGetter<String?> askPasswd, ValueSetter<String> onError,
      {bool? encrypted}) async {
    final encrypt = encrypted ?? false;
    final path = await FilePicker.platform.saveFile(
      dialogTitle: encrypt ? "Create a new encrypted DB file" : "Create a new DB file",
      fileName: encrypt ? "mydb.dbx" : "mydb.db",
      type: FileType.custom,
      allowedExtensions: encrypt ? ["dbx"] : ["db"],
      lockParentWindow: true,
    );
    if (path != null) {
      final file = File(path);
      if (file.existsSync()) {
        // TODO check "replace file?" on all platforms; probably is to remove this code section
        await _db.closeDb();
        file.deleteSync();
      }

      final ext = extension(path);
      switch (ext) {
        case ".db":                              // regular
          await _db.createDb(path);
          break;
        case ".dbx":                             // encrypted
          await passwdWarning();
          final password = await askPasswd();
          if (password == null) return;
          await _db.createDb(path, password: password);
          break;
        default:
          onError("File extension not supported: $ext\n Supported types: *.db (Regular DB), *.dbx (Encrypted DB)");
          return;
      }

      _currentPath = path;
      notifyListeners();
      Settings.local.addToRecentFiles(path);
    }
  }

  Future<void> closeFile() async {
    await _db.closeDb();
    _webDav.close();
    _currentPath = null;
    notifyListeners();
  }

  Future<Iterable<String>> getTags() => _db.getTags(showArchive);

  Future<Iterable<Note>> getAllNotes() => _db.getAllNotes(showArchive);

  Future<Iterable<Note>> getRandomNotes(int max) => _db.getRandomNotes(showArchive, max);

  Future<Note?> searchById(int noteId) => _db.searchByID(noteId);

  FutureOr<Iterable<Note>> searchByTag(String tag) {
    if (tag.trim().isEmpty) return [];
    return _db.searchByTag(tag, showArchive);
  }

  FutureOr<Iterable<Note>> searchByKeyword(String word) {
    if (word.trim().isEmpty) return [];
    return _db.searchByKeyword(word, showArchive);
  }

  Future<void> archiveNoteById(int noteId) => _db.softDeleteNote(noteId, true);

  Future<void> restoreNoteById(int noteId) => _db.softDeleteNote(noteId, false);

  Future<void> deleteNoteById(int noteId) => _db.deleteNote(noteId);

  FutureOr<int?> saveNote
      (int? noteId, String data, String newTags, String oldTags, Attachment? attachment, VoidCallback tagNeeded) async {
    final tags = Utils.split(newTags);

    if (!_db.isConnected()) return null;
    if (data.trim().isEmpty) return null;
    if (tags.isEmpty) {
      tagNeeded();
      return null;
    }

    if (noteId != null) {
      // UPDATE
      await _db.updateNote(noteId, data, attachment);
      await _updateTags(noteId, newTags, oldTags);
      return noteId;
    } else {
      // INSERT
      final newNoteId = await _db.insertNote(data, attachment);
      await _db.linkTagsToNote(newNoteId, tags);
      return newNoteId;
    }
  }

  Future<void> uploadWebDav() => _webDav.updateSafe(_currentPath);

  Future<void> _updateTags(int noteId, String newTagsStr, String oldTagsStr) async {
    final oldTags = Utils.split(oldTagsStr).toSet();
    final newTags = Utils.split(newTagsStr).toSet();
    final rmTags  = oldTags.difference(newTags);
    final addTags = newTags.difference(oldTags);

    await _db.unlinkTagsFromNote(noteId, rmTags);
    await _db.linkTagsToNote(noteId, addTags);
  }
}
