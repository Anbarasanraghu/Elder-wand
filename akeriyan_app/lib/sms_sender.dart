import 'package:url_launcher/url_launcher.dart';

class SmsSender {
  /// Opens the SMS app with the recipient + message pre-filled (you tap send).
  /// This is the safe, permission-free approach that works on every phone.
  static Future<bool> send({
    required String number,
    required String message,
  }) async {
    final clean = number.replaceAll(RegExp(r'[^0-9+]'), '');
    if (clean.isEmpty) return false;
    final uri = Uri(
      scheme: 'sms',
      path: clean,
      queryParameters: {'body': message},
    );
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }
}
