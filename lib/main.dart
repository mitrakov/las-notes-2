import 'dart:io';
import 'dart:ffi' show DynamicLibrary;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' show basename, extension;
import 'package:share_plus/share_plus.dart';
import 'package:native_context_menu/native_context_menu.dart';
import 'package:scoped_model/scoped_model.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:menubar/menubar.dart';
import 'package:window_manager/window_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqf;
import 'package:sqlite3/open.dart' show open;
import 'package:lasnotes/model/note.dart';
import 'package:lasnotes/model/model.dart';
import 'package:lasnotes/model/settings.dart';
import 'package:lasnotes/widgets/inputbox.dart';
import 'package:lasnotes/widgets/trixcontainer.dart';
import 'package:lasnotes/widgets/trixiconbutton.dart';
import 'package:lasnotes/widgets/webdavview.dart';
import 'package:lasnotes/widgets/collapsible.dart';
import 'package:lasnotes/utils.dart';
import 'package:lasnotes/trixstack.dart';

bool get isWinLinux => Platform.isWindows || Platform.isLinux;
bool get isDesktop  => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/*
Build for MacOS:
  bump version in pubspec.yaml
  flutter build macos
  xCode: Product -> Destination -> Any Mac (arm64, x86_64)
  xCode: Product -> Archive -> Distribute App -> Direct Distribution -> wait for 30-40 sec for notarization service to complete
  copy "Las Notes.app" to "_installer/macos/App"
  run _installer/macos/build-dmg.sh
  move *.dmg image to dist/

Build for iOS:
  bump version in pubspec.yaml
  flutter build ios
  xCode: Product -> Destination -> Any iOS Device (arm64)
  xCode: Product -> Archive -> Distribute App -> Release Testing
  rename and move *.ipa file to dist/

Build for Windows:
  bump version in "installer\windows\inno-setup.iss" (align with pubspec.yaml)
  lib\model\db.dart: replace "// #ifdef WIN_OR_LINUX " directives and fix errors (don't commit changes)
  flutter build windows
  copy files from "build\windows\x64\runner\Release" to "installer\windows\Las Notes"
  insert RuToken and run (PIN 12345678):
    signtool sign /v /a /tr http://timestamp.globalsign.com/tsa/r6advanced1 /td SHA256 /fd SHA256 'LasNotes.exe' '*.dll'
    signtool verify /v 'LasNotes.exe'
  add there "sqlite3.dll" from "sqlcipher\windows" folder
  add there "vcruntime140_1.dll" from "installer\windows" folder
  Compile "installer\windows\inno-setup.iss" with InnoSetup Compiler (CTRL+F9)
    signtool sign /v /a /tr http://timestamp.globalsign.com/tsa/r6advanced1 /td SHA256 /fd SHA256 '.\lasnotes-win64.exe'
    signtool verify /v '.\lasnotes-win64.exe'
  move *.exe file to dist\

Build for Linux:
  bump version in pubspec.yaml
  lib/model/db.dart: replace "// #ifdef WIN_OR_LINUX " directives and fix errors (don't commit changes)
  flutter build linux
  go to: build/linux/x64/release/bundle and rename "bundle" to "lasnotes"
  add "libsqlite3.so" to "lib" from "sqlcipher/linux" folder
  run: zip -r9 lasnotes-linux-x.y.z.zip lasnotes/
  TO-DO: package to .rpm or .deb images
  move *.zip file to dist/
*/
void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // allow async code in main()
  
  // Enable SQLite/SQLCipher support for Windows/Linux:
  // 1. https://stackoverflow.com/q/76158800         // enable FFI support for Windows/Linux
  // 2. pub dev: sqlite3_flutter_libs                // (deprecated) add DLLs for Windows/Linux
  // 3. https://github.com/simolus3/sqlite3.dart/blob/e66702c5bec7faec2bf71d374c008d5273ef2b3b/sqlite3/lib/src/load_library.dart
  if (isWinLinux) {
    final libName = Platform.isWindows ? "sqlite3.dll" : "libsqlite3.so";
    sqf.sqfliteFfiInit();
    sqf.databaseFactory = sqf.createDatabaseFactoryFfi(ffiInit: () => open.overrideForAll(() => DynamicLibrary.open(libName)));
  }

  if (isDesktop)
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
      theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.indigo), useMaterial3: true),
      home: Main(),
    );
  }
}

class Main extends StatefulWidget {
  @override State<Main> createState() => _MainState();
}

class _MainState extends State<Main> {
  static const _tableStr = "| A| B| C|\n|:--|---|--:|\n|  |  |  |\n|  |  |  |\n|  |  |  |\n";
  static const _linkStr = "[Link](https://)\n";

