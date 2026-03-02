import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

/// Shows the user's travel history with stats.
class TravelHistoryScreen extends StatelessWidget {
  final String category;
  const TravelHistoryScreen({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppTheme.elevationColor(context, 0),
      appBar: AppBar(
        title: const Text('Travel History'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Column(
        children: [
          // Stats Header
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            padding: const EdgeInsets.all(16),
            decoration: AppTheme.cardDecoration(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your Travel Stats',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    _StatItem(
                      icon: LucideIcons.plane,
                      value: '0',
                      label: 'Trips',
                      color: AppTheme.accent,
                    ),
                    _StatItem(
                      icon: LucideIcons.globe,
                      value: '0',
                      label: 'Countries',
                      color: Color(0xFF4CAF50),
                    ),
                    _StatItem(
                      icon: LucideIcons.mapPin,
                      value: '0',
                      label: 'Cities',
                      color: Color(0xFFFFA726),
                    ),
                    _StatItem(
                      icon: LucideIcons.star,
                      value: '0',
                      label: 'Points',
                      color: Color(0xFFAB47BC),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Timeline
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      LucideIcons.mapPinOff,
                      size: 48,
                      color: theme.colorScheme.onSurface.withOpacity(0.15),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No travel history yet',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface.withOpacity(0.4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your completed trips will appear here as a timeline.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurface.withOpacity(0.3),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Expanded(
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }
}
