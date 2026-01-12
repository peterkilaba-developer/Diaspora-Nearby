import 'package:flutter/foundation.dart';
import 'pwa_utils_stub.dart' if (dart.library.js) 'pwa_utils_web.dart' as impl;

class PwaUtils {
  static Future<bool> promptInstall() async {
    if (!kIsWeb) return false;
    return await impl.promptInstall();
  }
}
