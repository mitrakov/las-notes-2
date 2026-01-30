import 'dart:typed_data';

class Note {
  final int id;
  final String data;
  final String tags;
  final Attachment? attachment;
  final bool isDeleted;

  Note(this.id, this.data, this.tags, this.attachment, this.isDeleted);
}

class Attachment {
  final String name;
  final Uint8List data;

  Attachment(this.name, this.data);
}
