// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_platform_alert/flutter_platform_alert.dart';
import 'package:file_picker/file_picker.dart';
import 'package:scoped_model/scoped_model.dart';
import 'package:lasnotes/model/db.dart';
import 'package:lasnotes/model/note.dart';
import 'package:lasnotes/model/settings.dart';
import 'package:lasnotes/widgets/inputbox.dart';
import 'package:lasnotes/utils.dart';
import 'package:path/path.dart' as p;

final class TheModel extends Model {
  final _db = SQLiteDatabase();
  String? _currentPath;

  String? get currentPath => _currentPath;
  List<String> get recentFiles => Settings.local.recentFiles;
  bool get showArchive => Settings.local.showArchive;
  Future<void> setShowArchive(bool v) => Settings.local.setShowArchive(v);

  void openFile(BuildContext context, String path) async {
    if (File(path).existsSync()) {
      final ext = p.extension(path);
      switch (ext) {
        case ".db":                              // regular
          print("Opening regular DB file $path");
          await _db.openDb(path);
          break;
        case ".dbx":                             // encrypted
          final password = await showInputBox(context, "Enter password", hint: "Password");
          if (password == null) return;
          print("Opening encrypted DB file $path with password: ${password.replaceAll(RegExp(r'.'), '•')}.");
          try {
            await _db.openDb(path, password: password);
          } catch (e) {
            const msg = "Cannot open encrypted DB file. Wrong password?";
            FlutterPlatformAlert.showAlert(windowTitle: "Error", text: msg, iconStyle: IconStyle.error);
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
      Utils.showAlert("Error", "File not found:\n$path", IconStyle.error, AlertButtonStyle.ok);
      Settings.local.removeFromRecentFiles(path);
    }
  }

  void openFileWithDialog(BuildContext context) async {
    // set FileType.any, because "FileType.any, allowedExtensions: ["db"]" doesn't work on iOS
    // TODO if iOS
    final result = (await FilePicker.platform.pickFiles(dialogTitle: "Open a DB file", type: FileType.any, lockParentWindow: true));
    final path = result?.files.firstOrNull?.path;
    if (path != null && context.mounted)
      openFile(context, path);
  }

  void newFile(BuildContext context, bool encrypted) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: encrypted ? "Create a new encrypted DB file" : "Create a new DB file",
      fileName: encrypted ? "mydb.dbx" : "mydb.db",
      type: FileType.custom,
      allowedExtensions: encrypted ? ["dbx"] : ["db"],
      lockParentWindow: true
    );
    if (path != null) {
      final file = File(path);
      if (file.existsSync()) {
        // TODO check "replace file?" on all platforms; probably is to remove this code section
        await _db.closeDb();
        file.deleteSync();
      }

      final ext = p.extension(path);
      switch (ext) {
        case ".db":                              // regular
          print("Creating regular DB file $path");
          await _db.createDb(path);
          break;
        case ".dbx":                             // encrypted
          const msg = "Please note your password!\nLater on, you cannot decrypt the DB file without it";
          await FlutterPlatformAlert.showAlert(windowTitle: "DB encryption", text: msg, iconStyle: IconStyle.exclamation);
          if (!context.mounted) return;
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

  Future<void> archiveNoteById(int noteId) {
    const text = "Are you sure you want to archive this note?";
    return Utils.showAlert("Archive note", text, IconStyle.question, AlertButtonStyle.yesNo, onYes: () async {
      await _db.softDeleteNote(noteId, true);
    });
  }

  Future<void> restoreNoteById(int noteId) => _db.softDeleteNote(noteId, false);

  Future<void> deleteNoteById(int noteId) {
    const text = "Are you sure you want to delete this note? It cannot be undone";
    return Utils.showAlert("Delete note", text, IconStyle.stop, AlertButtonStyle.yesNo, onYes: () async {
      await _db.deleteNote(noteId);
    });
  }

  FutureOr<int?> saveNote(int? noteId, String data, String newTags, String oldTags) async {
    final tags = Utils.split(newTags);

    if (!_db.isConnected()) return null;
    if (data.trim().isEmpty) return null;
    if (tags.isEmpty) {
      Utils.showAlert("Tag needed", "Add at least 1 tag\n(e.g. Home or Work)", IconStyle.asterisk, AlertButtonStyle.ok);
      return null;
    }

    if (noteId != null) {
      // UPDATE
      await _db.updateNote(noteId, data);
      await _updateTags(noteId, newTags, oldTags);
      Utils.showAlert("Done", "Note updated", IconStyle.information, AlertButtonStyle.ok);
      return noteId;
    } else {
      // INSERT
      final newNoteId = await _db.insertNote(data);
      await _db.linkTagsToNote(newNoteId, tags);
      Utils.showAlert("Done", "Note added", IconStyle.information, AlertButtonStyle.ok);
      return newNoteId;
    }
  }

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
    Utils.showAlert("Error", msg, IconStyle.error, AlertButtonStyle.ok);
  }
}
