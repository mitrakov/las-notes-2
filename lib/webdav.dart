import 'dart:io';
import 'package:markdown_widget/config/all.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webdav_client/webdav_client.dart' as wd;

class WebdavConnector {
  late wd.Client client;
  late String tempDir;

  void connect(String url, String user, String password, ValueCallback onErr) async {
    try {
      client = wd.newClient(url, user: user, password: password);
      tempDir = (await getTemporaryDirectory()).path;
    } catch (e) {onErr(e);}
  }

  Future<String> download(String path) async {
    final newPath = "${tempDir}$path";                      // TODO check / on Windows
    await client.read2File(path, newPath);
    if (File(newPath).existsSync())
      return newPath;
    throw new Exception("Cannot open: $newPath");
  }

  Future<void> upload(String path) async {
    final wdPath = path.replaceAll(tempDir, "");
    print(wdPath);
    await client.writeFromFile(path, wdPath);
  }
}
