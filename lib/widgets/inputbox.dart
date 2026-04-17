import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<String?> showInputBox(BuildContext context, String title, {String? hint, String? initialText}) async {
  final ctrl = TextEditingController(text: initialText);
  final result = await showDialog<String>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(title),
        content: TextField(
          autofocus: true,
          obscureText: true,
          controller: ctrl,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: Navigator.of(context).pop,
        ),
        actions: [
          TextButton(
            onPressed: Navigator.of(context).pop,
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(ctrl.text),
            child: const Text("OK"),
          ),
        ],
      );
    },
  );

  Future.delayed(Duration(seconds: 1), () => ctrl.dispose()); // allow animation to finish before dispose()
  return result;
}

Future<void> showContextMenuBox(BuildContext context, String title, String message, List<TrixAction> actions) async {
  final action = await showDialog<TrixAction>(
    context: context,
    builder: (BuildContext context) {
      return KeyboardListener(
        focusNode: FocusNode(),
        autofocus: true,
        onKeyEvent: (KeyEvent event) {
          if (event is KeyUpEvent && event.logicalKey == LogicalKeyboardKey.enter)
            Navigator.of(context).pop(actions.where((a) => a.isDefault).firstOrNull);
        },
        child: AlertDialog(
          title: Text(title, textAlign: .center, style: TextStyle(fontWeight: .bold)),
          content: Text(message, textAlign: .center),
          constraints: BoxConstraints(maxWidth: 360),
          actionsOverflowButtonSpacing: 8,
          actionsAlignment: .center,
          actionsOverflowAlignment: .center,
          actions: [
            ...actions.map((a) =>
              OutlinedButton(
                child: Text(a.label, style: TextStyle(color: Colors.black)),
                onPressed: () => Navigator.of(context).pop(a),
                style: OutlinedButton.styleFrom(
                  minimumSize: Size(200, 40),
                  backgroundColor: a.isDanger? Colors.red[200] : a.isDefault ? Colors.blue[300] : Colors.grey[300],
                ),
              ),
            ),
            Divider(thickness: 2),
            OutlinedButton(
              child: Text("Cancel", style: TextStyle(color: Colors.black)),
              style: OutlinedButton.styleFrom(minimumSize: Size(200, 40)),
              onPressed: Navigator.of(context).pop,
            ),
          ],
        ),
      );
    },
  );

  action?.f();
}

class TrixAction {
  final String label;
  final bool isDefault;
  final bool isDanger;
  final VoidCallback f;
  TrixAction(this.label, this.isDefault, this.isDanger, this.f);
}
