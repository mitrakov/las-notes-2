import 'dart:io';
import 'package:flutter/material.dart';
import 'package:markdown_widget/config/all.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webdav_client/webdav_client.dart' as wd;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:lasnotes/model/settings.dart';
import 'package:lasnotes/utils.dart';
import 'package:lasnotes/widgets/trixcontainer.dart';

class WebDavView extends StatefulWidget {
  final WebDavController controller;
  final ValueCallback<String> onNewPath;
  const WebDavView(this.controller, this.onNewPath);

  @override
  State<WebDavView> createState() => _WebDavViewState();
}

class _WebDavViewState extends State<WebDavView> {
  final TextEditingController _ctrlUri = TextEditingController(text: Settings.local.webdavUri);
  final TextEditingController _ctrlLogin = TextEditingController(text: Settings.local.webdavLogin);
  final TextEditingController _ctrlPassword = TextEditingController(text: Settings.local.webdavPass);

  late final String _tempDir;                     // temp directory to download files from WebDAV
  String _pwd = Settings.local.webdavInitPath;    // current working directory (default is "/")
  wd.Client? _client;                             // WebDAV client
  Future<List<wd.File>>? _futureFiles;            // remote file list for a current directory

  @override
  void initState() {
    super.initState();
    getTemporaryDirectory().then((v) { _tempDir = v.path; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("WebDAV Connection"),
        leading: Visibility(
          visible: Platform.isIOS || Platform.isAndroid,
          child: IconButton(icon: const Icon(Icons.arrow_back_ios_new), onPressed: () => Navigator.of(context).pop()),
        ),
        actions: [
          Visibility(
            visible: Platform.isMacOS || Platform.isWindows || Platform.isLinux,
            child: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const .all(8),
        child: Column(
          spacing: 10,
          children: [
            TextField(controller: _ctrlUri, decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: "WebDAV URI",
              hintText: "E.g. https://webdav.yandex.ru",
            )),
            TextField(controller: _ctrlLogin, decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: "Login",
              hintText: "Your login",
            )),
            TextField(controller: _ctrlPassword, obscureText: true, decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: "Password",
              hintText: "Your App password (not primary password)",
            )),
            FilledButton(child: const Text("Connect"), onPressed: _connect),
            Container(height: 1, color: Colors.grey),
            Visibility(
              visible: _client != null,
              child: Text(_pwd, style: TextStyle(color: Colors.grey[600], fontSize: 20, fontWeight: .bold))
            ),
            FutureBuilder(
              future: _futureFiles, // use the stored variable, not the function call
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting)
                  return const Center(child: CircularProgressIndicator());
                if (snapshot.hasData)
                  return _buildListView(context, snapshot.data!);
                return Center(child: Text("Please connect to WebDAV server"));
              }
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListView(BuildContext context, List<wd.File> list) {
    final isRoot = _pwd == "/";                        // if root, then no need to display ".." (Back) button
    return ListView.builder(
      shrinkWrap: true,                                // necessary for constraints
      physics: const NeverScrollableScrollPhysics(),   // smooth scrolling (TODO: Guap?)
      itemCount: list.length + (isRoot ? 0 : 1),       // ".." ++ items
      itemBuilder: (context, index) {
        // first element is ".." (go to parent dir)
        if (!isRoot && index == 0) {
          return TrixContainer(child: ListTile(
            leading: Icon(Icons.reply_outlined,
              color: Colors.blueAccent
            ),
            title: Text("..", style: TextStyle(fontWeight: .bold)),
            onTap: () {
              setState(() {
                _pwd = dirname(_pwd);
                _futureFiles = _client!.readDir(_pwd);
              });
            },
          ));
        }

        // other items are just normal directory content
        final file = list[index - (isRoot ? 0 : 1)];  // index 0 is taken by ".." (go back)
        final path = file.path ?? "";
        final name = file.name ?? "";
        final ext = extension(name);
        final isDir = file.isDir ?? false;
        final isDb = ext == ".db" || ext == ".dbx";

        return Opacity(
          opacity: isDir || isDb ? 1 : 0.5,
          child: TrixContainer(child: ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: FaIcon(isDir ? FontAwesomeIcons.solidFolder : isDb
              ? FontAwesomeIcons.database
              : FontAwesomeIcons.question,
            color: isDir ? Colors.brown : isDb ? ext == ".db" ? Colors.blue : Colors.orange : Colors.grey),
            title: Text("${isDir ? "/" : ""}$name", style: TextStyle(fontWeight: isDir ? .bold : .normal)),
            subtitle: Text(file.mTime.toString().substring(0, 19)), // remove ".000" (milliseconds)
            onTap: () async {
              if (isDir) {
                setState(() {
                  _pwd = path;
                  _futureFiles = _client!.readDir(_pwd);
                });
              } else if (isDb) {
                Settings.local.setWebdavInitDir(_pwd);
                widget.onNewPath(await _download(path));
              }
            },
          )),
        );
      }
    );
  }

  void _connect() async {
    final uri = _ctrlUri.text.trim();
    final login = _ctrlLogin.text.trim();
    final pass = _ctrlPassword.text.trim();
    if (uri.isEmpty || login.isEmpty || pass.isEmpty) return;

    try {
      setState(() {
        _client = wd.newClient(uri, user: login, password: pass);
        _client!.c.options.contentType = "application/octet-stream"; // Bug: https://github.com/flymzero/webdav_client/issues/25
        _futureFiles = _client!.readDir(_pwd);
        widget.controller._init(_client!, _tempDir);
        Settings.local.setWebdavConnection(uri, login, pass);
      });
    } catch (e) {
      Utils.showAlert("Cannot connect", e.toString(), .error, .ok);
    }
  }

  Future<String> _download(String path) async {
    if (_client == null) return Future.error("Not connected");

    final newPath = "${_tempDir}$path";                      // TODO check / on Windows
    print("WebDAV: downloading file '$path' to temp dir: $newPath");
    await _client!.read2File(path, newPath);
    if (File(newPath).existsSync())
      return newPath;
    return Future.error("Cannot open file '$path' ($newPath)");
  }

  @override
  void dispose() {
    _ctrlUri.dispose();
    _ctrlLogin.dispose();
    _ctrlPassword.dispose();
    super.dispose();
  }
}

class WebDavController {
  wd.Client? _client;
  String _tempDir = "";

  bool get isConnected => _client != null;

  void _init(wd.Client client, String tempDir) {
    _client = client;
    _tempDir = tempDir;
  }

  Future<void> updateSafe(String? localPath) async {
    if (_client == null || localPath == null) return;

    final wdPath = localPath.replaceAll(_tempDir, "");
    print("WebDAV: uploading file to: $wdPath");
    final timer = Stopwatch()..start();
    await _client?.writeFromFile(localPath, wdPath); // may be very slow (≈ 1 Mb/min)
    print("WebDAV: uploading done: $wdPath (${timer.elapsed})");
  }

  void close() {
    _client = null;
  }
}
