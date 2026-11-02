import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:diaspora_nearby/features/chat/models/message.dart';
import 'package:diaspora_nearby/features/chat/widgets/message_content/top_level_text_content.dart';
import 'package:diaspora_nearby/features/sharing/services/share_receiver_service.dart';

void main() {
  group('ShareReceiverService.mergeCompanionTextIntoMedia', () {
    test(
      'attaches Android nativeExtraText (link + text) to image message field',
      () {
        final rawFiles = [
          SharedMediaFile(
            path: '/data/user/0/cache/invite_card.png',
            type: SharedMediaType.image,
            mimeType: 'image/png',
          ),
        ];

        final merged = ShareReceiverService.mergeCompanionTextIntoMedia(
          rawFiles,
          nativeExtraText:
              'Umealikwa Kujiunga! https://smartkijumbe.com/join/mh1',
        );

        expect(merged, hasLength(1));
        expect(merged.first.type, SharedMediaType.image);
        expect(merged.first.path, '/data/user/0/cache/invite_card.png');
        expect(
          merged.first.message,
          'Umealikwa Kujiunga! https://smartkijumbe.com/join/mh1',
        );
      },
    );

    test(
      'merges separate text/url items into primary image item as caption',
      () {
        final rawFiles = [
          SharedMediaFile(
            path: '/tmp/card.jpg',
            type: SharedMediaType.image,
            message: 'Join our group',
          ),
          SharedMediaFile(
            path: 'https://smartkijumbe.com/join/123',
            type: SharedMediaType.url,
          ),
        ];

        final merged = ShareReceiverService.mergeCompanionTextIntoMedia(
          rawFiles,
        );

        expect(merged, hasLength(1));
        expect(merged.first.type, SharedMediaType.image);
        expect(
          merged.first.message,
          'Join our group\nhttps://smartkijumbe.com/join/123',
        );
      },
    );

    test('leaves text-only shares untouched when no media file is present', () {
      final rawFiles = [
        SharedMediaFile(
          path: 'https://example.com/article',
          type: SharedMediaType.text,
        ),
      ];

      final merged = ShareReceiverService.mergeCompanionTextIntoMedia(rawFiles);

      expect(merged, hasLength(1));
      expect(merged.first.type, SharedMediaType.text);
      expect(merged.first.path, 'https://example.com/article');
    });
  });

  group('ShareReceiverService.extractSharedFiles', () {
    test('never throws when extra is null and uses fallback or empty list', () {
      expect(ShareReceiverService.extractSharedFiles(null), isEmpty);

      final fallback = [
        SharedMediaFile(
          path: '/tmp/shared.png',
          type: SharedMediaType.image,
          message: 'https://example.com',
        ),
      ];

      final extracted = ShareReceiverService.extractSharedFiles(
        null,
        fallback: fallback,
      );
      expect(extracted, hasLength(1));
      expect(extracted.first.path, '/tmp/shared.png');
      expect(extracted.first.message, 'https://example.com');
    });

    test('parses JSON-decoded Map list safely', () {
      final rawMaps = [
        {
          'path': '/tmp/shared.png',
          'type': 'image',
          'mimeType': 'image/png',
          'message': 'https://example.com/invite',
        },
      ];

      final extracted = ShareReceiverService.extractSharedFiles(rawMaps);
      expect(extracted, hasLength(1));
      expect(extracted.first.type, SharedMediaType.image);
      expect(extracted.first.message, 'https://example.com/invite');
    });
  });

  group('TopLevelTextContent clickable URL rendering', () {
    testWidgets('renders underlined tappable TextSpan for URLs in caption', (
      tester,
    ) async {
      const msg = Message(
        id: 'm1',
        chatId: 'c1',
        senderId: 'u1',
        senderName: 'Tester',
        content: 'Join here: https://smartkijumbe.com/invite/123',
        type: 'image',
        imageUrl: 'https://example.com/img.png',
        timestamp: 1000,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TopLevelTextContent(message: msg, isOwn: true),
          ),
        ),
      );

      final richText = tester.widget<RichText>(find.byType(RichText));
      final rootSpan = richText.text as TextSpan;
      expect(rootSpan.children, isNotNull);

      final urlSpan = rootSpan.children!.whereType<TextSpan>().firstWhere(
        (s) => s.text == 'https://smartkijumbe.com/invite/123',
      );
      expect(urlSpan.style?.decoration, TextDecoration.underline);
      expect(urlSpan.recognizer, isA<TapGestureRecognizer>());
    });
  });
}
