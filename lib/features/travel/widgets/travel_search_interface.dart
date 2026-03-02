import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/travel/models/travel_search_result.dart';
import 'package:diaspora_nearby/features/travel/widgets/travel_search_result_card.dart';
import 'package:diaspora_nearby/features/travel/widgets/travel_skeleton_loader.dart';

class TravelSearchInterface extends StatefulWidget {
  final String title;
  final IconData icon;
  final Widget searchForm;
  final bool isSearching;
  final List<TravelSearchResult> results;
  final VoidCallback onClear;
  final VoidCallback onSearch;
  final String emptyStateMessage;
  final bool showSearchForm;
  final Widget Function(BuildContext context, int index)? customResultBuilder;
  final int? customResultCount;

  const TravelSearchInterface({
    super.key,
    required this.title,
    required this.icon,
    required this.searchForm,
    required this.isSearching,
    required this.results,
    required this.onClear,
    required this.onSearch,
    this.emptyStateMessage = 'Enter your search criteria to see results.',
    this.showSearchForm = true,
    this.customResultBuilder,
    this.customResultCount,
  });

  @override
  State<TravelSearchInterface> createState() => _TravelSearchInterfaceState();
}

class _TravelSearchInterfaceState extends State<TravelSearchInterface> {
  Widget _buildSearchCard(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      decoration: AppTheme.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(widget.icon, color: AppTheme.accent),
              const SizedBox(width: 8),
              Text(
                widget.title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // The specific search form injected by the parent
          widget.searchForm,

          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: widget.onClear,
                icon: Icon(LucideIcons.x, size: 18, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                label: Text(
                  'Clear',
                  style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5)),
                ),
              ),
              ElevatedButton.icon(
                onPressed: widget.isSearching ? null : widget.onSearch,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  elevation: 0,
                ),
                icon: widget.isSearching 
                    ? const SizedBox(
                        width: 18, 
                        height: 18, 
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                      )
                    : const Icon(LucideIcons.search, size: 18),
                label: const Text('Search'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Column(
      children: [
        // Search form — always Flexible so it shrink-wraps to content.
        // SingleChildScrollView allows scrolling when keyboard covers content.
        // Widget tree is STABLE — no type changes on keyboard show/hide.
        if (widget.showSearchForm)
          Flexible(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.only(bottom: bottomInset),
              child: _buildSearchCard(theme),
            ),
          ),

        // Results area — always Expanded (stable widget type).
        if (!widget.showSearchForm || !widget.isSearching)
          Expanded(
            child: widget.isSearching
                ? const TravelApiSkeletonLoader(
                    label: 'Searching...',
                  )
                : widget.results.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                widget.icon,
                                size: 48,
                                color: theme.colorScheme.onSurface.withOpacity(0.15),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                widget.emptyStateMessage,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface.withOpacity(0.4),
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.only(
                          left: 8, right: 8, top: 8,
                          bottom: MediaQuery.of(context).padding.bottom + 16,
                        ),
                        itemCount: widget.customResultBuilder != null
                            ? (widget.customResultCount ?? widget.results.length)
                            : widget.results.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: widget.customResultBuilder != null
                                ? widget.customResultBuilder!(context, index)
                                : TravelSearchResultCard(
                                    result: widget.results[index],
                                    onTap: () {},
                                  ),
                          );
                        },
                      ),
          ),
      ],
    );
  }
}
