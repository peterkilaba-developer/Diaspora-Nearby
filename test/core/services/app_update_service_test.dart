import 'package:diaspora_nearby/core/services/app_update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  group('AppUpdateService.formatVersionLabel', () {
    test('includes version and build number when buildNumber is non-empty', () {
      final info = PackageInfo(
        appName: 'Diaspora',
        packageName: 'com.diasporanearby.diasporanearby',
        version: '1.2.8',
        buildNumber: '67',
      );
      expect(
        AppUpdateService.formatVersionLabel(info),
        'Version 1.2.8 (Build 67)',
      );
    });

    test('omits build parenthetical when buildNumber is empty', () {
      final info = PackageInfo(
        appName: 'Diaspora',
        packageName: 'com.diasporanearby.diasporanearby',
        version: '1.2.8',
        buildNumber: '',
      );
      expect(AppUpdateService.formatVersionLabel(info), 'Version 1.2.8');
    });

    test('falls back to fallbackVersionName when version is blank', () {
      final info = PackageInfo(
        appName: 'Diaspora',
        packageName: 'com.diasporanearby.diasporanearby',
        version: '',
        buildNumber: '67',
      );
      expect(
        AppUpdateService.formatVersionLabel(info),
        'Version ${AppUpdateService.fallbackVersionName} (Build 67)',
      );
    });
  });
}
