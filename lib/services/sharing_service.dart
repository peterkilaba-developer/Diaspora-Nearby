import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:diaspora_nearby/models/event_data.dart';
import 'package:diaspora_nearby/models/community_data.dart';

class SharingService {
  SharingService._();
  static final SharingService instance = SharingService._();

  // Basic App Invite
  Future<void> shareApp() async {
    const appLink = 'https://diasporanearby.com/download'; // Placeholder
    const message = 'Discover and Connect with People from your home country nearby: $appLink';
    await Share.share(message);
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
