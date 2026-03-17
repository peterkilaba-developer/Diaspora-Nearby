import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'pwa_install_service_stub.dart'
    if (dart.library.js_interop) 'pwa_install_service_web.dart';

export 'pwa_install_service_stub.dart'
    if (dart.library.js_interop) 'pwa_install_service_web.dart';

final pwaInstallServiceProvider = NotifierProvider<PWAInstallNotifier, bool>(
  PWAInstallNotifier.new,
);
