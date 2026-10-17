import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Checks for new app releases and triggers automatic updates or prompts the
/// user to update.
///
/// 1. On Android (Play Store installs): uses Google Play Core's native
///    [InAppUpdate] API to trigger an immediate or flexible in-app update
///    whenever Google Play has a newer versionCode on the user's track.
/// 2. On iOS, Android sideloaded builds, or when Firestore `system_stats/app_version`
///    specifies a newer build/version: shows a clean update dialog (blocking
///    if `forceUpdate == true` or below `minBuildNumber`, dismissible otherwise)
///    that deep-links to TestFlight / App Store / Google Play / direct APK.
class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  static const String _androidPlayStoreUrl =
      'https://play.google.com/store/apps/details?id=com.diasporanearby.diasporanearby';
  static const String _androidFallbackApkUrl =
      'https://github.com/peterkilaba-developer/Diaspora-Nearby/releases/latest/download/app-production-release.apk';
  static const String _iosTestFlightUrl = 'itms-beta://';
  static const String _iosAppStoreUrl =
      'https://apps.apple.com/app/id6821194997';

  DateTime? _lastCheckAt;
  bool _dialogShowing = false;
  int? _dismissedBuildNumber;

  /// Checks for updates at most once every [cooldown] unless [force] is true.
  Future<void> checkForUpdate(
    BuildContext context, {
    Duration cooldown = const Duration(minutes: 15),
    bool force = false,
  }) async {
    if (kIsWeb) return;
    final now = DateTime.now();
    if (!force &&
        _lastCheckAt != null &&
        now.difference(_lastCheckAt!) < cooldown) {
      return;
    }
    _lastCheckAt = now;

    // 1. On Android, try Google Play Core native In-App Update first.
    if (defaultTargetPlatform == TargetPlatform.android) {
      final handledByPlayCore = await _tryAndroidPlayInAppUpdate();
      if (handledByPlayCore) return;
    }

    // 2. Check Firestore `system_stats/app_version` metadata (works for iOS,
    // TestFlight, Play Store, and sideloaded Android APKs).
    if (!context.mounted) return;
    await _checkRemoteVersionDoc(context);
  }

  Future<bool> _tryAndroidPlayInAppUpdate() async {
    try {
      final info = await InAppUpdate.checkForUpdate().timeout(
        const Duration(seconds: 8),
      );
      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        if (info.immediateUpdateAllowed) {
          final result = await InAppUpdate.performImmediateUpdate();
          return result == AppUpdateResult.success;
        } else if (info.flexibleUpdateAllowed) {
          final result = await InAppUpdate.startFlexibleUpdate();
          if (result == AppUpdateResult.success) {
            await InAppUpdate.completeFlexibleUpdate();
            return true;
          }
        }
      } else if (info.updateAvailability ==
          UpdateAvailability.developerTriggeredUpdateInProgress) {
        await InAppUpdate.performImmediateUpdate();
        return true;
      }
    } catch (e) {
      // Sideloaded APKs or devices without Play Services throw PlatformException;
      // fall through to the Firestore version check.
      debugPrint('AppUpdateService: Play In-App Update unavailable ($e)');
    }
    return false;
  }

  Future<void> _checkRemoteVersionDoc(BuildContext context) async {
    if (_dialogShowing) return;
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;
      final currentVersion = packageInfo.version;

      final doc = await FirebaseFirestore.instance
          .collection('system_stats')
          .doc('app_version')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 6));

      if (!doc.exists || doc.data() == null) return;
      final data = doc.data()!;

      final isIOS = defaultTargetPlatform == TargetPlatform.iOS;
      final latestBuild = _readInt(
        data[isIOS ? 'iosBuildNumber' : 'androidBuildNumber'] ??
            data['latestBuildNumber'],
      );
      final minBuild = _readInt(
        data[isIOS ? 'iosMinBuildNumber' : 'androidMinBuildNumber'] ??
            data['minBuildNumber'],
      );
      final latestVersion =
          (data[isIOS ? 'iosVersion' : 'androidVersion'] ??
                  data['latestVersion'] ??
                  currentVersion)
              .toString();
      final forceUpdate =
          data['forceUpdate'] == true ||
          (minBuild != null && currentBuild > 0 && currentBuild < minBuild);

      final hasNewerBuild =
          latestBuild != null && currentBuild > 0 && currentBuild < latestBuild;
      final hasNewerSemver = _isSemverLess(currentVersion, latestVersion);

      if (!hasNewerBuild && !hasNewerSemver && !forceUpdate) {
        return;
      }

      if (!forceUpdate &&
          latestBuild != null &&
          _dismissedBuildNumber == latestBuild) {
        return;
      }

      final storeUrl = isIOS
          ? (data['iosUpdateUrl'] as String? ?? _iosAppStoreUrl)
          : (data['androidUpdateUrl'] as String? ?? _androidPlayStoreUrl);
      final directApkUrl =
          data['androidApkUrl'] as String? ?? _androidFallbackApkUrl;
      final releaseNotes =
          (data['releaseNotes'] as String?)?.trim().isNotEmpty == true
          ? (data['releaseNotes'] as String).trim()
          : 'A new version of Diaspora Nearby is available with important fixes and improvements.';

      if (!context.mounted) return;
      _dialogShowing = true;
      await showDialog<void>(
        context: context,
        barrierDismissible: !forceUpdate,
        builder: (dialogContext) => PopScope(
          canPop: !forceUpdate,
          child: AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.system_update, color: Color(0xFF2E7D32)),
                SizedBox(width: 10),
                Expanded(child: Text('Update Available')),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Version $latestVersion${latestBuild != null ? " (Build $latestBuild)" : ""} is ready.',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(releaseNotes),
              ],
            ),
            actions: [
              if (!forceUpdate)
                TextButton(
                  onPressed: () {
                    _dismissedBuildNumber = latestBuild;
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Later'),
                ),
              if (!isIOS)
                TextButton(
                  onPressed: () => _launchUpdateUrl(directApkUrl),
                  child: const Text('Direct APK'),
                ),
              FilledButton(
                onPressed: () => _launchUpdateUrl(
                  storeUrl,
                  fallbackUrl: isIOS ? _iosTestFlightUrl : directApkUrl,
                ),
                child: const Text('Update Now'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      debugPrint('AppUpdateService: Remote version check skipped ($e)');
    } finally {
      _dialogShowing = false;
    }
  }

  int? _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  bool _isSemverLess(String current, String latest) {
    final cParts = current
        .split('+')
        .first
        .split('.')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();
    final lParts = latest
        .split('+')
        .first
        .split('.')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();
    for (var i = 0; i < 3; i++) {
      final c = i < cParts.length ? cParts[i] : 0;
      final l = i < lParts.length ? lParts[i] : 0;
      if (c < l) return true;
      if (c > l) return false;
    }
    return false;
  }

  Future<void> _launchUpdateUrl(
    String primaryUrl, {
    String? fallbackUrl,
  }) async {
    try {
      final uri = Uri.parse(primaryUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {}
    if (fallbackUrl != null) {
      try {
        final fallbackUri = Uri.parse(fallbackUrl);
        await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
  }
}