  // === STATE VARS ===                         // !!! update them only in _setEditMode() and _setReadMode()
  final _currentText = TextEditingController(); // main text in add/edit mode
  final _currentTags = TextEditingController(); // comma-separated tags in the text field
  int? _currentNoteId;                          // if present, noteID in edit mode (otherwise NEW_NOTE mode)
  Attachment? _currentAttachment;
  var _oldTags = "";                            // old comma-separated tags for edit mode (to calc tags diff)
  Iterable<Note> _notes = [];                   // in view mode, DB notes array for markdown view
  EditorMode _editorMode = .edit;               // edit or view mode
  var _search = Search("", .all);               // search by tag name (.tag), keyword (.keyword), ID (.id) or all (.all)

  // Focus nodes
  final _focusNodeGlobal = FocusNode();         // main global focus for the whole desktop app (to get shortcuts working)
  final _focusNodeText   = FocusNode();         // main text focus
  final _focusNodeTags   = FocusNode();         // comma-separated tags focus
  final _focusNodeSearch = FocusNode();         // global search focus

  // Non-important state variables
  String? _currentPath;                         // copy of Model.currentPath to catch "onCurrentPathChange" event
  final _globalSearch = TextEditingController();// text in "Global search" field; only for mobile app
  var _fileChanged = false;                     // for iOS, we need to warn user that the DB file may be lost
  Future<void>? _webDavLoading;                 // when WebDAV enabled, shows progress indicator on save/delete/archive
  var _back = TrixStack<Search>();              // ⬅️ stack history
  var _forward = TrixStack<Search>();           // ➡️ stack history

  // Simple getters/setters
  String get _nowStr => "${DateTime.now().toString().substring(0, 19)}\n";
  bool get fileChanged => _fileChanged;
  set fileChanged(bool v) {
    if (Platform.isIOS && !ScopedModel.of<TheModel>(context).webDav.isConnected) // for WebDAV, it's OK
      _fileChanged = v;
  }

  @override
  void initState() {
    super.initState();
    _currentText.addListener(() { setState(() {}); });
    if (isWinLinux)
      _createMenuWindowsLinux();
  }

  @override
  Widget build(BuildContext context) {
    return ScopedModelDescendant<TheModel>(builder: (context, child, model) {
      if (_currentPath != model.currentPath) { // new file opened
        _currentPath = model.currentPath;
        _back.clear();
        _forward.clear();
        _setReadMode(Search("", .all));
        if (isDesktop)
          windowManager.setTitle(model.currentPath != null ? "Las Notes (${model.currentPath})" : "Las Notes");
      }
      return isDesktop ? _buildForDesktop(context, model) : _buildForMobile(context, model);
    });
  }

