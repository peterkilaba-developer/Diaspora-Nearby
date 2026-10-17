import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/router.dart' show invalidatePermissionCache;
import 'package:diaspora_nearby/core/services/app_update_service.dart';

class UserPermissionsScreen extends ConsumerStatefulWidget {
  const UserPermissionsScreen({super.key});

  @override
  ConsumerState<UserPermissionsScreen> createState() =>
      _UserPermissionsScreenState();
}

class _UserPermissionsScreenState extends ConsumerState<UserPermissionsScreen>
    with WidgetsBindingObserver {
  bool _locationGranted = false;
  bool _notificationGranted = false;
  bool _backgroundLocationGranted = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // [FIX] Always reset processing flag on (re-)mount — prevents permanent stuck state
    // if the router redirected us back here after a navigation attempt.
    _isProcessing = false;
    // Check permissions immediately to update UI state.
    _checkPermissions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(AppUpdateService.instance.checkForUpdate(context));
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // [FIX] Reset processing flag on resume — prevents permanent stuck state
      // if a previous navigation attempt was intercepted by the router.
      _isProcessing = false;
      // Auto-navigate when returning from settings with all permissions granted
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    try {
      final locationStatus = await Permission.location.status;
      final notificationStatus = await Permission.notification.status;

      // Check background location - handle legacy/new Android versions gracefully
      bool backgroundLocationGranted = false;
      try {
        final bgStatus = await Permission.locationAlways.status;
        // [FIX] Accept both isGranted and isLimited for background location
        backgroundLocationGranted = bgStatus.isGranted || bgStatus.isLimited;
        debugPrint(
          'Permission Check - Location: $locationStatus, Notification: $notificationStatus, BgLocation: $bgStatus',
        );
      } catch (e) {
        debugPrint('Error checking background location: $e');
        // [FIX] If we can't check background location, treat as granted
        // to avoid permanently blocking the user. The router only checks
        // foreground location anyway.
        backgroundLocationGranted = true;
      }

      if (mounted) {
        setState(() {
          _locationGranted = kIsWeb
              ? true
              : (locationStatus.isGranted || locationStatus.isLimited);
          _notificationGranted = kIsWeb ? true : notificationStatus.isGranted;
          _backgroundLocationGranted = kIsWeb
              ? true
              : backgroundLocationGranted;
        });

        debugPrint(
          'Permission State - loc=$_locationGranted, notif=$_notificationGranted, bgLoc=$_backgroundLocationGranted, allGranted=$_allPermissionsGranted, isProcessing=$_isProcessing',
        );

        // Auto-navigate as soon as all permissions are granted
        if (_allPermissionsGranted && !_isProcessing) {
          // Brief delay to let UI settle before navigating
          await Future.delayed(const Duration(milliseconds: 300));
          if (mounted && _allPermissionsGranted && !_isProcessing) {
            _continue();
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking permissions: $e');
    }
  }

  bool get _allPermissionsGranted =>
      kIsWeb ||
      (_locationGranted && _notificationGranted && _backgroundLocationGranted);

  Future<void> _requestLocation() async {
    try {
      final status = await Permission.location.request();
      if (status.isPermanentlyDenied) {
        await openAppSettings();
      }
      await _checkPermissions();
    } catch (e) {
      debugPrint('Error requesting location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error requesting permission: $e')),
        );
      }
    } finally {
      await _checkPermissions();
    }
  }

  Future<void> _requestNotifications() async {
    try {
      final status = await Permission.notification.request();
      if (status.isPermanentlyDenied) {
        await openAppSettings();
      }
      await _checkPermissions();
    } catch (e) {
      debugPrint('Error requesting notifications: $e');
    } finally {
      await _checkPermissions();
    }
  }

  Future<void> _requestBackgroundLocation() async {
    try {
      // Background location requires fine location first
      if (!_locationGranted) {
        final status = await Permission.location.request();
        if (!status.isGranted) return;
      }

      final status = await Permission.locationAlways.request();
      if (status.isPermanentlyDenied) {
        await openAppSettings();
      }

      // We don't need to auto-proceed here immediately if we are going to settings,
      // the resume handler will take care of updating the UI.
      await _checkPermissions();
    } catch (e) {
      debugPrint('Error requesting background location: $e');
      // Don't crash, just log
    } finally {
      await _checkPermissions();
    }
  }

  void _continue() {
    if (_isProcessing) return;

    if (_allPermissionsGranted) {
      setState(() => _isProcessing = true);
      // Invalidate the router's cached permission status so it
      // does a fresh check and doesn't redirect back to /permissions.
      invalidatePermissionCache();
      if (mounted) {
        context.go('/chats');
      }
      // [FIX] Safety reset — if navigation fails or router redirects back,
      // re-enable the button after 2 seconds so user is never permanently stuck.
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && _isProcessing) {
          setState(() => _isProcessing = false);
        }
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All permissions are required to continue.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.pageHorizontalPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 24),
                    Icon(
                      LucideIcons.shieldCheck,
                      size: 64,
                      color: Theme.of(context).primaryColor,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Permissions Required',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'To verify your location and keep you connected, we need a few permissions.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    const SizedBox(height: 32),

                    // Notification Permission (First)
                    _buildPermissionItem(
                      title: 'Notifications',
                      description:
                          'Stay updated with chat messages and alerts.',
                      icon: LucideIcons.bell,
                      isGranted: _notificationGranted,
                      onPressed: _requestNotifications,
                    ),

                    const SizedBox(height: 16),

                    // Location Permission (Second - Requires Notifications)
                    _buildPermissionItem(
                      title: 'Location Service',
                      description:
                          "Required to show nearby. Click on 'While using the app'.",
                      icon: LucideIcons.mapPin,
                      isGranted: _locationGranted,
                      onPressed: _requestLocation,
                      isDisabled:
                          !_notificationGranted, // Disabled until Notif granted
                    ),

                    const SizedBox(height: 16),

                    // Background Location Permission (Third - Requires Location)
                    if (!kIsWeb)
                      _buildPermissionItem(
                        title: 'Background Location',
                        description:
                            "Required for alerts. Click on 'Allow all the time' in settings.",
                        icon: LucideIcons.map,
                        isGranted: _backgroundLocationGranted,
                        onPressed: _requestBackgroundLocation,
                        isDisabled:
                            !_locationGranted, // Disabled until Location granted
                      ),

                    if (kIsWeb)
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        child: Text(
                          'Note: Background location and app-alerts are managed by your browser settings on the web.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // Sticky Continue Button
            Container(
              padding: const EdgeInsets.all(AppTheme.pageHorizontalPadding),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_allPermissionsGranted && !_isProcessing)
                      ? _continue
                      : null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                  ),
                  child: const Text(
                    'Continue',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionItem({
    required String title,
    required String description,
    required IconData icon,
    required bool isGranted,
    required VoidCallback onPressed,
    bool isDisabled = false,
  }) {
    return Opacity(
      opacity: isDisabled ? 0.6 : 1.0,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isDisabled || isGranted ? null : onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(AppTheme.pageHorizontalPadding),
            decoration: AppTheme.cardDecoration(context).copyWith(
              border: Border.all(
                color: isGranted
                    ? Theme.of(context).primaryColor
                    : Colors.grey.shade300,
                width: isGranted ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isGranted
                        ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
                        : Colors.grey.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: isGranted
                        ? Theme.of(context).primaryColor
                        : Colors.grey,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isGranted)
                  Icon(
                    LucideIcons.checkCircle2,
                    color: Theme.of(context).primaryColor,
                  )
                else
                  TextButton(
                    onPressed: isDisabled ? null : onPressed,
                    child: const Text('Allow'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
