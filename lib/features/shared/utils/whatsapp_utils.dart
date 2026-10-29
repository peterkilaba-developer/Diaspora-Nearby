import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

class WhatsAppUtils {
  /// Official Diaspora Nearby platform & Founder (Peter Swai) WhatsApp number.
  static const String platformWhatsAppNumber = '+16413020012';
  static const String platformWhatsAppDisplay = '+1 (641) 302-0012';

  /// Launches WhatsApp with the given phone number and optional message.
  /// Tries the app first, then falls back to the web interface.
  static Future<bool> launchWhatsApp(String phone, {String? message}) async {
    // Keep + for app scheme (e.g. +1234567890)
    final appPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    // Remove everything including + for web scheme (e.g. 1234567890)
    final webPhone = phone.replaceAll(RegExp(r'\D'), '');

    final msgPart = message != null
        ? '&text=${Uri.encodeComponent(message)}'
        : '';
    final appUrl = Uri.parse('whatsapp://send?phone=$appPhone$msgPart');
    final webUrl = Uri.parse(
      'https://wa.me/$webPhone?text=${Uri.encodeComponent(message ?? '')}',
    );

    try {
      try {
        final launched = await launchUrl(
          appUrl,
          mode: LaunchMode.externalApplication,
        );
        if (launched) return true;
      } catch (_) {}

      return await launchUrl(
        webUrl,
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('WhatsApp Launch Error: $e');
      return false;
    }
  }

  /// Launches WhatsApp to share text (no specific recipient).
  static Future<bool> shareText(String message) async {
    final appUrl = Uri.parse(
      'whatsapp://send?text=${Uri.encodeComponent(message)}',
    );
    final webUrl = Uri.parse(
      'https://api.whatsapp.com/send?text=${Uri.encodeComponent(message)}',
    );

    try {
      try {
        final launched = await launchUrl(
          appUrl,
          mode: LaunchMode.externalApplication,
        );
        if (launched) return true;
      } catch (_) {}
      return await launchUrl(webUrl, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('WhatsApp Share Error: $e');
      return false;
    }
  }
}
