import 'dart:io';
import 'package:flutter/material.dart';
import 'package:lasnotes/model/model.dart';
import 'package:lasnotes/utils.dart';
import 'package:lasnotes/widgets/inputbox.dart';
import 'package:lasnotes/widgets/webdavview.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:scoped_model/scoped_model.dart';

/// Helper class to relieve MainApp class
class Helper {
  void showWebDavDialogDesktop(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: .circular(20)),
          backgroundColor: Theme.of(context).colorScheme.surface,
          content: SizedBox(width: 400, child: WebDavView(this)),
        );
      },
    );
  }
  Future<String?> askPassword(BuildContext context) => showInputBox(context, "Enter password", hint: "Password");

  void showError(String msg) => Utils.showAlert("Error", msg, .error, .ok);

  void showTagWarning() => Utils.showAlert("Tag needed", "Add at least 1 tag\n(e.g. Home or Work)", .asterisk, .ok);

  Future<void> showDbxWarning() async {
    const msg = "Please note your password!\nLater on, you cannot decrypt the DB file without it";
    await Utils.showAlert("DB encryption", msg, .exclamation, .ok);
  }

  Future<bool> archiveNoteById(BuildContext context, int noteId) {
    const text = "Are you sure you want to archive this note?";
    return Utils.showAlert("Archive note", text, .question, .yesNo, onYes: () async {
      await ScopedModel.of<TheModel>(context).archiveNoteById(noteId);
    });
  }

  Future<bool> deleteNoteById(BuildContext context, int noteId) {
    const text = "Are you sure you want to delete this note? It cannot be undone";
    return Utils.showAlert("Delete note", text, .stop, .yesNo, onYes: () async {
      await ScopedModel.of<TheModel>(context).deleteNoteById(noteId);
    });
  }

  void showAboutDialog() async {
    final i = await PackageInfo.fromPlatform();
    final text = "v${i.version} (build: ${i.buildNumber})\n\nCopyright © 2024-2026\nmitrakov-artem@yandex.ru\nAll rights reserved.";
    if (Platform.isWindows) // bug in Windows: F1.keyUp event is swallowed by ModalDialog event loop => let's wait for 300 msec.
      Future.delayed(Duration(milliseconds: 300), () => Utils.showAlert(i.appName, text, .information, .ok));
    else Utils.showAlert(i.appName, text, .information, .ok);
  }
}

bool get isWinLinux => Platform.isWindows || Platform.isLinux;
bool get isDesktop  => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

enum EditorMode { read, edit }
enum SearchMode { all, tag, keyword, id, random }

class Search { // case class Search(String search, SearchMode by)
  final String search; final SearchMode by; Search(this.search, this.by);
  @override bool operator ==(Object o) =>
      identical(this,o) || o is Search && runtimeType == o.runtimeType && search == o.search && by == o.by;
  @override int get hashCode => Object.hash(search, by);
  @override String toString() => '{search: $search, by: $by}';
}

class NewDbFileIntent      extends Intent {}
class NewDbxFileIntent     extends Intent {}
class OpenDbFileIntent     extends Intent {}
class OpenWebDavFileIntent extends Intent {}
class CloseDbFileIntent    extends Intent {}
class NewNoteIntent        extends Intent {}
class EditNoteIntent       extends Intent {}
class SaveNoteIntent       extends Intent {}
class EscapeIntent         extends Intent {}
class GlobalSearchIntent   extends Intent {}
class AboutIntent          extends Intent {}
class BackIntent           extends Intent {}
class ForwardIntent        extends Intent {}
class InsertTableIntent    extends Intent {}
class InsertDateIntent     extends Intent {}
class InsertLinkIntent     extends Intent {}
class InsertAttachment     extends Intent {}
class CloseAppIntent       extends Intent {}
