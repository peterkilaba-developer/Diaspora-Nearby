import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:go_router/go_router.dart';
import 'package:diaspora_nearby/models/message.dart';

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
      color: widget.isOwn ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
      height: 1.5,
    );
    final mentionStyle = textStyle?.copyWith(
      fontWeight: FontWeight.bold,
      color: widget.isOwn ? theme.colorScheme.onPrimary : theme.colorScheme.primary,
    );

    final content = widget.message.richContent ?? widget.message.content;
    final spans = <InlineSpan>[];
    
    if (widget.message.richContent != null) {
       final regex = RegExp(r'@\{([^:]+):([^}]+)\}');
       content.splitMapJoin(
          regex,
          onMatch: (Match match) {
             final uid = match.group(1);
             final name = match.group(2);
             
             final recognizer = TapGestureRecognizer()
                ..onTap = () {
                   if (uid != null) {
                      context.push('/profile/$uid');
                   }
                };
             _recognizers.add(recognizer);
             
             spans.add(TextSpan(
               text: '@$name',
               style: mentionStyle,
               recognizer: recognizer,
             ));
             return '';
          },
          onNonMatch: (String text) {
             spans.add(TextSpan(text: text, style: textStyle));
             return '';
          },
       );
    } else {
       spans.add(TextSpan(text: content, style: textStyle));
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 12, right: 12),
      child: RichText(
        text: TextSpan(children: spans),
      ),
    );
  }
}
