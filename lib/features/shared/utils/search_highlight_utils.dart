import 'package:flutter/material.dart';

class SearchHighlightUtils {
  static Widget highlightText(String text, String? query, TextStyle? baseStyle, BuildContext context) {
    if (query == null || query.isEmpty) {
      return Text(text, style: baseStyle, maxLines: 1, overflow: TextOverflow.ellipsis);
    }

    final theme = Theme.of(context);
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();

    if (!lowerText.contains(lowerQuery)) {
      return Text(text, style: baseStyle, maxLines: 1, overflow: TextOverflow.ellipsis);
    }

    final List<TextSpan> spans = [];
    int start = 0;
    int indexOfMatch;

    while ((indexOfMatch = lowerText.indexOf(lowerQuery, start)) != -1) {
      if (indexOfMatch > start) {
        spans.add(TextSpan(text: text.substring(start, indexOfMatch)));
      }
      spans.add(TextSpan(
        text: text.substring(indexOfMatch, indexOfMatch + lowerQuery.length),
        style: TextStyle(
          backgroundColor: theme.colorScheme.primaryContainer.withOpacity(0.7),
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.bold,
        ),
      ));
      start = indexOfMatch + lowerQuery.length;
    }

    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }

    return RichText(
      text: TextSpan(
        style: baseStyle ?? theme.textTheme.bodyMedium,
        children: spans,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
