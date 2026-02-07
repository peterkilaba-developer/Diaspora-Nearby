import 'package:flutter/material.dart';

import 'package:diaspora_nearby/core/data/countries.dart' as country_data;

import 'package:diaspora_nearby/features/shared/ui/glass_container.dart';

class CountryPickerSheet extends StatefulWidget {
  final country_data.Country? selectedCountry;

  final Function(country_data.Country) onCountrySelected;

  final bool showDialCode;

  final VoidCallback? onUseGlobalView;

  const CountryPickerSheet({
    super.key,
    required this.selectedCountry,
    required this.onCountrySelected,
    this.showDialCode = true,
    this.onUseGlobalView,
  });
  @override
  State<CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<CountryPickerSheet>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  List<country_data.Country> _filteredCountries = country_data.countries;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterCountries);
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _filterCountries() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredCountries = country_data.countries;
      } else {
        _filteredCountries = country_data.countries.where((c) {
          return c.name.toLowerCase().contains(query) ||
              c.dialCode.contains(query) ||
              c.code.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  @override
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 1.0,
      minChildSize: 1.0,
      maxChildSize: 1.0,
      builder: (context, scrollController) {
        return SafeArea(
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withAlpha(76),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Select Country',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GlassContainer(
                  borderRadius: BorderRadius.circular(30),
                  padding: EdgeInsets.zero,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search country...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: widget.onUseGlobalView != null
                          ? ScaleTransition(
                              scale: _scaleAnimation,
                              child: IconButton(
                                icon: Image.asset(
                                  'assets/icons/logo-original.png',
                                  width: 24,
                                  height: 24,
                                ),
                                onPressed: widget.onUseGlobalView,
                                tooltip: 'Global View',
                              ),
                            )
                          : null,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: _filteredCountries.length,
                  itemBuilder: (context, index) {
                    final country = _filteredCountries[index];

                    final isSelected =
                        widget.selectedCountry?.code == country.code;

                    return ListTile(
                      leading: Text(
                        country.flag,
                        style: const TextStyle(fontSize: 24),
                      ),
                      title: Text(
                        country.name,
                        style: isSelected
                            ? const TextStyle(fontWeight: FontWeight.bold)
                            : null,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.showDialCode)
                            Text(
                              country.dialCode,
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          if (isSelected) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.check,
                              color: Colors.green.shade600,
                              size: 20,
                            ),
                          ],
                        ],
                      ),
                      onTap: () => widget.onCountrySelected(country),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
