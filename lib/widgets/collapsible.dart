import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lasnotes/utils.dart';
import 'package:markdown_widget/markdown_widget.dart';

class Collapsible extends StatefulWidget {
  final String data;
  final int linesToCollapse;
  final bool expanded;

  const Collapsible(this.data, {this.expanded = false, this.linesToCollapse = 32});

  @override
  State<Collapsible> createState() => _CollapsibleState();
}

class _CollapsibleState extends State<Collapsible> {
  late bool _isExpanded = widget.expanded;

  @override
  Widget build(BuildContext context) {
    final text = widget.data;
    return _isExpanded || Utils.linesCount(text) < widget.linesToCollapse ? _markdownWidget(text) : ExpansionTile(
      title: _markdownWidget(Utils.firstLines(text, 4).join("\n") + "\n...", selectable: false),
      children: [_markdownWidget(text)],
      onExpansionChanged: (bool expanded) { setState(() {_isExpanded = expanded;}); },
    );
  }

  Widget _markdownWidget(String data, {bool selectable = true}) {
    const monospace = const TextStyle(
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
