import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' show Document;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Cleaned and validated metadata for a link preview card.
class LinkPreviewData {
  final String url;
  final String title;
  final String? description;
  final String? imageUrl;
  final String? siteName;
  final bool isFallbackCard;

  const LinkPreviewData({
    required this.url,
    required this.title,
    this.description,
    this.imageUrl,
    this.siteName,
    this.isFallbackCard = false,
  });

  bool get hasValidContent => title.trim().isNotEmpty;

  Map<String, dynamic> toJson({required DateTime expiresAt}) => {
    'url': url,
    'title': title,
    'description': description,
    'imageUrl': imageUrl,
    'siteName': siteName,
    'isFallbackCard': isFallbackCard,
    'expiresAt': expiresAt.millisecondsSinceEpoch,
  };

  static LinkPreviewData? fromCacheJson(Map<String, dynamic> json) {
    final expiresAtMs = json['expiresAt'] as int?;
    if (expiresAtMs == null ||
        DateTime.fromMillisecondsSinceEpoch(
          expiresAtMs,
        ).isBefore(DateTime.now())) {
      return null;
    }
    final title = (json['title'] as String?)?.trim() ?? '';
    final url = (json['url'] as String?)?.trim() ?? '';
    if (title.isEmpty || url.isEmpty) return null;
    return LinkPreviewData(
      url: url,
      title: title,
      description: json['description'] as String?,
      imageUrl: json['imageUrl'] as String?,
      siteName: json['siteName'] as String?,
      isFallbackCard: json['isFallbackCard'] == true,
    );
  }
}

/// Service that resolves rich link preview metadata across social platforms
/// (TikTok, Instagram, Facebook, YouTube/Shorts, X/Twitter, and general web),
/// avoiding generic CSR shells, broken placeholder GIFs, and base64 splash icons.
class LinkPreviewService {
  static const String _cachePrefix = 'dn_link_preview_v3:';
  static const Duration _defaultCacheTtl = Duration(days: 7);
  static const Duration _requestTimeout = Duration(seconds: 8);

  static const String _crawlerUserAgent =
      'facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)';
  static const String _browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  static final Map<String, Future<LinkPreviewData?>> _inFlight = {};
  static final Map<String, LinkPreviewData> _memoryCache = {};

  /// Synchronous lookup of cached [LinkPreviewData] for [rawUrl] so chat
  /// bubbles render link previews on frame 0 without layout shift.
  static LinkPreviewData? getCachedPreviewSync(String rawUrl) {
    final normalizedUrl = _normalizeUrl(rawUrl);
    if (normalizedUrl == null) return null;
    return _memoryCache[normalizedUrl];
  }

  static final Set<String> _genericTitles = {
    'instagram',
    'login • instagram',
    'tiktok',
    'tiktok - make your day',
    'visit tiktok to discover videos!',
    'facebook',
    'log into facebook',
    'log in or sign up to view',
    'x',
    'x (formerly twitter)',
    'twitter',
    'youtube',
    ' - youtube',
  };

  /// Fetches validated [LinkPreviewData] for [rawUrl], or `null` if no
  /// meaningful preview metadata is available.
  static Future<LinkPreviewData?> getPreview(
    String rawUrl, {
    http.Client? httpClient,
    Duration cacheTtl = _defaultCacheTtl,
  }) async {
    final normalizedUrl = _normalizeUrl(rawUrl);
    if (normalizedUrl == null) return null;

    if (httpClient == null) {
      final memCached = _memoryCache[normalizedUrl];
      if (memCached != null) return memCached;

      final diskCached = await _readFromCache(normalizedUrl);
      if (diskCached != null) {
        _memoryCache[normalizedUrl] = diskCached;
        return diskCached;
      }

      final existingFuture = _inFlight[normalizedUrl];
      if (existingFuture != null) return existingFuture;
    }

    final future = _resolvePreview(
      normalizedUrl,
      httpClient: httpClient,
      cacheTtl: cacheTtl,
    );

    if (httpClient == null) {
      _inFlight[normalizedUrl] = future;
    }

    try {
      return await future;
    } finally {
      if (httpClient == null) {
        _inFlight.remove(normalizedUrl);
      }
    }
  }

