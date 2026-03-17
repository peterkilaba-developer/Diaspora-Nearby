import 'package:flutter_riverpod/flutter_riverpod.dart';

class PWAInstallNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  Future<bool> promptInstall() async {
    return false;
  }

  bool isPwaStandalone() => false;
}
