import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/core/data/countries.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:go_router/go_router.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';

import 'package:diaspora_nearby/features/shared/ui/glass_container.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart'; // [NEW]
import 'package:diaspora_nearby/features/dsp/widgets/exploration_tracker.dart'; // [NEW]
import 'package:diaspora_nearby/features/notifications/providers/notification_count_provider.dart';

class DiasporaAppBar extends ConsumerStatefulWidget
    implements PreferredSizeWidget {
  final String currentScreen;
  final String searchQuery;
  final ValueChanged<String> onSearchChange;
  final VoidCallback onSearchClear;
  final String? homeCountryCode;
  final bool isGlobalView;
  final VoidCallback? onToggleView;
  final bool showSearchField;
  final Widget? title;

  const DiasporaAppBar({
    super.key,
    this.currentScreen = '',
    this.searchQuery = '',
    this.onSearchChange = _defaultOnSearchChange,
    this.onSearchClear = _defaultOnSearchClear,
    this.homeCountryCode,
    this.isGlobalView = false,
    this.onToggleView,
    this.showSearchField = true,
    this.title,
  });

  // Default handlers
  static void _defaultOnSearchChange(String value) {}
  static void _defaultOnSearchClear() {}

  @override
  Size get preferredSize => Size.fromHeight(showSearchField ? 128 : 64);

  @override
  ConsumerState<DiasporaAppBar> createState() => _DiasporaAppBarState();
}

