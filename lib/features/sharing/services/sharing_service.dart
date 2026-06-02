import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:diaspora_nearby/features/events/models/event_data.dart';
import 'package:diaspora_nearby/features/shared/utils/whatsapp_utils.dart';

class SharingService {
  SharingService._();
  static final SharingService instance = SharingService._();

  // Basic App Invite
  Future<void> shareApp({String? referralCode}) async {
    final appLink = referralCode != null && referralCode.isNotEmpty
        ? 'https://diasporanearby.com/invite?code=$referralCode'
        : 'https://diasporanearby.com/invite';
    final message =
        'For my family and Friends at home and abroad. Join and connect with me in this platform.: $appLink';

    try {
      // Load logo from assets
      final byteData = await rootBundle.load(
        'assets/icons/logo-transparent-128.png',
      );
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/logo.png');
      await file.writeAsBytes(
        byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        ),
      );

      // Share image + text
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: message),
      );
    } catch (e) {
      // Fallback to text only if image fails
      await SharePlus.instance.share(ShareParams(text: message));
    }
  }

  // Share Event
  Future<void> shareEvent(Event event, {String? referralCode}) async {
    final eventLink = referralCode != null && referralCode.isNotEmpty
        ? 'https://diasporanearby.com/invite?code=$referralCode'
        : 'https://diasporanearby.com/invite';

    final StringBuffer sb = StringBuffer();
    sb.writeln('Check out this event: ${event.title}');
    sb.writeln('Date: ${event.startDate}');
    sb.writeln('Location: ${event.location}');
    sb.writeln('');
    sb.writeln('Join us on Diaspora Nearby: $eventLink');

    await SharePlus.instance.share(
      ShareParams(text: sb.toString(), subject: event.title),
    );
  }

  // Share to WhatsApp directly
  Future<void> shareToWhatsApp(String message) async {
    final success = await WhatsAppUtils.shareText(message);
    if (!success) {
      // Fallback to generic share if WhatsApp not installed
      await SharePlus.instance.share(ShareParams(text: message));
    }
  }
}
