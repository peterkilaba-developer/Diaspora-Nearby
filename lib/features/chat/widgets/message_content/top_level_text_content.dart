import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:diaspora_nearby/features/chat/models/message.dart';

/// Helper widget to display text content within media messages
/// Supports clickable URLs in media captions (e.g. shared images/videos with links).
class TopLevelTextContent extends StatefulWidget {
  final Message message;
  final bool isOwn;

  const TopLevelTextContent({
    super.key,
    required this.message,
    required this.isOwn,
  });

  @override
  State<TopLevelTextContent> createState() => _TopLevelTextContentState();
}

class _TopLevelTextContentState extends State<TopLevelTextContent> {
  static final RegExp _urlRegex = RegExp(
    r'((https?:www\.)|(https?:\/\/)|(www\.))[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9]{1,24}(\/[-a-zA-Z0-9()@:%_\+.~#?&\/=]*)?',
  );

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
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();

    final theme = Theme.of(context);
    final textStyle = theme.textTheme.bodyMedium?.copyWith(
      color: widget.isOwn
          ? theme.colorScheme.onPrimary
          : theme.colorScheme.onSurface,
      height: 1.4,
    );

    final content = widget.message.content;
    final spans = <InlineSpan>[];

    content.splitMapJoin(
      _urlRegex,
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

    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 12, right: 12, bottom: 6),
      child: RichText(
        textAlign: TextAlign.left,
        text: TextSpan(children: spans),
      ),
    );
  }
}
