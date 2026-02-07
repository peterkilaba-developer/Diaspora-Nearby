import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/community/viewmodels/community_hierarchy_viewmodel.dart';
import 'package:diaspora_nearby/features/community/models/hierarchy_item.dart';
import 'package:diaspora_nearby/features/chat/utils/community_chat_utils.dart';
import 'package:diaspora_nearby/features/community/models/community_data.dart';
// Import existing screen for reuse
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/discovery/providers/global_search_provider.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart'; // [NEW]
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart'; // [NEW]
import 'package:diaspora_nearby/features/dsp/widgets/exploration_tracker.dart'; // [NEW]


class CommunitiesScreen extends ConsumerStatefulWidget {
  const CommunitiesScreen({super.key});

  @override
  ConsumerState<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

class _CommunitiesScreenState extends ConsumerState<CommunitiesScreen> {
  List<HierarchyItem> _filterHierarchy(
    List<HierarchyItem> items,
    String query,
  ) {
    if (query.isEmpty) return items;

    final filtered = <HierarchyItem>[];
    for (var item in items) {
      final filteredItem = _filterItem(item, query);
      if (filteredItem != null) {
        filtered.add(filteredItem);
      }
    }
    return filtered;
  }

  HierarchyItem? _filterItem(HierarchyItem item, String query) {
    final matchesSelf = item.name.toLowerCase().contains(query.toLowerCase());

    // If self matches, we perform a "relaxed" match where we return the item as is,
    // assuming the user might want to see all children of a matching category.
    if (matchesSelf) return item;

    final filteredChildren = <HierarchyItem>[];
    for (var child in item.children) {
      final filteredChild = _filterItem(child, query);
      if (filteredChild != null) {
        filteredChildren.add(filteredChild);
      }
    }

    if (filteredChildren.isNotEmpty) {
      // If query doesn't match self but matches children, return self with filtered children
      return item.copyWith(children: filteredChildren);
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final hierarchyState = ref.watch(communityHierarchyProvider);
    final userAsync = ref.watch(userProfileProvider);
    final user = userAsync.value;
    final searchQuery = ref.watch(globalSearchProvider);

    if (userAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (userAsync.hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Unable to load profile',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => ref.refresh(userProfileProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    // Case: Profile is null (not found in DB) but no error thrown
    if (user == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_off,
              size: 48,
              color: Theme.of(context).disabledColor,
            ),
            const SizedBox(height: 16),
            Text(
              'Profile incomplete or missing.',
              style: TextStyle(color: Theme.of(context).hintColor),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => context.go('/profile-setup'),
              child: const Text('Complete Profile Setup'),
            ),
          ],
        ),
      );
    }

