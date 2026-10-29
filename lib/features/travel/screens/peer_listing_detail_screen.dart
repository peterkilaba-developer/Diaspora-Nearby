import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/core/data/countries.dart' as country_data;
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/dsp/providers/dsp_valuation_provider.dart';
import 'package:diaspora_nearby/features/shared/widgets/country_picker_sheet.dart';
import 'package:diaspora_nearby/features/travel/models/peer_listing.dart';
import 'package:diaspora_nearby/features/travel/services/peer_listing_repository.dart';
import 'package:diaspora_nearby/features/marketplace/utils/currency_helper.dart';
import 'package:diaspora_nearby/features/travel/widgets/smart_date_picker.dart';
import 'package:diaspora_nearby/features/travel/widgets/travel_stepper.dart';
import 'package:diaspora_nearby/features/travel/screens/create_hotel_listing_screen.dart';
import 'package:diaspora_nearby/features/travel/screens/create_car_listing_screen.dart';
import 'package:diaspora_nearby/features/travel/screens/create_stay_listing_screen.dart';
import 'package:diaspora_nearby/features/trust/services/trust_service.dart';

/// Detail screen for a peer-to-peer stay, car, or hotel listing,
/// with booking capability for guests.
class PeerListingDetailScreen extends ConsumerStatefulWidget {
  final PeerListing listing;

  const PeerListingDetailScreen({super.key, required this.listing});

  @override
  ConsumerState<PeerListingDetailScreen> createState() =>
      _PeerListingDetailScreenState();
}

