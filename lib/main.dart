import 'dart:io';
import 'dart:ffi' show DynamicLibrary;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_platform_alert/flutter_platform_alert.dart';
import 'package:path/path.dart' show basename;
import 'package:share_plus/share_plus.dart';
import 'package:native_context_menu/native_context_menu.dart';
import 'package:scoped_model/scoped_model.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:window_manager/window_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqf;
import 'package:sqlite3/open.dart' show open;
import 'package:lasnotes/model/note.dart';
import 'package:lasnotes/model/model.dart';
import 'package:lasnotes/model/settings.dart';
import 'package:lasnotes/widgets/trixcontainer.dart';
import 'package:lasnotes/widgets/trixiconbutton.dart';
import 'package:lasnotes/widgets/webdavview.dart';
import 'package:lasnotes/widgets/collapsible.dart';
import 'package:lasnotes/utils.dart';
import 'package:lasnotes/trixstack.dart';

bool get isDesktop => Platform.isMacOS || Platform.isWindows || Platform.isLinux;

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
    signtool sign /v /a /tr http://timestamp.globalsign.com/tsa/r6advanced1 /td SHA256 /fd SHA256 'las_notes.exe' '*.dll'
    signtool verify /v 'las_notes.exe'
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
  if (Platform.isWindows || Platform.isLinux) {
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
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo), useMaterial3: true),
      home: Main(),
    );
  }
}

class Main extends StatefulWidget {
  @override State<Main> createState() => _MainState();
}

class _MainState extends State<Main> {
  final _focusNodeGlobal = FocusNode();         // main global focus for the whole desktop app (to get shortcuts working)
  final _focusNodeText = FocusNode();           // main text focus
  final _focusNodeTags = FocusNode();           // comma-separated tags focus
  final _focusNodeSearch = FocusNode();         // global search focus

  final _currentText = TextEditingController(); // main text in add/edit mode
  final _currentTags = TextEditingController(); // comma-separated tags in the text field
  final _globalSearch = TextEditingController();// text in "Global search" field; only for mobile app

  int? _currentNoteId;                          // if present, noteID in edit mode (otherwise NEW_NOTE mode)
  var _oldTags = "";                            // old comma-separated tags for edit mode (to calc tags diff)
  Iterable<Note> _notes = [];                   // in view mode, DB notes array for markdown view
  var _search = Search("", SearchMode.all);     // search by tag name (.tag), keyword (.keyword), ID (.id) or all (.all)
  var _editorMode = EditorMode.edit;            // edit or view mode
  String? _currentPath;                         // copy of Model.currentPath to catch "onCurrentPathChange" event
  var _fileChanged = false;                     // for iOS, we need to warn user that the DB file may be lost
  Future<void>? _webDavLoading;                 // when WebDAV enabled, shows progress indicator on save/delete/archive
  var _back = TrixStack<Search>();              // ⬅️ stack history
  var _forward = TrixStack<Search>();           // ➡️ stack history

  bool get fileChanged => _fileChanged;
  set fileChanged(bool v) {
    if (Platform.isIOS && !ScopedModel.of<TheModel>(context).webDav.isConnected) // for WebDAV, it's OK
      _fileChanged = v;
  }

  @override
  void initState() {
    super.initState();
    _currentText.addListener(() { setState(() {}); });
  }

  @override
  Widget build(BuildContext context) {
    return ScopedModelDescendant<TheModel>(builder: (context, child, model) {
      if (_currentPath != model.currentPath) { // new file opened
        _currentPath = model.currentPath;
        _back.clear();
        _forward.clear();
        _setReadMode(Search("", SearchMode.all));
        if (isDesktop)
          windowManager.setTitle(model.currentPath != null ? "Las Notes (${model.currentPath})" : "Las Notes");
      }
      return isDesktop ? _buildForDesktop(context, model) : _buildForMobile(context, model);
    });
  }

