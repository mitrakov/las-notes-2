// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:sqflite/sqflite.dart';
import 'package:lasnotes/model/note.dart';

// IMPORTANT! Remove f*cking sandbox in MacOS and iOS .*entitlements files
class SQLiteDatabase {
  static const _GLOBAL_SCHEMA_VERSION = 5;
  Database? _db;

  Future<void> openDb(String path) async {
    await closeDb();
    _db = await openDatabase(path, onConfigure: (db) => db.execute("PRAGMA foreign_keys=ON;"));
    await _updateSchemaIfRequired();
  }

  Future<void> closeDb() async {
    await _db?.close();
    _db = null;
  }

  bool isConnected() {
    return _db?.isOpen ?? false;
  }

  Future<void> createDb(String path) async {
    await openDb(path);
    await _db?.transaction((tx) async {
      tx.execute("""
      CREATE TABLE IF NOT EXISTS note (
        note_id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
        author VARCHAR(64) NOT NULL DEFAULT '',
        client VARCHAR(255) NOT NULL DEFAULT '',
        user_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        colour INTEGER NOT NULL DEFAULT 16777215,
        rank TINYINT NOT NULL DEFAULT 0,
        is_visible BOOLEAN NOT NULL DEFAULT true,
        is_favourite BOOLEAN NOT NULL DEFAULT false,
        is_deleted BOOLEAN NOT NULL DEFAULT false,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
      CREATE VIRTUAL TABLE IF NOT EXISTS notedata USING FTS5(data);
      CREATE TABLE IF NOT EXISTS tag (
        tag_id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
        name VARCHAR(64) UNIQUE NOT NULL,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
      CREATE TABLE IF NOT EXISTS image (
        guid UUID PRIMARY KEY NOT NULL,
        data BLOB NOT NULL,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
      CREATE TABLE IF NOT EXISTS note_to_tag (
        note_id INTEGER NOT NULL REFERENCES note (note_id) ON UPDATE RESTRICT ON DELETE CASCADE,
        tag_id  INTEGER NOT NULL REFERENCES tag (tag_id) ON UPDATE RESTRICT ON DELETE CASCADE,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (note_id, tag_id)
      );
      CREATE TABLE IF NOT EXISTS metadata (
        key VARCHAR(64) PRIMARY KEY NOT NULL,
        value VARCHAR(255) NULL,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
      PRAGMA user_version=$_GLOBAL_SCHEMA_VERSION;
      """);
    });
  }

  /// returns new generated note_id > 0
  Future<int> insertNote(String data) async {
    return await _db?.transaction((tx) async {
      final noteId = await tx.rawInsert("INSERT INTO note DEFAULT VALUES;"); // don't use "RETURNING note_id" in SQFlite
      await tx.rawInsert("INSERT INTO notedata (rowid, data) VALUES (?, ?);", [noteId, data]);
      return noteId;
    }) ?? 0;
  }

  /// returns the number of rows affected
  Future<void> updateNote(int noteId, String data) async {
    await _db?.transaction((tx) async {
      tx.rawUpdate("UPDATE notedata SET data = ? WHERE rowid = ?;", [data, noteId]);
      tx.rawUpdate("UPDATE note SET updated_at = CURRENT_TIMESTAMP WHERE note_id = ?;", [noteId]);
    });
  }

  Future<void> softDeleteNote(int noteId, bool deleted) async {
    // Sqflite error: use 1/0 instead of BOOL (https://github.com/tekartik/sqflite/blob/master/sqflite/doc/supported_types.md)
    _db?.rawUpdate("UPDATE note SET is_deleted = ?, updated_at = CURRENT_TIMESTAMP WHERE note_id = ?;", [deleted ? 1 : 0, noteId]);
  }

  Future<void> deleteNote(int noteId) async {
    await _db?.transaction((tx) async {
      tx.rawDelete("DELETE FROM note     WHERE note_id = ?;", [noteId]);
      tx.rawDelete("DELETE FROM notedata WHERE rowid = ?;", [noteId]);
      tx.rawDelete("DELETE FROM tag      WHERE tag_id NOT IN (SELECT DISTINCT tag_id FROM note_to_tag);");
    });
  }

  Future<Iterable<Note>> getAllNotes(bool fetchDeleted) async {
    final dbResult = await _db?.rawQuery("""
      SELECT note_id, data, GROUP_CONCAT(name, ', ') AS tags, is_deleted
      FROM note
      INNER JOIN notedata ON note_id = notedata.rowid
      INNER JOIN note_to_tag USING (note_id)
      INNER JOIN tag         USING (tag_id)
      ${fetchDeleted ? "" : "WHERE NOT is_deleted "}      
      GROUP BY note_id
      ORDER BY note.updated_at DESC
      ;""");
    return dbResult?.map(toNote) ?? [];
  }

  Future<Iterable<Note>> getRandomNotes(bool fetchDeleted, int limit) async {
    final dbResult = await _db?.rawQuery("""
      SELECT note_id, data, GROUP_CONCAT(name, ', ') AS tags, is_deleted
      FROM note
      INNER JOIN notedata ON note_id = notedata.rowid
      INNER JOIN note_to_tag USING (note_id)
      INNER JOIN tag         USING (tag_id)
      ${fetchDeleted ? "" : "WHERE NOT is_deleted "}      
      GROUP BY note_id
      ORDER BY RANDOM()
      LIMIT ?
      ;""", [limit]);
    return dbResult?.map(toNote) ?? [];
  }

  Future<Iterable<String>> getTags() async {
    final dbResult = await _db?.rawQuery("SELECT name FROM tag ORDER BY name;"); // TODO don't show archived
    return dbResult?.map((e) => e["name"].toString()) ?? [];
  }

