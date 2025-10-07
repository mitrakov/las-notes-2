import 'package:flutter_platform_alert/flutter_platform_alert.dart';

class Utils {
  static Iterable<String> split(String str) => str.split(",").map((s) => s.trim()).where((s) => s.isNotEmpty);

  static void showAlert(String title, String text, IconStyle icon, AlertButtonStyle buttons, Function onYes, onNo) async {
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
      case AlertButton.yesButton:
      case AlertButton.okButton:
      case AlertButton.tryAgainButton:
      case AlertButton.retryButton:
        onYes();
        break;
      case AlertButton.noButton:
      case AlertButton.abortButton:
      case AlertButton.continueButton:
        onNo();
        break;
      default:
    }
  }
}
