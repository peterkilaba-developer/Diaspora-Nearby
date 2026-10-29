import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/travel/models/peer_listing.dart';
import 'package:diaspora_nearby/features/travel/services/peer_listing_repository.dart';
import 'package:diaspora_nearby/features/travel/screens/create_stay_listing_screen.dart';
import 'package:diaspora_nearby/features/travel/screens/create_car_listing_screen.dart';
import 'package:diaspora_nearby/features/travel/screens/create_hotel_listing_screen.dart';
import 'package:diaspora_nearby/features/travel/screens/peer_listing_detail_screen.dart';
import 'package:diaspora_nearby/features/travel/widgets/travel_skeleton_loader.dart';

class MyListingsScreen extends ConsumerStatefulWidget {
  final String? filterType; // 'stay', 'car', 'hotel', or null for all

  const MyListingsScreen({super.key, this.filterType});

  @override
  ConsumerState<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends ConsumerState<MyListingsScreen> {
  List<PeerListing>? _listings;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid != null) {
      final cached = ref
          .read(peerListingRepositoryProvider)
          .getCachedMyListings(uid, type: widget.filterType);
      if (cached.isNotEmpty) {
        _listings = cached;
        _isLoading = false;
      }
    }
    _load();
  }

  Future<void> _load() async {
    if (_listings == null || _listings!.isEmpty) {
      setState(() => _isLoading = true);
    }
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final repo = ref.read(peerListingRepositoryProvider);
    final all = await repo.getMyListings(uid);

    if (widget.filterType != null) {
      _listings = all.where((l) => l.type == widget.filterType).toList();
    } else {
      _listings = all;
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _toggleStatus(PeerListing listing) async {
    final repo = ref.read(peerListingRepositoryProvider);
    final prevStatus = listing.status;
    final newStatus = listing.status == 'active' ? 'paused' : 'active';
    setState(() {
      if (_listings != null) {
        _listings = [
          for (final l in _listings!)
            if (l.id == listing.id) l.copyWith(status: newStatus) else l,
        ];
      }
    });
    unawaited(
      repo.toggleListingStatus(listing.id, newStatus).catchError((_) {
        if (mounted) {
          setState(() {
            if (_listings != null) {
              _listings = [
                for (final l in _listings!)
                  if (l.id == listing.id) l.copyWith(status: prevStatus) else l,
              ];
            }
          });
        }
      }),
    );
  }

  Future<void> _deleteListing(PeerListing listing) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
          title: const Text('Delete Listing'),
          content: Text('Delete "${listing.title}"? This cannot be undone.'),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'Delete',
                style: TextStyle(color: Colors.red.shade400),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      final repo = ref.read(peerListingRepositoryProvider);
      final prevListings = _listings != null
          ? List<PeerListing>.from(_listings!)
          : null;
      setState(() {
        _listings?.removeWhere((l) => l.id == listing.id);
      });
      unawaited(
        repo.deleteListing(listing.id).catchError((_) {
          if (mounted && prevListings != null) {
            setState(() => _listings = prevListings);
          }
        }),
      );
    }
  }

  void _createNew() {
    _showTypeChooser();
  }

  void _showTypeChooser() {
    if (widget.filterType == 'stay') {
      _navigateToCreate('stay');
      return;
    }
    if (widget.filterType == 'car') {
      _navigateToCreate('car');
      return;
    }
    if (widget.filterType == 'hotel') {
      _navigateToCreate('hotel');
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.elevationColor(context, 3),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'What would you like to list?',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _typeOption(
                      theme,
                      icon: LucideIcons.home,
                      title: 'Stay / Property',
                      subtitle: 'List an apartment, house, room, or villa',
                      onTap: () {
                        Navigator.pop(ctx);
                        _navigateToCreate('stay');
                      },
                    ),
                    const SizedBox(height: 12),
                    _typeOption(
                      theme,
                      icon: LucideIcons.car,
                      title: 'Car Rental',
                      subtitle: 'List your car for others to rent',
                      onTap: () {
                        Navigator.pop(ctx);
                        _navigateToCreate('car');
                      },
                    ),
                    const SizedBox(height: 12),
                    _typeOption(
                      theme,
                      icon: LucideIcons.hotel,
                      title: 'Hotel',
                      subtitle: 'List your independent hotel or lodge',
                      onTap: () {
                        Navigator.pop(ctx);
                        _navigateToCreate('hotel');
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _typeOption(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.elevationColor(context, 2),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppTheme.accent, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              LucideIcons.chevronRight,
              size: 18,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
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
    if (result == true) _load();
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
    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: const Text('My Listings'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            onPressed: _createNew,
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                LucideIcons.plus,
                size: 18,
                color: AppTheme.accent,
              ),
            ),
            tooltip: 'New Listing',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _isLoading
          ? const TravelSkeletonLoader(label: 'Loading listings...')
          : _listings == null || _listings!.isEmpty
          ? _buildEmptyState(theme)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: EdgeInsets.only(
                  left: 8,
                  right: 8,
                  top: 8,
                  bottom: MediaQuery.of(context).padding.bottom + 16,
                ),
                itemCount: _listings!.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, i) => _buildListingCard(theme, _listings![i]),
              ),
            ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.home,
              size: 56,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.15),
            ),
            const SizedBox(height: 16),
            Text(
              'No listings yet',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'List your property or car for other diaspora members to book.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _createNew,
              icon: const Icon(LucideIcons.plus, size: 16),
              label: const Text('Create Your First Listing'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.accent,
                side: BorderSide.none,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListingCard(ThemeData theme, PeerListing listing) {
    final isActive = listing.status == 'active';
    final isCar = listing.type == 'car';
    final isHotel = listing.type == 'hotel';
    final IconData typeIcon = isHotel
        ? LucideIcons.hotel
        : isCar
        ? LucideIcons.car
        : LucideIcons.home;

    return Container(
      decoration: AppTheme.cardDecoration(context),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PeerListingDetailScreen(listing: listing),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon + Title + Status
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(typeIcon, color: AppTheme.accent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            listing.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            listing.subtitleLabel,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isActive
                            ? Colors.green.withValues(alpha: 0.1)
                            : Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isActive ? 'Active' : 'Paused',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isActive ? Colors.green : Colors.orange,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Price + Location
                Row(
                  children: [
                    Text(
                      listing.priceLabel,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.accent,
                      ),
                    ),
                    const Spacer(),
                    if (listing.locationLabel.isNotEmpty ||
                        (listing.city != null && listing.city!.isNotEmpty))
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.mapPin,
                            size: 12,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.4,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              listing.locationLabel.isNotEmpty
                                  ? listing.locationLabel
                                  : listing.city!,
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.4,
                                ),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: _actionButton(
                        icon: LucideIcons.edit3,
                        label: 'Edit',
                        onTap: () => _navigateToEdit(listing),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _actionButton(
                        icon: isActive ? LucideIcons.pause : LucideIcons.play,
                        label: isActive ? 'Pause' : 'Activate',
                        onTap: () => _toggleStatus(listing),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _actionButton(
                        icon: LucideIcons.trash2,
                        label: 'Delete',
                        onTap: () => _deleteListing(listing),
                        isDestructive: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final color = isDestructive
        ? Colors.red.shade400
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.elevationColor(context, 2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
