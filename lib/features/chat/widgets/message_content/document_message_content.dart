import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:diaspora_nearby/features/chat/models/message.dart';
import 'package:diaspora_nearby/features/chat/widgets/document_viewer_screen.dart';

class DocumentMessageContent extends StatelessWidget {
  final Message message;
  final bool isOwn;

  const DocumentMessageContent({
    super.key,
    required this.message,
    required this.isOwn,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fileName = message.documentName ?? 'Document';
    final isSending = message.status == 'sending';

    return InkWell(
      onTap: isSending
          ? null
          : () async {
              final docUrl = message.documentUrl ?? message.imageUrl;
              if (docUrl != null) {
                final url = docUrl;
                final isPdf =
                    (message.documentName?.toLowerCase().endsWith('.pdf') ??
                        false) ||
                    url.toLowerCase().contains('.pdf');

                if (isPdf) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DocumentViewerScreen(
                        url: url,
                        fileName: message.documentName ?? 'Document',
                      ),
                      fullscreenDialog: true,
                    ),
                  );
                } else {
                  // Non-PDF files open externally
                  final uri = Uri.parse(url);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } else {
                    debugPrint('Could not launch $url');
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Could not open document'),
                        ),
                      );
                    }
                  }
                }
              }
            },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: isSending
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.orange,
                      ),
                    )
                  : const Icon(
                      LucideIcons.fileText,
                      color: Colors.orange,
                      size: 24,
                    ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isOwn
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isSending ? 'Uploading...' : 'Tap to open',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isOwn
                          ? theme.colorScheme.onPrimary.withValues(alpha: 0.7)
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
