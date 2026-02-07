import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:diaspora_nearby/features/chat/models/message.dart';
import 'package:diaspora_nearby/config/env.dart';

class LocationMessageContent extends StatelessWidget {
  final Message message;
  final bool isOwn;

  const LocationMessageContent({
    super.key,
    required this.message,
    required this.isOwn,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lat = message.location?.lat ?? 0.0;
    final lng = message.location?.lng ?? 0.0;

    final apiKey = Env.googleMapsApiKey;

    // Construct Static Map URL
    final mapUrl =
        'https://maps.googleapis.com/maps/api/staticmap?'
        'center=$lat,$lng&'
        'zoom=15&'
        'size=600x300&'
        'maptype=roadmap&'
        'markers=color:red%7C$lat,$lng&'
        'key=$apiKey';

    return GestureDetector(
      onTap: () async {
        final url = Uri.parse(
          'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
        );
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        } else {
          debugPrint('Could not launch Maps');
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            height: 150,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  mapUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.map, size: 40, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
          if (message.content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(
                top: 6,
                left: 12,
                right: 12,
                bottom: 6,
              ),
              child: Text(
                message.content,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isOwn
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