  static Future<LinkPreviewData?> _resolvePreview(
    String url, {
    http.Client? httpClient,
    required Duration cacheTtl,
  }) async {
    final client = httpClient ?? http.Client();
    final shouldCloseClient = httpClient == null;

    try {
      LinkPreviewData? result;

      final youtubeId = extractYouTubeVideoId(url);
      if (youtubeId != null) {
        result = await _fetchYouTubePreview(client, url, youtubeId);
      }

      if (result == null && _isTikTokUrl(url)) {
        result = await _fetchTikTokPreview(client, url);
      }

      if (result == null && _isTwitterOrXUrl(url)) {
        result = await _fetchTwitterPreview(client, url);
      }

      result ??= await _fetchStandardOpenGraphPreview(client, url);
      result ??= buildSocialFallback(url);

      if (result != null && result.hasValidContent) {
        if (httpClient == null) {
          _memoryCache[url] = result;
          final effectiveTtl = result.isFallbackCard
              ? const Duration(hours: 6)
              : cacheTtl;
          unawaited(_writeToCache(url, result, effectiveTtl));
        }
        return result;
      }
      return null;
    } catch (e) {
      debugPrint('LinkPreviewService: failed to resolve $url ($e)');
      return buildSocialFallback(url);
    } finally {
      if (shouldCloseClient) {
        client.close();
      }
    }
  }

  @visibleForTesting
  static LinkPreviewData? buildSocialFallback(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();

    if (host == 'instagram.com' || host.endsWith('.instagram.com')) {
      String title = 'Instagram';
      String desc = 'Tap to open in Instagram';
      if (path.contains('/reel/') || path.contains('/reels/')) {
        title = 'Instagram Reel';
        desc = 'Tap to watch this Reel on Instagram';
      } else if (path.contains('/p/') || path.contains('/tv/')) {
        title = 'Instagram Post';
        desc = 'Tap to view this post on Instagram';
      } else if (path.contains('/stories/')) {
        title = 'Instagram Story';
        desc = 'Tap to view this story on Instagram';
      } else if (uri.pathSegments.isNotEmpty &&
          uri.pathSegments.first.isNotEmpty) {
        final handle = uri.pathSegments.first;
        title = '@$handle on Instagram';
      }
      return LinkPreviewData(
        url: url,
        title: title,
        description: desc,
        siteName: 'Instagram',
        isFallbackCard: true,
      );
    }

    if (host == 'tiktok.com' || host.endsWith('.tiktok.com')) {
      return LinkPreviewData(
        url: url,
        title: 'TikTok Video',
        description: 'Tap to watch on TikTok',
        siteName: 'TikTok',
        isFallbackCard: true,
      );
    }

    if (host == 'facebook.com' ||
        host.endsWith('.facebook.com') ||
        host == 'fb.watch') {
      final isVideo =
          host == 'fb.watch' ||
          path.contains('/reel/') ||
          path.contains('/share/r/') ||
          path.contains('/share/v/') ||
          path.contains('/watch');
      return LinkPreviewData(
        url: url,
        title: isVideo ? 'Facebook Reel' : 'Facebook Post',
        description: isVideo
            ? 'Tap to watch on Facebook'
            : 'Tap to view on Facebook',
        siteName: 'Facebook',
        isFallbackCard: true,
      );
    }

    if (host == 'x.com' ||
        host.endsWith('.x.com') ||
        host == 'twitter.com' ||
        host.endsWith('.twitter.com')) {
      return LinkPreviewData(
        url: url,
        title: 'Post on X',
        description: 'Tap to view post on X',
        siteName: 'X',
        isFallbackCard: true,
      );
    }

    return null;
  }

  @visibleForTesting
  static String? extractYouTubeVideoId(String url) {
    final regExp = RegExp(
      r'(?:https?:\/\/)?(?:www\.|m\.)?(?:youtube\.com\/(?:watch\?(?:.*&)?v=|embed\/|v\/|shorts\/|live\/)|youtu\.be\/)([a-zA-Z0-9_-]{11})',
      caseSensitive: false,
    );
    return regExp.firstMatch(url)?.group(1);
  }

  static bool _isTikTokUrl(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    return host == 'tiktok.com' || host.endsWith('.tiktok.com');
  }

