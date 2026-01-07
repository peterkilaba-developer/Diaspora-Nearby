import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/services/background_location_service.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

class UserPermissionsScreen extends ConsumerStatefulWidget {
  const UserPermissionsScreen({super.key});

  @override
  ConsumerState<UserPermissionsScreen> createState() => _UserPermissionsScreenState();
}

class _UserPermissionsScreenState extends ConsumerState<UserPermissionsScreen> with WidgetsBindingObserver {
  bool _locationGranted = false;
  bool _notificationGranted = false;
  bool _backgroundLocationGranted = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Check permissions immediately to update UI state.
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    try {
      final locationStatus = await Permission.location.status;
      final notificationStatus = await Permission.notification.status;
      
      debugPrint('Permission Check - Location: $locationStatus, Notification: $notificationStatus');
      
      // Check background location - handle legacy/new Android versions gracefully
      bool backgroundLocationGranted = false;
      try {
        backgroundLocationGranted = await Permission.locationAlways.isGranted;
      } catch (e) {
        debugPrint('Error checking background location: $e');
      }

      if (mounted) {
        setState(() {
          _locationGranted = locationStatus.isGranted || locationStatus.isLimited;
          _notificationGranted = notificationStatus.isGranted;
          _backgroundLocationGranted = backgroundLocationGranted;
        });
      }
    } catch (e) {
      debugPrint('Error checking permissions: $e');
    }
  }

  Future<void> _requestLocation() async {
    setState(() => _isLoading = true);
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _requestNotifications() async {
    setState(() => _isLoading = true);
    try {
      final status = await Permission.notification.request();
      if (status.isPermanentlyDenied) {
        await openAppSettings();
      }
      await _checkPermissions();
    } catch (e) {
      debugPrint('Error requesting notifications: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _requestBackgroundLocation() async {
    setState(() => _isLoading = true);
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _proceedToNextScreen() async {
    try {
      // Double check all required permissions
      if (_locationGranted && _notificationGranted && _backgroundLocationGranted) {
        // Proceed to home.
        // We delegate starting the background service to HomeScreen to avoid
        // Android 12+ ForegroundServiceStartNotAllowedException on resume.
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            // Navigate to Chats first to allow background service to stabilize
            if (mounted) {
              context.go('/chats');
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error proceeding to next screen: $e');
    }
  }

  void _continue() {
    if (_locationGranted && _notificationGranted && _backgroundLocationGranted) {
      _proceedToNextScreen();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All permissions are required to continue.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const Icon(LucideIcons.shieldCheck, size: 64, color: Color(0xFF9CAF88)),
              const SizedBox(height: 24),
              const Text(
                'Permissions Required',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'To verify your location and keep you connected, we need a few permissions.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const Spacer(),
              
              // Notification Permission (First)
              _buildPermissionItem(
                title: 'Notifications',
                description: 'Stay updated with chat messages and alerts.',
                icon: LucideIcons.bell,
                isGranted: _notificationGranted,
                onPressed: _requestNotifications,
              ),
              
              const SizedBox(height: 16),
              
              // Location Permission (Second - Requires Notifications)
              _buildPermissionItem(
                title: 'Location Service',
                description: "Required to show nearby. Click on 'While using the app'.",
                icon: LucideIcons.mapPin,
                isGranted: _locationGranted,
                onPressed: _requestLocation,
                isDisabled: !_notificationGranted, // Disabled until Notif granted
              ),
              
              const SizedBox(height: 16),
              
              // Background Location Permission (Third - Requires Location)
              _buildPermissionItem(
                title: 'Background Location',
                description: "Required for alerts. Click on 'Allow all the time' in settings.",
                icon: LucideIcons.map,
                isGranted: _backgroundLocationGranted,
                onPressed: _requestBackgroundLocation,
                isDisabled: !_locationGranted, // Disabled until Location granted
              ),

              const Spacer(flex: 2),
              
              // Continue Button - Requires ALL permissions
              ElevatedButton(
                onPressed: (_locationGranted && _notificationGranted && _backgroundLocationGranted) 
                    ? _continue 
                    : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: const Color(0xFF9CAF88),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                ),
                child: const Text('Continue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
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
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isGranted ? const Color(0xFF9CAF88) : Colors.grey.shade300,
                width: isGranted ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
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
                    color: isGranted ? const Color(0xFF9CAF88).withOpacity(0.1) : Colors.grey.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: isGranted ? const Color(0xFF9CAF88) : Colors.grey,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                if (isGranted)
                  const Icon(LucideIcons.checkCircle2, color: Color(0xFF9CAF88))
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
