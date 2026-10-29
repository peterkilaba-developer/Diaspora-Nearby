import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/community/viewmodels/community_hierarchy_viewmodel.dart';
import 'package:diaspora_nearby/features/community/repository/community_repository.dart';
import 'package:diaspora_nearby/features/community/models/hierarchy_item.dart';
import 'package:diaspora_nearby/features/chat/utils/community_chat_utils.dart';
import 'package:diaspora_nearby/features/community/models/community_data.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/discovery/providers/global_search_provider.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/dsp/widgets/exploration_tracker.dart';
import 'package:diaspora_nearby/features/hosting/widgets/request_host_dialog.dart';
import 'package:diaspora_nearby/core/providers/global_feature_provider.dart';
import 'package:diaspora_nearby/core/providers/view_mode_provider.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

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

    if (matchesSelf) return item;

    final filteredChildren = <HierarchyItem>[];
    for (var child in item.children) {
      final filteredChild = _filterItem(child, query);
      if (filteredChild != null) {
        filteredChildren.add(filteredChild);
      }
    }

    if (filteredChildren.isNotEmpty) {
      return item.copyWith(children: filteredChildren);
    }

    return null;
  }

  Widget _buildItemsList(
    BuildContext context,
    List<HierarchyItem> items,
    String searchQuery,
  ) {
    final filteredItems = _filterHierarchy(items, searchQuery);

    if (filteredItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.heartHandshake,
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
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      itemCount: filteredItems.length,
      itemBuilder: (context, index) {
        final item = filteredItems[index];
        return HierarchyItemWidget(
          item: item,
          hostDepth: 0,
          initiallyExpanded: searchQuery.isNotEmpty,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final hierarchyState = ref.watch(communityHierarchyProvider);
    final profileAsync = ref.watch(userProfileProvider);
    final searchQuery = ref.watch(globalSearchProvider);
    final mode = ref.watch(communitiesViewModeProvider);

    return Scaffold(
      body: hierarchyState.when(
        skipLoadingOnReload: true,
        skipLoadingOnRefresh: true,
        data: (items) => _buildItemsList(context, items, searchQuery),
        loading: () {
          final cachedItems = CommunityHierarchyViewModel.getCachedHierarchy(
            mode,
            profileAsync.value?.homeCountryCode,
          );
          if (cachedItems != null && cachedItems.isNotEmpty) {
            return _buildItemsList(context, cachedItems, searchQuery);
          }
          return const Center(child: CircularProgressIndicator());
        },
        error: (e, st) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class HierarchyItemWidget extends ConsumerStatefulWidget {
  final HierarchyItem item;
  final int hostDepth;
  final bool initiallyExpanded;

  const HierarchyItemWidget({
    super.key,
    required this.item,
    this.hostDepth = 0,
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
    if ((widget.item.children.isNotEmpty &&
            widget.item.isExpandable == false) ||
        widget.item.initiallyExpanded ||
        widget.initiallyExpanded) {
      _isExpanded = true;
    }
  }

  void _openMembersList(BuildContext context) {
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
      memberCount: widget.item.totalMembers,
      totalMembers: widget.item.totalMembers,
    );

    ref.read(communityRepositoryProvider).cacheCommunity(community);
    context.push('/communities/${community.id}/members', extra: community);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final hasChildren = item.children.isNotEmpty || item.isExpandable;
    final isPreExpanded =
        item.children.isNotEmpty && item.isExpandable == false;

    // 1. Global Community (Special Card)
    if (item.type == 'global' || item.id == 'global_community') {
      if (!ref.watch(isGlobalUnlockedSyncProvider)) {
        return const SizedBox.shrink();
      }
      return Column(
        children: [
          Card(
            margin: EdgeInsets.zero,
            color: AppTheme.cardDecoration(context).color,
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
                                    LucideIcons.heartHandshake,
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
          if (item.children.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 0, top: 4),
              child: Column(
                children: item.children
                    .map(
                      (child) => Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: HierarchyItemWidget(item: child, hostDepth: 0),
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
      color: AppTheme.cardDecoration(context).color,
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
            title: Row(
              children: [
                if (CommunityChatUtils.isBilateral(
                  id: item.id,
                  locationType: item.locationType,
                )) ...[
                  const Icon(
                    LucideIcons.heartHandshake,
                    size: 16,
                    color: AppTheme.accent,
                  ),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    item.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            subtitle: Row(
              children: [
                Icon(
                  LucideIcons.heartHandshake,
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
              // Navigate immediately in 0ms
              _openMembersList(context);

              // Track Member View in background
              final user = ref.read(authRepositoryProvider).currentUser;
              if (user != null) {
                unawaited(
                  ref
                      .read(pointsServiceProvider)
                      .trackExplorationReward(
                        user.uid,
                        'action_community_members',
                      )
                      .then((rewarded) {
                        if (rewarded && context.mounted) {
                          showExplorationRewardToast(
                            context,
                            message: 'Community discovered!',
                          );
                        }
                      }),
                );
              }
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
                            final wasExpanded = _isExpanded;
                            setState(() {
                              _isExpanded = !_isExpanded;
                            });
                            if (!wasExpanded) {
                              final user = ref
                                  .read(authRepositoryProvider)
                                  .currentUser;
                              if (user != null) {
                                unawaited(
                                  ref
                                      .read(pointsServiceProvider)
                                      .trackExplorationReward(
                                        user.uid,
                                        'action_community_expand',
                                      )
                                      .then((rewarded) {
                                        if (rewarded && context.mounted) {
                                          showExplorationRewardToast(
                                            context,
                                            message: 'Expansion bonus!',
                                          );
                                        }
                                      }),
                                );
                              }
                            }
                          },
                        ))
                : (item.type == 'city' || item.type == 'community'
                      ? IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Request Free Peer Host',
                          icon: const Icon(
                            LucideIcons.plane,
                            color: AppTheme.accent,
                            size: 20,
                          ),
                          onPressed: () {
                            RequestHostDialog.show(
                              context,
                              communityId: item.id,
                              communityName: item.name,
                              communityChatId: 'chat_${item.id}',
                            );
                          },
                        )
                      : null),
          ),

          if (hasChildren && (_isExpanded || isPreExpanded))
            Column(
              children: item.children
                  .map(
                    (child) => Padding(
                      padding: EdgeInsets.only(
                        top: 8,
                        left:
                            (child.type == 'continent' ||
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
    final viewerHomeCountryCode = ref
        .watch(userProfileProvider)
        .value
        ?.homeCountryCode;
    return CommunityChatUtils.getCommunityAvatar(
      context: context,
      type: item.type,
      locationType: item.locationType,
      homeCountryCode: item.homeCountryCode,
      hostCountryCode: item.hostCountryCode,
      viewerHomeCountryCode: viewerHomeCountryCode,
      flag: item.flag,
      communityId: item.id,
      profileImage: item.profileImage?.value,
      size: size,
    );
  }
}