class _DiasporaAppBarState extends ConsumerState<DiasporaAppBar> {
  late TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.searchQuery);
  }

  @override
  void didUpdateWidget(DiasporaAppBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchQuery != oldWidget.searchQuery &&
        widget.searchQuery != _controller.text) {
      _controller.text = widget.searchQuery;
      _controller.selection = TextSelection.collapsed(
        offset: widget.searchQuery.length,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // State is passed from parent (ScaffoldWithNavBar)
    final isGlobalView = widget.isGlobalView;

    // Only show toggle if a callback is provided (i.e. supported screen)
    // AND if showSearchField is true?
    // No, if showSearchField is false (Events), the logo becomes the toggle (per earlier requirement).
    // The user wants "Global Toggle" feature.
    final showGlobalToggle = widget.onToggleView != null;

    final theme = Theme.of(context);
    final activeColor = theme.colorScheme.primary; // Use global accent
    final inactiveColor = theme.colorScheme.onSurface; // Same as title color

    return Container(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // AppBar Section with Communities, Radio, More buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  // Logo (Interactive Toggle if Search Hidden)
                  if (!widget.showSearchField && showGlobalToggle)
                    IconButton(
                      icon: Icon(
                        LucideIcons.globe,
                        size: 30,
                        color: isGlobalView ? activeColor : inactiveColor,
                      ),
                      onPressed: widget.onToggleView,
                      tooltip: isGlobalView
                          ? 'Switch to Home View'
                          : 'Switch to Global View',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    )
                  else
                    Image.asset(
                      'assets/icons/logo-transparent-32.png',
                      width: 36,
                      height: 36,
                    ),
                  const SizedBox(width: 4),

                  // Title
                  Expanded(
                    child: Text(
                      'Diaspora Nearby',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                      ),
                    ),
                  ),

                  // Communities Icon
                  IconButton(
                    icon: const Icon(LucideIcons.heartHandshake, size: 22),
                    color: widget.currentScreen == 'communities'
                        ? activeColor
                        : inactiveColor,
                    onPressed: () {
                      // [NEW] Track Exploration
                      final user = ref.read(authRepositoryProvider).currentUser;
                      if (user != null) {
                        ref
                            .read(pointsServiceProvider)
                            .trackExplorationReward(
                              user.uid,
                              'action_appbar_community',
                            )
                            .then((rewarded) {
                              if (rewarded && context.mounted) {
                                showExplorationRewardToast(
                                  context,
                                  message: 'Community Network Unlocked',
                                );
                              }
                            });
                      }
                      context.go('/communities');
                    },
                  ),

                  // Notification Bell with Badge
                  _buildNotificationBell(context, ref),

                  // More Menu (Redirects to Economy Hub)
                  IconButton(
                    icon: const Icon(LucideIcons.moreVertical, size: 22),
                    onPressed: () {
                      context.push('/economy');
                    },
                  ),
                ],
              ),
            ),

            // Search Bar Section with logo toggle inside
            if (widget.showSearchField)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: GlassContainer(
                  borderRadius: BorderRadius.circular(
                    30,
                  ), // Increased radius for pill shape
                  padding: EdgeInsets.zero,
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    autofocus: false, // [FIX] Disable auto-focus
                    onChanged: widget.onSearchChange,
                    decoration: InputDecoration(
                      hintText: _getPlaceholder(isGlobalView),
                      prefixIcon: const Icon(LucideIcons.search, size: 20),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Clear / Exit button (when text exists)
                          if (widget.searchQuery.isNotEmpty)
                            IconButton(
                              icon: const Icon(LucideIcons.x, size: 20),
                              onPressed: widget.onSearchClear,
                              tooltip: 'Clear search',
                            ),

                          // Global toggle - hidden when searching to focus on search results
                          if (showGlobalToggle && widget.searchQuery.isEmpty)
                            IconButton(
                              icon: Icon(
                                LucideIcons.globe,
                                size: 24,
                                color: isGlobalView
                                    ? activeColor
                                    : inactiveColor,
                              ),
                              onPressed: () {
                                if (widget.onToggleView != null) {
                                  widget.onToggleView!();
                                }
                              },
                              tooltip: isGlobalView
                                  ? 'Switch to Home View'
                                  : 'Switch to Global View',
                            ),
                        ],
                      ),
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
          ],
        ),
      ),
    );
  }

  String _getPlaceholder(bool isGlobal) {
    // Special case for Nearby screen
    if (widget.currentScreen == 'nearby') {
      return 'Search people from any country...';
    }

    // Resolve home country name for placeholder
    final homeCountryName = widget.homeCountryCode != null
        ? getCountryByCode(widget.homeCountryCode!)?.name
        : null;

    // Special case for Events screen
    if (widget.currentScreen == 'events') {
      if (isGlobal) {
        return 'Search global community events...';
      } else {
        return homeCountryName != null
            ? 'Search $homeCountryName community events...'
            : 'Search local community events...';
      }
    }

    // Special case for Radio screen (Always static placeholder)
    if (widget.currentScreen == 'radio') {
      return 'Listen from any country...';
    }

    if (widget.currentScreen == 'communities') {
      if (isGlobal) {
        return 'Search for global communities';
      } else {
        return homeCountryName != null
            ? 'Search for $homeCountryName communities...'
            : 'Search for local communities...';
      }
    }

    // Rest remain same logic...
    if (widget.currentScreen == 'chats') {
      return isGlobal ? 'Search for all chats' : 'Search my chats';
    }

    if (isGlobal) {
      return 'Search globally...';
    }

    switch (widget.currentScreen) {
      case 'chats':
        return 'Search chats...';
      default:
        return 'Search...';
    }
  }

  Widget _buildNotificationBell(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(pendingActionCountProvider);
    final pendingCount = pendingAsync.value ?? 0;
    final unreadAsync = ref.watch(unreadNotificationCountProvider);
    final unreadCount = unreadAsync.value ?? 0;

    // Show the higher of the two counts — pending actions take priority
    final badgeCount = pendingCount > 0 ? pendingCount : unreadCount;
    final textColor = Theme.of(context).colorScheme.onPrimary;

    return IconButton(
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(LucideIcons.bell, size: 22),
          if (badgeCount > 0)
            Positioned(
              right: -4,
              top: -2,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: AppTheme.accent,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  badgeCount > 99 ? '99+' : '$badgeCount',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
      onPressed: () {
        context.push('/notifications');
      },
    );
  }
}
