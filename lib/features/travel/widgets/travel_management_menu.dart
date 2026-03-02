import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/travel/screens/my_bookings_screen.dart';
import 'package:diaspora_nearby/features/travel/screens/saved_travels_screen.dart';
import 'package:diaspora_nearby/features/travel/screens/travel_history_screen.dart';
import 'package:diaspora_nearby/features/travel/screens/loyalty_rewards_screen.dart';
import 'package:diaspora_nearby/features/travel/screens/my_listings_screen.dart';
import 'package:diaspora_nearby/features/travel/screens/host_bookings_screen.dart';

/// Three-dot menu shown in travel page AppBars.
/// Opens management options for travelers.
class TravelManagementMenu extends StatelessWidget {
  /// The travel category label, e.g. "Flight", "Hotel", "Stay", "Car Rental"
  final String category;

  const TravelManagementMenu({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(LucideIcons.moreVertical),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (value) => _handleMenuAction(context, value),
      itemBuilder: (context) => [
        const PopupMenuItem(
          enabled: false,
          child: Text(
            'TRAVEL MANAGEMENT',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.accent,
              letterSpacing: 1.2,
            ),
          ),
        ),
        const PopupMenuItem(
          value: 'my_bookings',
          child: _MenuRow(icon: LucideIcons.ticket, label: 'My Bookings'),
        ),
        const PopupMenuItem(
          value: 'saved',
          child: _MenuRow(icon: LucideIcons.heart, label: 'Saved & Wishlist'),
        ),
        const PopupMenuItem(
          value: 'travel_history',
          child: _MenuRow(icon: LucideIcons.history, label: 'Travel History'),
        ),
        const PopupMenuItem(
          value: 'loyalty',
          child: _MenuRow(icon: LucideIcons.award, label: 'Loyalty & Rewards'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          enabled: false,
          child: Text(
            'HOST / PROVIDER',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.accent,
              letterSpacing: 1.2,
            ),
          ),
        ),
        const PopupMenuItem(
          value: 'my_listings',
          child: _MenuRow(icon: LucideIcons.layoutList, label: 'My Listings'),
        ),
        const PopupMenuItem(
          value: 'booking_requests',
          child: _MenuRow(icon: LucideIcons.bellRing, label: 'Booking Requests'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'settings',
          child: _MenuRow(icon: LucideIcons.settings, label: 'Travel Preferences'),
        ),
        const PopupMenuItem(
          value: 'support',
          child: _MenuRow(icon: LucideIcons.helpCircle, label: 'Help & Support'),
        ),
      ],
    );
  }

  void _handleMenuAction(BuildContext context, String action) {
    switch (action) {
      case 'my_bookings':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => MyBookingsScreen(category: category)),
        );
        break;
      case 'saved':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => SavedTravelsScreen(category: category)),
        );
        break;
      case 'travel_history':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => TravelHistoryScreen(category: category)),
        );
        break;
      case 'loyalty':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LoyaltyRewardsScreen()),
        );
        break;
      case 'my_listings':
        // Map category to filter type
        String? filterType;
        switch (category) {
          case 'Stay':
            filterType = 'stay';
            break;
          case 'Car Rental':
            filterType = 'car';
            break;
          case 'Hotel':
            filterType = 'hotel';
            break;
        }
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => MyListingsScreen(filterType: filterType)),
        );
        break;
      case 'booking_requests':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const HostBookingsScreen()),
        );
        break;
      case 'settings':
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Travel Preferences — coming soon'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
        break;
      case 'support':
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Help & Support — coming soon'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
        break;
    }
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MenuRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurface.withOpacity(0.7)),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(fontSize: 14)),
      ],
    );
  }
}
