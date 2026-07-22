import 'package:url_launcher/url_launcher.dart';

class WhatsAppSender {
  /// Opens WhatsApp with the chat + message pre-filled.
  /// Honest limitation: this opens the chat with text ready — you tap send.
  /// (Fully automatic send needs the Accessibility Service, added in Step 8C.)
  static Future<bool> openChat({
    required String phoneNumber, // with country code, no + or spaces
    required String message,
  }) async {
    final encoded = Uri.encodeComponent(message);
    final uri = Uri.parse('https://wa.me/$phoneNumber?text=$encoded');
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }
}