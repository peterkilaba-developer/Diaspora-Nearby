import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

class TelegramUtils {
  /// Share text via Telegram (no specific recipient).
  /// Tries the Telegram app first, then falls back to web.
  static Future<bool> shareText(String message) async {
    final appUrl = Uri.parse(
      'tg://msg?text=${Uri.encodeComponent(message)}',
    );
    final webUrl = Uri.parse(
      'https://t.me/share/url?url=&text=${Uri.encodeComponent(message)}',
    );

    try {
      if (await canLaunchUrl(appUrl)) {
        return await launchUrl(appUrl, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(webUrl)) {
        return await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      }
      return false;
    } catch (e) {
      debugPrint('Telegram Share Error: $e');
      return false;
    }
  }
}
