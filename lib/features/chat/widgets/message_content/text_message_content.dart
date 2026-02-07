import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart'; // [NEW]
import 'package:any_link_preview/any_link_preview.dart'; // [NEW]
import 'package:diaspora_nearby/features/chat/models/message.dart';

class TextMessageContent extends StatefulWidget {
  final Message message;
  final bool isOwn;

  const TextMessageContent({
    super.key,
    required this.message,
    required this.isOwn,
  });

  @override
  State<TextMessageContent> createState() => _TextMessageContentState();
}

class _TextMessageContentState extends State<TextMessageContent> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.bodyMedium?.copyWith(
      color: widget.isOwn
          ? theme.colorScheme.onPrimary
          : theme.colorScheme.onSurface,
      height: 1.5,
    );
    final mentionStyle = textStyle?.copyWith(
      fontWeight: FontWeight.bold,
      color: widget.isOwn
          ? theme.colorScheme.onPrimary
          : theme.colorScheme.primary,
    );

    final content = widget.message.richContent ?? widget.message.content;
    final spans = <InlineSpan>[];

    if (widget.message.richContent != null) {
      final regex = RegExp(r'(@\{([^:]+):([^}]+)\})');
      content.splitMapJoin(
        regex,
        onMatch: (Match match) {
          final fullMatch = match.group(0);
          final uid = match.group(2); // Group 2 is UID
          final name = match.group(3); // Group 3 is Name

          final recognizer = TapGestureRecognizer()
            ..onTap = () {
              if (uid != null) {
                context.push('/profile/$uid');
              }
            };
          _recognizers.add(recognizer);

          spans.add(
            TextSpan(
              text: '@$name',
              style: mentionStyle,
              recognizer: recognizer,
            ),
          );
          return '';
        },
        onNonMatch: (String text) {
          // Now check for URLs in the non-mention text
          final urlRegex = RegExp(
            r'((https?:www\.)|(https?:\/\/)|(www\.))[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9]{1,6}(\/[-a-zA-Z0-9()@:%_\+.~#?&\/=]*)?',
          );

          text.splitMapJoin(
            urlRegex,
            onMatch: (Match urlMatch) {
              final url = urlMatch.group(0)!;
              final recognizer = TapGestureRecognizer()
                ..onTap = () async {
                  final uri = Uri.parse(
                    url.startsWith('http') ? url : 'https://$url',
                  );
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                };
              _recognizers.add(recognizer);

              spans.add(
                TextSpan(
                  text: url,
                  style: textStyle?.copyWith(
                    color: widget.isOwn
                        ? Colors.white
                        : theme.colorScheme.primary, // Make links visible
                    decoration: TextDecoration.underline,
                  ),
                  recognizer: recognizer,
                ),
              );
              return '';
            },
            onNonMatch: (String plainText) {
              spans.add(TextSpan(text: plainText, style: textStyle));
              return '';
            },
          );
          return '';
        },
      );
    } else {
      // Check for URLs in standard content too
      final urlRegex = RegExp(
        r'((https?:www\.)|(https?:\/\/)|(www\.))[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9]{1,6}(\/[-a-zA-Z0-9()@:%_\+.~#?&\/=]*)?',
      );

      content.splitMapJoin(
        urlRegex,
        onMatch: (Match urlMatch) {
          final url = urlMatch.group(0)!;
          final recognizer = TapGestureRecognizer()
            ..onTap = () async {
              final uri = Uri.parse(
                url.startsWith('http') ? url : 'https://$url',
              );
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            };
          _recognizers.add(recognizer);

          spans.add(
            TextSpan(
              text: url,
              style: textStyle?.copyWith(
                color: widget.isOwn ? Colors.white : theme.colorScheme.primary,
                decoration: TextDecoration.underline,
              ),
              recognizer: recognizer,
            ),
          );
          return '';
        },
        onNonMatch: (String plainText) {
          spans.add(TextSpan(text: plainText, style: textStyle));
          return '';
        },
      );
    }

    // Extract first URL for preview
    String? firstUrl;
    final urlRegex = RegExp(
      r'((https?:www\.)|(https?:\/\/)|(www\.))[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9]{1,6}(\/[-a-zA-Z0-9()@:%_\+.~#?&\/=]*)?',
    );
    final match = urlRegex.firstMatch(content);
    if (match != null) {
      firstUrl = match.group(0);
      if (firstUrl != null && !firstUrl.startsWith('http')) {
        firstUrl = 'https://$firstUrl';
      }
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 12, right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(text: TextSpan(children: spans)),
          if (firstUrl != null) ...[
            const SizedBox(height: 8),
            AnyLinkPreview(
              link: firstUrl,
              displayDirection: UIDirection.uiDirectionVertical,
              showMultimedia: true,
              bodyMaxLines: 2,
              bodyTextOverflow: TextOverflow.ellipsis,
              titleStyle:
                  theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ) ??
                  const TextStyle(fontWeight: FontWeight.bold),
              bodyStyle:
                  theme.textTheme.bodySmall ?? const TextStyle(fontSize: 12),
              errorWidget: const SizedBox.shrink(), // Hide if preview fails
              cache: const Duration(days: 7),
              backgroundColor: theme.colorScheme.surfaceContainerHighest
                  .withOpacity(0.3),
              borderRadius: 8,
              removeElevation: true,
              boxShadow: const [],
              onTap: () async {
                final uri = Uri.parse(firstUrl!);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}
