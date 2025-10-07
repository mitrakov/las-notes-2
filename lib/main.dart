// ignore_for_file: curly_braces_in_flow_control_structures, use_key_in_widget_constructors, sort_child_properties_last
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' show basename;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_platform_alert/flutter_platform_alert.dart';
import 'package:share_plus/share_plus.dart';
import 'package:native_context_menu/native_context_menu.dart';
import 'package:scoped_model/scoped_model.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:window_manager/window_manager.dart';
import 'package:lasnotes/model/note.dart';
import 'package:lasnotes/model/model.dart';
import 'package:lasnotes/model/settings.dart';
import 'package:lasnotes/widgets/trixcontainer.dart';
import 'package:lasnotes/widgets/trixiconbutton.dart';
import 'package:lasnotes/utils.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // allow async code in main()
  await WindowManager.instance.ensureInitialized(); // must have
  await Settings.init(); // must have
  final model = TheModel();
  runApp(ScopedModel(model: model, child: LaApp(model)));
}

class LaApp extends StatelessWidget {
  final TheModel model;
  const LaApp(this.model);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Las Notes",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo), useMaterial3: true),
      home: Main(),
    );
  }
}

class Main extends StatefulWidget {
  @override State<Main> createState() => _MainState();
}

class _MainState extends State<Main> {
  final _currentText = TextEditingController(); // main text in add/edit mode
  final _currentTags = TextEditingController(); // comma-separated tags in the text field
  int? _currentNoteId;                          // if present, noteID in edit mode (otherwise NEW_NOTE mode)
  var _oldTags = "";                            // old comma-separated tags for edit mode (to calc tags diff)
  Iterable<Note> _notes = [];                   // in view mode, DB notes array for markdown view
  var _search = "";                             // search by tag name (SearchMode.tag), keyword (.keyword) or ID (.id)
  var _editorMode = EditorMode.edit;            // edit or view mode
  var _searchMode = SearchMode.tag;             // how to search notes (by clicking tag, by full-text search, by ID, or ALL)
  String? _currentPath;                         // copy of Model.currentPath to catch "onCurrentPathChange" event
  var _fileChanged = false;                     // for iOS, we need to warn user that the DB file may be lost

  bool get isDesktop => Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  bool get fileChanged => Platform.isIOS ? _fileChanged : false;
  set fileChanged(bool v) { if (Platform.isIOS) _fileChanged = v; }

  @override
  void initState() {
    super.initState();
    _currentText.addListener(() { setState(() {}); });
  }

  @override
  Widget build(BuildContext context) {
    return ScopedModelDescendant<TheModel>(builder: (context, child, model) {
      if (_currentPath != model.currentPath) {
        _currentPath = model.currentPath;
        _setReadMode("", SearchMode.all);
        if (isDesktop)
          windowManager.setTitle(model.currentPath != null ? "Las Notes (${model.currentPath})" : "Las Notes"); // careful, heavy op
      }
      return isDesktop ? _buildForDesktop(context, model) : _buildForMobile(context, model);
    });
  }

