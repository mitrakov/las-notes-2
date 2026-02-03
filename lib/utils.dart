import 'package:flutter/material.dart';
import 'package:flutter_platform_alert/flutter_platform_alert.dart';

class Utils {
  static Iterable<String> split(String str) => str.split(",").map((s) => s.trim()).where((s) => s.isNotEmpty);

  static int linesCount(String str) => str.split("\n").where((s) => s.trim().isNotEmpty).length;

  static String firstLine(String str) => str.split("\n").firstWhere((s) => s.trim().isNotEmpty, orElse: () => "");

  static Iterable<String> firstLines(String str, int n) => str.split("\n").take(n);

  // on MacOS, supported icons only .stop, .error and .hand (all look like ⚠️)
  static Future<bool> showAlert(
      String title, String text, IconStyle icon, AlertButtonStyle buttons, {VoidCallback? onYes, VoidCallback? onNo}) async {
    final result = await FlutterPlatformAlert.showAlert(
      windowTitle: title,
      text: text,
      iconStyle: icon,
      alertStyle: buttons,
      options: PlatformAlertOptions(
        windows: WindowsAlertOptions(preferMessageBox: true),
      ),
    );

    switch (result) {
      case .yesButton:
      case .okButton:
      case .tryAgainButton:
      case .retryButton:
        onYes?.call();
        return true;
      case .noButton:
      case .abortButton:
      case .continueButton:
      default:
        onNo?.call();
        return false;
    }
  }

  static void insertText(TextEditingController ctrl, String value, [String? selectedSubstring]) {
    if (selectedSubstring != null && !value.contains(selectedSubstring)) throw Exception("SelectedString must be in value");

    final pos = ctrl.selection.start;
    final text = ctrl.text;
    final start = text.substring(0, pos);
    final end = text.substring(pos);
    ctrl.text = "$start$value$end";
    ctrl.selection = selectedSubstring != null
        ? TextSelection(
          baseOffset: pos + value.indexOf(selectedSubstring),
          extentOffset: pos + value.indexOf(selectedSubstring) + selectedSubstring.length)
        : .collapsed(offset: pos + value.length);
  }
}
