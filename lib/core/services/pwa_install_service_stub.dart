import 'package:flutter_riverpod/flutter_riverpod.dart';

class PWAInstallNotifier extends StateNotifier<bool> {
  PWAInstallNotifier() : super(false);

  Future<bool> promptInstall() async {
    return false;
  }
}
