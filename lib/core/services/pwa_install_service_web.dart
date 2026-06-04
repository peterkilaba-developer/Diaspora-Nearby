import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:js_interop';

// External JS definitions
@JS('presentPWAInstall')
external JSPromise<JSBoolean> _presentPWAInstall();

@JS('isInstallPromptAvailable')
external JSBoolean _isInstallPromptAvailable();

@JS('window.addEventListener')
external void _addEventListener(JSString type, JSFunction listener);

@JS('isPwaStandalone')
external JSBoolean _isPwaStandalone();

class PWAInstallNotifier extends Notifier<bool> {
  @override
  bool build() {
    if (kIsWeb) {
      _init();
    }
    return false;
  }

  void _init() {
    _checkStatus();

    // Listen for custom event 'pwa-install-changed' from index.html
    try {
      _addEventListener(
        'pwa-install-changed'.toJS,
        (() => _checkStatus()).toJS,
      );
    } catch (e) {
      debugPrint('Failed to add PWA event listener: $e');
    }
  }

  void _checkStatus() {
    try {
      final isAvailable = _isInstallPromptAvailable().toDart;
      if (state != isAvailable) {
        state = isAvailable;
      }
    } catch (_) {
      // Function might not exist or verify failed
    }
  }

  Future<bool> promptInstall() async {
    if (!kIsWeb) return false;
    try {
      final result = await _presentPWAInstall().toDart;
      return result.toDart;
    } catch (e) {
      debugPrint('PWA Install Error: $e');
      return false;
    }
  }

  bool isPwaStandalone() {
    if (!kIsWeb) return false;
    try {
      return _isPwaStandalone().toDart;
    } catch (_) {
      return false;
    }
  }
}
