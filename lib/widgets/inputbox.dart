import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<String?> showInputBox(BuildContext context, String title, {String? hint, String? initialText}) async {
  final ctrl = TextEditingController(text: initialText);
  final focusNode = FocusNode();

  return showDialog<String>(
    context: context,
    builder: (BuildContext context) {
      return KeyboardListener(
        focusNode: focusNode,
        onKeyEvent: (KeyEvent event) {
          if (event.logicalKey == LogicalKeyboardKey.enter) {
            Navigator.of(context).pop(ctrl.text);
          }
        },
        child: AlertDialog(
          title: Text(title),
          content: TextField(
            autofocus: true,
            obscureText: true,
            controller: ctrl,
            decoration: InputDecoration(hintText: hint),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: Navigator.of(context).pop,
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(ctrl.text),
              child: const Text("OK"),
            ),
          ],
        ),
      );
    },
  );
}