class _PeerListingDetailScreenState
    extends ConsumerState<PeerListingDetailScreen> {
  final _imagePageController = PageController();
  int _currentImageIndex = 0;
  DateTime? _startDate;
  DateTime? _endDate;
  int _guests = 1;
  bool _isBooking = false;
  final _notesC = TextEditingController();

  // ── Guest flexible / host-country address controllers ──
  final _guestAddressC = TextEditingController();
  final _guestCityC = TextEditingController();
  final _guestStateC = TextEditingController();
  final _guestPostalC = TextEditingController();
  String _guestAddressCountryCode = 'US';
  country_data.Country? _guestAddressCountry;
  bool _guestAddressExpanded = false;

  // ── Owner dashboard state ──
  List<PeerBooking>? _ownerBookings;
  bool _dashboardLoading = true;

  // ── Save / engagement state ──
  bool _isSaved = false;

  bool get _isStay => widget.listing.type == 'stay';
  bool get _isHotel => widget.listing.type == 'hotel';
  bool get _isCar => widget.listing.type == 'car';
  bool get _isApiHotel => _isHotel && widget.listing.ownerId == 'amadeus';
  bool get _isOwner {
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    return uid == widget.listing.ownerId;
  }

  int get _days {
    if (_startDate == null || _endDate == null) return 0;
    return _endDate!.difference(_startDate!).inDays;
  }

  double get _totalPrice => _days * widget.listing.pricePerUnit;

  @override
  void initState() {
    super.initState();
    _prefillHotelDates();
    _prefillGuestAddressFromProfile();
    final repo = ref.read(peerListingRepositoryProvider);
    _isSaved = repo.isListingSavedSync(widget.listing.id);
    if (_isOwner) {
      _ownerBookings = repo.getCachedListingBookings(widget.listing.id);
      _dashboardLoading = false;
      _loadOwnerBookings();
    }
    // Track view & check saved state
    _recordView();
    _checkSavedState();
  }

  void _prefillHotelDates() {
    if (!_isHotel) return;
    final checkInRaw = widget.listing.checkInTime;
    final checkOutRaw = widget.listing.checkOutTime;
    if (checkInRaw != null && checkInRaw.contains('-')) {
      _startDate = DateTime.tryParse(checkInRaw);
    }
    if (checkOutRaw != null && checkOutRaw.contains('-')) {
      _endDate = DateTime.tryParse(checkOutRaw);
    }
    if (_startDate != null &&
        (_endDate == null || !_endDate!.isAfter(_startDate!))) {
      _endDate = _startDate!.add(const Duration(days: 1));
    }
  }

  void _prefillGuestAddressFromProfile() {
    final profile = ref.read(userProfileProvider).value;
    if (profile == null) return;
    final hostCode =
        (profile.hostCountryCode ??
                profile.hostLocation.countryCode ??
                profile.homeCountryCode ??
                'US')
            .toUpperCase();
    _guestAddressCountryCode = hostCode;
    _guestAddressCountry = country_data.getCountryByCode(hostCode);
    _guestCityC.text = profile.hostLocation.city ?? '';
    _guestStateC.text = profile.hostLocation.state ?? '';
    if (profile.hostLocation.formattedAddress.isNotEmpty) {
      _guestAddressC.text = profile.hostLocation.formattedAddress;
    }
  }

  @override
  void dispose() {
    _imagePageController.dispose();
    _notesC.dispose();
    _guestAddressC.dispose();
    _guestCityC.dispose();
    _guestStateC.dispose();
    _guestPostalC.dispose();
    super.dispose();
  }

  /// Resolves the 2-letter ISO country code of the hotel/listing location.
  String _resolvedListingCountryCode(PeerListing listing) {
    if (listing.countryCode != null &&
        listing.countryCode!.trim().length == 2) {
      return listing.countryCode!.trim().toUpperCase();
    }
    final candidates = <String>[
      if (listing.country != null) listing.country!,
      if (listing.address != null) listing.address!,
      listing.locationLabel,
    ];
    for (final raw in candidates) {
      final lower = raw.trim().toLowerCase();
      if (lower.isEmpty) continue;
      for (final c in country_data.countries) {
        if (lower == c.name.toLowerCase() ||
            lower.endsWith(c.name.toLowerCase()) ||
            lower.contains(c.name.toLowerCase())) {
          return c.code.toUpperCase();
        }
      }
    }
    final homeCc = ref.read(userProfileProvider).value?.homeCountryCode;
    if (homeCc != null && homeCc.trim().length == 2) {
      return homeCc.trim().toUpperCase();
    }
    return 'US';
  }

  /// Resolves the base country code in which [listing.pricePerUnit] is stored.
  String _baseCurrencyCountryCode(
    PeerListing listing,
    String hotelLocationCountryCode,
  ) {
    if (_isApiHotel &&
        listing.currency.toUpperCase() == 'USD' &&
        hotelLocationCountryCode != 'US') {
      return 'US';
    }
    return hotelLocationCountryCode;
  }

  /// Record a view for this listing.
  void _recordView() {
    final listing = widget.listing;
    // Skip API hotels and own listings
    if (listing.id.startsWith('api_') || listing.id.startsWith('mock_')) return;
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid == null || uid == listing.ownerId) return;
    try {
      ref.read(peerListingRepositoryProvider).incrementViewCount(listing.id);
    } catch (_) {}
  }

  /// Check if user has saved this listing.
  Future<void> _checkSavedState() async {
    final listing = widget.listing;
    if (listing.id.startsWith('api_') || listing.id.startsWith('mock_')) return;
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid == null) return;
    try {
      final saved = await ref
          .read(peerListingRepositoryProvider)
          .isListingSaved(listing.id, uid);
      if (mounted) setState(() => _isSaved = saved);
    } catch (_) {}
  }

  /// Toggle save state.
  Future<void> _toggleSave() async {
    final listing = widget.listing;
    if (listing.id.startsWith('api_') || listing.id.startsWith('mock_')) return;
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid == null) return;
    setState(() => _isSaved = !_isSaved);
    try {
      final repo = ref.read(peerListingRepositoryProvider);
      if (_isSaved) {
        await repo.saveListing(listing.id, uid);
      } else {
        await repo.unsaveListing(listing.id, uid);
      }
    } catch (_) {
      if (mounted) setState(() => _isSaved = !_isSaved);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isSaved ? 'Listing saved!' : 'Removed from saved'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _loadOwnerBookings() async {
    final repo = ref.read(peerListingRepositoryProvider);
    final bookings = await repo.getListingBookings(widget.listing.id);
    if (mounted) {
      setState(() {
        _ownerBookings = bookings;
        _dashboardLoading = false;
      });
    }
  }

  String _formatDate(DateTime dt) => '${dt.month}/${dt.day}/${dt.year}';

  Future<void> _pickStartDate() async {
    final date = await SmartDatePicker.show(
      context: context,
      title: (_isStay || _isHotel) ? 'Check-in Date' : 'Pick-up Date',
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null && mounted) {
      setState(() {
        _startDate = date;
        if (_endDate != null && _endDate!.isBefore(date)) {
          _endDate = date.add(const Duration(days: 1));
        }
      });
    }
  }

  Future<void> _pickEndDate() async {
    final first =
        _startDate?.add(const Duration(days: 1)) ??
        DateTime.now().add(const Duration(days: 1));
    final date = await SmartDatePicker.show(
      context: context,
      title: (_isStay || _isHotel) ? 'Check-out Date' : 'Drop-off Date',
      initialDate: _endDate ?? first,
      firstDate: first,
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null && mounted) {
      setState(() => _endDate = date);
    }
  }

  void _pickGuestAddressCountry() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      backgroundColor: Colors.transparent,
      builder: (_) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: CountryPickerSheet(
            selectedCountry: _guestAddressCountry,
            showDialCode: false,
            onCountrySelected: (country) {
              Navigator.pop(context);
              setState(() {
                _guestAddressCountry = country;
                _guestAddressCountryCode = country.code.toUpperCase();
              });
            },
          ),
        ),
      ),
    );
  }

  String _postalLabelForCountry(String countryCode) {
    switch (countryCode.toUpperCase()) {
      case 'US':
        return 'ZIP Code';
      case 'GB':
      case 'AU':
      case 'NZ':
      case 'ZA':
        return 'Postcode';
      case 'CA':
        return 'Postal Code';
      case 'IN':
        return 'PIN Code';
      case 'IE':
        return 'Eircode';
      default:
        return 'Postal Code / P.O. Box (optional)';
    }
  }

  String _composeGuestAddressSummary() {
    final parts = <String>[
      _guestAddressC.text.trim(),
      _guestCityC.text.trim(),
      _guestStateC.text.trim(),
      _guestPostalC.text.trim(),
      _guestAddressCountry?.name ?? _guestAddressCountryCode,
    ].where((s) => s.isNotEmpty).toList();
    return parts.join(', ');
  }

  Future<void> _book() async {
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select dates'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_isHotel) {
      await _showHotelBookingComingSoonDialog();
      return;
    }

    setState(() => _isBooking = true);

    try {
      final user = ref.read(authRepositoryProvider).currentUser;
      final profile = ref.read(userProfileProvider).value;
      if (user == null || profile == null) throw Exception('Not logged in');

      if (widget.listing.isPeerHosting) {
        final trustData = ref.read(userTrustProvider(user.uid)).value;
        if (trustData == null || trustData.trustScore < 91) {
          throw Exception(
            'You need a Trust Score of 91+ to book a free Peer Hosting stay.',
          );
        }
      }

      final repo = ref.read(peerListingRepositoryProvider);
      final combinedNotes = <String>[
        if (_notesC.text.trim().isNotEmpty) _notesC.text.trim(),
        if (_composeGuestAddressSummary().isNotEmpty)
          'Guest Address: ${_composeGuestAddressSummary()}',
      ].join('\n');

      final bookingId = repo.generateBookingId();
      final booking = PeerBooking(
        id: bookingId,
        listingId: widget.listing.id,
        listingType: widget.listing.type,
        listingTitle: widget.listing.title,
        guestId: user.uid,
        guestName: profile.fullName,
        guestPhone: profile.phone,
        hostId: widget.listing.ownerId,
        hostName: widget.listing.ownerName,
        startDate: _startDate!,
        endDate: _endDate!,
        guests: _guests,
        totalPrice: _totalPrice,
        notes: combinedNotes.isEmpty ? null : combinedNotes,
      );

      repo.cacheBooking(booking);

      if (mounted) {
        setState(() => _isBooking = false);
        _showBookingConfirmation();
      }

      unawaited(
        repo.createBooking(booking).catchError((e) {
          debugPrint('Booking background persist failed: $e');
          return bookingId;
        }),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Booking failed: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isBooking = false);
    }
  }

  Future<void> _showHotelBookingComingSoonDialog() async {
    final theme = Theme.of(context);
    final profile = ref.read(userProfileProvider).value;
    final valuation = ref.read(dspValuationProvider);
    final guestCountryCode = (profile?.hostCountryCode ?? 'US').toUpperCase();
    final hotelCountryCode = _resolvedListingCountryCode(widget.listing);
    final baseCountryCode = _baseCurrencyCountryCode(
      widget.listing,
      hotelCountryCode,
    );

    final guestTotal = CurrencyHelper.convertCurrency(
      _totalPrice,
      baseCountryCode,
      guestCountryCode,
    );
    final localTotal = CurrencyHelper.convertCurrency(
      _totalPrice,
      baseCountryCode,
      hotelCountryCode,
    );
    final guestTotalFormatted =
        '${CurrencyHelper.currencySymbol(guestCountryCode)} ${CurrencyHelper.formatFiatAmount(guestTotal)}';
    final localTotalFormatted =
        '${CurrencyHelper.currencySymbol(hotelCountryCode)} ${CurrencyHelper.formatFiatAmount(localTotal)}';
    final diasporaTotalFormatted = CurrencyHelper.formatDiasporaTokenPrice(
      localTotal,
      hotelCountryCode,
      dspPriceFloorUsd: valuation.impliedValueUsd,
    );

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (dialogContext) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
          backgroundColor: AppTheme.elevationColor(context, 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.accent.withValues(alpha: 0.14),
                  ),
                  child: const Icon(
                    LucideIcons.hotel,
                    color: AppTheme.accent,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'COMING SOON',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.accent,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Booking Coming Soon',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Live hotel discovery and room rates are active! Direct in-app hotel reservations are launching soon — you have not been charged.',
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    height: 1.45,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.elevationColor(context, 2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      _dialogSummaryRow(
                        theme,
                        LucideIcons.building2,
                        widget.listing.title,
                      ),
                      if (_startDate != null && _endDate != null)
                        _dialogSummaryRow(
                          theme,
                          LucideIcons.calendar,
                          '${_formatDate(_startDate!)} → ${_formatDate(_endDate!)} · $_days night${_days > 1 ? 's' : ''}',
                        ),
                      _dialogSummaryRow(
                        theme,
                        LucideIcons.users,
                        '$_guests guest${_guests > 1 ? 's' : ''}',
                      ),
                      _dialogSummaryRow(
                        theme,
                        LucideIcons.tag,
                        '$guestTotalFormatted  ·  ≈ $localTotalFormatted  ·  ≈ $diasporaTotalFormatted',
                        isLast: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Done',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dialogSummaryRow(
    ThemeData theme,
    IconData icon,
    String text, {
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              icon,
              size: 14,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showBookingConfirmation() {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: AlertDialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            backgroundColor: AppTheme.elevationColor(context, 3),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    LucideIcons.checkCircle,
                    color: Colors.green,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Booking Request Sent!',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your request has been sent to ${widget.listing.ownerName}. You\'ll be notified once they confirm.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.elevationColor(context, 2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        CurrencyHelper.formatLocalPrice(
                          _totalPrice,
                          widget.listing.countryCode,
                        ),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.accent,
                        ),
                      ),
                      Text(
                        ' for $_days ${(_isStay || _isHotel) ? 'night' : 'day'}${_days > 1 ? 's' : ''}',
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Builds the 3-tier price display block for the detail screen header:
  /// 1. Guest Host Currency (primary)
  /// 2. Hotel/Listing Location Local Fiat
  /// 3. $DIASPORA token equivalent
  Widget _buildThreePriceHeaderBlock(ThemeData theme, PeerListing listing) {
    final profile = ref.watch(userProfileProvider).value;
    final valuation = ref.watch(dspValuationProvider);
    final suffix = (_isHotel || _isStay) ? '/night' : '/day';

    final guestCountryCode = (profile?.hostCountryCode ?? 'US').toUpperCase();
    final hotelCountryCode = _resolvedListingCountryCode(listing);
    final baseCountryCode = _baseCurrencyCountryCode(listing, hotelCountryCode);

    final guestAmount = CurrencyHelper.convertCurrency(
      listing.pricePerUnit,
      baseCountryCode,
      guestCountryCode,
    );
    final localFiatAmount = CurrencyHelper.convertCurrency(
      listing.pricePerUnit,
      baseCountryCode,
      hotelCountryCode,
    );

    final guestFormatted =
        '${CurrencyHelper.currencySymbol(guestCountryCode)} ${CurrencyHelper.formatFiatAmount(guestAmount)}$suffix';
    final localFormatted =
        '≈ ${CurrencyHelper.currencySymbol(hotelCountryCode)} ${CurrencyHelper.formatFiatAmount(localFiatAmount)}$suffix';
    final diasporaFormatted =
        '≈ ${CurrencyHelper.formatDiasporaTokenPrice(localFiatAmount, hotelCountryCode, dspPriceFloorUsd: valuation.impliedValueUsd)}$suffix';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. Guest Host Currency (Primary)
        Text(
          guestFormatted,
          textAlign: TextAlign.end,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppTheme.accent,
          ),
        ),
        const SizedBox(height: 3),
        // 2. Hotel Location Local Fiat
        Text(
          localFormatted,
          textAlign: TextAlign.end,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
          ),
        ),
        const SizedBox(height: 2),
        // 3. Diaspora Token
        Text(
          diasporaFormatted,
          textAlign: TextAlign.end,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.accent.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final listing = widget.listing;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── Hero Image Carousel SliverAppBar ──
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            stretch: true,
            backgroundColor: AppTheme.elevationColor(context, 1),
            leading: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(
                  Icons.arrow_back,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            actions: [
              if (!widget.listing.id.startsWith('api_') &&
                  !widget.listing.id.startsWith('mock_'))
                Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                      _isSaved ? Icons.bookmark : Icons.bookmark_border,
                      color: _isSaved ? AppTheme.accent : Colors.white,
                      size: 20,
                    ),
                    onPressed: _toggleSave,
                    tooltip: _isSaved ? 'Remove from saved' : 'Save listing',
                  ),
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _buildHeroCarousel(theme, listing),
            ),
            title: null,
          ),
          // ── Content ──
          SliverPadding(
            padding: EdgeInsets.only(
              left: 8,
              right: 8,
              top: 12,
              bottom: MediaQuery.of(context).padding.bottom + 16,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Header card
                Container(
                  decoration: AppTheme.cardDecoration(context),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Type badge + 3-price block
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.accent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _isHotel
                                      ? LucideIcons.hotel
                                      : _isStay
                                      ? LucideIcons.home
                                      : LucideIcons.car,
                                  size: 14,
                                  color: AppTheme.accent,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _isApiHotel
                                      ? 'Partner Hotel'
                                      : _isHotel
                                      ? 'Community Hotel'
                                      : _isStay
                                      ? (listing.isPeerHosting
                                            ? 'Peer Hosting'
                                            : (listing.propertyType ?? 'Stay'))
                                      : 'Car Rental',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.accent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildThreePriceHeaderBlock(theme, listing),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Title
                      Text(
                        listing.title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      // Subtitle — shown for stays & cars only.
                      if (!_isHotel && listing.subtitleLabel.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          listing.subtitleLabel,
                          style: TextStyle(
                            fontSize: 14,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                      ],

                      // Location
                      if (listing.locationLabel.isNotEmpty ||
                          (listing.city != null &&
                              listing.city!.isNotEmpty)) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(
                              LucideIcons.mapPin,
                              size: 14,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.4,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                listing.locationLabel.isNotEmpty
                                    ? [listing.locationLabel, listing.country]
                                          .where(
                                            (s) => s != null && s.isNotEmpty,
                                          )
                                          .join(', ')
                                    : [
                                            listing.address,
                                            listing.city,
                                            listing.country,
                                          ]
                                          .where(
                                            (s) => s != null && s.isNotEmpty,
                                          )
                                          .join(', '),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Description / About
                Container(
                  decoration: AppTheme.cardDecoration(context),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionLabel(theme, 'About'),
                      const SizedBox(height: 8),
                      if (listing.description.isNotEmpty)
                        Text(
                          listing.description,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.7,
                            ),
                          ),
                        )
                      else
                        Text(
                          _isOwner
                              ? 'No description added yet. Edit your listing to add one.'
                              : 'No description available.',
                          style: TextStyle(
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.35,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Hotel details section
                if (_isHotel) _buildHotelDetails(theme, listing),

                // Stay amenities, Hotel amenities, or Car features
                _buildAmenitiesSection(theme, listing),
                const SizedBox(height: 12),

                // Host info
                Container(
                  decoration: AppTheme.cardDecoration(context),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundImage:
                            !_isApiHotel && listing.ownerPhoto.isNotEmpty
                            ? NetworkImage(listing.ownerPhoto)
                            : null,
                        backgroundColor: AppTheme.accent.withValues(alpha: 0.1),
                        child: (_isApiHotel || listing.ownerPhoto.isEmpty)
                            ? Icon(
                                _isApiHotel
                                    ? LucideIcons.building2
                                    : LucideIcons.user,
                                size: 18,
                                color: AppTheme.accent,
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isApiHotel
                                  ? 'Managed by'
                                  : _isHotel
                                  ? 'Owned by'
                                  : _isStay
                                  ? 'Hosted by'
                                  : 'Listed by',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.4,
                                ),
                              ),
                            ),
                            Text(
                              listing.ownerName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!_isOwner)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                LucideIcons.messageCircle,
                                size: 14,
                                color: AppTheme.accent,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Message',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.accent,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),

                // ── Owner Dashboard OR Guest Booking ────────────────
                if (_isOwner) ...[
                  const SizedBox(height: 12),
                  _buildOwnerDashboard(theme, listing),
                ] else ...[
                  const SizedBox(height: 12),
                  _buildGuestBookingSection(theme, listing),
                ],

                SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Owner Dashboard ──────────────────────────────────────────────

  Widget _buildOwnerDashboard(ThemeData theme, PeerListing listing) {
    final bookings = _ownerBookings ?? [];
    final pending = bookings.where((b) => b.status == 'pending').length;
    final confirmed = bookings.where((b) => b.status == 'confirmed').length;
    final totalRevenue = bookings
        .where((b) => b.status == 'confirmed' || b.status == 'completed')
        .fold(0.0, (sum, b) => sum + b.totalPrice);
    final typeLabel = _isHotel
        ? 'Hotel'
        : _isStay
        ? 'Stay'
        : 'Car';

    return Column(
      children: [
        // ── Stats Overview ──
        Container(
          decoration: AppTheme.cardDecoration(context),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionLabel(theme, 'Dashboard'),
              const SizedBox(height: 14),
              if (_dashboardLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.accent,
                    ),
                  ),
                )
              else
                Row(
                  children: [
                    _statTile(
                      theme,
                      icon: LucideIcons.calendarCheck,
                      value: '${bookings.length}',
                      label: 'Total\nBookings',
                    ),
                    _statTile(
                      theme,
                      icon: LucideIcons.clock,
                      value: '$pending',
                      label: 'Pending',
                      color: const Color(0xFFF59E0B),
                    ),
                    _statTile(
                      theme,
                      icon: LucideIcons.checkCircle,
                      value: '$confirmed',
                      label: 'Confirmed',
                      color: const Color(0xFF22C55E),
                    ),
                    _statTile(
                      theme,
                      icon: LucideIcons.wallet,
                      value: CurrencyHelper.formatLocalPrice(
                        totalRevenue,
                        listing.countryCode,
                      ),
                      label: 'Revenue',
                      color: AppTheme.accent,
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Quick Actions ──
        Container(
          decoration: AppTheme.cardDecoration(context),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionLabel(theme, 'Quick Actions'),
              const SizedBox(height: 14),
              Row(
                children: [
                  _actionButton(
                    theme,
                    icon: LucideIcons.pencil,
                    label: 'Edit',
                    onTap: () => _navigateToEdit(listing),
                  ),
                  const SizedBox(width: 8),
                  _actionButton(
                    theme,
                    icon: LucideIcons.plusCircle,
                    label: 'Add $typeLabel',
                    onTap: () => _navigateToCreate(listing.type),
                  ),
                  const SizedBox(width: 8),
                  _actionButton(
                    theme,
                    icon: listing.status == 'active'
                        ? LucideIcons.pauseCircle
                        : LucideIcons.playCircle,
                    label: listing.status == 'active' ? 'Pause' : 'Activate',
                    color: listing.status == 'active'
                        ? const Color(0xFFF59E0B)
                        : const Color(0xFF22C55E),
                    onTap: () => _toggleListingStatus(listing),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Recent Bookings ──
        Container(
          decoration: AppTheme.cardDecoration(context),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: _sectionLabel(theme, 'Recent Bookings')),
                  if (bookings.isNotEmpty)
                    GestureDetector(
                      onTap: () {},
                      child: Text(
                        'View All',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.accent.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (_dashboardLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.accent,
                    ),
                  ),
                )
              else if (bookings.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 24,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.elevationColor(context, 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        LucideIcons.inbox,
                        size: 32,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No bookings yet',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.35,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Bookings will appear here when guests request to book',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ...bookings.take(5).map((b) => _bookingTile(theme, b)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statTile(
    ThemeData theme, {
    required IconData icon,
    required String value,
    required String label,
    Color? color,
  }) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          color: AppTheme.elevationColor(context, 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color ?? AppTheme.accent),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: color ?? theme.colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final c = color ?? AppTheme.accent;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: c),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: c,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bookingTile(ThemeData theme, PeerBooking booking) {
    final statusColors = {
      'pending': const Color(0xFFF59E0B),
      'confirmed': const Color(0xFF22C55E),
      'cancelled': const Color(0xFFEF4444),
      'completed': const Color(0xFF3B82F6),
    };
    final statusColor = statusColors[booking.status] ?? AppTheme.accent;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.elevationColor(context, 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Icon(LucideIcons.user, size: 18, color: statusColor),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  booking.guestName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_formatDate(booking.startDate)} → ${_formatDate(booking.endDate)}  •  ${booking.nights} night${booking.nights > 1 ? 's' : ''}',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              booking.status[0].toUpperCase() + booking.status.substring(1),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToEdit(PeerListing listing) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) {
          if (listing.type == 'hotel') {
            return CreateHotelListingScreen(existing: listing);
          }
          if (listing.type == 'car') {
            return CreateCarListingScreen(existing: listing);
          }
          return CreateStayListingScreen(existing: listing);
        },
      ),
    );
    if (result == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  void _navigateToCreate(String type) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) {
          if (type == 'hotel') return const CreateHotelListingScreen();
          if (type == 'car') return const CreateCarListingScreen();
          return const CreateStayListingScreen();
        },
      ),
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('New listing created!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _toggleListingStatus(PeerListing listing) async {
    final repo = ref.read(peerListingRepositoryProvider);
    final newStatus = listing.status == 'active' ? 'paused' : 'active';
    repo.cacheListing(listing.copyWith(status: newStatus));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Listing ${newStatus == 'active' ? 'activated' : 'paused'}',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, true);
    }
    unawaited(repo.toggleListingStatus(listing.id, newStatus));
  }

  // ─── Guest Booking Section ────────────────────────────────────────

  Widget _buildGuestBookingSection(ThemeData theme, PeerListing listing) {
    final profile = ref.watch(userProfileProvider).value;
    final valuation = ref.watch(dspValuationProvider);
    final guestCountryCode = (profile?.hostCountryCode ?? 'US').toUpperCase();
    final hotelCountryCode = _resolvedListingCountryCode(listing);
    final baseCountryCode = _baseCurrencyCountryCode(listing, hotelCountryCode);

    final unitGuestAmount = CurrencyHelper.convertCurrency(
      listing.pricePerUnit,
      baseCountryCode,
      guestCountryCode,
    );
    final totalGuestAmount = CurrencyHelper.convertCurrency(
      _totalPrice,
      baseCountryCode,
      guestCountryCode,
    );
    final totalLocalAmount = CurrencyHelper.convertCurrency(
      _totalPrice,
      baseCountryCode,
      hotelCountryCode,
    );
    final suffix = (_isStay || _isHotel) ? '/night' : '/day';

    final hasState = country_data.hasStateLevelHierarchyFromData(
      _guestAddressCountryCode,
    );
    final stateTerm = country_data.getStateTerminology(
      _guestAddressCountryCode,
    );
    final postalLabel = _postalLabelForCountry(_guestAddressCountryCode);
    final inputDecoration = InputDecoration(
      filled: true,
      fillColor: AppTheme.elevationColor(context, 2),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );

    return Container(
      decoration: AppTheme.cardDecoration(context),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(
            theme,
            _isHotel
                ? 'Book this hotel'
                : _isStay
                ? 'Book this stay'
                : 'Rent this car',
          ),
          const SizedBox(height: 14),

          // Date pickers
          Row(
            children: [
              Expanded(
                child: _dateButton(
                  theme,
                  label: (_isStay || _isHotel) ? 'Check-in' : 'Pick-up',
                  value: _startDate != null
                      ? _formatDate(_startDate!)
                      : 'Select',
                  onTap: _pickStartDate,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  LucideIcons.arrowRight,
                  size: 16,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                ),
              ),
              Expanded(
                child: _dateButton(
                  theme,
                  label: (_isStay || _isHotel) ? 'Check-out' : 'Drop-off',
                  value: _endDate != null ? _formatDate(_endDate!) : 'Select',
                  onTap: _pickEndDate,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Guests (for stays and hotels)
          if (_isStay || _isHotel)
            TravelStepper(
              label: 'Guests',
              icon: LucideIcons.users,
              value: _guests,
              min: 1,
              max: listing.maxGuests ?? 10,
              onChanged: (v) => setState(() => _guests = v),
            ),
          if (_isStay || _isHotel) const SizedBox(height: 12),

          // Flexible Host-Country Guest Address Section
          Container(
            decoration: BoxDecoration(
              color: AppTheme.elevationColor(context, 2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                InkWell(
                  onTap: () => setState(
                    () => _guestAddressExpanded = !_guestAddressExpanded,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          LucideIcons.mapPin,
                          size: 16,
                          color: AppTheme.accent,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Guest Address (${_guestAddressCountry?.flag ?? ''} ${_guestAddressCountry?.name ?? _guestAddressCountryCode})',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _composeGuestAddressSummary().isNotEmpty
                                    ? _composeGuestAddressSummary()
                                    : 'Tap to enter your address',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.55,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          _guestAddressExpanded
                              ? LucideIcons.chevronUp
                              : LucideIcons.chevronDown,
                          size: 16,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_guestAddressExpanded)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Column(
                      children: [
                        // Country selector
                        InkWell(
                          onTap: _pickGuestAddressCountry,
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.elevationColor(context, 1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  _guestAddressCountry?.flag ?? '🌍',
                                  style: const TextStyle(fontSize: 18),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _guestAddressCountry?.name ??
                                        _guestAddressCountryCode,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Text(
                                  'Change Country',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.accent.withValues(
                                      alpha: 0.85,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _guestAddressC,
                          textCapitalization: TextCapitalization.words,
                          onChanged: (_) => setState(() {}),
                          decoration: inputDecoration.copyWith(
                            fillColor: AppTheme.elevationColor(context, 1),
                            hintText:
                                'Street Address / Area / Landmark (flexible)',
                          ),
                          style: const TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _guestCityC,
                                textCapitalization: TextCapitalization.words,
                                onChanged: (_) => setState(() {}),
                                decoration: inputDecoration.copyWith(
                                  fillColor: AppTheme.elevationColor(
                                    context,
                                    1,
                                  ),
                                  hintText: 'City / Town',
                                ),
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            if (hasState) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  controller: _guestStateC,
                                  textCapitalization: TextCapitalization.words,
                                  onChanged: (_) => setState(() {}),
                                  decoration: inputDecoration.copyWith(
                                    fillColor: AppTheme.elevationColor(
                                      context,
                                      1,
                                    ),
                                    hintText: stateTerm,
                                  ),
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _guestPostalC,
                          textCapitalization: TextCapitalization.characters,
                          onChanged: (_) => setState(() {}),
                          decoration: inputDecoration.copyWith(
                            fillColor: AppTheme.elevationColor(context, 1),
                            hintText: postalLabel,
                          ),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Notes
          TextFormField(
            controller: _notesC,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Any special requests? (optional)',
              filled: true,
              fillColor: AppTheme.elevationColor(context, 2),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
          const SizedBox(height: 16),

          // Price summary (shows all 3 currencies: Guest Host, Location Local Fiat, and Diaspora)
          if (_days > 0) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.elevationColor(context, 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _priceRow(
                    theme,
                    '${CurrencyHelper.currencySymbol(guestCountryCode)} ${CurrencyHelper.formatFiatAmount(unitGuestAmount)}$suffix',
                    '× $_days ${(_isStay || _isHotel) ? 'night' : 'day'}${_days > 1 ? 's' : ''}',
                  ),
                  const Divider(height: 16),
                  _priceRow(
                    theme,
                    'Total',
                    '${CurrencyHelper.currencySymbol(guestCountryCode)} ${CurrencyHelper.formatFiatAmount(totalGuestAmount)}',
                    isBold: true,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '≈ ${CurrencyHelper.currencySymbol(hotelCountryCode)} ${CurrencyHelper.formatFiatAmount(totalLocalAmount)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '≈ ${CurrencyHelper.formatDiasporaTokenPrice(totalLocalAmount, hotelCountryCode, dspPriceFloorUsd: valuation.impliedValueUsd)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.accent.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Book button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isBooking || _days <= 0 ? null : _book,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppTheme.accent.withValues(alpha: 0.3),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: _isBooking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      _isHotel || _isStay
                          ? 'Request to Book'
                          : 'Request to Rent',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(ThemeData theme, String text) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppTheme.accent,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _dateButton(
    ThemeData theme, {
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        decoration: BoxDecoration(
          color: AppTheme.elevationColor(context, 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  LucideIcons.calendar,
                  size: 14,
                  color: AppTheme.accent,
                ),
                const SizedBox(width: 6),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: value == 'Select'
                        ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _priceRow(
    ThemeData theme,
    String label,
    String value, {
    bool isBold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isBold ? 15 : 13,
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w500,
            color: isBold
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isBold ? 16 : 13,
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w500,
            color: isBold
                ? AppTheme.accent
                : theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  // ─── Amenities / Features section ─────────────────────────────────

  Widget _buildAmenitiesSection(ThemeData theme, PeerListing listing) {
    final isStayOrHotel = _isStay || _isHotel;
    final label = isStayOrHotel ? 'Amenities' : 'Features';
    final items = isStayOrHotel ? listing.amenities : listing.features;
    final hasItems = items != null && items.isNotEmpty;

    return Container(
      decoration: AppTheme.cardDecoration(context),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(theme, label),
          const SizedBox(height: 10),
          if (hasItems)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: items
                  .map(
                    (a) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.elevationColor(context, 2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isHotel) ...[
                            Icon(
                              _amenityIcon(a),
                              size: 12,
                              color: AppTheme.accent.withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            a,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            )
          else
            Text(
              _isOwner
                  ? 'No $label added yet. Edit your listing to add some.'
                  : 'No $label listed.',
              style: TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Hero image carousel (SliverAppBar) ──────────────────────────

  Widget _buildHeroCarousel(ThemeData theme, PeerListing listing) {
    if (listing.photos.isEmpty) {
      return Container(
        color: AppTheme.elevationColor(context, 2),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isHotel
                    ? LucideIcons.hotel
                    : _isCar
                    ? LucideIcons.car
                    : LucideIcons.home,
                size: 56,
                color: AppTheme.accent.withValues(alpha: 0.25),
              ),
              const SizedBox(height: 12),
              Text(
                'No photos yet',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _imagePageController,
          itemCount: listing.photos.length,
          onPageChanged: (i) => setState(() => _currentImageIndex = i),
          itemBuilder: (_, i) => CachedNetworkImage(
            imageUrl: listing.photos[i],
            fit: BoxFit.cover,
            width: double.infinity,
            placeholder: (_, _) => Container(
              color: AppTheme.elevationColor(context, 2),
              child: const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.accent,
                ),
              ),
            ),
            errorWidget: (_, _, _) => Container(
              color: AppTheme.accent.withValues(alpha: 0.08),
              child: const Center(
                child: Icon(
                  LucideIcons.imageOff,
                  size: 40,
                  color: AppTheme.accent,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 120,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.6),
                ],
              ),
            ),
          ),
        ),
        if (listing.photos.length > 1)
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                listing.photos.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: i == _currentImageIndex ? 20 : 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: i == _currentImageIndex
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
        if (listing.photos.length > 1)
          Positioned(
            bottom: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    LucideIcons.image,
                    size: 12,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${_currentImageIndex + 1}/${listing.photos.length}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ─── Hotel details card ──────────────────────────────────────────

  Widget _buildHotelDetails(ThemeData theme, PeerListing listing) {
    final isTimeFormat =
        listing.checkInTime != null && !listing.checkInTime!.contains('-');

    return Column(
      children: [
        Container(
          decoration: AppTheme.cardDecoration(context),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionLabel(theme, 'Hotel Details'),
              const SizedBox(height: 12),
              if (listing.starRating != null && listing.starRating! > 0)
                _hotelInfoRow(
                  theme,
                  LucideIcons.star,
                  'Rating',
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      listing.starRating!,
                      (_) => const Padding(
                        padding: EdgeInsets.only(right: 2),
                        child: Icon(
                          LucideIcons.star,
                          size: 14,
                          color: Colors.amber,
                        ),
                      ),
                    ),
                  ),
                ),
              if (listing.hotelCategory != null && !_isApiHotel)
                _hotelInfoRowText(
                  theme,
                  LucideIcons.tag,
                  'Category',
                  listing.hotelCategory!,
                ),
              if (listing.beds != null)
                _hotelInfoRowText(
                  theme,
                  LucideIcons.bedDouble,
                  _isApiHotel ? 'Beds' : 'Rooms',
                  '${listing.beds} ${listing.beds! > 1 ? (_isApiHotel ? 'beds' : 'rooms') : (_isApiHotel ? 'bed' : 'room')}',
                ),
              if (listing.maxGuests != null)
                _hotelInfoRowText(
                  theme,
                  LucideIcons.users,
                  'Max Guests',
                  '${listing.maxGuests}',
                ),
              if (listing.checkInTime != null && isTimeFormat)
                _hotelInfoRowText(
                  theme,
                  LucideIcons.logIn,
                  'Check-in',
                  listing.checkInTime!,
                ),
              if (listing.checkOutTime != null && isTimeFormat)
                _hotelInfoRowText(
                  theme,
                  LucideIcons.logOut,
                  'Check-out',
                  listing.checkOutTime!,
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _hotelInfoRow(
    ThemeData theme,
    IconData icon,
    String label,
    Widget trailing,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Align(alignment: Alignment.centerRight, child: trailing),
          ),
        ],
      ),
    );
  }

  Widget _hotelInfoRowText(
    ThemeData theme,
    IconData icon,
    String label,
    String value,
  ) {
    return _hotelInfoRow(
      theme,
      icon,
      label,
      Text(
        value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.end,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }

  IconData _amenityIcon(String amenity) {
    switch (amenity.toLowerCase()) {
      case 'wi-fi':
      case 'wifi':
        return LucideIcons.wifi;
      case 'pool':
        return LucideIcons.waves;
      case 'spa':
        return LucideIcons.sparkles;
      case 'gym':
        return LucideIcons.dumbbell;
      case 'restaurant':
        return LucideIcons.utensils;
      case 'room service':
        return LucideIcons.bellRing;
      case 'bar / lounge':
      case 'bar':
        return LucideIcons.wine;
      case 'parking':
        return LucideIcons.car;
      case 'airport shuttle':
        return LucideIcons.plane;
      case 'ac':
        return LucideIcons.thermometer;
      case 'laundry':
        return LucideIcons.shirt;
      default:
        return LucideIcons.checkCircle;
    }
  }
}
