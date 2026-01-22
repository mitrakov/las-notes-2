import 'package:flutter/material.dart';
import 'package:lasnotes/utils.dart';
import 'package:markdown_widget/markdown_widget.dart';

class Collapsible extends StatefulWidget {
  final String data;
  final int linesToCollapse;

  const Collapsible(this.data, {this.linesToCollapse = 32});

  @override
  State<Collapsible> createState() => _CollapsibleState();
}

class _CollapsibleState extends State<Collapsible> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final text = widget.data;
    return Utils.linesCount(text) < widget.linesToCollapse || _isExpanded
      ? MarkdownWidget(data: text, shrinkWrap: true)
      : ExpansionTile(
        title: MarkdownWidget(data: Utils.firstLines(text, 4).join("\n") + "\n...", shrinkWrap: true, selectable: false),
        children: [MarkdownWidget(data: text, shrinkWrap: true)],
        onExpansionChanged: (bool expanded) {
          setState(() {
            _isExpanded = expanded;
          });
        },
      );
  }
}
