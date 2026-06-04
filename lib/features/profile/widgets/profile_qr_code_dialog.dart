import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:diaspora_nearby/core/data/countries.dart' as country_data;
import 'package:diaspora_nearby/core/utils/location_utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/trust/services/trust_service.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:go_router/go_router.dart';
import 'package:diaspora_nearby/features/profile/widgets/user_profile_form.dart';
import 'package:diaspora_nearby/features/profile/widgets/complete_profile_modal.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/dsp/services/exploration_registry.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/dsp/widgets/exploration_tracker.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';

class ProfileQRCodeDialog extends ConsumerStatefulWidget {
  final ProfileData profile;

  const ProfileQRCodeDialog({super.key, required this.profile});

  @override
  ConsumerState<ProfileQRCodeDialog> createState() =>
      _ProfileQRCodeDialogState();
}

class _ProfileQRCodeDialogState extends ConsumerState<ProfileQRCodeDialog> {
  bool _isScanning = false;
  final MobileScannerController _scannerController = MobileScannerController(
    formats: [BarcodeFormat.qrCode],
  );
  StreamSubscription<QuerySnapshot>? _qrSubscription;
  String? _lastConnectionUid;
  String? _cachedAddress;
  bool _isProcessing = false;
  bool _isCompletingProfile = false;
  List<String> _missingFields = [];
  late ProfileData _currentProfile;
  ProfileData? _knownConnectionProfile;

  @override
  void initState() {
    super.initState();
    _currentProfile = widget.profile;
    _lastConnectionUid = widget.profile.firstQrConnection?.otherUid;
    _checkProfileCompleteness();
    _startListeningForConnections();
    _preCacheLocation();
    _fetchKnownProfile();
    _trackExploration();
  }

  Future<void> _trackExploration() async {
    final userId = ref.read(authRepositoryProvider).currentUser?.uid;
    if (userId != null) {
      final rewarded = await ref
          .read(pointsServiceProvider)
          .trackExplorationReward(userId, ExplorationAction.profileQr);
      if (rewarded && mounted) {
        showExplorationRewardToast(context);
      }
    }
  }

  Future<void> _fetchKnownProfile() async {
    if (_lastConnectionUid != null) {
      try {
        final profile = await ref
            .read(profileRepositoryProvider)
            .getUserProfile(_lastConnectionUid!);
        if (mounted) {
          setState(() {
            _knownConnectionProfile = profile;
          });
        }
      } catch (e) {
        debugPrint('Error fetching known connection profile: $e');
      }
    }
  }

  void _checkProfileCompleteness() {
    final fields = _currentProfile.getMissingRequiredFields();

    if (fields.isNotEmpty) {
      setState(() {
        _missingFields = fields;
        _isCompletingProfile = true;
      });
    }
  }

  /// Formats a Placemark as "City, State, Country" or "City, Country" to match
  /// the user card's "From" / "Lives in" display format, always including country.
  String? _formatPlacemarkLocation(Placemark p) {
    final city = p.locality?.isNotEmpty == true
        ? p.locality!
        : p.subLocality?.isNotEmpty == true
        ? p.subLocality!
        : null;

    final country = p.country?.isNotEmpty == true
        ? formatLocationName(p.country)
        : null;

    if (city == null) {
      return country ?? p.administrativeArea;
    }

    final countryCode = p.isoCountryCode;
    if (countryCode != null &&
        country_data.hasStateLevelHierarchyFromData(countryCode)) {
      // State-level countries (US, India, etc.): "City, State, Country"
      final state = p.administrativeArea;
      if (state != null && state.isNotEmpty) {
        final parts = [city, formatLocationName(state)];
        if (country != null) parts.add(country);
        return parts.join(', ');
      }
    }

    // Other countries or no state: "City, Country"
    if (country != null) return '$city, $country';
    return city;
  }

