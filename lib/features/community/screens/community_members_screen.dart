import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:diaspora_nearby/features/shared/widgets/diaspora_app_bar.dart';
import 'package:diaspora_nearby/models/community_data.dart';
import 'package:diaspora_nearby/features/chat/utils/community_chat_utils.dart';
import 'package:diaspora_nearby/features/profile/screens/user_profile_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diaspora_nearby/models/profile_data.dart';
import 'package:diaspora_nearby/features/shared/widgets/user_card.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';

class CommunityMembersScreen extends ConsumerStatefulWidget {
  final String communityId;
  final Community community;

  const CommunityMembersScreen({
    super.key,
    required this.communityId,
    required this.community,
  });

  @override
  ConsumerState<CommunityMembersScreen> createState() => _CommunityMembersScreenState();
}

class _CommunityMembersScreenState extends ConsumerState<CommunityMembersScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CommunityChatUtils.getCommunityAvatar(
              context: context,
              type: widget.community.type,
              locationType: widget.community.locationType,
              homeCountryCode: widget.community.homeCountryCode,
              hostCountryCode: widget.community.hostCountryCode,
              communityId: widget.community.id,
              profileImage: widget.community.profileImage,
              size: 32,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.community.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
      body: FutureBuilder<List<ProfileData>>(
        // Fetch members from Firestore
        future: _fetchMembers(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final members = snapshot.data ?? [];
          final currentUser = ref.watch(authRepositoryProvider).currentUser;

          if (members.isEmpty) {
            return const Center(child: Text('No members found.'));
          }

          // Check if single member is self
          final isSingleMember = members.length == 1 && members.first.uid == currentUser?.uid;

          if (isSingleMember) {
             return Center(
               child: Padding(
                 padding: const EdgeInsets.all(32.0),
                 child: Column(
                   mainAxisAlignment: MainAxisAlignment.center,
                   children: [
                     Container(
                       padding: const EdgeInsets.all(24),
                       decoration: BoxDecoration(
                         color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                         shape: BoxShape.circle,
                       ),
                       child: const Icon(LucideIcons.partyPopper, size: 48, color: Colors.amber),
                     ),
                     const SizedBox(height: 24),
                     const Text(
                       'Congratulations!',
                       style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                     ),
                     const SizedBox(height: 12),
                     const Text(
                       'You are the first member of this community!\nInvite others to join the conversation.',
                       textAlign: TextAlign.center,
                       style: TextStyle(fontSize: 16, color: Colors.grey),
                     ),
                   ],
                 ),
               ),
             );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: members.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final member = members[index];
              return UserCardView(
                user: member,
                isStatic: true, // List view style
                onNameTap: () => context.push('/profile/${member.uid}'),
                onChatTap: () => context.push('/chat/direct/${member.uid}'),
              );
            },
          );
        },
      ),
    );
  }

  Future<List<ProfileData>> _fetchMembers() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('communityMemberships', arrayContains: widget.communityId)
          .limit(50)
          .get();
          
      final members = snapshot.docs.map((doc) {
        final data = doc.data();
        final profile = ProfileData.fromJson(data);
        profile.uid = doc.id;
        return profile;
      }).toList();

      // [FIX] Self-Correction for "First Member" scenario involving index lag.
      if (members.isEmpty) {
         final currentUserData = ref.read(userProfileProvider).value; 
         // If provider has data and confirms membership, assume we are the first member
         if (currentUserData != null && 
             currentUserData.communityMemberships != null && 
             currentUserData.communityMemberships!.contains(widget.communityId)) {
             return [currentUserData];
         }
      }

      return members;
    } catch (e) {
      debugPrint('Error fetching members: $e');
      return [];
    }
  }
}

