import 'dart:async';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/router.dart';

final shareReceiverServiceProvider = Provider<ShareReceiverService>((ref) {
  return ShareReceiverService(ref);
});

class ShareReceiverService {
  final Ref _ref;
  StreamSubscription? _intentDataStreamSubscription;

  ShareReceiverService(this._ref);

  void initialize() {
    // For sharing images coming from outside the app while the app is in the memory
    _intentDataStreamSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen(
          (List<SharedMediaFile> value) {
            _handleSharedFiles(value);
          },
          onError: (err) {
            debugPrint("getIntentDataStream error: $err");
          },
        );

    // For sharing images coming from outside the app while the app is closed
    ReceiveSharingIntent.instance.getInitialMedia().then((
      List<SharedMediaFile> value,
    ) {
      _handleSharedFiles(value);
      ReceiveSharingIntent.instance
          .reset(); // [FIX] Clear intent to prevent loop on restart
    });
  }

  void _handleSharedFiles(List<SharedMediaFile> files) {
    if (files.isEmpty) return;

    // [FIX] Ignore ALL links to our own domain to prevent triggering the share screen.
    // These should be handled by deep linking (GoRouter) instead.
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

    _navigateToShare(files);
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
