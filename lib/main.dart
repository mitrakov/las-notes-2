import 'dart:io';
import 'dart:ffi' show DynamicLibrary;
import 'package:flutter/material.dart';
import 'package:lasnotes/helper.dart';
import 'package:lasnotes/mainapp.dart';
import 'package:scoped_model/scoped_model.dart';
import 'package:window_manager/window_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqf;
import 'package:sqlite3/open.dart' show open;
import 'package:lasnotes/cli.dart';
import 'package:lasnotes/model/model.dart';
import 'package:lasnotes/model/settings.dart';

/*
Build for MacOS:
  bump version in pubspec.yaml
  flutter build macos
  xCode: Product -> Destination -> Any Mac (arm64, x86_64)
  xCode: Product -> Archive -> Distribute App -> Direct Distribution -> wait for 30-40 sec for notarization service to complete
  copy "*.app" to "installer/macos/App"
  run installer/macos/build-dmg.sh
  move *.dmg image to dist/

Build for iOS:
  bump version in pubspec.yaml
  flutter build ios
  xCode: Product -> Destination -> Any iOS Device (arm64)
  xCode: Product -> Archive -> Distribute App -> Custom -> Release Testing -> include manifest for installation
  rename and move *.ipa file to dist/
  upload *.ipa, and manifest.plist to your https-server for further distribution

Build for Android:
  bump version in pubspec.yaml
  flutter build apk
  AndroidStudio: Build -> Generate Signed App Bundle or APK -> APK -> choose android/keystore.jks -> release
  rename and move *.apk file to dist/

Build for Windows:
  bump version in pubspec.yaml
  installer\windows\build.bat

Build for Linux:
  bump version in pubspec.yaml
  installer/linux/build.sh
*/
void main(List<String> args) async {
  // 1. Sharing-Intent plugin needs extra iOS/Android setup! See https://pub.dev/packages/receive_sharing_intent
  WidgetsFlutterBinding.ensureInitialized(); // allow async code in main()
  await Settings.init(); // must have

  // Enable SQLite/SQLCipher support for Windows/Linux:
  // 1. https://stackoverflow.com/q/76158800         // enable FFI support for Windows/Linux
  // 2. pub dev: sqlite3_flutter_libs                // (deprecated) add DLLs for Windows/Linux
  // 3. https://github.com/simolus3/sqlite3.dart/blob/e66702c5bec7faec2bf71d374c008d5273ef2b3b/sqlite3/lib/src/load_library.dart
  if (isWinLinux) {
    final libName = Platform.isWindows ? "sqlite3.dll" : "libsqlite3.so";
    sqf.sqfliteFfiInit();
    sqf.databaseFactory = sqf.createDatabaseFactoryFfi(ffiInit: () => open.overrideForAll(() => DynamicLibrary.open(libName)));
  }

  final model = TheModel();
  if (args.isNotEmpty) {
    stdout.write(await Cli(model).processCLI(args));
    exit(0);
  }

  if (isDesktop)
    await WindowManager.instance.ensureInitialized(); // must have

  runApp(ScopedModel(model: model, child: LasNotes(model)));
}

class LasNotes extends StatelessWidget {
  final TheModel model;
  const LasNotes(this.model);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Las Notes",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.indigo), useMaterial3: true),
      home: MainApp(),
    );
  }
}
