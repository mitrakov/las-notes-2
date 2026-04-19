import 'dart:io';

import 'package:flutter/material.dart';

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
