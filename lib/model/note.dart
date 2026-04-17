import 'dart:convert';
import 'dart:typed_data';

class Note {
  final int id;
  final String data;
  final String tags;
  final Attachment? attachment;
  final bool isDeleted;

  Note(this.id, this.data, this.tags, this.attachment, this.isDeleted);

  Map<String, dynamic> toMap() => {"id": id, "tags": tags, "isDeleted": isDeleted, "data": data,
    if (attachment != null) "attachment" : attachment!.toMap()};
}

class Attachment {
  final String name;
  final Uint8List data;

  Attachment(this.name, this.data);

  Map<String, dynamic> toMap() => {"name": name, "data": base64Encode(data)};
}