  static bool _isTwitterOrXUrl(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    return host == 'x.com' ||
        host.endsWith('.x.com') ||
        host == 'twitter.com' ||
        host.endsWith('.twitter.com');
  }

  static Future<LinkPreviewData?> _fetchYouTubePreview(
    http.Client client,
    String originalUrl,
    String videoId,
  ) async {
    try {
      final oembedUri = Uri.parse(
        'https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=$videoId&format=json',
      );
      final response = await client
          .get(oembedUri, headers: {'User-Agent': _crawlerUserAgent})
          .timeout(_requestTimeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data is Map) {
          final title = _cleanText(data['title']?.toString());
          final author = _cleanText(data['author_name']?.toString());
          final thumb = _cleanImageUrl(
            data['thumbnail_url']?.toString(),
            baseUrl: originalUrl,
          );
          if (title != null && !_isGenericTitle(title)) {
            return LinkPreviewData(
              url: originalUrl,
              title: title,
              description: author,
              imageUrl: thumb,
              siteName: 'YouTube',
            );
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<LinkPreviewData?> _fetchTikTokPreview(
    http.Client client,
    String originalUrl,
  ) async {
    try {
      final browserResult = await _fetchWithRedirects(
        client,
        originalUrl,
        userAgent: _browserUserAgent,
      );

      final resolvedUrl = browserResult.finalUrl;
      String? title;
      String? description;
      String? imageUrl;

      if (browserResult.response.statusCode == 200) {
        final html = utf8.decode(
          browserResult.response.bodyBytes,
          allowMalformed: true,
        );
        final rehydrationMatch = RegExp(
          r'<script[^>]+id="__UNIVERSAL_DATA_FOR_REHYDRATION__"[^>]*>([^<]+)<\/script>',
          caseSensitive: false,
        ).firstMatch(html);

        if (rehydrationMatch != null) {
          try {
            final json = jsonDecode(rehydrationMatch.group(1)!);
            final defaultScope = json['__DEFAULT_SCOPE__'];
            final videoDetail = defaultScope is Map
                ? defaultScope['webapp.video-detail']
                : null;
            if (videoDetail is Map) {
              final shareMeta = videoDetail['shareMeta'];
              if (shareMeta is Map) {
                title = _cleanText(shareMeta['title']?.toString());
                description = _cleanText(shareMeta['desc']?.toString());
              }
              final itemStruct = videoDetail['itemInfo'] is Map
                  ? videoDetail['itemInfo']['itemStruct']
                  : null;
              if (itemStruct is Map) {
                final itemDesc = _cleanText(itemStruct['desc']?.toString());
                if (itemDesc != null && itemDesc.isNotEmpty) {
                  description = itemDesc;
                }
                final author = itemStruct['author'];
                if (author is Map) {
                  final nickname = _cleanText(author['nickname']?.toString());
                  if ((title == null || _isGenericTitle(title)) &&
                      nickname != null) {
                    title = '$nickname on TikTok';
                  }
                }
                final video = itemStruct['video'];
                if (video is Map) {
                  final rawCover =
                      (video['cover'] ??
                              video['originCover'] ??
                              video['dynamicCover'])
                          ?.toString();
                  imageUrl = _cleanImageUrl(rawCover, baseUrl: resolvedUrl);
                }
                if (imageUrl == null && author is Map) {
                  final rawAvatar =
                      (author['avatarLarger'] ?? author['avatarMedium'])
                          ?.toString();
                  imageUrl = _cleanImageUrl(rawAvatar, baseUrl: resolvedUrl);
                }
              }
            }
          } catch (_) {}
        }
      }

      if (imageUrl == null || title == null || _isGenericTitle(title)) {
        final crawlerResult = await _fetchWithRedirects(
          client,
          resolvedUrl,
          userAgent: _crawlerUserAgent,
        );
        if (crawlerResult.response.statusCode == 200) {
          final parsed = parseHtmlMetadata(
            utf8.decode(crawlerResult.response.bodyBytes, allowMalformed: true),
            url: crawlerResult.finalUrl,
          );
          if (parsed != null) {
            if (title == null || _isGenericTitle(title)) {
              title = parsed.title;
            }
            description ??= parsed.description;
            if (parsed.imageUrl != null &&
                !_isTikTokGenericFallbackCover(parsed.imageUrl!)) {
              imageUrl ??= parsed.imageUrl;
            }
          }
        }
      }

      if (imageUrl == null) {
        final authorMatch = RegExp(
          r'tiktok\.com\/(@[A-Za-z0-9_.-]+)',
        ).firstMatch(resolvedUrl);
        if (authorMatch != null) {
          final authorHandle = authorMatch.group(1)!;
          final profileUrl = 'https://www.tiktok.com/$authorHandle';
          final profileRes = await _fetchWithRedirects(
            client,
            profileUrl,
            userAgent: _crawlerUserAgent,
          );
          if (profileRes.response.statusCode == 200) {
            final profileMeta = parseHtmlMetadata(
              utf8.decode(profileRes.response.bodyBytes, allowMalformed: true),
              url: profileUrl,
            );
            if (profileMeta?.imageUrl != null &&
                !_isTikTokGenericFallbackCover(profileMeta!.imageUrl!)) {
              imageUrl = profileMeta.imageUrl;
            }
            if ((title == null || _isGenericTitle(title)) &&
                profileMeta?.title != null) {
              title = profileMeta!.title;
            }
          }
        }
      }

      if (title != null && !_isGenericTitle(title)) {
        return LinkPreviewData(
          url: originalUrl,
          title: title,
          description: description,
          imageUrl: imageUrl,
          siteName: 'TikTok',
        );
      }
    } catch (_) {}
    return null;
  }

  static Future<LinkPreviewData?> _fetchTwitterPreview(
    http.Client client,
    String originalUrl,
  ) async {
    try {
      final statusMatch = RegExp(
        r'(?:x\.com|twitter\.com)\/([A-Za-z0-9_]+)\/status\/(\d+)',
        caseSensitive: false,
      ).firstMatch(originalUrl);

      if (statusMatch != null) {
        final user = statusMatch.group(1)!;
        final statusId = statusMatch.group(2)!;
        final apiUri = Uri.parse(
          'https://api.fxtwitter.com/$user/status/$statusId',
        );
        final apiRes = await client
            .get(apiUri, headers: {'User-Agent': _crawlerUserAgent})
            .timeout(_requestTimeout);
        if (apiRes.statusCode == 200) {
          final json = jsonDecode(utf8.decode(apiRes.bodyBytes));
          final tweet = json is Map ? json['tweet'] : null;
          if (tweet is Map) {
            final author = tweet['author'];
            final authorName = author is Map
                ? _cleanText(author['name']?.toString())
                : null;
            final screenName = author is Map
                ? _cleanText(author['screen_name']?.toString())
                : user;
            final text = _cleanText(tweet['text']?.toString());
            String? mediaUrl;
            final media = tweet['media'];
            if (media is Map) {
              final all = media['all'];
              if (all is List && all.isNotEmpty && all.first is Map) {
                mediaUrl = _cleanImageUrl(
                  (all.first['thumbnail_url'] ?? all.first['url'])?.toString(),
                  baseUrl: originalUrl,
                );
              }
            }
            mediaUrl ??= author is Map
                ? _cleanImageUrl(
                    author['avatar_url']?.toString(),
                    baseUrl: originalUrl,
                  )
                : null;

            final title = authorName != null
                ? '$authorName (@$screenName) on X'
                : '@$screenName on X';
            return LinkPreviewData(
              url: originalUrl,
              title: title,
              description: text,
              imageUrl: mediaUrl,
              siteName: 'X',
            );
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<LinkPreviewData?> _fetchStandardOpenGraphPreview(
    http.Client client,
    String originalUrl,
  ) async {
    final crawlerResult = await _fetchWithRedirects(
      client,
      originalUrl,
      userAgent: _crawlerUserAgent,
    );

    final contentType =
        crawlerResult.response.headers['content-type']?.toLowerCase() ?? '';
    if (contentType.startsWith('image/')) {
      return LinkPreviewData(
        url: originalUrl,
        title: Uri.parse(originalUrl).host,
        imageUrl: originalUrl,
      );
    }

    if (crawlerResult.response.statusCode == 200) {
      final html = utf8.decode(
        crawlerResult.response.bodyBytes,
        allowMalformed: true,
      );
      final parsed = parseHtmlMetadata(
        html,
        url: crawlerResult.finalUrl,
        originalUrl: originalUrl,
      );
      if (parsed != null && parsed.hasValidContent) {
        return parsed;
      }
    }

    final browserResult = await _fetchWithRedirects(
      client,
      originalUrl,
      userAgent: _browserUserAgent,
    );
    if (browserResult.response.statusCode == 200) {
      final html = utf8.decode(
        browserResult.response.bodyBytes,
        allowMalformed: true,
      );
      final parsed = parseHtmlMetadata(
        html,
        url: browserResult.finalUrl,
        originalUrl: originalUrl,
      );
      if (parsed != null && parsed.hasValidContent) {
        return parsed;
      }
    }

    return null;
  }

  @visibleForTesting
  static LinkPreviewData? parseHtmlMetadata(
    String html, {
    required String url,
    String? originalUrl,
  }) {
    Document document;
    try {
      document = html_parser.parse(html);
    } catch (_) {
      return null;
    }

    final ogTitle = _cleanText(
      _getMeta(document, 'property', 'og:title') ??
          _getMeta(document, 'name', 'og:title'),
    );
    final twitterTitle = _cleanText(
      _getMeta(document, 'name', 'twitter:title') ??
          _getMeta(document, 'property', 'twitter:title'),
    );
    final docTitle = _cleanText(document.head?.querySelector('title')?.text);

    final ogDesc = _cleanText(
      _getMeta(document, 'property', 'og:description') ??
          _getMeta(document, 'name', 'og:description'),
    );
    final twitterDesc = _cleanText(
      _getMeta(document, 'name', 'twitter:description') ??
          _getMeta(document, 'property', 'twitter:description'),
    );
    final metaDesc = _cleanText(
      _getMeta(document, 'name', 'description') ??
          _getMeta(document, 'property', 'description'),
    );

    final ogImage = _cleanImageUrl(
      _getMeta(document, 'property', 'og:image') ??
          _getMeta(document, 'name', 'og:image') ??
          _getMeta(document, 'property', 'og:image:url'),
      baseUrl: url,
    );
    final twitterImage = _cleanImageUrl(
      _getMeta(document, 'name', 'twitter:image') ??
          _getMeta(document, 'property', 'twitter:image') ??
          _getMeta(document, 'name', 'twitter:image:src'),
      baseUrl: url,
    );

    final siteName = _cleanText(
      _getMeta(document, 'property', 'og:site_name') ??
          _getMeta(document, 'name', 'application-name'),
    );

    String? title;
    for (final candidate in [ogTitle, twitterTitle, docTitle]) {
      if (candidate != null && !_isGenericTitle(candidate, url: url)) {
        title = candidate;
        break;
      }
    }

    String? description;
    for (final candidate in [ogDesc, twitterDesc, metaDesc]) {
      if (candidate != null &&
          candidate.isNotEmpty &&
          candidate.toLowerCase() != url.toLowerCase() &&
          candidate != title) {
        description = candidate;
        break;
      }
    }

    final imageUrl = ogImage ?? twitterImage;

    if (title == null && description != null) {
      title = siteName ?? _formatHostName(url);
    }

    if (title == null || title.isEmpty) {
      return null;
    }

    return LinkPreviewData(
      url: originalUrl ?? url,
      title: title,
      description: description,
      imageUrl: imageUrl,
      siteName: siteName,
    );
  }

  static String? _getMeta(
    Document document,
    String attrName,
    String attrValue,
  ) {
    final elements = document.getElementsByTagName('meta');
    final target = attrValue.toLowerCase();
    for (final el in elements) {
      final val = el.attributes[attrName]?.toLowerCase();
      if (val == target) {
        final content = el.attributes['content'];
        if (content != null && content.trim().isNotEmpty) {
          return content;
        }
      }
    }
    return null;
  }

  static Future<_RedirectFetchResult> _fetchWithRedirects(
    http.Client client,
    String initialUrl, {
    required String userAgent,
    int maxRedirects = 7,
  }) async {
    var currentUri = Uri.parse(initialUrl);
    final headers = <String, String>{
      'User-Agent': userAgent,
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
    };

    for (var i = 0; i <= maxRedirects; i++) {
      final request = http.Request('GET', currentUri)
        ..followRedirects = false
        ..headers.addAll(headers);

      final streamed = await client.send(request).timeout(_requestTimeout);
      final response = await http.Response.fromStream(
        streamed,
      ).timeout(_requestTimeout);

      if (_isRedirectStatus(response.statusCode)) {
        final location = response.headers['location'];
        if (location == null || location.trim().isEmpty) {
          return _RedirectFetchResult(response, currentUri.toString());
        }
        currentUri = currentUri.resolve(location.trim());
        continue;
      }

      return _RedirectFetchResult(response, currentUri.toString());
    }

    throw Exception('Maximum redirect limit reached for $initialUrl');
  }

  static bool _isRedirectStatus(int statusCode) =>
      statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308;

  static bool _isGenericTitle(String title, {String? url}) {
    final normalized = title.trim().toLowerCase();
    if (normalized.isEmpty || normalized == 'null') return true;
    if (_genericTitles.contains(normalized)) return true;

    if (url != null) {
      final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
      final bareHost = host.startsWith('www.') ? host.substring(4) : host;
      final domainLabel = bareHost.split('.').first;
      if (normalized == host ||
          normalized == bareHost ||
          normalized == domainLabel) {
        return true;
      }
    }
    return false;
  }

  static bool _isTikTokGenericFallbackCover(String imageUrl) {
    return imageUrl.contains('cover-fallback.png') ||
        imageUrl.contains('tiktok-logo/logo.png');
  }

  static String? _cleanImageUrl(
    String? rawImageUrl, {
    required String baseUrl,
  }) {
    if (rawImageUrl == null) return null;
    final unescaped = _unescapeHtmlEntities(rawImageUrl).trim();
    if (unescaped.isEmpty || unescaped.toLowerCase() == 'null') return null;

    if (unescaped.startsWith('data:')) return null;
    if (unescaped.contains(
      'any_link_preview/blob/master/lib/assets/giphy.gif',
    )) {
      return null;
    }

    try {
      final resolved = Uri.parse(baseUrl).resolve(unescaped);
      if (resolved.scheme != 'http' && resolved.scheme != 'https') {
        return null;
      }
      return resolved.toString();
    } catch (_) {
      return null;
    }
  }

  static String? _cleanText(String? raw) {
    if (raw == null) return null;
    final unescaped = _unescapeHtmlEntities(
      raw,
    ).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (unescaped.isEmpty || unescaped.toLowerCase() == 'null') return null;
    return unescaped;
  }

  @visibleForTesting
  static String unescapeHtml(String input) => _unescapeHtmlEntities(input);

  static String _unescapeHtmlEntities(String input) {
    if (!input.contains('&')) return input;

    var result = input
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&bull;', '•')
        .replaceAll('&middot;', '·');

    result = result.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (match) {
      final code = int.tryParse(match.group(1)!, radix: 16);
      if (code == null) return match.group(0)!;
      try {
        return String.fromCharCode(code);
      } catch (_) {
        return match.group(0)!;
      }
    });

    result = result.replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
      final code = int.tryParse(match.group(1)!);
      if (code == null) return match.group(0)!;
      try {
        return String.fromCharCode(code);
      } catch (_) {
        return match.group(0)!;
      }
    });

    return result;
  }

  static String _formatHostName(String url) {
    final host = Uri.tryParse(url)?.host ?? url;
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  static String? _normalizeUrl(String rawUrl) {
    var trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return null;
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      trimmed = 'https://$trimmed';
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) return null;
    return uri.toString();
  }

  static Future<LinkPreviewData?> _readFromCache(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_cachePrefix$url');
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final data = LinkPreviewData.fromCacheJson(decoded);
        if (data == null) {
          await prefs.remove('$_cachePrefix$url');
        }
        return data;
      }
    } catch (_) {}
    return null;
  }

  static Future<void> _writeToCache(
    String url,
    LinkPreviewData data,
    Duration ttl,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(
        data.toJson(expiresAt: DateTime.now().add(ttl)),
      );
      await prefs.setString('$_cachePrefix$url', jsonStr);
    } catch (_) {}
  }
}

class _RedirectFetchResult {
  final http.Response response;
  final String finalUrl;

  const _RedirectFetchResult(this.response, this.finalUrl);
}
