import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/travel/models/peer_listing.dart';
import 'package:diaspora_nearby/features/travel/services/peer_listing_repository.dart';
import 'package:diaspora_nearby/features/marketplace/utils/currency_helper.dart';
import 'package:diaspora_nearby/features/shared/widgets/currency_price_display.dart';
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
    // Track view & check saved state
    _recordView();
    _checkSavedState();
    // Load owner bookings lazily after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isOwner) _loadOwnerBookings();
    });
  }

  @override
  void dispose() {
    _imagePageController.dispose();
    _notesC.dispose();
    super.dispose();
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
      title: _isStay ? 'Check-in Date' : 'Pick-up Date',
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
      title: _isStay ? 'Check-out Date' : 'Drop-off Date',
      initialDate: _endDate ?? first,
      firstDate: first,
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null && mounted) {
      setState(() => _endDate = date);
    }
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

      final booking = PeerBooking(
        id: '',
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
        notes: _notesC.text.trim().isEmpty ? null : _notesC.text.trim(),
      );

      await repo.createBooking(booking);

      if (mounted) {
        _showBookingConfirmation();
      }
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

  void _showBookingConfirmation() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
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
                      ' for $_days ${_isStay ? 'night' : 'day'}${_days > 1 ? 's' : ''}',
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
        );
      },
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
                    horizontal: 8,
                    vertical: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Type badge
                      Row(
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
                          const Spacer(),
                          Flexible(
                            child: CurrencyPriceDisplay(
                              amount: listing.pricePerUnit,
                              sellerCountryCode: listing.countryCode,
                              viewerCountryCode: ref
                                  .read(userProfileProvider)
                                  .value
                                  ?.hostCountryCode,
                              priceSuffix: _isHotel || _isStay
                                  ? '/night'
                                  : '/day',
                              showToggle: false,
                              primaryColor: AppTheme.accent,
                              primaryStyle: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.accent,
                              ),
                            ),
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
                      // Hotels skip this because the same info (stars, category,
                      // rooms, guests) is already in the Hotel Details card below.
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
                      onTap: () {
                        // TODO: navigate to full bookings list
                      },
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
            border: Border.all(color: c.withValues(alpha: 0.15)),
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
      // Reload the listing after edit
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
    await repo.toggleListingStatus(listing.id, newStatus);
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
  }

  // ─── Guest Booking Section ────────────────────────────────────────

  Widget _buildGuestBookingSection(ThemeData theme, PeerListing listing) {
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

          // Price summary
          if (_days > 0) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.elevationColor(context, 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _priceRow(
                    theme,
                    listing.priceLabel,
                    '× $_days ${_isStay ? 'night' : 'day'}${_days > 1 ? 's' : ''}',
                  ),
                  const Divider(height: 16),
                  _priceRow(
                    theme,
                    'Total',
                    CurrencyHelper.formatLocalPrice(
                      _totalPrice,
                      listing.countryCode,
                    ),
                    isBold: true,
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

  // Guest stepper now uses shared TravelStepper widget

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
      // Stylish placeholder when no photos
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
        // Photo PageView
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
        // Bottom gradient for readability
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
        // Page indicator dots
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
        // Photo counter badge (top-right, below the status bar area)
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
    // API hotels store dates in checkInTime/checkOutTime,
    // community hotels store actual times (e.g. "15:00").
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
              // Star rating row
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
              // Category — skip for API hotels since chain name
              // already appears in the "Managed by" host section.
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
              // Check-in/out — times for community, dates for API
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
