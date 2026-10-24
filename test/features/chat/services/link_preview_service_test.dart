import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:diaspora_nearby/features/chat/services/link_preview_service.dart';

void main() {
  group('LinkPreviewService', () {
    test('extractYouTubeVideoId supports standard, shorts, live, and youtu.be URLs', () {
      expect(
        LinkPreviewService.extractYouTubeVideoId(
          'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        ),
        'dQw4w9WgXcQ',
      );
      expect(
        LinkPreviewService.extractYouTubeVideoId(
          'https://www.youtube.com/shorts/dQw4w9WgXcQ?feature=share',
        ),
        'dQw4w9WgXcQ',
      );
      expect(
        LinkPreviewService.extractYouTubeVideoId(
          'https://m.youtube.com/shorts/abc123DEF_-',
        ),
        'abc123DEF_-',
      );
      expect(
        LinkPreviewService.extractYouTubeVideoId(
          'https://youtu.be/dQw4w9WgXcQ?si=123',
        ),
        'dQw4w9WgXcQ',
      );
      expect(
        LinkPreviewService.extractYouTubeVideoId(
          'https://www.youtube.com/live/dQw4w9WgXcQ',
        ),
        'dQw4w9WgXcQ',
      );
    });

    test('rejects generic Instagram shell with base64 splash icon', () {
      const igShellHtml = '''
        <!DOCTYPE html>
        <html>
          <head><title>Instagram</title></head>
          <body>
            <img src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAKAAAACg" />
          </body>
        </html>
      ''';

      final parsed = LinkPreviewService.parseHtmlMetadata(
        igShellHtml,
        url: 'https://www.instagram.com/reel/Deu05k4o593/?vrfl=Y3k0MzFreTd1cG8y',
      );

      expect(parsed, isNull);
    });

    test('rejects generic TikTok shell title "TikTok - Make Your Day"', () {
      const ttShellHtml = '''
        <!DOCTYPE html>
        <html>
          <head><title>TikTok - Make Your Day</title></head>
          <body></body>
        </html>
      ''';

      final parsed = LinkPreviewService.parseHtmlMetadata(
        ttShellHtml,
        url: 'https://www.tiktok.com/t/ZTfSTKr7p/',
      );

      expect(parsed, isNull);
    });

    test('parses valid Instagram OpenGraph metadata and unescapes HTML entities', () {
      const igOgHtml = '''
        <!DOCTYPE html>
        <html>
          <head>
            <title>Instagram</title>
            <meta property="og:title" content="ZUCHU (&#064;officialzuchu) &#x2022; Instagram photos and videos" />
            <meta property="og:description" content="8M Followers, 36 Following &amp; 63 Posts" />
            <meta property="og:image" content="https://scontent.cdninstagram.com/v/t51.82787-19/547861360.jpg?a=1&amp;b=2" />
            <meta property="og:site_name" content="Instagram" />
          </head>
          <body></body>
        </html>
      ''';

      final parsed = LinkPreviewService.parseHtmlMetadata(
        igOgHtml,
        url: 'https://www.instagram.com/officialzuchu/',
      );

      expect(parsed, isNotNull);
      expect(
        parsed!.title,
        'ZUCHU (@officialzuchu) • Instagram photos and videos',
      );
      expect(parsed.description, '8M Followers, 36 Following & 63 Posts');
      expect(
        parsed.imageUrl,
        'https://scontent.cdninstagram.com/v/t51.82787-19/547861360.jpg?a=1&b=2',
      );
    });

    test('resolves TikTok short link redirect and extracts rehydration metadata', () async {
      final rehydrationPayload = {
        '__DEFAULT_SCOPE__': {
          'webapp.video-detail': {
            'shareMeta': {
              'title': 'Lopez Family on TikTok',
              'desc': 'Funny family moment #fyp',
            },
            'itemInfo': {
              'itemStruct': {
                'desc': 'Funny family moment #fyp',
                'author': {'nickname': 'Lopez Family'},
                'video': {
                  'cover': 'https://p16-common-sign.tiktokcdn-us.com/cover.jpeg',
                },
              },
            },
          },
        },
      };

      final client = MockClient((request) async {
        if (request.url.toString() == 'https://www.tiktok.com/t/ZTfSwrmbx/') {
          return http.Response(
            '',
            301,
            headers: {
              'location':
                  'https://www.tiktok.com/@lopezfamily13/video/7698509201634528542',
            },
          );
        }
        if (request.url.path.contains('/@lopezfamily13/video/')) {
          return http.Response.bytes(
            utf8.encode('''
              <html>
                <head><title>TikTok - Make Your Day</title></head>
                <body>
                  <script id="__UNIVERSAL_DATA_FOR_REHYDRATION__" type="application/json">${jsonEncode(rehydrationPayload)}</script>
                </body>
              </html>
            '''),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final preview = await LinkPreviewService.getPreview(
        'https://www.tiktok.com/t/ZTfSwrmbx/',
        httpClient: client,
      );

      expect(preview, isNotNull);
      expect(preview!.title, 'Lopez Family on TikTok');
      expect(preview.description, 'Funny family moment #fyp');
      expect(
        preview.imageUrl,
        'https://p16-common-sign.tiktokcdn-us.com/cover.jpeg',
      );
    });

    test('falls back to TikTok author profile avatar when video is classified', () async {
      final classifiedPayload = {
        '__DEFAULT_SCOPE__': {
          'webapp.video-detail': {
            'shareMeta': {
              'title': 'Tallon on TikTok',
              'desc': "Tallon's short video with original sound",
            },
            'itemInfo': {
              'itemStruct': {
                'id': '7698931217554525453',
                'desc': '',
                'video': <String, dynamic>{},
                'isContentClassified': true,
              },
            },
          },
        },
      };

      final client = MockClient((request) async {
        if (request.url.toString() == 'https://www.tiktok.com/t/ZTfSTKr7p/') {
          return http.Response(
            '',
            301,
            headers: {
              'location':
                  'https://www.tiktok.com/@_whooistallon/video/7698931217554525453',
            },
          );
        }
        if (request.url.path == '/@_whooistallon/video/7698931217554525453') {
          final ua = request.headers['User-Agent'] ?? '';
          if (ua.contains('facebookexternalhit')) {
            return http.Response(
              '''
              <html><head>
                <meta property="og:title" content="Visit TikTok to discover videos!" />
                <meta property="og:image" content="https://sf16-sg.tiktokcdn.com/obj/eden-sg/kvyweh7vhohpqbog/cover-fallback.png" />
              </head></html>
              ''',
              200,
            );
          }
          return http.Response.bytes(
            utf8.encode('''
              <html>
                <head><title>TikTok - Make Your Day</title></head>
                <body>
                  <script id="__UNIVERSAL_DATA_FOR_REHYDRATION__" type="application/json">${jsonEncode(classifiedPayload)}</script>
                </body>
              </html>
            '''),
            200,
          );
        }
        if (request.url.path == '/@_whooistallon') {
          return http.Response(
            '''
            <html><head>
              <meta property="og:title" content="Tallon on TikTok" />
              <meta property="og:image" content="https://p19-common-sign.tiktokcdn-us.com/avatar.jpeg" />
            </head></html>
            ''',
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final preview = await LinkPreviewService.getPreview(
        'https://www.tiktok.com/t/ZTfSTKr7p/',
        httpClient: client,
      );

      expect(preview, isNotNull);
      expect(preview!.title, 'Tallon on TikTok');
      expect(preview.description, "Tallon's short video with original sound");
      expect(
        preview.imageUrl,
        'https://p19-common-sign.tiktokcdn-us.com/avatar.jpeg',
      );
    });

    test('returns branded Instagram Reel fallback card when post is age-restricted or private', () async {
      final client = MockClient((request) async {
        return http.Response(
          '''
          <!DOCTYPE html>
          <html>
            <head><title>Instagram</title></head>
            <body>
              <img src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAKAAAACg" />
            </body>
          </html>
          ''',
          200,
        );
      });

      final preview = await LinkPreviewService.getPreview(
        'https://www.instagram.com/reel/Deu05k4o593/?vrfl=Y3k0MzFreTd1cG8y',
        httpClient: client,
      );

      expect(preview, isNotNull);
      expect(preview!.title, 'Instagram Reel');
      expect(preview.description, 'Tap to watch this Reel on Instagram');
      expect(preview.siteName, 'Instagram');
      expect(preview.imageUrl, isNull);
      expect(preview.isFallbackCard, isTrue);
    });
  });
}