  Future<void> _preCacheLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 5),
        ),
      );
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        // Format as "City, State" or "City, Country" matching user card format
        _cachedAddress = _formatPlacemarkLocation(p);
        if (_cachedAddress?.isEmpty == true) _cachedAddress = null;
        debugPrint('📍 QR: Location precached: $_cachedAddress');
      }
    } catch (e) {
      debugPrint('Error precaching location for QR: $e');
    }
  }

  void _startListeningForConnections() {
    final uid = widget.profile.uid;
    if (uid == null) return;

    debugPrint(
      "ProfileQRCodeDialog: Listening for QR exchanges targeting $uid",
    );

    _qrSubscription = FirebaseFirestore.instance
        .collection('qr_exchanges')
        .where('toUid', isEqualTo: uid)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .listen((snapshot) async {
          if (!mounted) return;
          if (snapshot.docs.isEmpty) return;

          final doc = snapshot.docs.first;
          final data = doc.data();
          final fromUid = data['fromUid'] as String;

          debugPrint("ProfileQRCodeDialog: Detected exchange from $fromUid");

          // If this is a NEW connection we haven't processed yet
          if (fromUid != _lastConnectionUid) {
            _lastConnectionUid = fromUid;

            try {
              // Fetch the other user's name for the profile update
              final fromProfile = await ref
                  .read(profileRepositoryProvider)
                  .getUserProfile(fromUid);
              if (!mounted || fromProfile == null) return;

              // [HANDSHAKE] Now update OUR OWN profile on OUR device
              await ref.read(profileRepositoryProvider).updateProfileData(uid, {
                'firstQrConnection': QRConnectionInfo(
                  otherUid: fromUid,
                  otherName: fromProfile.fullName,
                  locationAddress:
                      data['locationAddress'] ?? 'Location Unavailable',
                  timestamp: DateTime.now().toIso8601String(),
                ).toJson(),
              });

              debugPrint(
                "ProfileQRCodeDialog: Handshake complete. Navigating...",
              );

              if (mounted) {
                context.push('/profile/$fromUid?src=qr');
                Navigator.pop(context);
              }
            } catch (e) {
              debugPrint("ProfileQRCodeDialog: Error during handshake: $e");
            }
          }
        });
  }

  String _generateQRData() {
    return 'https://diasporanearby.com/profile/${widget.profile.uid}?src=qr';
  }

  Future<void> _handleScan(BarcodeCapture capture) async {
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null) {
        final rawValue = barcode.rawValue!;

        try {
          final uri = Uri.parse(rawValue);
          final host = uri.host.toLowerCase();
          final path = uri.path;

          // Support both diasporanearby.com and www.diasporanearby.com
          final isOurDomain =
              host == 'diasporanearby.com' || host == 'www.diasporanearby.com';

          if (isOurDomain && path.startsWith('/profile/')) {
            // Extract UID from path segments to ignore query parameters
            // Path segments for "/profile/123" are ["profile", "123"]
            if (uri.pathSegments.length < 2) continue;

            final targetUid = uri.pathSegments[1];
            if (targetUid.isEmpty) continue;

            final currentUid = widget.profile.uid;

            if (targetUid == currentUid) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('You cannot scan your own code'),
                  ),
                );
              }
              return;
            }

            if (_isProcessing) return;
            _isProcessing = true;

            // Stop scanner immediately
            _scannerController.stop();
            if (mounted) setState(() => _isScanning = false);

            // Use cached address if available, otherwise try one quick fetch
            String? finalAddress = _cachedAddress;
            if (finalAddress == null) {
              try {
                // Quick check for service and permission
                bool serviceEnabled =
                    await Geolocator.isLocationServiceEnabled();
                LocationPermission permission =
                    await Geolocator.checkPermission();

                if (serviceEnabled &&
                    (permission == LocationPermission.whileInUse ||
                        permission == LocationPermission.always)) {
                  final position = await Geolocator.getCurrentPosition(
                    locationSettings: const LocationSettings(
                      accuracy: LocationAccuracy.medium,
                      timeLimit: Duration(seconds: 2),
                    ),
                  );
                  final placemarks = await placemarkFromCoordinates(
                    position.latitude,
                    position.longitude,
                  );
                  if (placemarks.isNotEmpty) {
                    final p = placemarks.first;
                    // Format as "City, State" or "City, Country" matching user card format
                    finalAddress = _formatPlacemarkLocation(p);
                  }
                } else {
                  debugPrint(
                    'QR Scan: Location unavailable (Service: $serviceEnabled, Permission: $permission)',
                  );
                }
              } catch (e) {
                debugPrint('QR Scan: Location capture failed: $e');
              }
            }

            // Perform Exchange
            debugPrint(
              'QR: Starting exchange from $currentUid to $targetUid with address: $finalAddress',
            );
            await _performExchange(currentUid!, targetUid, finalAddress);
          }
        } catch (e) {
          debugPrint('Error parsing QR data: $e');
          _isProcessing = false;
        }
      }
    }
  }

  Future<void> _performExchange(
    String fromUid,
    String toUid,
    String? address,
  ) async {
    try {
      final int earnedPoints = await ref
          .read(trustServiceProvider)
          .performQRExchange(
            fromUid: fromUid,
            toUid: toUid,
            locationAddress: address,
          );

      if (mounted) {
        // Fetch target user's name for the success dialog
        final targetProfile = await ref
            .read(profileRepositoryProvider)
            .getUserProfile(toUid);
        if (!mounted) return;

        // Show Success Dialog
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: Row(
              children: [
                const Icon(
                  LucideIcons.checkCircle2,
                  color: Colors.green,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Connection Successful!',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'You are now connected in-person with ${targetProfile?.fullName ?? 'your peer'}.',
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
                  ),
                  if (earnedPoints > 0) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            LucideIcons.coins,
                            color: Colors.amber,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${NumberFormat('#,###').format(earnedPoints)} DSP EARNED!',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.amber,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0, right: 8.0),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0, // Ensure no shadow/border feel
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('View Profile'),
                ),
              ),
            ],
          ),
        );

        if (mounted) {
          context.push('/profile/$toUid?src=qr');
          Navigator.pop(context); // Close QR dialog
        }
      }
    } on AlreadyConnectedException catch (e) {
      if (!mounted) return;
      try {
        final profile = await ref
            .read(profileRepositoryProvider)
            .getUserProfile(e.otherUid);
        if (mounted) {
          setState(() {
            _knownConnectionProfile = profile;
          });
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.message)));
          setState(() => _isScanning = true);
          _scannerController.start();
        }
      }
    } on IncompleteProfileException catch (e) {
      if (!mounted) return;

      if (e.isOwnProfile) {
        // Show modal to complete OWN profile
        final success = await _showCompleteProfileModal(e.missingFields);
        if (success == true) {
          // Re-trigger exchange now that profile is updated
          await _performExchange(fromUid, toUid, address);
        } else {
          // User cancelled or failed - restart scanner
          setState(() => _isScanning = true);
          _scannerController.start();
        }
      } else {
        // OTHER user profile is incomplete
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'The other user needs to complete their profile first. Missing: ${e.missingFields.join(', ')}',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
        // Restart scanner
        setState(() => _isScanning = true);
        _scannerController.start();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
        // Restart scanner on error
        setState(() => _isScanning = true);
        _scannerController.start();
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<bool?> _showCompleteProfileModal(List<String> missingFields) async {
    // Fetch latest profile data to ensure modal has current state
    final latestProfile = await ref
        .read(profileRepositoryProvider)
        .getUserProfile(_currentProfile.uid!);

    if (!mounted) return false;

    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CompleteProfileModal(
        profile: latestProfile ?? _currentProfile,
        missingFields: missingFields,
      ),
    );
  }

  @override
  void dispose() {
    _qrSubscription?.cancel();
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _isCompletingProfile ? 'Finish Profile' : 'Identity Verification',
          ),
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(LucideIcons.x),
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.pageHorizontalPadding,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              if (_isCompletingProfile) ...[
                const Text(
                  'Please complete these details to enable identity verification.',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: UserProfileForm(
                    initialProfile: _currentProfile,
                    highlightFields: _missingFields,
                    submitLabel: 'Save & Open QR',
                    showUserCard: false,
                    isFinishProfile: true,
                    onSave: (updated, newImage) async {
                      try {
                        String imageUrl = updated.profileImage;
                        if (newImage != null) {
                          imageUrl = await ref
                              .read(profileRepositoryProvider)
                              .uploadProfileImage(updated.uid!, newImage);
                        }

                        final finalProfile = updated.copyWith(
                          profileImage: imageUrl,
                        );
                        await ref
                            .read(profileRepositoryProvider)
                            .saveUserProfile(finalProfile.uid!, finalProfile);

                        if (mounted) {
                          setState(() {
                            _currentProfile = finalProfile;
                            _isCompletingProfile = false;
                          });
                        }
                      } catch (e) {
                        debugPrint('Error saving profile in QR dialog: $e');
                        rethrow;
                      }
                    },
                  ),
                ),
              ] else if (!_isScanning) ...[
                const Text(
                  'Show this code to a peer to verify your human identity in person.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: QrImageView(
                    data: _generateQRData(),
                    version: QrVersions.auto,
                    size: 200.0,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: AppTheme.accent,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: AppTheme.accent,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  _currentProfile.fullName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      setState(() => _isScanning = true);
                      _scannerController.start();
                    },
                    icon: const Icon(LucideIcons.camera),
                    label: const Text('Scan Peer Code'),
                  ),
                ),
              ] else if (_isScanning && _knownConnectionProfile != null) ...[
                const SizedBox(height: 12),
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppTheme.accent.withValues(alpha: 0.2),
                          width: 2,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 60,
                        backgroundColor: Colors.grey.shade100,
                        backgroundImage:
                            _knownConnectionProfile!.profileImage.isNotEmpty
                            ? CachedNetworkImageProvider(
                                _knownConnectionProfile!.profileImage,
                              )
                            : null,
                        child: _knownConnectionProfile!.profileImage.isEmpty
                            ? Icon(
                                LucideIcons.user,
                                size: 60,
                                color: Colors.grey.shade400,
                              )
                            : null,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        LucideIcons.shieldCheck,
                        color: AppTheme.accent,
                        size: 32,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  'Identity Verified!',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'You are connected in-person with',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  _knownConnectionProfile!.fullName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.accent,
                  ),
                  textAlign: TextAlign.center,
                ),

                // Display location if available in their record
                if (_knownConnectionProfile!
                        .firstQrConnection
                        ?.locationAddress !=
                    null) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        LucideIcons.mapPin,
                        size: 14,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          _knownConnectionProfile!
                              .firstQrConnection!
                              .locationAddress!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () {
                      context.push(
                        '/profile/${_knownConnectionProfile!.uid}?src=qr',
                      );
                      Navigator.pop(context);
                    },
                    child: const Text('View Profile'),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _knownConnectionProfile = null;
                      _isProcessing = false;
                    });
                    _scannerController.start();
                  },
                  icon: const Icon(LucideIcons.camera, size: 18),
                  label: const Text('Scan Another Peer'),
                ),
              ] else ...[
                const Text(
                  'Scan your peer\'s Identity QR Code',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 300,
                    width: double.infinity,
                    child: MobileScanner(
                      controller: _scannerController,
                      onDetect: _handleScan,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () {
                    _scannerController.stop();
                    setState(() => _isScanning = false);
                  },
                  child: const Text('Back to My Code'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
