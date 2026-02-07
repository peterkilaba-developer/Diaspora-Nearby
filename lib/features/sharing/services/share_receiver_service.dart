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
      ReceiveSharingIntent.instance.reset(); // [FIX] Clear intent to prevent loop on restart
    });
  }

  void _handleSharedFiles(List<SharedMediaFile> files) {
    if (files.isEmpty) return;

    // [FIX] Ignore profile deep links to prevent opening "Send to..." / Share screen
    // GoRouter should handle these deep links directly.
    final hasProfileLink = files.any((f) {
      final path = f.path.toLowerCase();
      final isUrl = f.type == SharedMediaType.url || f.type == SharedMediaType.text;
      final match = path.contains('diasporanearby.com/profile/');
      
      if (isUrl && match) {
        debugPrint("ShareReceiverService: Detected profile deep link in path: ${f.path}");
        return true;
      }
      return false;
    });

    if (hasProfileLink) {
      debugPrint("ShareReceiverService: Ignoring shared files because profile deep link was detected.");
      return;
    }

    _navigateToShare(files);
  }

  void _navigateToShare(List<SharedMediaFile> files) {
    // Navigate to Share Destination Screen with the files
    // Use a small delay to ensure router is ready
    Future.delayed(const Duration(milliseconds: 500), () {
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