  Widget _buildForMobile(BuildContext context, TheModel model) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Las Notes"),
        actions: [
          IconButton(onPressed: _shareFile, icon: const Icon(Icons.ios_share)),
          IconButton(onPressed: _showAboutDialog, icon: const Icon(Icons.info_outline)),
        ],
      ),
      body: model.currentPath == null
          ? const Center(child: Text("Welcome!\nOpen a DB file"))
          : Padding(padding: const EdgeInsets.all(8.0), child: _makeMainAreaMobile(model)),
      drawer: Drawer(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(children: [
            const SizedBox(height: 50),
            TextField(
              decoration: const InputDecoration(border: OutlineInputBorder(), label: Text("Global search")),
              onSubmitted: (s) {
                _setReadMode(s, SearchMode.keyword);
                Navigator.pop(context);
              },
            ),
            CheckboxListTile(
              title: const Text("Show archive"),
              value: model.showArchive,
              onChanged: (v) => model.showArchive = v ?? false,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 20,),
            const Text("TAGS", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            FutureBuilder(future: model.getTags(), builder: (context, snapshot) {
              if (snapshot.hasData)
                return Expanded(child: ListView(children: snapshot.data!.map((tag) =>
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: OutlinedButton(
                      style: ButtonStyle(
                        alignment: Alignment.centerLeft,
                        backgroundColor: MaterialStateProperty.all(Colors.brown[50])
                      ),
                      child: Text(tag),
                      onPressed: () {
                        _setReadMode(tag, SearchMode.tag);
                        Navigator.pop(context);
                      },
                    ),
                  ),
                ).toList()));
              else return const CircularProgressIndicator(color: Colors.lime);
            },)
          ],),
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Visibility(
            visible: model.currentPath != null && _editorMode == EditorMode.read,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: FloatingActionButton(
                heroTag: "newNote",
                child: const Icon(Icons.note_add_outlined, size: 32),
                backgroundColor: Colors.lightGreen[800],
                onPressed: () => _setEditMode(null, "", ""),
              ),
            ),
          ),
          Visibility(
            visible: model.currentPath != null && _editorMode == EditorMode.edit,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: FloatingActionButton(
                heroTag: "saveNote",
                child: const Icon(Icons.cloud_done_sharp, size: 32),
                backgroundColor: Colors.green[500],
                onPressed: _saveNote,
              ),
            ),
          ),
          Visibility(
            visible: model.currentPath != null && _editorMode == EditorMode.edit,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: FloatingActionButton(
                heroTag: "cancelEdit",
                child: const Icon(Icons.cancel_presentation, size: 32),
                backgroundColor: Colors.red[300],
                onPressed: () => _setReadMode(_search, _searchMode),
              ),
            ),
          ),
          Visibility(
            visible: model.currentPath == null,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: FloatingActionButton(
                heroTag: "openFile",
                child: const Icon(Icons.open_in_new, size: 32),
                backgroundColor: Colors.blueAccent[100],
                onPressed: model.openFileWithDialog,
              ),
            ),
          ),
          Visibility(
            visible: model.currentPath != null && _editorMode == EditorMode.read,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: FloatingActionButton(
                heroTag: "closeFile",
                child: const Icon(Icons.stop_circle_outlined, size: 32),
                backgroundColor: Colors.blueAccent[100],
                onPressed: _closeFile,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForDesktop(BuildContext context, TheModel model) {
    final settings = Settings.local;
    return PlatformMenuBar(
      menus: [ // TODO: create menu for Windows/Linux
        PlatformMenu(
          label: "",
          menus: [
            PlatformMenuItemGroup(members: [
              PlatformMenuItem(label: "About Tommynotes", onSelected: _showAboutDialog),
            ]),
            PlatformMenuItem(label: "Quit", onSelected: () => exit(0)),
          ],
        ),
        PlatformMenu(
          label: "File",
          menus: [
            PlatformMenu(label: "Open Recent", menus: settings.recentFiles.map((path) =>
              PlatformMenuItem(label: path, onSelected: () => model.openFile(path))
            ).toList()),
            PlatformMenuItemGroup(members: [
              PlatformMenuItem(label: "New File", onSelected: model.newFile),
              PlatformMenuItem(label: "Open...", onSelected: model.openFileWithDialog),
            ]),
            PlatformMenuItem(label: "Close File", onSelected: model.closeFile),
          ],
        ),
      ],
      child: Shortcuts(
        shortcuts: {
          const SingleActivator(LogicalKeyboardKey.f1)                                                : AboutIntent(),
          const SingleActivator(LogicalKeyboardKey.escape)                                            : EscapeIntent(),
          SingleActivator(LogicalKeyboardKey.keyN, meta: Platform.isMacOS, control: !Platform.isMacOS): NewDbFileIntent(),
          SingleActivator(LogicalKeyboardKey.keyO, meta: Platform.isMacOS, control: !Platform.isMacOS): OpenDbFileIntent(),
          SingleActivator(LogicalKeyboardKey.keyS, meta: Platform.isMacOS, control: !Platform.isMacOS): SaveNoteIntent(),
          SingleActivator(LogicalKeyboardKey.keyW, meta: Platform.isMacOS, control: !Platform.isMacOS): CloseDbFileIntent(),
          SingleActivator(LogicalKeyboardKey.keyQ, meta: Platform.isMacOS, control: !Platform.isMacOS): CloseAppIntent(),
        },
        child: Actions(
          actions: {
            AboutIntent:       CallbackAction(onInvoke: (_) => _showAboutDialog()),
            EscapeIntent:      CallbackAction(onInvoke: (_) => _setReadMode(_search, _searchMode)),
            NewDbFileIntent:   CallbackAction(onInvoke: (_) => model.newFile()),
            OpenDbFileIntent:  CallbackAction(onInvoke: (_) => model.openFileWithDialog()),
            SaveNoteIntent:    CallbackAction(onInvoke: (_) => _saveNote()),
            CloseDbFileIntent: CallbackAction(onInvoke: (_) => model.closeFile()),
            CloseAppIntent:    CallbackAction(onInvoke: (_) => exit(0)),
          },
          child: Focus(               // needed for Shortcuts TODO RTFM about FocusNode
            autofocus: true,          // focused by default
            child: Scaffold(
              body: model.currentPath == null ? const Center(child: Text("Welcome!\nOpen or create a new DB file")) : Center(
                child: Row(children: [ // [left: tags, right: main window]
                  Expanded( // tags
                    child: FutureBuilder(
                      future: model.getTags(),
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          final tags = snapshot.data!.map((tag) => Padding(
                            padding: const EdgeInsets.only(top: 2), // Tag button on the left side
                            child: Padding( // TODO to method
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: OutlinedButton(
                                style: ButtonStyle(
                                  alignment: Alignment.centerLeft,
                                  backgroundColor: MaterialStateProperty.all(Colors.brown[50])
                                ),
                                child: Text(tag),
                                onPressed: () {
                                  _setReadMode(tag, SearchMode.tag);
                                  /// Navigator.pop(context);
                                },
                              ),
                            ),
                          )).toList();

                          return ListView(padding: const EdgeInsets.all(6),
                            children: [
                              Row(children: [
                                TrixIconTextButton.icon(
                                  icon: const Icon(Icons.add_box_rounded),
                                  label: const Text("New"),
                                  onPressed: () => _setEditMode(null, "", ""),
                                ),
                                Expanded(
                                  child: TextField(
                                    decoration: const InputDecoration(border: OutlineInputBorder(), label: Text("Global search")),
                                    onSubmitted: (s) { _setReadMode(s, SearchMode.keyword); },
                                  ),
                                ),
                              ]),
                              const Text("TAGS", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                              ...tags,
                            ]);
                        } else return const CircularProgressIndicator();
                      },
                    ),
                  ),
                  Flexible( // main window
                    flex: 6,
                    child: Column(children: [ // [top: edit/render panels, bottom: edit-tags/buttons panels]
                      Expanded(child: _editorMode == EditorMode.edit
                        ? Row(children: [ // [left: edit panel, right: render panel]
                            Expanded(child: TrixContainer(child: TextField(
                              controller: _currentText,
                              maxLines: 1024,
                              onChanged: (s) => setState(() {}) // TODO addListener
                            ))),
                            Expanded(child: TrixContainer(child: MarkdownWidget(data: _currentText.text))),
                          ])
                        : FutureBuilder(
                            future: _makeMainAreaDesktop(),
                            builder: (context, snapshot) => snapshot.data ?? const CircularProgressIndicator(),
                          ),
                      ),
                      Visibility(
                        visible: _editorMode == EditorMode.edit,
                        child: Row(children: [
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: SizedBox(
                              width: 400,
                              child: TextFormField(
                                controller: _currentTags,
                                decoration: const InputDecoration(
                                  label: Text("Tags:"),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                                  hintText: "Tag1, Tag2, ..."
                                ),
                                onEditingComplete: _saveNote,
                              )
                            ),
                          ),
                          const SizedBox(width: 10),
                          FilledButton(style: ButtonStyle(
                            backgroundColor: MaterialStateProperty.all(Colors.blueAccent),
                            minimumSize: const MaterialStatePropertyAll(Size(120, 50))),
                            onPressed: _saveNote,
                            child: Text(_currentNoteId == null ? "Save" : "Update",
                              style: const TextStyle(fontSize: 18),
                            )),
                        ]),
                      )],
                    ),
                  )],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _makeMainAreaMobile(TheModel model) {
    switch (_editorMode) {
      case EditorMode.read:
        return ListView(children: _notes.map((note) => TrixContainer(child: GestureDetector(
          onLongPress: () => _contextMenu(note), // doesn't work on iOS (=> also use DoubleTap)
          onDoubleTap: () => _contextMenu(note),
          child: MarkdownWidget(data: note.data, shrinkWrap: true)))).toList()
        );
      case EditorMode.edit:
        return Column(children: [
          Expanded(child: TextField(
            controller: _currentText,
            autofocus: true,
            keyboardType: TextInputType.multiline,
            maxLines: null,
            expands: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(1))),
          )),
          Expanded(child: TrixContainer(child: MarkdownWidget(data: _currentText.text, shrinkWrap: true))),
          Row(children: [
            const Text("Tags:", style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: TextField(
                controller: _currentTags,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(1)),
                  hintText: "Tag1, Tag2, ...",
                ),
              ),
            )),
            const SizedBox(width: 70)
          ]),
        ]);
    }
  }

  void _contextMenu(Note note) async {
    final model = ScopedModel.of<TheModel>(context);
    final result = await FlutterPlatformAlert.showCustomAlert(
      windowTitle: "Update note",
      text: "${note.data.substring(0, min(note.data.length, 25))}...",
      iconStyle: IconStyle.question,
      positiveButtonTitle: "Edit",
      neutralButtonTitle: "Archive",
      negativeButtonTitle: "Delete",
      options: PlatformAlertOptions(
        macos: MacosAlertOptions(isNegativeActionDestructive: true),
        ios: IosAlertOptions(negativeButtonStyle: IosButtonStyle.destructive),
        // TODO other platforms
      ),
    );
    switch (result) {
      case CustomButton.positiveButton:
        _setEditMode(note.id, note.data, note.tags);
        break;
      case CustomButton.neutralButton:
        model.archiveNoteById(note.id);
        break;
      case CustomButton.negativeButton:
        model.deleteNoteById(note.id);
        break;
      default:
    }
  }

  Future<Widget> _makeMainAreaDesktop() async {
    const editTitle = "Edit note";
    const archiveTitle = "Archive note";
    const deleteTitle = "Delete note";
    final model = ScopedModel.of<TheModel>(context);
    final children = _notes.map((note) => ContextMenuRegion(
      menuItems: [MenuItem(title: editTitle), MenuItem(title: archiveTitle), MenuItem(title: deleteTitle)],
      onItemSelected: (item) async { // MenuItem::onSelected doesn't work
        switch (item.title) {
          case editTitle:
            _setEditMode(note.id, note.data, note.tags);
            break;
          case archiveTitle:
            await model.archiveNoteById(note.id);
            break;
          case deleteTitle:
            await model.deleteNoteById(note.id);
            break;
          default:
        }
      },
      child: TrixContainer(child: MarkdownWidget(data: note.data, shrinkWrap: true)),
    )).toList();
    return ListView(children: children);
  }

  void _saveNote() async {
    if (_currentText.text.trim().isEmpty) return;

    final model = ScopedModel.of<TheModel>(context);
    final newId = await model.saveNote(_currentNoteId, _currentText.text, _currentTags.text, _oldTags);
    if (newId != null) {
      fileChanged = true; // for iOS, we need to warn user that the DB file may be lost
      _setReadMode(newId.toString(), SearchMode.id);
    }
    // TODO: else set focus to tags
  }

  void _closeFile() {
    final model = ScopedModel.of<TheModel>(context);
    if (fileChanged) {
      const header = "DB file is not exported";
      const msg = "On iOS you have to share this file to external storage. Do you want to share?";
      Utils.showAlert(header, msg, IconStyle.information, AlertButtonStyle.yesNoCancel, _shareFile, model.closeFile);
    } else model.closeFile();
  }

  void _showAboutDialog() async {
    final i = await PackageInfo.fromPlatform();
    final text = "v${i.version} (build: ${i.buildNumber})\n\nCopyright © 2024-2025\nmitrakov-artem@yandex.ru\nAll rights reserved.";
    FlutterPlatformAlert.showAlert(windowTitle: i.appName, text: text, iconStyle: IconStyle.information);
  }

  void _shareFile() async {
    final model = ScopedModel.of<TheModel>(context);
    if (model.currentPath != null) {
      final filename = basename(model.currentPath!);
      Share.shareXFiles([XFile(model.currentPath!)], subject: 'Export file "$filename"?');
      fileChanged = false;
    }
  }

  void _setEditMode(int? noteId, String text, String tags) async {
    setState(() {
      _currentText.text = text;
      _currentTags.text = tags;
      _currentNoteId = noteId;
      _oldTags = tags;
      _notes = [];
      _editorMode = EditorMode.edit;
      /// _search = _search;
      /// _searchMode = _searchMode;
    });
  }

  Future<void> _setReadMode(String search, SearchMode by) async {
    final model = ScopedModel.of<TheModel>(context);
    final Iterable<Note> notes =
      by == SearchMode.all     ? await model.getAllNotes(model.showArchive) :
      by == SearchMode.tag     ? await model.searchByTag(search, model.showArchive) :
      by == SearchMode.keyword ? await model.searchByKeyword(search, model.showArchive) :
      by == SearchMode.id      ? await model.searchById(int.tryParse(search) ?? 0).then((note) => [if (note != null) note]) :
      by == SearchMode.random  ? await model.getRandomNotes(model.showArchive, 10) : [];

    setState(() {
      _currentText.text = "";
      _currentTags.text = "";
      _currentNoteId = null;
      _oldTags = "";
      _notes = notes;
      _editorMode = EditorMode.read;
      _search = search;
      _searchMode = by;
    });
  }

  @override
  void dispose() {
    _currentText.dispose();
    _currentTags.dispose();
    super.dispose();
  }
}

enum EditorMode { read, edit }
enum SearchMode { all, tag, keyword, id, random }

class AboutIntent       extends Intent {}
class EscapeIntent      extends Intent {}
class NewDbFileIntent   extends Intent {}
class OpenDbFileIntent  extends Intent {}
class SaveNoteIntent    extends Intent {}
class CloseDbFileIntent extends Intent {}
class CloseAppIntent    extends Intent {}
