// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:io';
import 'dart:async';
import 'package:flutter_platform_alert/flutter_platform_alert.dart';
import 'package:file_picker/file_picker.dart';
import 'package:scoped_model/scoped_model.dart';
import 'package:lasnotes/model/db.dart';
import 'package:lasnotes/model/note.dart';
import 'package:lasnotes/model/settings.dart';
import 'package:lasnotes/utils.dart';

final class TheModel extends Model {
  final _db = SQLiteDatabase();
  String? _currentPath;

  String? get currentPath => _currentPath;
  List<String> get recentFiles => Settings.local.recentFiles;
  bool get showArchive => Settings.local.showArchive;
  set showArchive(bool value) => Settings.local.showArchive = value;

  void openFile(String path) async {
    if (File(path).existsSync()) {
      print("Opening file $path");
      await _db.openDb(path);
      _currentPath = path;
      notifyListeners();
      _addToRecentFilesList(path);
    } else {
      Utils.showAlert("Error", "File not found:\n$path", IconStyle.error, AlertButtonStyle.ok, (){}, (){});
      _removeFromRecentFilesList(path);
    }
  }

  void openFileWithDialog() async {
    // set FileType.any, because "FileType.any, allowedExtensions: ["db"]" doesn't work on iOS
    final result = (await FilePicker.platform.pickFiles(dialogTitle: "Open a DB file", type: FileType.any, lockParentWindow: true));
    final path = result?.files.firstOrNull?.path;
    if (path != null)
      openFile(path);
  }

  void newFile() async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: "Create a new DB file",
      fileName: "mydb.db",
      type: FileType.custom,
      allowedExtensions: ["db"],
      lockParentWindow: true
    );
    if (path != null) {
      final file = File(path);
      if (file.existsSync()) {
        // TODO check "replace file?" on all platforms
        await _db.closeDb();
        file.deleteSync();
      }

      print("Creating file $path");
      await _db.createDb(path);
      _currentPath = path;
      notifyListeners();
      _addToRecentFilesList(path);
    }
  }

  void closeFile() async {
    await _db.closeDb();
    _currentPath = null;
    notifyListeners();
  }

  Future<Iterable<String>> getTags() => _db.getTags();

  Future<Iterable<Note>> getAllNotes(bool showArchive) => _db.getAllNotes(showArchive);

  Future<Iterable<Note>> getRandomNotes(bool showArchive, int max) => _db.getRandomNotes(showArchive, max);

  Future<Note?> searchById(int noteId) => _db.searchByID(noteId);

  FutureOr<Iterable<Note>> searchByTag(String tag, bool showArchive) {
    if (tag.trim().isEmpty) return [];
    return _db.searchByTag(tag, showArchive);
  }

  FutureOr<Iterable<Note>> searchByKeyword(String word, bool showArchive) {
    if (word.trim().isEmpty) return [];
    return _db.searchByKeyword(word, showArchive);
  }

  Future<void> archiveNoteById(int noteId) async {
    const text = "Are you sure you want to archive this note?";
    Utils.showAlert("Archive note", text, IconStyle.question, AlertButtonStyle.yesNo, () async {
      await _db.softDeleteNote(noteId, true);
      notifyListeners(); // TODO: note is still shown on iOS
    }, (){});
  }

  Future<void> restoreNoteById(int noteId) async {
    await _db.softDeleteNote(noteId, false);
    notifyListeners();
  }

  Future<void> deleteNoteById(int noteId) async {
    const text = "Are you sure you want to delete this note? It cannot be undone";
    Utils.showAlert("Delete note", text, IconStyle.stop, AlertButtonStyle.yesNo, () async {
      await _db.deleteNote(noteId);
      notifyListeners(); // TODO: note is still shown on iOS
    }, (){});
  }

  FutureOr<int?> saveNote(int? noteId, String data, String newTags, String oldTags) async {
    final tags = Utils.split(newTags);

    if (!_db.isConnected()) return null;
    if (data.trim().isEmpty) return null;
    if (tags.isEmpty) {
      Utils.showAlert("Tag needed", "Add at least 1 tag\n(e.g. Home or Work)", IconStyle.asterisk, AlertButtonStyle.ok, () {}, (){});
      return null;
    }

    if (noteId != null) {
      // UPDATE
      await _db.updateNote(noteId, data);
      await _updateTags(noteId, newTags, oldTags);
      Utils.showAlert("Done", "Note updated", IconStyle.information, AlertButtonStyle.ok, () {}, (){});
      return noteId;
    } else {
      // INSERT
      final newNoteId = await _db.insertNote(data);
      await _db.linkTagsToNote(newNoteId, tags);
      Utils.showAlert("Done", "Note added", IconStyle.information, AlertButtonStyle.ok, () {}, (){});
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

  void _addToRecentFilesList(String item) {
    Settings.local.addToRecentFiles(item);
  }

  void _removeFromRecentFilesList(String item) {
    Settings.local.removeFromRecentFiles(item);
  }
}
