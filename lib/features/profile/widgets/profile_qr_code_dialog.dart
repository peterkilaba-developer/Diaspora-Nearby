import 'dart:async';
import 'dart:ui';
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
import 'package:cloud_functions/cloud_functions.dart';
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
  // [PERF] Static in-memory cache for QR handshake tokens so reopening the QR dialog
  // renders the QR code in 0ms without waiting on a Cloud Function round-trip.
  static final Map<String, ({String token, DateTime fetchedAt})>
  _cachedTokenByUid = {};
  static const Duration _tokenCacheTtl = Duration(minutes: 4);

  bool _isScanning = false;
  final MobileScannerController _scannerController = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    autoStart: false,
  );
  StreamSubscription<QuerySnapshot>? _qrSubscription;
  String? _lastConnectionUid;
  String? _cachedAddress;
  bool _isProcessing = false;
  bool _isCompletingProfile = false;
  List<String> _missingFields = [];
  late ProfileData _currentProfile;
  ProfileData? _knownConnectionProfile;
  String? _handshakeToken;
  String? _handshakeError;

  @override
  void initState() {
    super.initState();
    _currentProfile = widget.profile;
    _lastConnectionUid = widget.profile.firstQrConnection?.otherUid;
    _cachedAddress = _fallbackHostLocation();

    // [PERF] Seed handshake token synchronously from memory cache if fresh
    final uid = widget.profile.uid;
    if (uid != null) {
      final cachedEntry = _cachedTokenByUid[uid];
      if (cachedEntry != null &&
          DateTime.now().difference(cachedEntry.fetchedAt) < _tokenCacheTtl) {
        _handshakeToken = cachedEntry.token;
      }
    }

    // [PERF] Seed known connection profile synchronously from memory cache
    if (_lastConnectionUid != null) {
      _knownConnectionProfile = ref
          .read(profileRepositoryProvider)
          .getCachedProfile(_lastConnectionUid!);
    }

    _checkProfileCompleteness();
    _startListeningForConnections();
    _preCacheLocation();
    _fetchKnownProfile();
    _trackExploration();
    _refreshHandshake();
  }

  Future<void> _refreshHandshake() async {
    try {
      final response = await FirebaseFunctions.instance
          .httpsCallable('createQrHandshake')
          .call();
      final data = Map<String, dynamic>.from(response.data as Map);
      final token = data['token'] as String?;
      final uid = widget.profile.uid;
      if (uid != null && token != null && token.isNotEmpty) {
        _cachedTokenByUid[uid] = (token: token, fetchedAt: DateTime.now());
      }
      if (!mounted) return;
      setState(() {
        _handshakeToken = token;
        _handshakeError = null;
      });
    } catch (error) {
      if (!mounted) return;
      if (_handshakeToken == null) {
        setState(() => _handshakeError = 'Unable to create a secure QR code.');
      }
      debugPrint('QR challenge creation failed: $error');
    }
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
      final state = p.administrativeArea;
      if (state != null && state.isNotEmpty) {
        final parts = [city, formatLocationName(state)];
        if (country != null) parts.add(country);
        return parts.join(', ');
      }
    }

    if (country != null) return '$city, $country';
    return city;
  }

  String? _fallbackHostLocation() {
    final host = widget.profile.hostLocation;
    final city = host.city?.trim();
    final country = host.country?.trim();
    final state = host.state?.trim();

    if (city != null && city.isNotEmpty) {
      if (state != null && state.isNotEmpty) {
        return '$city, $state${country != null && country.isNotEmpty ? ', $country' : ''}';
      }
      if (country != null && country.isNotEmpty) {
        return '$city, $country';
      }
      return city;
    }
    if (country != null && country.isNotEmpty) {
      return country;
    }
    return null;
  }

  Future<String?> _resolveLocationAddress() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return _fallbackHostLocation();
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return _fallbackHostLocation();
      }

      // 1. Try instant last known position first (0ms)
      Position? position = await Geolocator.getLastKnownPosition();

      // 2. If no cached position, query current position with a realistic timeout
      position ??= await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 6),
        ),
      );

      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        final formatted = _formatPlacemarkLocation(placemarks.first);
        if (formatted != null && formatted.isNotEmpty) {
          _cachedAddress = formatted;
          return formatted;
        }
      }
    } catch (e) {
      debugPrint('QR: Location resolution error: $e');
    }

    return _fallbackHostLocation();
  }

  Future<void> _preCacheLocation() async {
    try {
      final address = await _resolveLocationAddress();
      if (address != null && address.isNotEmpty) {
        _cachedAddress = address;
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

          if (fromUid != _lastConnectionUid) {
            _lastConnectionUid = fromUid;

            try {
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
    final token = _handshakeToken;
    if (token == null) return '';
    return Uri.https('diasporanearby.com', '/profile/${widget.profile.uid}', {
      'src': 'qr',
      'qrToken': token,
    }).toString();
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

          final isOurDomain =
              host == 'diasporanearby.com' || host == 'www.diasporanearby.com';

          if (isOurDomain && path.startsWith('/profile/')) {
            if (uri.pathSegments.length < 2) continue;

            final targetUid = uri.pathSegments[1];
            final handshakeToken = uri.queryParameters['qrToken'];
            if (targetUid.isEmpty) continue;
            if (handshakeToken == null || handshakeToken.isEmpty) {
              throw const FormatException(
                'This QR code is missing its secure challenge.',
              );
            }

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

            // [PERF] Never block QR scan on GPS; use pre-cached address or host location fallback in 0ms
            final finalAddress = _cachedAddress ?? _fallbackHostLocation();

            debugPrint(
              'QR: Starting exchange from $currentUid to $targetUid with address: $finalAddress',
            );
            await _performExchange(
              currentUid!,
              targetUid,
              handshakeToken,
              finalAddress,
            );
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
    String handshakeToken,
    String? address,
  ) async {
    try {
      final profileRepo = ref.read(profileRepositoryProvider);
      // Pre-fetch target profile in parallel with QR exchange
      final cachedTarget = profileRepo.getCachedProfile(toUid);
      final targetProfileFuture = cachedTarget != null
          ? Future.value(cachedTarget)
          : profileRepo.getUserProfile(toUid);

      final int earnedPoints = await ref
          .read(trustServiceProvider)
          .performQRExchange(
            fromUid: fromUid,
            toUid: toUid,
            handshakeToken: handshakeToken,
            locationAddress: address,
          );

      if (mounted) {
        final targetProfile = await targetProfileFuture;
        if (!mounted) return;

        // Show Success Dialog
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AlertDialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 24,
              ),
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
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade700,
                      ),
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
                      elevation: 0,
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('View Profile'),
                  ),
                ),
              ],
            ),
          ),
        );

        if (mounted) {
          context.push('/profile/$toUid?src=qr');
          Navigator.pop(context); // Close QR dialog
        }
      }
    } on AlreadyConnectedException catch (e) {
      if (!mounted) return;
      final cached = ref
          .read(profileRepositoryProvider)
          .getCachedProfile(e.otherUid);
      if (cached != null) {
        setState(() {
          _knownConnectionProfile = cached;
        });
        return;
      }
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
        final success = await _showCompleteProfileModal(e.missingFields);
        if (success == true) {
          await _performExchange(fromUid, toUid, handshakeToken, address);
        } else {
          setState(() => _isScanning = true);
          _scannerController.start();
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'The other user needs to complete their profile first. Missing: ${e.missingFields.join(', ')}',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
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
        setState(() => _isScanning = true);
        _scannerController.start();
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<bool?> _showCompleteProfileModal(List<String> missingFields) async {
    // [PERF] Use synchronous cached profile so modal opens in 0ms
    final latestProfile =
        ref.read(userProfileProvider).value ??
        ref
            .read(profileRepositoryProvider)
            .getCachedProfile(_currentProfile.uid!) ??
        _currentProfile;

    if (!mounted) return false;

    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CompleteProfileModal(
        profile: latestProfile,
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
          child: _isCompletingProfile
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 16),
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
                          final profileRepo = ref.read(
                            profileRepositoryProvider,
                          );
                          final profileNotifier = ref.read(
                            userProfileProvider.notifier,
                          );
                          final provisionalProfile = updated.copyWith(
                            profileImage: newImage != null
                                ? newImage.path
                                : updated.profileImage,
                          );

                          // [PERF] Transition to QR view immediately on frame 0 (0ms)
                          if (mounted) {
                            setState(() {
                              _currentProfile = provisionalProfile;
                              _isCompletingProfile = false;
                            });
                            profileRepo.cacheProfile(
                              provisionalProfile.uid!,
                              provisionalProfile,
                            );
                            profileNotifier.updateProfile(provisionalProfile);
                            if (_handshakeToken == null) {
                              _refreshHandshake();
                            }
                          }

                          unawaited(() async {
                            try {
                              String imageUrl = updated.profileImage;
                              if (newImage != null) {
                                imageUrl = await profileRepo.uploadProfileImage(
                                  updated.uid!,
                                  newImage,
                                );
                              }
                              final finalProfile = updated.copyWith(
                                profileImage: imageUrl,
                              );
                              await profileRepo.saveUserProfile(
                                finalProfile.uid!,
                                finalProfile,
                              );
                              profileRepo.cacheProfile(
                                finalProfile.uid!,
                                finalProfile,
                              );
                              profileNotifier.updateProfile(finalProfile);
                            } catch (e) {
                              debugPrint(
                                'Error saving profile in QR dialog: $e',
                              );
                            }
                          }());
                        },
                      ),
                    ),
                  ],
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 16, bottom: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!_isScanning) ...[
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
                          child: _handshakeToken != null
                              ? QrImageView(
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
                                )
                              : SizedBox(
                                  width: 200,
                                  height: 200,
                                  child: Center(
                                    child: _handshakeError == null
                                        ? const CircularProgressIndicator()
                                        : TextButton(
                                            onPressed: _refreshHandshake,
                                            child: Text(_handshakeError!),
                                          ),
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
                        const SizedBox(height: 8),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              LucideIcons.qrCode,
                              size: 14,
                              color: AppTheme.accent,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'In-person handshake • Counts toward 10 QR milestone',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.accent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
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
                      ] else if (_isScanning &&
                          _knownConnectionProfile != null) ...[
                        const SizedBox(height: 12),
                        Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Color(0x14888888),
                                shape: BoxShape.circle,
                              ),
                              child: CircleAvatar(
                                radius: 60,
                                backgroundColor: Colors.grey.shade100,
                                backgroundImage:
                                    _knownConnectionProfile!
                                        .profileImage
                                        .isNotEmpty
                                    ? CachedNetworkImageProvider(
                                        _knownConnectionProfile!.profileImage,
                                      )
                                    : null,
                                child:
                                    _knownConnectionProfile!
                                        .profileImage
                                        .isEmpty
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
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                          ),
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
                        if (_knownConnectionProfile!
                                    .firstQrConnection
                                    ?.locationAddress !=
                                null &&
                            _knownConnectionProfile!
                                .firstQrConnection!
                                .locationAddress!
                                .trim()
                                .isNotEmpty &&
                            _knownConnectionProfile!
                                    .firstQrConnection!
                                    .locationAddress!
                                    .trim()
                                    .toLowerCase() !=
                                'location unavailable') ...[
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
      ),
    );
  }
}
