import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:lasnotes/model/note.dart';
import 'package:lasnotes/utils.dart';

const monospace = TextStyle(
  fontFamily: 'Menlo',   // MacOS/iOS
  fontFamilyFallback: [
    'Consolas',          // Windows
    'Ubuntu Mono',       // Ubuntu/Debian
    'Liberation Mono',   // RedHat/Fedora/CentOS
    'DejaVu Sans Mono',  // Debian/Arch/Suse
    'Courier New',       // The "Global" backup
    'monospace',         // The "Emergency" system generic
  ],
);

class Collapsible extends StatefulWidget {
  final Note note;
  const Collapsible(this.note);
  @override
  State<Collapsible> createState() => _CollapsibleState();

  static Widget simple(String data) {
    return MarkdownWidget(data: data, selectable: false,
      config: MarkdownConfig(configs: [
        PreConfig(
          textStyle: monospace,
          wrapper: (child, code, language) {
            return DefaultTextStyle.merge(style: monospace, child: child); // propagate "monospace" to all children in Highlight
          },
        ),
      ]),
    );
  }
}

class _CollapsibleState extends State<Collapsible> {
  static const linesToCollapse = 32;
  var _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final text = widget.note.data;
    final md = _isExpanded || Utils.linesCount(text) < linesToCollapse ? _markdownWidget(text) : ExpansionTile(
      title: _markdownWidget(Utils.firstLines(text, 4).join("\n") + "\n...", selectable: false),
      children: [_markdownWidget(text)],
      onExpansionChanged: (bool expanded) { setState(() {_isExpanded = expanded;}); },
    );
    final tags = Row(mainAxisSize: .min, spacing: 10, children: Utils.split(widget.note.tags).map((tag) =>
        Container(
          decoration: BoxDecoration(
            color: .fromARGB(155, 216, 230, 245),
            border: .all(color: Colors.blueAccent, width: 0.5,),
            borderRadius: .circular(8),
          ),
          padding: const .symmetric(horizontal: 7),
          child: Text(tag, style: TextStyle(color: Colors.blueAccent, fontSize: 12)),
        )
    ).toList());
    return Stack(alignment: .topRight, children: [md, tags]);
  }

  Widget _markdownWidget(String data, {bool selectable = true}) {
    return MarkdownWidget(
      data: data,
      shrinkWrap: true,
      selectable: selectable,
      config: MarkdownConfig(configs: [
        PreConfig(
          textStyle: monospace,
          wrapper: (child, code, language) {
            return Stack(
              children: [
                DefaultTextStyle.merge(style: monospace, child: child), // propagate "monospace" to all children in Highlight plugin
                Positioned(top: 4, right: 0, child: IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 16), onPressed: () => Clipboard.setData(ClipboardData(text: code)),
                )),
              ],
            );
          },
        ),
      ]),
    );
  }
}
