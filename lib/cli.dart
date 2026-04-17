import 'dart:convert';
import 'package:args/args.dart';
import 'package:lasnotes/model/model.dart';
import 'package:lasnotes/model/note.dart';

/**
 * Command line tool for Las Notes
 */
class Cli {
  final parser = ArgParser();
  final TheModel model;
  Cli(this.model);

  Future<String> processCLI(List<String> args) async {
    parser.addCommand('search')
      ..addOption('id')
      ..addOption('tag')
      ..addOption('keyword')
      ..addOption('password')
      ..addOption('db', mandatory: true);
    parser.addCommand('save')
      ..addOption('id') // optional for INSERT/UPDATE
      ..addOption('data', mandatory: true)
      ..addOption('tags', mandatory: true)
      ..addOption('password')
      ..addOption('db', mandatory: true);
    for (final cmd in ['delete', 'archive', 'restore'])
      parser.addCommand(cmd)..addOption('id', mandatory: true)..addOption('password')..addOption('db', mandatory: true);
    parser.addCommand('help');

    try {
      final cmd = parser.parse(args).command;
      if (cmd == null)
        return jsonEncode({"status": "error", "message": "Command required: search, save, delete, archive, restore, help"});

      if (cmd.name == "help") return _help();

      if (!await model.openFile(null, cmd['db'], passwd: cmd['password']))
        return jsonEncode({"status": "error", "message": "Cannot open file: ${cmd['db']}"});

      dynamic output;
      switch (cmd.name) {
        case 'search':
          final list = await _search(cmd);
          output = {"status": "ok", "count": list.length, "result": list.map((note) => note.toMap()).toList()};
          break;
        case 'save':
          final id = int.tryParse(cmd['id'] ?? "");
          final oldTags = (await model.searchById(id ?? -1))?.tags ?? "";
          final newId = await model.saveNote(id, cmd['data'], cmd['tags'], oldTags, null);
          output = {"status": newId != null ? "ok" : "error", "id": newId};
          break;
        case 'delete':
          final id = int.parse(cmd['id']);
          await model.deleteNoteById(id, bypassAlert: true);
          output = {"status": "ok", "id": id};
          break;
        case 'archive':
          final id = int.parse(cmd['id']);
          await model.archiveNoteById(id, bypassAlert: true);
          output = {"status": "ok", "id": id};
          break;
        case 'restore':
          final id = int.parse(cmd['id']);
          await model.restoreNoteById(id);
          output = {"status": "ok", "id": id};
          break;
      }

      await model.closeFile();
      return jsonEncode(output);
    } catch (e) {
      return jsonEncode({"status": "error", "message": e.toString()});
    }
  }

  Future<Iterable<Note>> _search(ArgResults cmd) async {
    if (cmd['id'] != null)      return model.searchById(int.parse(cmd['id'])).then((note) => [if (note != null) note]);
    if (cmd['tag'] != null)     return model.searchByTag(cmd['tag']);
    if (cmd['keyword'] != null) return model.searchByKeyword(cmd['keyword']);
    throw Exception("For search, use --id, or --tag, or --keyword");
  }

  String _help() {
    return """Examples:
    lasnotes search --id 55         --db /path/to/file.db 2>/dev/null
    lasnotes search --tag Scala     --db /path/to/file.db 2>/dev/null
    lasnotes search --keyword Scala --db /path/to/file.db 2>/dev/null
    lasnotes delete  --id 55        --db /path/to/file.db 2>/dev/null
    lasnotes archive --id 55        --db /path/to/file.db 2>/dev/null
    lasnotes restore --id 55        --db /path/to/file.db 2>/dev/null
    lasnotes save --data 'data' --tags 'tag1,tag2'         --db /path/to/file.db 2>/dev/null
    lasnotes save --data 'data' --tags 'tag1,tag2' --id 55 --db /path/to/file.db 2>/dev/null
    
    * --password       provides password for *.dbx files
    """;
  }
}
