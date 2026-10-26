import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:diaspora_nearby/features/marketplace/models/marketplace_listing.dart';
import 'package:diaspora_nearby/features/marketplace/repository/marketplace_repository.dart';
import 'package:diaspora_nearby/features/marketplace/widgets/marketplace_card_helpers.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';

/// Screen that displays car parts matching a specific vehicle (make + model).
class CompatiblePartsScreen extends ConsumerStatefulWidget {
  final String make;
  final String? model;
  final String? year;

  const CompatiblePartsScreen({
    super.key,
    required this.make,
    this.model,
    this.year,
  });

  @override
  ConsumerState<CompatiblePartsScreen> createState() =>
      _CompatiblePartsScreenState();
}

class _CompatiblePartsScreenState extends ConsumerState<CompatiblePartsScreen> {
  List<MarketplaceListing>? _parts;
  bool _loading = true;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchParts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchParts() async {
    final repo = ref.read(marketplaceRepositoryProvider);
    final results = await repo.getPartsForVehicle(
      make: widget.make,
      model: widget.model,
    );
    if (mounted) {
      setState(() {
        _parts = results;
        _loading = false;
      });
    }
  }

  List<MarketplaceListing> get _filteredParts {
    if (_parts == null) return [];
    if (_searchQuery.isEmpty) return _parts!;
    final q = _searchQuery.toLowerCase();
    return _parts!.where((part) {
      final title = part.title.toLowerCase();
      final partNumber =
          part.carPartsDetails?['partNumber']?.toString().toLowerCase() ?? '';
      return title.contains(q) || partNumber.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final vehicleLabel = [
      if (widget.year != null) widget.year!,
      widget.make,
      if (widget.model != null) widget.model!,
    ].join(' ');

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Compatible Parts',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            Text(
              vehicleLabel,
              style: TextStyle(fontSize: 12, color: theme.hintColor),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _parts == null || _parts!.isEmpty
          ? _buildEmptyState(theme)
          : Column(
              children: [
                // Search bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _searchQuery = v),
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.colorScheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search by name or part number...',
                      hintStyle: TextStyle(
                        fontSize: 14,
                        color: theme.hintColor.withValues(alpha: 0.6),
                      ),
                      prefixIcon: Icon(
                        LucideIcons.search,
                        size: 18,
                        color: theme.hintColor,
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(
                                LucideIcons.x,
                                size: 16,
                                color: theme.hintColor,
                              ),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.04),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                // Parts list
                Expanded(
                  child: _filteredParts.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                LucideIcons.searchX,
                                size: 40,
                                color: theme.hintColor.withValues(alpha: 0.4),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No parts match "$_searchQuery"',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: theme.hintColor,
                                ),
                              ),
                            ],
                          ),
                        )
                      : _buildPartsList(theme, isDark),
                ),
              ],
            ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.package,
              size: 56,
              color: theme.hintColor.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'No Parts Listed Yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'There are no parts listed for this vehicle yet.\nCheck back later or list a part yourself!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: theme.hintColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPartsList(ThemeData theme, bool isDark) {
    final parts = _filteredParts;
    return RefreshIndicator(
      onRefresh: _fetchParts,
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.of(context).padding.bottom,
        ),
        itemCount: parts.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final part = parts[index];
          return _buildPartCard(part, theme, isDark);
        },
      ),
    );
  }

  Widget _buildPartCard(MarketplaceListing part, ThemeData theme, bool isDark) {
    final cp = part.carPartsDetails;
    final partNumber = cp?['partNumber']?.toString() ?? '';
    final fitsYear = cp?['carYear']?.toString() ?? '';

    return GestureDetector(
      onTap: () => context.push('/marketplace/listing/${part.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                bottomLeft: Radius.circular(14),
              ),
              child: SizedBox(
                width: 110,
                height: 100,
                child: part.images.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: part.images.first,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.04)
                              : Colors.grey[100],
                          child: Icon(
                            LucideIcons.wrench,
                            size: 28,
                            color: theme.hintColor.withValues(alpha: 0.3),
                          ),
                        ),
                        errorWidget: (_, _, _) => Container(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.04)
                              : Colors.grey[100],
                          child: Icon(
                            LucideIcons.wrench,
                            size: 28,
                            color: theme.hintColor.withValues(alpha: 0.3),
                          ),
                        ),
                      )
                    : Container(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.04)
                            : Colors.grey[100],
                        child: Icon(
                          LucideIcons.wrench,
                          size: 28,
                          color: theme.hintColor.withValues(alpha: 0.3),
                        ),
                      ),
              ),
            ),

            // Details
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Text(
                      part.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),

                    // Subcategory + part number
                    Row(
                      children: [
                        if (part.subcategory != null) ...[
                          Icon(
                            LucideIcons.tag,
                            size: 10,
                            color: theme.hintColor,
                          ),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              part.subcategory!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.hintColor,
                              ),
                            ),
                          ),
                        ],
                        if (partNumber.isNotEmpty) ...[
                          if (part.subcategory != null)
                            const SizedBox(width: 8),
                          Text(
                            '#$partNumber',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.orange.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),

                    // Fits year badge
                    if (fitsYear.isNotEmpty)
                      Text(
                        'Fits year: $fitsYear',
                        style: TextStyle(fontSize: 11, color: theme.hintColor),
                      ),
                    const SizedBox(height: 6),

                    // Price
                    LocalPriceRow(
                      listing: part,
                      viewerCountryCode: ref
                          .watch(userProfileProvider)
                          .value
                          ?.hostCountryCode,
                    ),
                  ],
                ),
              ),
            ),

            // Chevron
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Icon(
                LucideIcons.chevronRight,
                size: 16,
                color: theme.hintColor.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
