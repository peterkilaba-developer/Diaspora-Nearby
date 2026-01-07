import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart'; 
import 'package:diaspora_nearby/features/community/viewmodels/community_hierarchy_viewmodel.dart';
import 'package:diaspora_nearby/features/community/models/hierarchy_item.dart';
import 'package:diaspora_nearby/features/chat/utils/community_chat_utils.dart'; 
import 'package:diaspora_nearby/models/community_data.dart';
import 'package:diaspora_nearby/features/community/screens/community_members_screen.dart'; // Import existing screen for reuse
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/providers/global_search_provider.dart';

class CommunitiesScreen extends ConsumerStatefulWidget {
  const CommunitiesScreen({super.key});

  @override
  ConsumerState<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

class _CommunitiesScreenState extends ConsumerState<CommunitiesScreen> {
  
  List<HierarchyItem> _filterHierarchy(List<HierarchyItem> items, String query) {
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
               Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
               const SizedBox(height: 16),
               Text('Unable to load profile', style: TextStyle(color: Theme.of(context).colorScheme.error)),
               const SizedBox(height: 8),
               ElevatedButton(
                 onPressed: () => ref.refresh(userProfileProvider), 
                 child: const Text('Retry')
               )
             ],
           )
         );
      }
      
      // Case: Profile is null (not found in DB) but no error thrown
      if (user == null) {
          return Center(
           child: Column(
             mainAxisAlignment: MainAxisAlignment.center,
             children: [
               Icon(Icons.person_off, size: 48, color: Theme.of(context).disabledColor),
               const SizedBox(height: 16),
               Text('Profile incomplete or missing.', style: TextStyle(color: Theme.of(context).hintColor)),
               const SizedBox(height: 8),
               ElevatedButton(
                 onPressed: () => context.go('/profile-setup'), 
                 child: const Text('Complete Profile Setup')
               )
             ],
           )
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
                   Icon(Icons.handshake, size: 64, color: Theme.of(context).disabledColor),
                   const SizedBox(height: 16),
                   Text(
                      searchQuery.isNotEmpty ? 'No communities match your search.' : 'No communities found.',
                      style: TextStyle(color: Theme.of(context).hintColor)
                   ),
                   if (searchQuery.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      // No retry button on search empty state usually
                   ] else ...[
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () => ref.refresh(communityHierarchyProvider),
                        child: const Text('Retry'),
                      )
                   ]
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
                initiallyExpanded: searchQuery.isNotEmpty, // Auto-expand if searching to show matches deep in tree
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

class HierarchyItemWidget extends StatefulWidget {
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
  State<HierarchyItemWidget> createState() => _HierarchyItemWidgetState();
}

class _HierarchyItemWidgetState extends State<HierarchyItemWidget> {
  bool _isExpanded = false;
  
  @override
  void initState() {
    super.initState();
    // Pre-expand items where isExpandable is false (countries)
    // These items have children but should always show them
    if ((widget.item.children.isNotEmpty && widget.item.isExpandable == false) || widget.initiallyExpanded) {
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
      description: '', // Default description
      homeCountryCode: widget.item.homeCountryCode ?? '',
      hostCountryCode: widget.item.hostCountryCode ?? '',
      location: widget.item.location ?? {},
      profileImage: widget.item.profileImage?.value,
      flag: widget.item.flag ?? ''
    );

    // Push to full screen route instead of modal bottom sheet
    context.push('/communities/${community.id}/members', extra: community);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final hasChildren = item.children.isNotEmpty || item.isExpandable;
    final isPreExpanded = item.children.isNotEmpty && item.isExpandable == false;

    // 1. Global Community (Special Card)
    if (item.type == 'global') {
      return Column(
        children: [
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            color: Theme.of(context).cardColor,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide.none), // Strict no border
            child: InkWell(
              onTap: () => _openMembersList(context),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                 padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                 child: Column(
                   children: [
                     Row(
                       children: [
                         // Use consistent avatar builder
                         _buildAvatar(item, size: 48),
                         const SizedBox(width: 12),
                         Expanded(
                           child: Column(
                             crossAxisAlignment: CrossAxisAlignment.start,
                             children: [
                               Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                               Row(
                                 children: [
                                   Icon(Icons.handshake, size: 14, color: Theme.of(context).hintColor),
                                   const SizedBox(width: 4),
                                   Text('${item.totalMembers} members worldwide', style: TextStyle(color: Theme.of(context).hintColor)),
                                 ],
                               ),
                             ],
                           )
                         ),
                         Icon(LucideIcons.chevronRight, color: Theme.of(context).primaryColor), // Indication to click
                       ],
                     ),
                     if (item.globalStats != null) ...[
                       const SizedBox(height: 16),
                       Row(
                         mainAxisAlignment: MainAxisAlignment.spaceAround,
                         children: [
                            _buildStat('Continents', item.globalStats!.continents),
                            _buildStat('Countries', item.globalStats!.countries),
                            _buildStat('Cities', item.globalStats!.cities),
                         ],
                       )
                     ]
                   ],
                 )
              ),
            ),
          ),
          // Show global children (continents) always
          if (item.children.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 0, top: 4),
              child: Column(
                children: item.children.map((child) => 
                     Padding(
                       padding: const EdgeInsets.only(top: 8), 
                       child: HierarchyItemWidget(
                         item: child,
                         hostDepth: 0, // Continents are home, not host
                       ),
                     )
                ).toList(),
              ),
            ),
        ],
      );
    }

    // 2. Standard Items (Custom Split Interaction)
    return Card(
      margin: const EdgeInsets.only(bottom: 8), // Horizontal is 0 by default for only(bottom)
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide.none),
      child: Column(
        children: [
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), 
            leading: CommunityChatUtils.getCommunityAvatar(
                type: item.type,
                locationType: item.locationType,
                profileImage: item.profileImage?.value, // [NEW] Use rich data
                homeCountryCode: item.homeCountryCode,
                hostCountryCode: item.hostCountryCode,
                flag: item.flag,
                communityId: item.id,
                size: 48, // Slightly larger for hierarchy items
                context: context
            ),
            title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Row(
              children: [
                Icon(Icons.handshake, size: 14, color: Theme.of(context).hintColor),
                const SizedBox(width: 4),
                Text('${item.totalMembers} members', style: TextStyle(color: Theme.of(context).hintColor)),
              ],
            ),
            onTap: () => _openMembersList(context), // <--- Main tap opens members
            trailing: hasChildren 
                ? (isPreExpanded 
                    // Pre-expanded items: no chevron button, just show indicator
                    ? const SizedBox(width: 16) // Empty space to maintain alignment
                    // Regular expandable items: show toggleable chevron
                    : IconButton(
                        icon: Icon(
                          _isExpanded ? LucideIcons.chevronDown : LucideIcons.chevronRight, 
                          color: Theme.of(context).iconTheme.color?.withOpacity(0.5)
                        ),
                        onPressed: () {
                          setState(() {
                            _isExpanded = !_isExpanded;
                          });
                        },
                      )
                  )
                : null, // NO CHEVRON for leaf nodes (Cities)
          ),
          
          // Show children if expanded OR if pre-expanded
          if (hasChildren && _isExpanded)
            Padding(
              padding: EdgeInsets.only(
                // Only indent host locations, not home/global
                left: item.locationType == 'host' 
                    ? widget.hostDepth * 12.0  // 12px per host depth level
                    : 0,  // Home/global: no indent
                bottom: 8,
                right: 8
              ),
              child: Column(
                children: item.children.map((child) => 
                     Padding(
                       padding: const EdgeInsets.only(top: 8), 
                       child: HierarchyItemWidget(
                         item: child,
                         // Increment hostDepth only if this is a host location
                         hostDepth: child.locationType == 'host' 
                             ? widget.hostDepth + 1  // Host location: increment
                             : 0,  // Home/global location: reset to 0
                       ),
                     )
                ).toList(),
              ),
            )
        ],
      ),
    );
  }

  Widget _buildStat(String label, int value) {
    return Column(
      children: [
        Text(value.toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
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
          size: size
      );
  }
}


