import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:go_router/go_router.dart';
import 'package:diaspora_nearby/providers/view_mode_provider.dart';
import 'package:diaspora_nearby/features/shared/ui/glass_container.dart';

class DiasporaAppBar extends ConsumerStatefulWidget implements PreferredSizeWidget {
  final String currentScreen;
  final String searchQuery;
  final ValueChanged<String> onSearchChange;
  final VoidCallback onSearchClear;
  final String? homeCountry;
  final bool isGlobalView;
  final VoidCallback? onToggleView;
  final bool showSearchField;

  const DiasporaAppBar({
    super.key,
    this.currentScreen = '',
    this.searchQuery = '',
    this.onSearchChange = _defaultOnSearchChange,
    this.onSearchClear = _defaultOnSearchClear,
    this.homeCountry,
    this.isGlobalView = false,
    this.onToggleView,
    this.showSearchField = true,
    this.title, // Backward compatibility
  });

  final Widget? title;

  // Default handlers to allow usage without search params (e.g. initial simple usage)
  static void _defaultOnSearchChange(String value) {}
  static void _defaultOnSearchClear() {}

  @override
  Size get preferredSize => Size.fromHeight(showSearchField ? 128 : 64);

  @override
  ConsumerState<DiasporaAppBar> createState() => _DiasporaAppBarState();
}

class _DiasporaAppBarState extends ConsumerState<DiasporaAppBar> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    
    // State is passed from parent (ScaffoldWithNavBar)
    final isGlobalView = widget.isGlobalView;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
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
                    ScaleTransition(
                      scale: _scaleAnimation,
                      child: IconButton(
                        icon: Image.asset(
                          'assets/icons/logo-original.png',
                          width: 36,
                          height: 36,
                        ),
                        onPressed: widget.onToggleView,
                        tooltip: isGlobalView ? 'Switch to Home View' : 'Switch to Global View',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    )
                  else
                    Image.asset(
                      'assets/icons/logo-original.png',
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
                    icon: const Icon(Icons.handshake, size: 22),
                    color: widget.currentScreen == 'communities' ? activeColor : inactiveColor,
                    onPressed: () => context.push('/communities'), // Changed to push for top-level stack
                  ),
                  
                  // Radio Icon
                  IconButton(
                    icon: const Icon(Icons.radio, size: 22),
                    color: widget.currentScreen == 'radio' ? activeColor : inactiveColor,
                    onPressed: () => context.push('/radio'), // Changed to push for top-level stack
                  ),
                  
                  // More Menu
                  IconButton(
                    icon: const Icon(LucideIcons.moreVertical, size: 22),
                    onPressed: () => context.push('/more'),
                  ),
                ],
              ),
            ),

            // Search Bar Section with logo toggle inside
            if (widget.showSearchField)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: GlassContainer(
                borderRadius: BorderRadius.circular(30), // Increased radius for pill shape
                padding: EdgeInsets.zero,
                child: TextField(
                  controller: TextEditingController(text: widget.searchQuery)
                    ..selection = TextSelection.collapsed(offset: widget.searchQuery.length),
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
                          ScaleTransition(
                            scale: _scaleAnimation,
                            child: IconButton(
                              icon: ColorFiltered(
                                colorFilter: ColorFilter.mode(
                                  isGlobalView
                                      ? activeColor  // Sage green when global
                                      : inactiveColor, // Off-white/off-black when home
                                  BlendMode.srcIn,
                                ),
                                child: Image.asset(
                                  'assets/icons/logo-original.png',
                                  width: 24,
                                  height: 24,
                                ),
                              ),
                              // Call the callback provided by parent
                              onPressed: widget.onToggleView,
                              tooltip: isGlobalView ? 'Switch to Home View' : 'Switch to Global View',
                            ),
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
    
    // Special case for Events screen
    if (widget.currentScreen == 'events') {
       if (isGlobal) {
         return 'Search global community events...';
       } else {
         return widget.homeCountry != null
             ? 'Search ${widget.homeCountry} community events...'
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
         return widget.homeCountry != null
             ? 'Search for ${widget.homeCountry} communities...'
             : 'Search for local communities...';
       }
    }

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
  }
