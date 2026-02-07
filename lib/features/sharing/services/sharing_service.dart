import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:diaspora_nearby/features/events/models/event_data.dart';

class SharingService {
  SharingService._();
  static final SharingService instance = SharingService._();

  // Basic App Invite
  Future<void> shareApp() async {
    const appLink = 'https://diasporanearby.com/download';
    const message =
        'For my family and Friends at home and abroad. Join and connect with me in this platform.: $appLink';

    try {
      // Load logo from assets
      final byteData = await rootBundle.load('assets/icons/logo-original.png');
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/logo.png');
      await file.writeAsBytes(
        byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        ),
      );

      // Share image + text
      await Share.shareXFiles([XFile(file.path)], text: message);
    } catch (e) {
      // Fallback to text only if image fails
      await Share.share(message);
    }
  }

  // Share Event
  Future<void> shareEvent(Event event) async {
    // In a real app, this would be a dynamic link like https://diasporanearby.com/events/${event.id}
    final eventLink = 'https://diasporanearby.com/events/${event.id}';

    final StringBuffer sb = StringBuffer();
    sb.writeln('Check out this event: ${event.title}');
    sb.writeln('Date: ${event.startDate}');
    sb.writeln('Location: ${event.location}');
    sb.writeln('');
    sb.writeln('Join us on Diaspora Nearby: $eventLink');

    await Share.share(sb.toString(), subject: event.title);
  }

  // Share to WhatsApp directly
  Future<void> shareToWhatsApp(String message) async {
    final encodedMessage = Uri.encodeComponent(message);
    final url = Uri.parse('whatsapp://send?text=$encodedMessage');

    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      // Fallback to generic share if WhatsApp not installed
      await Share.share(message);
    }
  }
}
