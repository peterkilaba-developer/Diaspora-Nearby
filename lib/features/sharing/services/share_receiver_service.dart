import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/router.dart';

final shareReceiverServiceProvider = Provider<ShareReceiverService>((ref) {
  return ShareReceiverService(ref);
});

class ShareReceiverService {
  static const MethodChannel _shareIntentChannel = MethodChannel(
    'com.diasporanearby/share_intent',
  );

  final Ref _ref;
  StreamSubscription? _intentDataStreamSubscription;
  List<SharedMediaFile> _pendingSharedFiles = const [];

  ShareReceiverService(this._ref);

  List<SharedMediaFile> get pendingSharedFiles => _pendingSharedFiles;

  void clearPendingFiles() {
    _pendingSharedFiles = const [];
  }

  /// Safely extracts [SharedMediaFile] items from GoRouter's `state.extra`
  /// (handling direct lists, JSON-decoded maps, or null) with an in-memory fallback.
  static List<SharedMediaFile> extractSharedFiles(
    Object? extra, {
    List<SharedMediaFile>? fallback,
  }) {
    if (extra is List<SharedMediaFile> && extra.isNotEmpty) {
      return extra;
    }
    if (extra is List && extra.isNotEmpty) {
      final parsed = <SharedMediaFile>[];
      for (final item in extra) {
        if (item is SharedMediaFile) {
          parsed.add(item);
        } else if (item is Map) {
          try {
            parsed.add(
              SharedMediaFile.fromMap(Map<String, dynamic>.from(item)),
            );
          } catch (_) {}
        }
      }
      if (parsed.isNotEmpty) {
        return parsed;
      }
    }
    if (fallback != null && fallback.isNotEmpty) {
      return fallback;
    }
    return const <SharedMediaFile>[];
  }

  /// Merges companion text/URL (e.g. Android `Intent.EXTRA_TEXT` from `navigator.share`
  /// alongside an image/video file, or separate text/url items) into the primary media
  /// item's `message` field so both the media and link/caption are sent together.
  @visibleForTesting
  static List<SharedMediaFile> mergeCompanionTextIntoMedia(
    List<SharedMediaFile> files, {
    String? nativeExtraText,
  }) {
    if (files.isEmpty) return files;

    final hasMediaFile = files.any(
      (f) =>
          f.type == SharedMediaType.image ||
          f.type == SharedMediaType.video ||
          f.type == SharedMediaType.file,
    );
    if (!hasMediaFile) {
      return files;
    }

    final textParts = <String>[];
    void addPart(String? raw) {
      final trimmed = raw?.trim();
      if (trimmed == null || trimmed.isEmpty) return;
      final alreadyIncluded = textParts.any(
        (existing) => existing.toLowerCase().contains(trimmed.toLowerCase()),
      );
      if (alreadyIncluded) return;
      textParts.removeWhere(
        (existing) => trimmed.toLowerCase().contains(existing.toLowerCase()),
      );
      textParts.add(trimmed);
    }

    for (final f in files) {
      if (f.type == SharedMediaType.image ||
          f.type == SharedMediaType.video ||
          f.type == SharedMediaType.file) {
        addPart(f.message);
      }
    }

    addPart(nativeExtraText);

    for (final f in files) {
      if (f.type == SharedMediaType.text || f.type == SharedMediaType.url) {
        addPart(f.path);
        addPart(f.message);
      }
    }

    final combinedCaption = textParts.join('\n').trim();
    final mediaFiles = files
        .where(
          (f) =>
              f.type == SharedMediaType.image ||
              f.type == SharedMediaType.video ||
              f.type == SharedMediaType.file,
        )
        .toList();

    if (combinedCaption.isEmpty) {
      return mediaFiles;
    }

    final result = <SharedMediaFile>[];
    for (var i = 0; i < mediaFiles.length; i++) {
      final item = mediaFiles[i];
      if (i == 0) {
        result.add(
          SharedMediaFile(
            path: item.path,
            type: item.type,
            thumbnail: item.thumbnail,
            duration: item.duration,
            mimeType: item.mimeType,
            message: combinedCaption,
          ),
        );
      } else {
        result.add(item);
      }
    }
    return result;
  }

  void initialize() {
    // For sharing images coming from outside the app while the app is in the memory
    _intentDataStreamSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen(
          (List<SharedMediaFile> value) {
            unawaited(_handleSharedFiles(value));
          },
          onError: (err) {
            debugPrint("getIntentDataStream error: $err");
          },
        );

    // For sharing images coming from outside the app while the app is closed
    ReceiveSharingIntent.instance.getInitialMedia().then((
      List<SharedMediaFile> value,
    ) async {
      await _handleSharedFiles(value);
      ReceiveSharingIntent.instance
          .reset(); // [FIX] Clear intent to prevent loop on restart
    });
  }

  Future<void> _handleSharedFiles(List<SharedMediaFile> files) async {
    if (files.isEmpty) return;

    String? nativeExtraText;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        nativeExtraText = await _shareIntentChannel.invokeMethod<String>(
          'consumeSharedText',
        );
      } catch (e) {
        debugPrint(
          'ShareReceiverService: Failed to read native shared text: $e',
        );
      }
    }

    final hasMediaFile = files.any(
      (f) =>
          f.type == SharedMediaType.image ||
          f.type == SharedMediaType.video ||
          f.type == SharedMediaType.file,
    );

    // [FIX] Ignore internal deep links (when no media file is attached) to prevent
    // triggering the share screen on ACTION_VIEW deep links.
    if (!hasMediaFile) {
      final hasOurLink = files.any((f) {
        final isUrl =
            f.type == SharedMediaType.url || f.type == SharedMediaType.text;
        final path = f.path.toLowerCase();
        final isInternal = path.contains('diasporanearby.com');

        if (isUrl && isInternal) {
          debugPrint(
            "ShareReceiverService: Detected internal deep link in path: ${f.path}. Ignoring.",
          );
          return true;
        }
        return false;
      });

      if (hasOurLink) {
        return;
      }
    }

    final mergedFiles = mergeCompanionTextIntoMedia(
      files,
      nativeExtraText: nativeExtraText,
    );

    _pendingSharedFiles = mergedFiles;
    _navigateToShare(mergedFiles);
  }

  void _navigateToShare(List<SharedMediaFile> files) {
    // Navigate immediately on the current/next frame without a 500ms delay
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _ref.read(routerProvider).pushNamed('share_destination', extra: files);
      } catch (e) {
        debugPrint("Share navigation failed: $e");
      }
    });
  }

  void dispose() {
    _intentDataStreamSubscription?.cancel();
  }
}
