import 'package:flutter/material.dart';

class TrixContainer extends StatelessWidget {
  final Widget child;
  const TrixContainer({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const .all(2),
      child: Container(
        padding: const .all(4),
        decoration: BoxDecoration(border: .all(color: const Color(0xFFBDBDBD), width: 0.7), borderRadius: .circular(8)),
        child: child
      )
    );
  }
}
