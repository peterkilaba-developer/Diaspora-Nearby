import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:diaspora_nearby/core/data/countries.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

/// A reusable All / Host-country / Home-country segmented toggle.
///
/// Used in Stay search, Car Rental search, and potentially Hotel search
/// to filter listings by geographic scope.
class CountryFilterToggle extends StatelessWidget {
  const CountryFilterToggle({
    super.key,
    required this.selected,
    required this.onChanged,
    this.hostCountryCode,
    this.homeCountryCode,
  });

  /// Current selection: `'all'`, `'host'`, or `'home'`.
  final String selected;
  final ValueChanged<String> onChanged;
  final String? hostCountryCode;
  final String? homeCountryCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final hostCountry =
        hostCountryCode != null ? getCountryByCode(hostCountryCode!) : null;
    final homeCountry =
        homeCountryCode != null ? getCountryByCode(homeCountryCode!) : null;
    final hostName = hostCountry?.name ?? 'Host';
    final homeName = homeCountry?.name ?? 'Home';
    final hostFlag = hostCountry?.flag;
    final homeFlag = homeCountry?.flag;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppTheme.elevationColor(context, 1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          _chip(context, theme, isDark, 'All', 'all', LucideIcons.globe),
          _chip(context, theme, isDark, hostName, 'host', LucideIcons.mapPin,
              flag: hostFlag),
          _chip(context, theme, isDark, homeName, 'home', LucideIcons.home,
              flag: homeFlag),
        ]),
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    String label,
    String value,
    IconData icon, {
    String? flag,
  }) {
    final isSelected = selected == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.accent.withOpacity(isDark ? 0.18 : 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (flag != null) ...[
                Text(flag, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 4),
              ] else ...[
                Icon(icon,
                    size: 13,
                    color: isSelected ? AppTheme.accent : theme.hintColor),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? AppTheme.accent : theme.hintColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
