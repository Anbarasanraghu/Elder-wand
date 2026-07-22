import 'package:url_launcher/url_launcher.dart';

class PhoneCaller {
  /// Opens the dialer with the number ready (or places the call on devices
  /// that allow it). Free + reliable; no extra permission needed for the
  /// dialer. For fully hands-free dialing, add the CALL_PHONE permission and
  /// the flutter_phone_direct_caller package.
  static Future<bool> call(String number) async {
    final clean = number.replaceAll(RegExp(r'[^0-9+]'), '');
    if (clean.isEmpty) return false;
    final uri = Uri(scheme: 'tel', path: clean);
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }
}