    // Communities is accessed via AppBar modal, needs Scaffold wrapper
    return Scaffold(
      body: hierarchyState.when(
        data: (items) {
          final filteredItems = _filterHierarchy(items, searchQuery);

          if (filteredItems.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.handshake,
                    size: 64,
                    color: Theme.of(context).disabledColor,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    searchQuery.isNotEmpty
                        ? 'No communities match your search.'
                        : 'No communities found.',
                    style: TextStyle(color: Theme.of(context).hintColor),
                  ),
                  if (searchQuery.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    // No retry button on search empty state usually
                  ] else ...[
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () => ref.refresh(communityHierarchyProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            itemCount: filteredItems.length,
            itemBuilder: (context, index) {
              final item = filteredItems[index];
              return HierarchyItemWidget(
                item: item,
                hostDepth: 0, // Start at 0 for top-level items
                // Pass search query to maybe force expansion?
                // For now just basic rendering.
                initiallyExpanded: searchQuery
                    .isNotEmpty, // Auto-expand if searching to show matches deep in tree
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class HierarchyItemWidget extends ConsumerStatefulWidget {
  final HierarchyItem item;
  final int hostDepth; // Tracks depth within host hierarchy only
  final bool initiallyExpanded; // [NEW]

  const HierarchyItemWidget({
    super.key,
    required this.item,
    this.hostDepth = 0, // Start at 0 for non-host items
    this.initiallyExpanded = false,
  });

  @override
  ConsumerState<HierarchyItemWidget> createState() =>
      _HierarchyItemWidgetState();
}

class _HierarchyItemWidgetState extends ConsumerState<HierarchyItemWidget> {
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    // Pre-expand items where isExpandable is false (countries)
    // These items have children but should always show them
    if ((widget.item.children.isNotEmpty &&
            widget.item.isExpandable == false) ||
        widget.item.initiallyExpanded ||
        widget.initiallyExpanded) {
      _isExpanded = true;
    }
  }

  void _openMembersList(BuildContext context) {
    // Reconstruct Community object
    final community = Community(
      id: widget.item.id,
      name: widget.item.name,
      type: widget.item.type,
      locationType: widget.item.locationType,
      homeCountryCode: widget.item.homeCountryCode ?? '',
      hostCountryCode: widget.item.hostCountryCode ?? '',
      location: widget.item.location ?? {},
      profileImage: widget.item.profileImage?.value,
      flag: widget.item.flag ?? '',
    );

    // Push to full screen route instead of modal bottom sheet
    context.push('/communities/${community.id}/members', extra: community);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final hasChildren = item.children.isNotEmpty || item.isExpandable;
    final isPreExpanded =
        item.children.isNotEmpty && item.isExpandable == false;

    // 1. Global Community (Special Card)
    if (item.type == 'global') {
      return Column(
        children: [
          Card(
            margin: EdgeInsets.zero,
            color: Theme.of(context).cardColor,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide.none,
            ),
            child: InkWell(
              onTap: () => _openMembersList(context),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 16,
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _buildAvatar(item, size: 48),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              Row(
                                children: [
                                  Icon(
                                    Icons.handshake,
                                    size: 14,
                                    color: Theme.of(context).hintColor,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${item.totalMembers} members worldwide',
                                    style: TextStyle(
                                      color: Theme.of(context).hintColor,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // [FIX] Removed chevron for global community as it's not expandable here
                      ],
                    ),
                    if (item.globalStats != null) ...[
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStat(
                            'Continents',
                            item.globalStats!.continents,
                          ),
                          _buildStat('Countries', item.globalStats!.countries),
                          _buildStat('Cities', item.globalStats!.cities),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          // Show global children (continents) always
          if (item.children.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 0, top: 4),
              child: Column(
                children: item.children
                    .map(
                      (child) => Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: HierarchyItemWidget(
                          item: child,
                          hostDepth: 0,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      );
    }

    // 2. Standard Items (Custom Split Interaction)
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide.none,
      ),
      child: Column(
        children: [
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            contentPadding: const EdgeInsets.only(
              left: 8,
              right: 0,
              top: 4,
              bottom: 4,
            ),
            horizontalTitleGap: 8.0,
            leading: CommunityChatUtils.getCommunityAvatar(
              type: item.type,
              locationType: item.locationType,
              profileImage: item.profileImage?.value,
              homeCountryCode: item.homeCountryCode,
              hostCountryCode: item.hostCountryCode,
              flag: item.flag,
              communityId: item.id,
              size: 48,
              context: context,
            ),
            title: Text(
              item.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Row(
              children: [
                Icon(
                  Icons.handshake,
                  size: 14,
                  color: Theme.of(context).hintColor,
                ),
                const SizedBox(width: 4),
                Text(
                  '${item.totalMembers} members',
                  style: TextStyle(color: Theme.of(context).hintColor),
                ),
              ],
            ),
            onTap: () {
              // [NEW] Track Member View
              final user = ref.read(authRepositoryProvider).currentUser;
              if (user != null) {
                ref
                    .read(pointsServiceProvider)
                    .trackExplorationReward(
                      user.uid,
                      'action_community_members',
                    )
                    .then((rewarded) {
                  if (rewarded && context.mounted) {
                    showExplorationRewardToast(context, message: 'Community discovered!');
                  }
                });
              }
              _openMembersList(context);
            },
            trailing: hasChildren
                ? (isPreExpanded
                      ? const SizedBox(width: 16)
                      : IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: Icon(
                            _isExpanded
                                ? LucideIcons.chevronDown
                                : LucideIcons.chevronRight,
                            color: Theme.of(
                              context,
                            ).iconTheme.color?.withValues(alpha: 0.5),
                          ),
                          onPressed: () {
                            // [NEW] Track Expand
                            if (!_isExpanded) {
                              final user = ref
                                  .read(authRepositoryProvider)
                                  .currentUser;
                              if (user != null) {
                                ref
                                    .read(pointsServiceProvider)
                                    .trackExplorationReward(
                                      user.uid,
                                      'action_community_expand',
                                    )
                                    .then((rewarded) {
                                  if (rewarded && context.mounted) {
                                    showExplorationRewardToast(context, message: 'Expansion bonus!');
                                  }
                                });
                              }
                            }
                            setState(() {
                              _isExpanded = !_isExpanded;
                            });
                          },
                        ))
                : null,
          ),

          // Show children if expanded OR if pre-expanded
          if (hasChildren && (_isExpanded || isPreExpanded))
            Column(
              children: item.children
                  .map(
                    (child) => Padding(
                      padding: EdgeInsets.only(
                        top: 8,
                        // 4px per level, but keep Continent and Country at 0px
                        left: (child.type == 'continent' ||
                                child.type == 'country' ||
                                child.type == 'global')
                            ? 0
                            : 4.0,
                        bottom: 0,
                        right: 8,
                      ),
                      child: HierarchyItemWidget(
                        item: child,
                        hostDepth: widget.hostDepth + 1,
                        initiallyExpanded: child.initiallyExpanded,
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, int value) {
    return Column(
      children: [
        Text(
          value.toString(),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
        ),
      ],
    );
  }

  Widget _buildAvatar(HierarchyItem item, {double size = 40}) {
    // Use CommunityChatUtils for consistent avatar rendering!
    return CommunityChatUtils.getCommunityAvatar(
      context: context,
      type: item.type,
      locationType: item.locationType,
      flag: item.flag,
      profileImage: item.profileImage?.value,
      size: size,
    );
  }
}