  Widget _buildForMobile(BuildContext context, TheModel model) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Las Notes", style: TextStyle(fontWeight: .bold)),
        centerTitle: true,
        actions: [
          IconButton(onPressed: () => _history(_back, _forward), icon: const Icon(Icons.chevron_left)),
          IconButton(onPressed: () => _history(_forward, _back), icon: const Icon(Icons.chevron_right)),
          IconButton(onPressed: _shareFile, icon: const Icon(Icons.ios_share)),
          IconButton(onPressed: _showAboutDialog, icon: const Icon(Icons.info_outline)),
        ],
      ),
      body: model.currentPath == null
        ? Center(child: Text("Welcome to Las Notes", textAlign: .center, style: TextStyle(fontWeight: .bold, fontSize: 36)))
        : Padding(padding: const .all(8.0), child: _makeMainAreaMobile(model)),
      drawer: Drawer(
        child: Padding(
          padding: const .all(8.0),
          child: Column(children: [
            const SizedBox(height: 50),
            TextField(
              controller: _globalSearch, // only for Mobile app to keep the text after "Navigator.pop()"
              focusNode: _focusNodeSearch,
              decoration: const InputDecoration(border: OutlineInputBorder(), label: Text("Global search")),
              onSubmitted: (s) {
                _setReadMode(Search(s, .keyword));
                Navigator.pop(context);
              },
            ),
            CheckboxListTile(
              title: const Text("Show archive"),
              value: model.showArchive,
              onChanged: (v) {
                model.setShowArchive(v ?? false);
                _setReadMode(_search);
                Navigator.pop(context);
              },
              controlAffinity: .leading,
            ),
            const SizedBox(height: 10),
            const Text("TAGS", style: TextStyle(fontSize: 20, fontWeight: .bold)),
            FutureBuilder(future: model.getTags(), builder: (context, snapshot) {
              if (snapshot.hasData)
                return Expanded(child: ListView(children: snapshot.data!.map((tag) =>
                  OutlinedButton(
                    style: ButtonStyle(
                      alignment: .centerLeft,
                      backgroundColor: .all(Colors.brown[50])
                    ),
                    child: Text(tag),
                    onPressed: () {
                      _setReadMode(Search(tag, .tag));
                      Navigator.pop(context);
                    },
                  ),
                ).toList()));
              else return const CircularProgressIndicator(color: Colors.lime);
            })
          ]),
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .end,
        children: [
          _webDavProgressIndicator(),
          Visibility(
            visible: model.currentPath != null && _editorMode == .read,
            child: Padding(
              padding: const .all(8.0),
              child: FloatingActionButton(
                heroTag: "newNote",
                child: const Icon(Icons.note_add_outlined, size: 32),
                backgroundColor: Colors.lightGreen[700],
                onPressed: () => _setEditMode(null, "", "", null),
              ),
            ),
          ),
          Visibility(
            visible: model.currentPath != null && _editorMode == .edit,
            child: Padding(
              padding: const .all(8.0),
              child: FloatingActionButton(
                heroTag: "saveNote",
                child: const Icon(Icons.domain_verification, size: 32),
                backgroundColor: Colors.green[500],
                onPressed: _saveNote,
              ),
            ),
          ),
          Visibility(
            visible: model.currentPath != null && _editorMode == .edit,
            child: Padding(
              padding: const .all(8.0),
              child: FloatingActionButton(
                heroTag: "cancelEdit",
                child: const Icon(Icons.cancel, size: 30),
                backgroundColor: Colors.red[300],
                onPressed: () => _setReadMode(_search),
              ),
            ),
          ),
          Visibility(
            visible: model.currentPath == null,
            child: Padding(
              padding: const .all(8.0),
              child: FloatingActionButton(
                heroTag: "openFile",
                child: const Icon(Icons.download, size: 28),
                backgroundColor: Colors.brown[400],
                onPressed: () => model.openFileWithDialog(context),
              ),
            ),
          ),
          Visibility(
            visible: model.currentPath == null,
            child: Padding(
              padding: const .all(8.0),
              child: FloatingActionButton(
                heroTag: "openWebDav",
                child: const Icon(Icons.cloud_download_outlined, size: 36),
                backgroundColor: Colors.blue[300],
                onPressed: _showWebDavDialogMobile,
              ),
            ),
          ),
          Visibility(
            visible: model.currentPath != null && _editorMode == .read,
            child: Padding(
              padding: const .all(8.0),
              child: FloatingActionButton(
                heroTag: "closeFile",
                child: const Icon(Icons.stop_circle_outlined, size: 32),
                backgroundColor: Colors.red[400],
                onPressed: _closeFile,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForDesktop(BuildContext context, TheModel model) {
    final isMacOS = Platform.isMacOS;
    return PlatformMenuBar(
      // This menu is only for MacOS. For Windows/Linux see: _createMenuWindowsLinux().
      // Use only "onSelectedIntent" (do NOT use "onSelected") in order to make the logic uniform across MacOS/Linux/Windows.
      // Shortcuts are specified here only to draw a hint (e.g. "⌘N") on MacOS menu items (all logic is done through intents).
      menus: [
        PlatformMenu(
          label: "",
          menus: [
            PlatformMenuItemGroup(members: [
              PlatformMenuItem(
                label: "About Las Notes",
                onSelectedIntent: AboutIntent(),
                shortcut: SingleActivator(LogicalKeyboardKey.f1),
              ),
            ]),
            PlatformMenuItem(
              label: "Quit",
              onSelectedIntent: CloseAppIntent(),
              shortcut: SingleActivator(LogicalKeyboardKey.keyQ, meta: true),
            ),
          ],
        ),
        PlatformMenu(
          label: "File",
          menus: [
            PlatformMenu(label: "Open Recent", menus: Settings.local.recentFiles.map((path) =>
              PlatformMenuItem(label: path, onSelected: () => model.openFile(context, path)) // no intents/shortcuts here
            ).toList()),
            PlatformMenuItemGroup(members: [
              PlatformMenuItem(
                label: "New DB File",
                onSelectedIntent: NewDbFileIntent(),
                shortcut: SingleActivator(LogicalKeyboardKey.keyN, meta: true, shift: true),
              ),
              PlatformMenuItem(
                label: "New DB File (encrypted)",
                onSelectedIntent: NewDbxFileIntent(),
                shortcut: SingleActivator(LogicalKeyboardKey.keyE, meta: true, shift: true),
              ),
              PlatformMenuItem(
                label: "Open...",
                onSelectedIntent: OpenDbFileIntent(),
                shortcut: SingleActivator(LogicalKeyboardKey.keyO, meta: true),
              ),
              PlatformMenuItem(
                label: "Open WebDAV...",
                onSelectedIntent: OpenWebDavFileIntent(),
                shortcut: SingleActivator(LogicalKeyboardKey.keyO, meta: true, shift: true),
              ),
            ]),
            PlatformMenuItem(
              label: "Close DB File",
              onSelectedIntent: CloseDbFileIntent(),
              shortcut: SingleActivator(LogicalKeyboardKey.keyW, meta: true),
            ),
          ],
        ),
        PlatformMenu(
          label: "Edit",
          menus: [
            PlatformMenuItem(
              label: " ᎒᎒᎒  Insert Table",
              onSelectedIntent: InsertTableIntent(),
              shortcut: SingleActivator(LogicalKeyboardKey.keyT, meta: true, shift: true),
            ),
            PlatformMenuItem(
              label: "🔗 Insert Link",
              onSelectedIntent: InsertLinkIntent(),
              shortcut: SingleActivator(LogicalKeyboardKey.keyL, meta: true, shift: true),
            ),
            PlatformMenuItem(
              label: "🕓 Insert DateTime",
              onSelectedIntent: InsertDateIntent(),
              shortcut: SingleActivator(LogicalKeyboardKey.keyD, meta: true, shift: true),
            ),
            PlatformMenuItem(
              label: "📎 Insert Attachment",
              onSelectedIntent: InsertAttachment(),
              shortcut: SingleActivator(LogicalKeyboardKey.keyA, meta: true, shift: true),
            ),
          ],
        ),
        PlatformMenu(
          label: "Navigate",
          menus: [
            PlatformMenuItem(
              label: "⬅️ Back",
              onSelectedIntent: BackIntent(),
              shortcut: SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true),
            ),
            PlatformMenuItem(
              label: "➡️ Forward",
              onSelectedIntent: ForwardIntent(),
              shortcut: SingleActivator(LogicalKeyboardKey.bracketRight, meta: true),
            ),
          ],
        ),
      ],
      child: Shortcuts(
        shortcuts: {
          SingleActivator(LogicalKeyboardKey.keyN, meta: isMacOS, control: !isMacOS, shift: true): NewDbFileIntent(),
          SingleActivator(LogicalKeyboardKey.keyE, meta: isMacOS, control: !isMacOS, shift: true): NewDbxFileIntent(),
          SingleActivator(LogicalKeyboardKey.keyO, meta: isMacOS, control: !isMacOS, shift: true): OpenWebDavFileIntent(),
          SingleActivator(LogicalKeyboardKey.keyT, meta: isMacOS, control: !isMacOS, shift: true): InsertTableIntent(),
          SingleActivator(LogicalKeyboardKey.keyL, meta: isMacOS, control: !isMacOS, shift: true): InsertLinkIntent(),
          SingleActivator(LogicalKeyboardKey.keyD, meta: isMacOS, control: !isMacOS, shift: true): InsertDateIntent(),
          SingleActivator(LogicalKeyboardKey.keyA, meta: isMacOS, control: !isMacOS, shift: true): InsertAttachment(),
          SingleActivator(LogicalKeyboardKey.keyF, meta: isMacOS, control: !isMacOS, shift: true): GlobalSearchIntent(),
          SingleActivator(LogicalKeyboardKey.keyO, meta: isMacOS, control: !isMacOS):              OpenDbFileIntent(),
          SingleActivator(LogicalKeyboardKey.keyW, meta: isMacOS, control: !isMacOS):              CloseDbFileIntent(),
          SingleActivator(LogicalKeyboardKey.keyN, meta: isMacOS, control: !isMacOS):              NewNoteIntent(),
          SingleActivator(LogicalKeyboardKey.keyS, meta: isMacOS, control: !isMacOS):              SaveNoteIntent(),
          SingleActivator(LogicalKeyboardKey.escape):                                              EscapeIntent(),
          SingleActivator(LogicalKeyboardKey.f1):                                                  AboutIntent(),
          SingleActivator(LogicalKeyboardKey.bracketLeft,  meta: isMacOS, control: !isMacOS):      BackIntent(),
          SingleActivator(LogicalKeyboardKey.bracketRight, meta: isMacOS, control: !isMacOS):      ForwardIntent(),
          SingleActivator(LogicalKeyboardKey.keyQ, meta: isMacOS, control: !isMacOS):              CloseAppIntent(),
        },
        child: Actions(
          actions: {
            NewDbFileIntent:      CallbackAction(onInvoke: (_) => model.newFile(context)),
            NewDbxFileIntent:     CallbackAction(onInvoke: (_) => model.newFile(context, encrypted: true)),
            OpenWebDavFileIntent: CallbackAction(onInvoke: (_) => _showWebDavDialogDesktop()),
            InsertTableIntent:    CallbackAction(onInvoke: (_) => Utils.insertText(_currentText, _tableStr)),
            InsertLinkIntent:     CallbackAction(onInvoke: (_) => Utils.insertText(_currentText, _linkStr)),
            InsertDateIntent:     CallbackAction(onInvoke: (_) => Utils.insertText(_currentText, _nowStr)),
            InsertAttachment:     CallbackAction(onInvoke: (_) => _insertAttachment()),
            GlobalSearchIntent:   CallbackAction(onInvoke: (_) => _focusNodeSearch.requestFocus()),
            OpenDbFileIntent:     CallbackAction(onInvoke: (_) => model.openFileWithDialog(context)),
            CloseDbFileIntent:    CallbackAction(onInvoke: (_) => model.closeFile()),
            NewNoteIntent:        CallbackAction(onInvoke: (_) => _setEditMode(null, "", "", null)),
            SaveNoteIntent:       CallbackAction(onInvoke: (_) => _saveNote()),
            EscapeIntent:         CallbackAction(onInvoke: (_) => _setReadMode(_search)),
            AboutIntent:          CallbackAction(onInvoke: (_) => _showAboutDialog()),
            BackIntent:           CallbackAction(onInvoke: (_) => _history(_back, _forward)),
            ForwardIntent:        CallbackAction(onInvoke: (_) => _history(_forward, _back)),
            CloseAppIntent:       CallbackAction(onInvoke: (_) => exit(0)),
          },
          child: Focus(               // needed for Shortcuts
            autofocus: true,          // focused by default
            focusNode: _focusNodeGlobal,
            child: Scaffold(
              body: model.currentPath == null ? _splashScreen() : Center(
                child: Row(children: [ // [left: tags, right: main window]
                  Expanded( // tags
                    child: FutureBuilder(
                      future: model.getTags(),
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          final tags = snapshot.data!.map((tag) => Padding(
                            padding: const .only(top: 2), // Tag button on the left side
                            child: Padding(
                              padding: const .symmetric(vertical: 2),
                              child: OutlinedButton(
                                style: ButtonStyle(
                                  alignment: .centerLeft,
                                  backgroundColor: .all(Colors.brown[50])
                                ),
                                child: Text(tag),
                                onPressed: () => _setReadMode(Search(tag, .tag)),
                              ),
                            ),
                          )).toList();

                          return ListView(padding: const .all(6),
                            children: [
                              Row(children: [
                                TrixIconTextButton.icon(
                                  icon: const Icon(Icons.add_box_rounded),
                                  label: const Text("New"),
                                  onPressed: () => _setEditMode(null, "", "", null),
                                ),
                                Expanded(
                                  child: TextField(
                                    focusNode: _focusNodeSearch,
                                    decoration: const InputDecoration(border: OutlineInputBorder(), label: Text("Global search")),
                                    onSubmitted: (s) { _setReadMode(Search(s, .keyword)); },
                                  ),
                                ),
                              ]),
                              CheckboxListTile(
                                title: const Text("Show archive"),
                                value: model.showArchive,
                                onChanged: (v) {
                                  model.setShowArchive(v ?? false);
                                  _setReadMode(_search);
                                },
                                controlAffinity: .leading,
                              ),
                              const Text("TAGS", textAlign: .center, style: TextStyle(fontSize: 20, fontWeight: .bold)),
                              ...tags,
                            ]);
                        } else return const CircularProgressIndicator();
                      },
                    ),
                  ),
                  Flexible( // main window
                    flex: 5,
                    child: Column(children: [ // [top: edit/render panels, bottom: edit-tags/buttons panels]
                      Expanded(child: _editorMode == .edit
                        ? Row(children: [ // [left: edit panel, right: render panel]
                            Expanded(child: Padding(
                              padding: const .all(2),
                              child: TextField(
                                controller: _currentText,
                                focusNode: _focusNodeText,
                                autofocus: true,
                                keyboardType: .multiline,
                                maxLines: 128, // only for sizing widget (it's not a real limit of lines)
                                autocorrect: false,
                                decoration: InputDecoration(border: OutlineInputBorder(borderRadius: .circular(6))),
                              ),
                            )),
                            Expanded(child: TrixContainer(child: Collapsible.simple(_currentText.text))),
                          ])
                        : FutureBuilder(
                            future: _makeMainAreaDesktop(),
                            builder: (context, snapshot) => snapshot.data ?? const CircularProgressIndicator(),
                          ),
                      ),
                      Visibility(
                        visible: _editorMode == .edit,
                        child: Row(
                          spacing: 10,
                          children: [
                            Padding(
                              padding: const .all(4),
                              child: SizedBox(
                                width: 400,
                                child: TextField(
                                  controller: _currentTags,
                                  focusNode: _focusNodeTags,
                                  decoration: const InputDecoration(
                                    label: Text("Tags:"),
                                    border: const OutlineInputBorder(borderRadius: .all(.circular(10))),
                                    hintText: "Tag1, Tag2, ..."
                                  ),
                                  onEditingComplete: _saveNote,
                                ),
                              ),
                            ),
                            FilledButton(style: ButtonStyle(
                              backgroundColor: .all(Colors.blueAccent),
                              minimumSize: const WidgetStatePropertyAll(Size(120, 50))),
                              onPressed: _saveNote,
                              child: Text(_currentNoteId == null ? "Save" : "Update",
                                style: const TextStyle(fontSize: 18),
                              ),
                            ),
                            Visibility(
                              visible: _currentAttachment != null,
                              child: IconButton(
                                tooltip: "Delete attachment '${_currentAttachment?.name}'",
                                icon: FaIcon(FontAwesomeIcons.paperclip, color: Colors.brown[800]),
                                onPressed: () {
                                  setState(() {
                                    _currentAttachment = null;
                                    _focusNodeText.requestFocus();
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      )],
                    ),
                  )],
                ),
              ),
              floatingActionButton: _webDavProgressIndicator(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _makeMainAreaMobile(TheModel model) {
    switch (_editorMode) {
      case .read:
        return ListView(children: _notes.map((note) => TrixContainer(child: GestureDetector(
          onLongPress: () => _contextMenuMobile(note), // doesn't work on iOS (=> also use DoubleTap)
          onDoubleTap: () => _contextMenuMobile(note),
          child: Opacity(opacity: note.isDeleted ? 0.67 : 1, child: Collapsible(note))))).toList()
        );
      case .edit:
        return Column(children: [
          Expanded(child: TextField(
            controller: _currentText,
            focusNode: _focusNodeText,
            autofocus: true,
            keyboardType: .multiline,
            maxLines: 128,            // only for sizing widget (it's not a real limit of lines)
            autocorrect: true,        // T9 hints for iOS
            enableSuggestions: false, // Android only
            decoration: InputDecoration(border: OutlineInputBorder(borderRadius: .circular(6))),
          )),
          Expanded(child: TrixContainer(child: Collapsible.simple(_currentText.text))),
          Row(children: [
            const Text("Tags:", style: TextStyle(fontWeight: .bold)),
            Expanded(child: Padding(
              padding: const .symmetric(horizontal: 8.0),
              child: TextField(
                controller: _currentTags,
                focusNode: _focusNodeTags,
                autocorrect: false,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: .circular(1)),
                  hintText: "Tag1, Tag2, ...",
                ),
              ),
            )),
            const SizedBox(width: 70)
          ]),
        ]);
    }
  }

  void _contextMenuMobile(Note note) async {
    final model = ScopedModel.of<TheModel>(context);

    // archived notes
    if (note.isDeleted) {
      await Utils.showAlert("Restore", "Restore note from archive?", .information, .yesNo, onYes: () async {
        await model.restoreNoteById(note.id);
        _webDavLoading = model.uploadWebDav();
        _setReadMode(_search);
      });
      return;
    }

    // regular notes
    showContextMenuBox(context, "Update note", Utils.firstLine(note.data), [
      TrixAction("Edit note", true, false, () => _setEditMode(note.id, note.data, note.tags, note.attachment)),
      TrixAction("Archive note", false, false, () async {
        if (await model.archiveNoteById(note.id))
          _webDavLoading = model.uploadWebDav();
        _setReadMode(_search);
      }),
      TrixAction("Delete note", false, true, () async {
        if (await model.deleteNoteById(note.id))
          _webDavLoading = model.uploadWebDav();
        _setReadMode(_search);
      }),
    ]);
  }

  Future<Widget> _makeMainAreaDesktop() async {
    const editTitle = "Edit note";
    const archiveTitle = "Archive note";
    const deleteTitle = "Delete note";
    const restoreTitle = "Restore from archive";
    final model = ScopedModel.of<TheModel>(context);
    final children = _notes.map((note) => ContextMenuRegion(
      menuItems: note.isDeleted
        ? [MenuItem(title: restoreTitle)]
        : [MenuItem(title: editTitle), MenuItem(title: archiveTitle), MenuItem(title: deleteTitle)],
      onItemSelected: (item) async { // MenuItem::onSelected doesn't work
        switch (item.title) {
          case editTitle:
            _setEditMode(note.id, note.data, note.tags, note.attachment);
            break;
          case archiveTitle:
            if (await model.archiveNoteById(note.id))
              _webDavLoading = model.uploadWebDav();
            _setReadMode(_search);
            break;
          case deleteTitle:
            if (await model.deleteNoteById(note.id))
              _webDavLoading = model.uploadWebDav();
            _setReadMode(_search);
            break;
          case restoreTitle:
            await model.restoreNoteById(note.id);
            _webDavLoading = model.uploadWebDav();
            _setReadMode(_search);
            break;
          default:
        }
      },
      child: TrixContainer(child: Opacity(opacity: note.isDeleted ? 0.67 : 1, child: Collapsible(note))),
    )).toList();
    return ListView(children: children);
  }

  Widget _webDavProgressIndicator() {
    return FutureBuilder(
      future: _webDavLoading,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return Opacity(opacity: 0.3,
            child: const Column(mainAxisAlignment: .end, children: [
              Text("WebDAV", style: TextStyle(color: Colors.purple)),
              CircularProgressIndicator(color: Colors.purple),
            ]),
          );
        return const SizedBox.shrink();
      }
    );
  }

  Widget _splashScreen() {
    final model = ScopedModel.of<TheModel>(context);
    return Padding(padding: const .all(32), child: Center(child: TrixContainer(child: SizedBox(width: 600,
      child: Column(
        mainAxisSize: .min,
        children: [
          const Text("Welcome to Las Notes", textAlign: .center, style: TextStyle(fontWeight: .bold, fontSize: 36)),
          Padding(
            padding: .all(20),
            child: Row(
              spacing: 10,
              children: [
                Expanded(
                  child: FilledButton(
                    child: const Text("Open File"),
                    style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 60), alignment: .center),
                    onPressed: () => model.openFileWithDialog(context),
                  ),
                ),
                Expanded(
                  child: FilledButton(
                    child: const Text("WebDAV"),
                    style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 60), alignment: .center),
                    onPressed: _showWebDavDialogDesktop,
                  )
                ),
                Expanded(
                  child: FilledButton(
                    child: const Text("New File"),
                    style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 60), alignment: .center),
                    onPressed: () => model.newFile(context)
                  ),
                ),
                Expanded(
                  child: FilledButton(
                    child: const Text("New File (encrypted)", textAlign: .center),
                    style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 60), alignment: .center),
                    onPressed: () => model.newFile(context, encrypted: true)
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              shrinkWrap: true,
              children: Settings.local.recentFiles.map((path) => TrixContainer(
                child: ListTile(
                  leading: FaIcon(FontAwesomeIcons.database, color: extension(path) == ".dbx" ? Colors.orange : Colors.blue, size:32),
                  title: Text(basename(path), style: TextStyle(fontWeight: .bold)),
                  subtitle: Text(path, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                  onTap: () => model.openFile(context, path),
                ),
              )).toList(),
            ),
          ),
        ],
      )))),
    );
  }

  void _saveNote() async {
    if (_currentText.text.trim().isEmpty) return;

    final model = ScopedModel.of<TheModel>(context);
    final newId = await model.saveNote(_currentNoteId, _currentText.text, _currentTags.text, _oldTags, _currentAttachment);
    if (newId != null) {
      fileChanged = true; // for iOS, we need to warn user that the DB file may be lost
      _webDavLoading = model.uploadWebDav();
      _setReadMode(Search(newId.toString(), .id));
    } else _focusNodeTags.requestFocus();

    if (!isDesktop)
      FocusManager.instance.primaryFocus?.unfocus(); // hide keyboard on iOS/Android
  }

  void _closeFile() {
    final model = ScopedModel.of<TheModel>(context);
    if (fileChanged) {
      const header = "DB file is not exported";
      const msg = "On iOS you have to share this file to external storage. Do you want to share?";
      Utils.showAlert(header, msg, .information, .yesNoCancel, onYes: _shareFile, onNo: model.closeFile);
    } else model.closeFile();
  }

  void _showAboutDialog() async {
    final i = await PackageInfo.fromPlatform();
    final text = "v${i.version} (build: ${i.buildNumber})\n\nCopyright © 2024-2026\nmitrakov-artem@yandex.ru\nAll rights reserved.";
    if (Platform.isWindows) // bug in Windows: F1.keyUp event is swallowed by ModalDialog event loop => let's wait for 300 msec.
      Future.delayed(Duration(milliseconds: 300), () => Utils.showAlert(i.appName, text, .information, .ok));
    else Utils.showAlert(i.appName, text, .information, .ok);
  }

  void _showWebDavDialogDesktop() {
    final model = ScopedModel.of<TheModel>(context);
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: .circular(20)),
          backgroundColor: Theme.of(context).colorScheme.surface,
          content: SizedBox(width: 400, child: WebDavView(model.webDav, (path) => _webDavOpenPath(context, path))),
        );
      },
    );
  }

  void _showWebDavDialogMobile() {
    final model = ScopedModel.of<TheModel>(context);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => WebDavView(model.webDav, (path) => _webDavOpenPath(context, path)),
    ));
  }

  void _webDavOpenPath(BuildContext context, String path) {
    final model = ScopedModel.of<TheModel>(context);
    Navigator.of(context).pop(); // should be first, for ".dbx" files to ask a password
    model.openFile(context, path);
  }

  void _shareFile() async {
    final path = ScopedModel.of<TheModel>(context).currentPath;
    if (path != null) {
      final filename = basename(path);
      await SharePlus.instance.share(ShareParams(title: 'Export file "$filename"?', files: [XFile(path)]));
      fileChanged = false;
    }
  }

  void _history(TrixStack<Search> stack1, TrixStack<Search> stack2) {
    final search = stack1.pop();
    if (search != null) {
      stack2.push(search);
      if (search == _search)
        _history(stack1, stack2); // skip top element in history
      else _setReadMode(search, pushToHistory: false);
    }
  }

  void _createMenuWindowsLinux() {
    // This is a temp solution until Flutter adds "PlatformMenuBar" support for Windows/Linux.
    // shortcuts don't work here, use std "Intent" approach.
    final model = ScopedModel.of<TheModel>(context);
    setApplicationMenu([
      NativeSubmenu(label: "File", children: [
        NativeSubmenu(label: "Open Recent", children: Settings.local.recentFiles.map((path) =>
          NativeMenuItem(label: path, onSelected: () => model.openFile(context, path))
        ).toList()),
        NativeMenuItem(label: "New DB File                    Ctrl+Shift+N", onSelected: () => model.newFile(context)),
        NativeMenuItem(label: "New DB File (encrypted)",                   onSelected: () => model.newFile(context, encrypted: true)),
        NativeMenuItem(label: "Open...                             Ctrl+O",  onSelected: () => model.openFileWithDialog(context)),
        NativeMenuItem(label: "Open WebDAV...             Ctrl+Shift+O",     onSelected: () => _showWebDavDialogDesktop()),
        const NativeMenuDivider(),
        NativeMenuItem(label: "Close DB File                  Ctrl+W",       onSelected: model.closeFile),
        const NativeMenuDivider(),
        NativeMenuItem(label: "Quit                                 Alt+F4", onSelected: () => exit(0)),
      ]),
      NativeSubmenu(label: "Edit", children: [
        NativeMenuItem(label: " ᎒᎒᎒  Insert Table          Ctrl+Shift+T",onSelected: ()=>Utils.insertText(_currentText, _tableStr)),
        NativeMenuItem(label: "🔗 Insert Link             Ctrl+Shift+L",onSelected: ()=>Utils.insertText(_currentText, _linkStr)),
        NativeMenuItem(label: "🕓 Insert DateTime   Ctrl+Shift+D",         onSelected: ()=>Utils.insertText(_currentText, _nowStr)),
        NativeMenuItem(label: "💾 Insert Attachment  Ctrl+Shift+A",        onSelected: _insertAttachment),
      ]),
      NativeSubmenu(label: "Navigate", children: [
        NativeMenuItem(label: "⇐ Back          Ctrl+[", onSelected: () => _history(_back, _forward)),
        NativeMenuItem(label: "⇒ Forward    Ctrl+]",       onSelected: () => _history(_forward, _back)),
      ]),
      NativeSubmenu(label: "Help", children: [
        NativeMenuItem(label: "About Las Notes    F1", onSelected: _showAboutDialog),
      ])
    ]);
  }

  void _insertAttachment() async {
    // All State variables MUST be updated in _setEditMode()/_setReadMode();
    // here is the only exception for "_currentAttachment" to avoid introduction of "Controller" pattern
    var ok = true;
    if (_currentAttachment != null) {
      final msg = "Are you sure you want to overwrite the existing attachment:\n\n'${_currentAttachment?.name}'?";
      await Utils.showAlert("Attachment exists", msg, .hand, .yesNo, onNo: () => ok = false);
    }

    if (ok) {
      final result = await FilePicker.platform.pickFiles(dialogTitle: "Add attachment", withData: true, lockParentWindow: true);
      final file = result?.files.firstOrNull;
      if (file != null) {
        if (file.bytes != null) {
          if (file.bytes!.length > 2*1024*1024) {
            const msg = "Attachments greater than 2 Mb are NOT recommended.\n\nContinue?";
            await Utils.showAlert("File is too large", msg, .stop, .yesNo, onNo: () => ok = false);
          }
          if (ok) {
            setState(() {
              _currentAttachment = Attachment(file.name, file.bytes!);
            });
          }
        }
      }
    }
  }

  /// ALL state changes MUST be done in _setEditMode() and _setReadMode(). Keep these methods at the end of the class
  void _setEditMode(int? noteId, String text, String tags, Attachment? attachment) {
    setState(() {
      _currentText.text = text;
      _currentTags.text = tags;
      _currentNoteId = noteId;
      _currentAttachment = attachment;
      _oldTags = tags;
      _notes = [];
      _editorMode = .edit;
      /// _search = _search; (keep the same)
    });
    _focusNodeText.requestFocus();
  }

  /// ALL state changes MUST be done in _setEditMode() and _setReadMode(). Keep these methods at the end of the class
  void _setReadMode(Search sch, {bool pushToHistory = true}) async {
    final model = ScopedModel.of<TheModel>(context);
    final Iterable<Note> notes =
      sch.by == .all     ? await model.getAllNotes() :
      sch.by == .tag     ? await model.searchByTag(sch.search) :
      sch.by == .keyword ? await model.searchByKeyword(sch.search) :
      sch.by == .id      ? await model.searchById(int.tryParse(sch.search) ?? 0).then((note) => [if (note != null) note]) :
      sch.by == .random  ? await model.getRandomNotes(10) : [];

    setState(() {
      _currentText.text = "";
      _currentTags.text = "";
      _currentNoteId = null;
      _currentAttachment = null;
      _oldTags = "";
      _notes = notes;
      _editorMode = .read;
      _search = sch;
    });

    if (pushToHistory && _back.peek() != sch)
      _back.push(sch);                  // push to history

    _focusNodeGlobal.requestFocus();    // w/o this, shortcuts won't work, we need to focus something
  }

  @override
  void dispose() {
    _currentText.dispose();
    _currentTags.dispose();
    _focusNodeGlobal.dispose();
    _focusNodeText.dispose();
    _focusNodeTags.dispose();
    _focusNodeSearch.dispose();
    super.dispose();
  }
}

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
