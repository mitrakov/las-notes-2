import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:scoped_model/scoped_model.dart';
import 'package:lasnotes/model/db.dart';
import 'package:lasnotes/model/note.dart';
import 'package:lasnotes/model/settings.dart';
import 'package:lasnotes/widgets/inputbox.dart';
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

  void openFile(BuildContext context, String path, {String? removeMe}) async {
    if (File(path).existsSync()) {
      final ext = extension(path);
      switch (ext) {
        case ".db":                              // regular
          print("Opening regular DB file $path");
          await _db.openDb(path);
          break;
        case ".dbx":                             // encrypted
          final password = removeMe ?? await showInputBox(context, "Enter password", hint: "Password");
          if (password == null) return;
          print("Opening encrypted DB file $path with password: ${password.replaceAll(RegExp(r'.'), '•')}.");
          try {
            await _db.openDb(path, password: password);
          } catch (e) {
            // note that messages differ on iOS/MacOS and Windows
            if (e.toString().contains("file is not a database") || e.toString().startsWith("DatabaseException(open_failed")) {
              const msg = "Cannot open encrypted DB file. Wrong password?";
              Utils.showAlert("Error", msg, .error, .ok);
            } else if (e.toString().startsWith('DatabaseException(Error Domain=FMDatabase Code=7 "out of memory"')) {
              // BUG in sqflite_sqlcipher: https://github.com/davidmartos96/sqflite_sqlcipher/issues/115. Once fixed, rm recursion
              openFile(context, path, removeMe: password);
            } else Utils.showAlert("Error", e.toString(), .error, .ok);
            return;
          }
          break;
        default:
          return _showExtensionError(ext);
      }

      _currentPath = path;
      notifyListeners();
      Settings.local.addToRecentFiles(path);
    } else {
      Utils.showAlert("Error", "File not found:\n$path", .error, .ok);
      Settings.local.removeFromRecentFiles(path);
    }
  }

  void openFileWithDialog(BuildContext context) async {
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
      openFile(context, path);
  }

  void newFile(BuildContext context, {bool? encrypted}) async {
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
          print("Creating regular DB file $path");
          await _db.createDb(path);
          break;
        case ".dbx":                             // encrypted
          const msg = "Please note your password!\nLater on, you cannot decrypt the DB file without it";
          await Utils.showAlert("DB encryption", msg, .exclamation, .ok);
          final password = await showInputBox(context, "Enter password", hint: "Password");
          if (password == null) return;
          print("Creating encrypted DB file $path");
          await _db.createDb(path, password: password);
          break;
        default:
          return _showExtensionError(ext);
      }

      _currentPath = path;
      notifyListeners();
      Settings.local.addToRecentFiles(path);
    }
  }

  void closeFile() async {
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

  Future<bool> archiveNoteById(int noteId) {
    return Utils.showAlert("Archive note", "Are you sure you want to archive this note?", .question, .yesNo, onYes: () async {
      await _db.softDeleteNote(noteId, true);
    });
  }

  Future<void> restoreNoteById(int noteId) {
    return _db.softDeleteNote(noteId, false);
  }

  Future<bool> deleteNoteById(int noteId) {
    const text = "Are you sure you want to delete this note? It cannot be undone";
    return Utils.showAlert("Delete note", text, .stop, .yesNo, onYes: () async {
      await _db.deleteNote(noteId);
    });
  }

  FutureOr<int?> saveNote(int? noteId, String data, String newTags, String oldTags, Attachment? attachment) async {
    final tags = Utils.split(newTags);

    if (!_db.isConnected()) return null;
    if (data.trim().isEmpty) return null;
    if (tags.isEmpty) {
      Utils.showAlert("Tag needed", "Add at least 1 tag\n(e.g. Home or Work)", .asterisk, .ok);
      return null;
    }

    if (noteId != null) {
      // UPDATE
      await _db.updateNote(noteId, data, attachment);
      await _updateTags(noteId, newTags, oldTags);
      Utils.showAlert("Done", "Note updated", .information, .ok);
      return noteId;
    } else {
      // INSERT
      final newNoteId = await _db.insertNote(data, attachment);
      await _db.linkTagsToNote(newNoteId, tags);
      Utils.showAlert("Done", "Note added", .information, .ok);
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

  void _showExtensionError(String ext) {
    final msg = "File extension not supported: $ext\n Supported types: *.db (Regular DB), *.dbx (Encrypted DB)";
    Utils.showAlert("Error", msg, .error, .ok);
  }
}
