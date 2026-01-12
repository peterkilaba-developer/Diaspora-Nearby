import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:diaspora_nearby/models/message.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'top_level_text_content.dart';

class ImageMessageContent extends StatelessWidget {
  final Message message;
  final bool isOwn;

  const ImageMessageContent({
    super.key,
    required this.message,
    required this.isOwn,
  });

  void _showFullScreenImage(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.95),
      builder: (context) => Stack(
        children: [
          Positioned(
            top: 40,
            right: 20,
            child: Material(
              color: Colors.transparent,
              child: IconButton(
                icon: const Icon(LucideIcons.x, color: Colors.white, size: 30),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          Center(
            child: InteractiveViewer(
              panEnabled: true,
              boundaryMargin: const EdgeInsets.all(20),
              minScale: 0.5,
              maxScale: 4.0,
              child: (kIsWeb || imageUrl.startsWith('http') || imageUrl.startsWith('blob:'))
                ? Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const Center(child: CircularProgressIndicator(color: Colors.white));
                    },
                    errorBuilder: (context, error, stackTrace) {
                      if (kIsWeb) {
                        debugPrint('❌ Message Image failed to load on Web: $error');
                      }
                      return _buildErrorWidget();
                    },
                  )
                : Image.file(
                    File(imageUrl.replaceFirst('file://', '')),
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return _buildErrorWidget();
                    },
                  ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imageUrl = message.imageUrl;
    final isSending = message.status == 'sending';
    final isLocalFile = imageUrl?.startsWith('file://') ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (imageUrl != null)
          GestureDetector(
            onTap: isSending ? null : () => _showFullScreenImage(context, imageUrl),
            child: Stack(
              children: [
                Hero(
                  tag: imageUrl,
                  child: (kIsWeb || imageUrl.startsWith('http') || imageUrl.startsWith('blob:'))
                      ? Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              width: 200,
                              height: 150,
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: Center(
                                child: CircularProgressIndicator(
                                  value: loadingProgress.expectedTotalBytes != null
                                      ? loadingProgress.cumulativeBytesLoaded /
                                          loadingProgress.expectedTotalBytes!
                                      : null,
                                ),
                              ),
                            );
                          },
                          errorBuilder: (_, __, ___) => Container(
                            width: 200,
                            height: 150,
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Icon(LucideIcons.imageOff),
                          ),
                        )
                      : Image.file(
                          File(imageUrl.replaceFirst('file://', '')),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder: (_, __, ___) => Container(
                            width: 200,
                            height: 150,
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Icon(LucideIcons.imageOff),
                          ),
                        ),
                ),
                if (isSending)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(0.4),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Uploading...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (message.content.isNotEmpty)
           TopLevelTextContent(message: message, isOwn: isOwn),
      ],
    );
  }

  Widget _buildErrorWidget() {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(LucideIcons.imageOff, color: Colors.white, size: 48),
        SizedBox(height: 16),
        Text(
          'Could not load image',
          style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              decoration: TextDecoration.none),
        ),
      ],
    );
  }
}
