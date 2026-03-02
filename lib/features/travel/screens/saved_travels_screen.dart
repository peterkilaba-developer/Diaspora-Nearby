import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

/// Shows the user's saved/wishlisted travel items.
class SavedTravelsScreen extends StatefulWidget {
  final String category;
  const SavedTravelsScreen({super.key, required this.category});

  @override
  State<SavedTravelsScreen> createState() => _SavedTravelsScreenState();
}

class _SavedTravelsScreenState extends State<SavedTravelsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppTheme.elevationColor(context, 0),
      appBar: AppBar(
        title: const Text('Saved & Wishlist'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: AppTheme.accent,
          unselectedLabelColor: theme.colorScheme.onSurface.withOpacity(0.5),
          indicatorColor: AppTheme.accent,
          indicatorSize: TabBarIndicatorSize.label,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Flights'),
            Tab(text: 'Hotels'),
            Tab(text: 'Stays'),
            Tab(text: 'Car Rentals'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSavedList(context, 'Flight', LucideIcons.plane),
          _buildSavedList(context, 'Hotel', LucideIcons.hotel),
          _buildSavedList(context, 'Stay', LucideIcons.home),
          _buildSavedList(context, 'Car Rental', LucideIcons.car),
        ],
      ),
    );
  }

  Widget _buildSavedList(BuildContext context, String type, IconData icon) {
    final theme = Theme.of(context);
    // Empty for now — will be replaced with Firestore saved items
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.heart,
              size: 48,
              color: theme.colorScheme.onSurface.withOpacity(0.15),
            ),
            const SizedBox(height: 16),
            Text(
              'No saved ${type.toLowerCase()}s yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withOpacity(0.4),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: theme.colorScheme.onSurface.withOpacity(0.3)),
                const SizedBox(width: 6),
                Text(
                  'Tap the heart icon on any $type to save it',
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurface.withOpacity(0.3),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