  Widget _buildForMobile(BuildContext context, TheModel model) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Las Notes", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(onPressed: () => _history(_back, _forward), icon: const Icon(Icons.chevron_left)),
          IconButton(onPressed: () => _history(_forward, _back), icon: const Icon(Icons.chevron_right)),
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
              controller: _globalSearch, // only for Mobile app to keep the text after "Navigator.pop()"
              focusNode: _focusNodeSearch,
              decoration: const InputDecoration(border: OutlineInputBorder(), label: Text("Global search")),
              onSubmitted: (s) {
                _setReadMode(Search(s, SearchMode.keyword));
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
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 10),
            const Text("TAGS", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            FutureBuilder(future: model.getTags(), builder: (context, snapshot) {
              if (snapshot.hasData)
                return Expanded(child: ListView(children: snapshot.data!.map((tag) =>
                  OutlinedButton(
                    style: ButtonStyle(
                      alignment: Alignment.centerLeft,
                      backgroundColor: WidgetStateProperty.all(Colors.brown[50])
                    ),
                    child: Text(tag),
                    onPressed: () {
                      _setReadMode(Search(tag, SearchMode.tag));
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
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _webDavProgressIndicator(),
          Visibility(
            visible: model.currentPath != null && _editorMode == EditorMode.read,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: FloatingActionButton(
                heroTag: "newNote",
                child: const Icon(Icons.note_add_outlined, size: 32),
                backgroundColor: Colors.lightGreen[700],
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
                child: const Icon(Icons.domain_verification, size: 32),
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
                child: const Icon(Icons.cancel, size: 30),
                backgroundColor: Colors.red[300],
                onPressed: () => _setReadMode(_search),
              ),
            ),
          ),
          Visibility(
            visible: model.currentPath == null,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
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
              padding: const EdgeInsets.all(8.0),
              child: FloatingActionButton(
                heroTag: "openWebDav",
                child: const Icon(Icons.cloud_download_outlined, size: 36),
                backgroundColor: Colors.blue[300],
                onPressed: _showWebDavDialogMobile,
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
    final settings = Settings.local;
    final isMacOS = Platform.isMacOS;
    return PlatformMenuBar(
      menus: [ // TODO: create menu for Windows/Linux
        PlatformMenu(
          label: "",
          menus: [
            PlatformMenuItemGroup(members: [
              PlatformMenuItem(label: "About Las Notes", onSelected: _showAboutDialog),
            ]),
            PlatformMenuItem(label: "Quit", onSelected: () => exit(0)),
          ],
        ),
        PlatformMenu(
          label: "File",
          menus: [
            PlatformMenu(label: "Open Recent", menus: settings.recentFiles.map((path) =>
              PlatformMenuItem(label: path, onSelected: () => model.openFile(context, path))
            ).toList()),
            PlatformMenuItemGroup(members: [
              PlatformMenuItem(label: "New DB File", onSelected: () => model.newFile(context)),
              PlatformMenuItem(label: "New DB File (encrypted)", onSelected: () => model.newFile(context, encrypted: true)),
              PlatformMenuItem(label: "Open...", onSelected: () => model.openFileWithDialog(context)),
              PlatformMenuItem(label: "Open WebDAV...", onSelected: () => _showWebDavDialogDesktop()),
            ]),
            PlatformMenuItem(label: "Close DB File", onSelected: model.closeFile),
          ],
        ),
        PlatformMenu(
          label: "Edit",
          menus: [
            PlatformMenuItem(label: " ᎒᎒᎒  Insert Table", onSelected: () =>
                Utils.insertText(_currentText, "| A| B| C|\n|:--|---|--:|\n|  |  |  |\n|  |  |  |\n|  |  |  |\n")),
            PlatformMenuItem(label: "🔗 Insert Link", onSelected: () =>
                Utils.insertText(_currentText, "[Link](https://)\n")),
            PlatformMenuItem(label: "🕓 Insert DateTime", onSelected: () =>
                Utils.insertText(_currentText, "${DateTime.now().toString().substring(0, 19)}\n")),
          ],
        ),
        PlatformMenu(
          label: "Navigate",
          menus: [
            PlatformMenuItem(label: "⬅️ Back         ⌘[", onSelected: () => _history(_back, _forward), ),
            PlatformMenuItem(label: "➡️ Forward    ⌘]", onSelected:   () => _history(_forward, _back)),
          ],
        ),
      ],
      child: Shortcuts(
        shortcuts: {
          SingleActivator(LogicalKeyboardKey.keyN, meta: isMacOS, control: !isMacOS, shift: true): NewDbFileIntent(),
          SingleActivator(LogicalKeyboardKey.keyE, meta: isMacOS, control: !isMacOS, shift: true): NewDbxFileIntent(),
          SingleActivator(LogicalKeyboardKey.keyO, meta: isMacOS, control: !isMacOS, shift: true): OpenWebDavFileIntent(),
          SingleActivator(LogicalKeyboardKey.keyO, meta: isMacOS, control: !isMacOS):              OpenDbFileIntent(),
          SingleActivator(LogicalKeyboardKey.keyW, meta: isMacOS, control: !isMacOS):              CloseDbFileIntent(),
          SingleActivator(LogicalKeyboardKey.keyN, meta: isMacOS, control: !isMacOS):              NewNoteIntent(),
          SingleActivator(LogicalKeyboardKey.keyS, meta: isMacOS, control: !isMacOS):              SaveNoteIntent(),
          SingleActivator(LogicalKeyboardKey.escape):                                              EscapeIntent(),
          SingleActivator(LogicalKeyboardKey.keyF, meta: isMacOS, control: !isMacOS, shift: true): GlobalSearchIntent(),
          SingleActivator(LogicalKeyboardKey.f1):                                                  AboutIntent(),
          SingleActivator(LogicalKeyboardKey.bracketLeft,  meta: isMacOS, control: !isMacOS):      UndoIntent(),
          SingleActivator(LogicalKeyboardKey.bracketRight, meta: isMacOS, control: !isMacOS):      RedoIntent(),
          SingleActivator(LogicalKeyboardKey.keyQ, meta: isMacOS, control: !isMacOS):              CloseAppIntent(),
        },
        child: Actions(
          actions: {
            NewDbFileIntent:      CallbackAction(onInvoke: (_) => model.newFile(context)),
            NewDbxFileIntent:     CallbackAction(onInvoke: (_) => model.newFile(context, encrypted: true)),
            OpenDbFileIntent:     CallbackAction(onInvoke: (_) => model.openFileWithDialog(context)),
            OpenWebDavFileIntent: CallbackAction(onInvoke: (_) => _showWebDavDialogDesktop()),
            CloseDbFileIntent:    CallbackAction(onInvoke: (_) => model.closeFile()),
            NewNoteIntent:        CallbackAction(onInvoke: (_) => _setEditMode(null, "", "")),
            SaveNoteIntent:       CallbackAction(onInvoke: (_) => _saveNote()),
            EscapeIntent:         CallbackAction(onInvoke: (_) => _setReadMode(_search)),
            GlobalSearchIntent:   CallbackAction(onInvoke: (_) => _focusNodeSearch.requestFocus()),
            AboutIntent:          CallbackAction(onInvoke: (_) => _showAboutDialog()),
            UndoIntent:           CallbackAction(onInvoke: (_) => _history(_back, _forward)),
            RedoIntent:           CallbackAction(onInvoke: (_) => _history(_forward, _back)),
            CloseAppIntent:       CallbackAction(onInvoke: (_) => exit(0)),
          },
          child: Focus(               // needed for Shortcuts
            autofocus: true,          // focused by default
            focusNode: _focusNodeGlobal,
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
                                  backgroundColor: WidgetStateProperty.all(Colors.brown[50])
                                ),
                                child: Text(tag),
                                onPressed: () => _setReadMode(Search(tag, SearchMode.tag)),
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
                                    focusNode: _focusNodeSearch,
                                    decoration: const InputDecoration(border: OutlineInputBorder(), label: Text("Global search")),
                                    onSubmitted: (s) { _setReadMode(Search(s, SearchMode.keyword)); },
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
                                controlAffinity: ListTileControlAffinity.leading,
                              ),
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
                            Expanded(child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: TextField(
                                controller: _currentText,
                                focusNode: _focusNodeText,
                                autofocus: true,
                                keyboardType: TextInputType.multiline,
                                maxLines: 128, // only for sizing widget (it's not a real limit of lines)
                                autocorrect: false,
                                decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(6))),
                              ),
                            )),
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
                              child: TextField(
                                controller: _currentTags,
                                focusNode: _focusNodeTags,
                                decoration: const InputDecoration(
                                  label: Text("Tags:"),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                                  hintText: "Tag1, Tag2, ..."
                                ),
                                onEditingComplete: _saveNote,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          FilledButton(style: ButtonStyle(
                            backgroundColor: WidgetStateProperty.all(Colors.blueAccent),
                            minimumSize: const WidgetStatePropertyAll(Size(120, 50))),
                            onPressed: _saveNote,
                            child: Text(_currentNoteId == null ? "Save" : "Update",
                              style: const TextStyle(fontSize: 18),
                            ),
                          ),
                        ]),
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
      case EditorMode.read:
        return ListView(children: _notes.map((note) => TrixContainer(child: GestureDetector(
          onLongPress: () => _contextMenuMobile(note), // doesn't work on iOS (=> also use DoubleTap)
          onDoubleTap: () => _contextMenuMobile(note),
          child: Opacity(
            opacity: note.isDeleted ? 0.67 : 1,
            child: Collapsible(note.data, linesToCollapse: 32),
          )))).toList()
        );
      case EditorMode.edit:
        return Column(children: [
          Expanded(child: TextField( // TODO reuse
            controller: _currentText,
            focusNode: _focusNodeText,
            autofocus: true,
            keyboardType: TextInputType.multiline,
            maxLines: 128, // only for sizing widget (it's not a real limit of lines)
            autocorrect: true,        // T9 hints for iOS
            enableSuggestions: false, // Android only
            decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(6))),
          )),
          Expanded(child: TrixContainer(child: MarkdownWidget(data: _currentText.text, shrinkWrap: true))),
          Row(children: [
            const Text("Tags:", style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: TextField(
                controller: _currentTags,
                focusNode: _focusNodeTags,
                autocorrect: false,
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

  void _contextMenuMobile(Note note) async {
    final model = ScopedModel.of<TheModel>(context);

    // archived notes
    if (note.isDeleted) {
      const h1 = "Restore";
      const msg = "Restore note from archive?";
      const style = AlertButtonStyle.yesNo;
      await Utils.showAlert(h1, msg, IconStyle.information, style, onYes: () async {
        await model.restoreNoteById(note.id);
        _webDavLoading = model.uploadWebDav();
        _setReadMode(_search);
      });
      return;
    }

    // regular notes
    final result = await FlutterPlatformAlert.showCustomAlert(
      windowTitle: "Update note",
      text: Utils.firstLine(note.data),
      iconStyle: IconStyle.question,
      positiveButtonTitle: "Edit",
      neutralButtonTitle: "Archive",
      negativeButtonTitle: "Delete",
      options: PlatformAlertOptions(
        ios: IosAlertOptions(negativeButtonStyle: IosButtonStyle.destructive),
        // TODO Android?
      ),
    );
    switch (result) {
      case CustomButton.positiveButton:
        _setEditMode(note.id, note.data, note.tags);
        break;
      case CustomButton.neutralButton:
        if (await model.archiveNoteById(note.id))
          _webDavLoading = model.uploadWebDav();
        _setReadMode(_search);
        break;
      case CustomButton.negativeButton:
        if (await model.deleteNoteById(note.id))
          _webDavLoading = model.uploadWebDav();
        _setReadMode(_search);
        break;
      default:
    }
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
            _setEditMode(note.id, note.data, note.tags);
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
      child: TrixContainer(child: Opacity(
        opacity: note.isDeleted ? 0.67 : 1,
        child: Collapsible(note.data, linesToCollapse: 32),
      )),
    )).toList();
    return ListView(children: children);
  }

  Widget _webDavProgressIndicator() {
    return FutureBuilder(
      future: _webDavLoading,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return Opacity(opacity: 0.3,
            child: const Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              Text("WebDAV", style: TextStyle(color: Colors.purple)),
              CircularProgressIndicator(color: Colors.purple),
            ]),
          );
        return const SizedBox.shrink();
      }
    );
  }

  void _saveNote() async {
    if (_currentText.text.trim().isEmpty) return;

    final model = ScopedModel.of<TheModel>(context);
    final newId = await model.saveNote(_currentNoteId, _currentText.text, _currentTags.text, _oldTags);
    if (newId != null) {
      fileChanged = true; // for iOS, we need to warn user that the DB file may be lost
      _webDavLoading = model.uploadWebDav();
      _setReadMode(Search(newId.toString(), SearchMode.id));
    } else _focusNodeTags.requestFocus();

    if (!isDesktop)
      FocusManager.instance.primaryFocus?.unfocus(); // hide keyboard on iOS/Android
  }

  void _closeFile() {
    final model = ScopedModel.of<TheModel>(context);
    if (fileChanged) {
      const header = "DB file is not exported";
      const msg = "On iOS you have to share this file to external storage. Do you want to share?";
      Utils.showAlert(header, msg, IconStyle.information, AlertButtonStyle.yesNoCancel, onYes: _shareFile, onNo: model.closeFile);
    } else model.closeFile();
  }

  void _showAboutDialog() async {
    final i = await PackageInfo.fromPlatform();
    final text = "v${i.version} (build: ${i.buildNumber})\n\nCopyright © 2024-2026\nmitrakov-artem@yandex.ru\nAll rights reserved.";
    Utils.showAlert(i.appName, text, IconStyle.information, AlertButtonStyle.ok);
  }

  void _showWebDavDialogDesktop() {
    final model = ScopedModel.of<TheModel>(context);
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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

  void _setEditMode(int? noteId, String text, String tags) {
    setState(() {
      _currentText.text = text;
      _currentTags.text = tags;
      _currentNoteId = noteId;
      _oldTags = tags;
      _notes = [];
      _editorMode = EditorMode.edit;
      /// _search = _search; (keep the same)
    });
    _focusNodeText.requestFocus();
  }

  void _setReadMode(Search sch, {bool pushToHistory = true}) async {
    final model = ScopedModel.of<TheModel>(context);
    final Iterable<Note> notes =
      sch.by == SearchMode.all     ? await model.getAllNotes() :
      sch.by == SearchMode.tag     ? await model.searchByTag(sch.search) :
      sch.by == SearchMode.keyword ? await model.searchByKeyword(sch.search) :
      sch.by == SearchMode.id      ? await model.searchById(int.tryParse(sch.search) ?? 0).then((note) => [if (note != null) note]) :
      sch.by == SearchMode.random  ? await model.getRandomNotes(10) : [];

    setState(() {
      _currentText.text = "";
      _currentTags.text = "";
      _currentNoteId = null;
      _oldTags = "";
      _notes = notes;
      _editorMode = EditorMode.read;
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
class UndoIntent           extends Intent {}
class RedoIntent           extends Intent {}
class CloseAppIntent       extends Intent {}
