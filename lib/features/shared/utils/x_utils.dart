import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

class XUtils {
  /// Share text via X (Twitter).
  /// Tries the X/Twitter app first, then falls back to web intent.
  static Future<bool> shareText(String message) async {
    final appUrl = Uri.parse(
      'twitter://post?message=${Uri.encodeComponent(message)}',
    );
    final webUrl = Uri.parse(
      'https://x.com/intent/post?text=${Uri.encodeComponent(message)}',
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
      debugPrint('X Share Error: $e');
      return false;
    }
  }
}
