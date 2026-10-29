import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Checks for new app releases and triggers automatic updates or prompts the
/// user to update.
///
/// 1. On Android (Play Store installs): uses Google Play Core's native
///    [InAppUpdate] API to trigger an immediate or flexible in-app update
///    whenever Google Play has a newer versionCode on the user's track.
///    If Google Play reports [UpdateAvailability.updateNotAvailable] (for
///    instance while a newly uploaded build is still under Play Store review),
///    we do NOT show a false modal that would loop the user into Play Store's
///    "Open" button.
/// 2. On iOS, or when Firestore `system_stats/app_version` specifies a newer
///    build/version on platforms without Play Core: shows a clean update dialog
///    that deep-links to TestFlight / App Store / Google Play.
class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  static const String _androidPlayStoreUrl =
      'https://play.google.com/store/apps/details?id=com.diasporanearby.diasporanearby';
  static const String _iosTestFlightUrl =
      'https://testflight.apple.com/join/vB3XzPKg';
  static const String _iosAppStoreUrl =
      'https://apps.apple.com/app/id6821194997';
  static const String _dismissedBuildPrefKey =
      'app_update_dismissed_build_number';

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

    // 1. On Android, rely on Google Play Core's authoritative In-App Update API.
    // If Play Store responds cleanly (either triggering an update or reporting
    // that no update is available yet on the user's track), stop here so we
    // never trap users in a "Play Store shows Open -> app shows Update modal"
    // loop while a release is pending Play Store review.
    if (defaultTargetPlatform == TargetPlatform.android) {
      final handledByPlayCore = await _tryAndroidPlayInAppUpdate();
      if (handledByPlayCore) return;
    }

    // 2. Check Firestore `system_stats/app_version` metadata (for iOS / TestFlight,
    // or Android devices where Google Play Services is unavailable).
    if (!context.mounted) return;
    await _checkRemoteVersionDoc(context);
  }

  /// Queries Google Play Core for update availability.
  /// Returns `true` whenever Google Play Core authoritatively handled the check
  /// (including when Play Store reports `updateNotAvailable` for this user's track),
  /// and `false` only if Play Core threw an exception (e.g. missing Play Services).
  Future<bool> _tryAndroidPlayInAppUpdate() async {
    try {
      final info = await InAppUpdate.checkForUpdate().timeout(
        const Duration(seconds: 8),
      );
      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        if (info.immediateUpdateAllowed) {
          await InAppUpdate.performImmediateUpdate();
          return true;
        } else if (info.flexibleUpdateAllowed) {
          final result = await InAppUpdate.startFlexibleUpdate();
          if (result == AppUpdateResult.success) {
            await InAppUpdate.completeFlexibleUpdate();
          }
          return true;
        }
      } else if (info.updateAvailability ==
          UpdateAvailability.developerTriggeredUpdateInProgress) {
        await InAppUpdate.performImmediateUpdate();
        return true;
      } else if (info.updateAvailability ==
          UpdateAvailability.updateNotAvailable) {
        // Play Store authoritatively says no newer build is live for this user
        // yet (e.g. new build is still in Google Play review). Do NOT fall
        // through to the Firestore modal, which would send the user to Play
        // Store where only "Open" is shown.
        return true;
      }
    } catch (e) {
      // Devices without Play Services or sideloaded builds throw PlatformException;
      // fall through to the Firestore version check.
      debugPrint('AppUpdateService: Play In-App Update unavailable ($e)');
    }
    return false;
  }

  Future<void> _checkRemoteVersionDoc(BuildContext context) async {
    if (_dialogShowing) return;
    try {
      final results = await Future.wait([
        PackageInfo.fromPlatform(),
        SharedPreferences.getInstance(),
        FirebaseFirestore.instance
            .collection('system_stats')
            .doc('app_version')
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 6)),
      ]);
      final packageInfo = results[0] as PackageInfo;
      final prefs = results[1] as SharedPreferences;
      final doc = results[2] as DocumentSnapshot<Map<String, dynamic>>;

      final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;
      final currentVersion = packageInfo.version;
      _dismissedBuildNumber ??= prefs.getInt(_dismissedBuildPrefKey);

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
      final releaseNotes =
          (data['releaseNotes'] as String?)?.trim().isNotEmpty == true
          ? (data['releaseNotes'] as String).trim()
          : 'A new version of Diaspora Nearby is available with important fixes and improvements.';

      if (!context.mounted) return;
      _dialogShowing = true;
      await showDialog<void>(
        context: context,
        barrierDismissible: !forceUpdate,
        builder: (dialogContext) => BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: PopScope(
            canPop: !forceUpdate,
            child: AlertDialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 24,
              ),
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
                TextButton(
                  onPressed: () {
                    if (latestBuild != null) {
                      _dismissedBuildNumber = latestBuild;
                      unawaited(
                        prefs.setInt(_dismissedBuildPrefKey, latestBuild),
                      );
                    }
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Later'),
                ),
                FilledButton(
                  onPressed: () {
                    if (latestBuild != null) {
                      _dismissedBuildNumber = latestBuild;
                      unawaited(
                        prefs.setInt(_dismissedBuildPrefKey, latestBuild),
                      );
                    }
                    Navigator.of(dialogContext).pop();
                    unawaited(
                      _launchUpdateUrl(
                        storeUrl,
                        fallbackUrl: isIOS ? _iosTestFlightUrl : null,
                      ),
                    );
                  },
                  child: const Text('Update Now'),
                ),
              ],
            ),
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
