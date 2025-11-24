// ignore_for_file: sort_child_properties_last
import 'package:flutter/material.dart';

Future<String?> showInputBox(BuildContext context, String title, {String? hint, String? initialText}) async {
  TextEditingController ctrl = TextEditingController(text: initialText);

  // TODO: autofocus, ENTER key, ESC key
  return showDialog<String>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: <Widget>[
          TextButton(
            child: const Text("Cancel"),
            onPressed: Navigator.of(context).pop,
          ),
          ElevatedButton(
            child: const Text("OK"),
            onPressed: () => Navigator.of(context).pop(ctrl.text),
          ),
        ],
      );
    },
  );
}