  Future<Note?> searchByID(int id) async {
    final dbResult = await _db?.rawQuery("""
      SELECT note_id, data, GROUP_CONCAT(name, ', ') AS tags, is_deleted
      FROM note
      INNER JOIN notedata ON note_id = notedata.rowid
      INNER JOIN note_to_tag USING (note_id)
      INNER JOIN tag         USING (tag_id)
      WHERE note_id = ?
      GROUP BY note_id
      ;""", [id]);
    return dbResult?.map(toNote).firstOrNull;
  }

  Future<Iterable<Note>> searchByTag(String tag, bool fetchDeleted) async {
    final dbResult = await _db?.rawQuery("""
      SELECT note_id, data, GROUP_CONCAT(name, ', ') AS tags, is_deleted
      FROM note
      INNER JOIN notedata ON note_id = notedata.rowid
      INNER JOIN note_to_tag USING (note_id)
      INNER JOIN tag         USING (tag_id)
      WHERE note_id IN (SELECT note_id FROM tag INNER JOIN note_to_tag USING (tag_id) WHERE name = ?)
      ${fetchDeleted ? "" : " AND NOT is_deleted "}          
      GROUP BY note_id
      ORDER BY note.updated_at DESC
      ;""", [tag]);
    return dbResult?.map(toNote) ?? [];
  }

  Future<Iterable<Note>> searchByKeyword(String word, bool fetchDeleted) async {
    if (word.isEmpty) return [];

    final dbResult = await _db?.rawQuery("""
      SELECT note_id, data, GROUP_CONCAT(name, ', ') AS tags, is_deleted
      FROM note
      INNER JOIN notedata ON note_id = notedata.rowid
      INNER JOIN note_to_tag USING (note_id)
      INNER JOIN tag         USING (tag_id)
      WHERE data MATCH ?
      ${fetchDeleted ? "" : " AND NOT is_deleted "}          
      GROUP BY note_id
      ORDER BY notedata.rank ASC, note.updated_at DESC
      ;""", [word]
    );
    return dbResult?.map(toNote) ?? [];
  }

  Future<void> linkTagsToNote(int noteId, Iterable<String> tags) async {
    if (tags.isEmpty) return;

    return _db?.transaction((tx) async {
      await Future.wait(tags.map((tag) async {
        final tagIdOpt = (await tx.rawQuery("SELECT tag_id FROM tag WHERE name = ?;", [tag])).firstOrNull;
        final tagId = tagIdOpt != null
          ? int.parse(tagIdOpt["tag_id"].toString())
          : await tx.rawInsert("INSERT INTO tag (name) VALUES (?);", [tag]);
        await tx.rawInsert("INSERT INTO note_to_tag (note_id, tag_id) VALUES (?, ?);", [noteId, tagId]);
      }));
    });
  }

  Future<void> unlinkTagsFromNote(int noteId, Iterable<String> tags) async {
    // FROM https://github.com/tekartik/sqflite/blob/master/sqflite/doc/sql.md:
    // A common mistake is to expect to use IN (?) and give a list of values. This does not work.
    // Instead you should list each argument one by one.
    final IN = List.filled(tags.length, '?').join(', '); // "?,?,?,?"
    await _db?.transaction((tx) async {
      final args = [noteId, ...tags];
      tx.rawDelete("DELETE FROM note_to_tag WHERE note_id = ? AND tag_id IN (SELECT tag_id FROM tag WHERE name IN ($IN));", args);
      tx.rawDelete("DELETE FROM tag WHERE tag_id NOT IN (SELECT DISTINCT tag_id FROM note_to_tag);");
    });
  }

  Future<String?> getMetadata(String key) async {
    final valueOpt = (await _db?.rawQuery("SELECT value FROM metadata WHERE key = ?;", [key]))?.firstOrNull;
    return valueOpt?["tag_id"].toString();
  }

  Future<void> setMetadata(String key, String? value) async {
    if (value == null) {
      final args = [key, value];
      await _db?.rawInsert("INSERT INTO metadata (key, value) VALUES (@0, @1) ON CONFLICT (key) DO UPDATE SET value = @1;", args);
    } else await _db?.rawDelete("DELETE FROM metadata WHERE key = ?;", [key]);
  }

  Future<int> _getSchemaVersion() async {
    final valueOpt = (await _db!.rawQuery("PRAGMA user_version")).firstOrNull;
    final value = valueOpt?.values.firstOrNull?.toString();
    return int.tryParse(value ?? "0") ?? 0; // for real users, min = 3
  }

  Future<void> _updateSchemaIfRequired() async {
    final dbVersion = await _getSchemaVersion();

    if (dbVersion < _GLOBAL_SCHEMA_VERSION) {
      _db!.transaction((tx) async {
        if (dbVersion < 4) { // new "metadata" table
          await tx.execute("""
          CREATE TABLE IF NOT EXISTS metadata (
            key VARCHAR(64) PRIMARY KEY NOT NULL,
            value VARCHAR(255) NULL,
            created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
          );
          """);
          print("Migration 3 -> 4 done");
        }
        if (dbVersion < 5) { // bug fix to trim " tagName "
          await tx.execute("UPDATE tag SET name = (trim(name) || '_bugfix_tag_id_' || tag_id) WHERE name != trim(name);");
          print("Migration 4 -> 5 done");
        }
        await tx.execute("PRAGMA user_version=$_GLOBAL_SCHEMA_VERSION");
      });
    }
  }

  Note toNote(Map<String, Object?> e) =>
    Note(id: e["note_id"] as int, data: e["data"] as String, tags: e["tags"] as String, isDeleted: e["is_deleted"] as int != 0);
}
