import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/organization/repository/organization_repository.dart';
import 'package:diaspora_nearby/features/chat/providers/chat_identity_provider.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/models/profile_data.dart';
import 'package:diaspora_nearby/features/organization/widgets/organization_chat_preview.dart';
import 'package:firebase_database/firebase_database.dart';

class OrganizationManagementScreen extends ConsumerStatefulWidget {
  final String? initialOrgId;
  const OrganizationManagementScreen({super.key, this.initialOrgId});

  @override
  ConsumerState<OrganizationManagementScreen> createState() => _OrganizationManagementScreenState();
}

class _OrganizationManagementScreenState extends ConsumerState<OrganizationManagementScreen> {
  String? _selectedOrgId;
  Map<String, dynamic>? _extraOrg;
  bool _isLoadingExtra = false;
  bool _hasAttemptedFetch = false;

  @override
  void initState() {
    super.initState();
    _selectedOrgId = widget.initialOrgId;
  }

  Future<void> _fetchInitialOrg() async {
    if (widget.initialOrgId == null || _hasAttemptedFetch || _isLoadingExtra) return;
    
    setState(() => _isLoadingExtra = true);
    
    try {
      final repo = ref.read(organizationRepositoryProvider);
      final org = await repo.getOrganization(widget.initialOrgId!);
      if (mounted) {
        setState(() {
          _extraOrg = org;
          _isLoadingExtra = false;
          _hasAttemptedFetch = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingExtra = false;
           _hasAttemptedFetch = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final orgsAsync = ref.watch(userOrganizationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Organizations'),
      ),
      body: SafeArea(
        child: orgsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('Error: $err')),
          data: (orgs) {
            // Check if we need to fetch the initial org
            if (widget.initialOrgId != null && 
                !orgs.any((o) => o['id'] == widget.initialOrgId) && 
                !_hasAttemptedFetch) {
               // Schedule fetch after build
               WidgetsBinding.instance.addPostFrameCallback((_) => _fetchInitialOrg());
            }
  
            if (_isLoadingExtra) {
               return const Center(child: CircularProgressIndicator());
            }
  
            final allOrgs = [...orgs];
            final currentUserId = ref.read(authRepositoryProvider).currentUser?.uid;
  
            if (_extraOrg != null) {
                // Verify admin status
                final admins = (_extraOrg!['admins'] as List?)?.map((e) => e.toString()).toList() ?? [];
                final pending = (_extraOrg!['pendingAdmins'] as List?)?.map((e) => e.toString()).toList() ?? [];
                final isSuper = _extraOrg!['superAdminId'] == currentUserId;
                
                if (admins.contains(currentUserId) || pending.contains(currentUserId) || isSuper) {
                    if (!allOrgs.any((o) => o['id'] == _extraOrg!['id'])) {
                      allOrgs.add(_extraOrg!);
                    }
                }
            }
  
            if (allOrgs.isEmpty) {
               return Center(
                 child: SingleChildScrollView(
                   padding: const EdgeInsets.all(20),
                   child: Column(
                     mainAxisAlignment: MainAxisAlignment.center,
                     children: [
                       const Icon(LucideIcons.building2, size: 64, color: Colors.grey),
                       const SizedBox(height: 16),
                       Text('No organizations found', style: Theme.of(context).textTheme.titleLarge),
                       const SizedBox(height: 8),
                       const Text('You do not manage any organizations yet.'),
                       if (widget.initialOrgId != null) ...[
                          const SizedBox(height: 24),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Column(
                              children: [
                                Text('Debug Info (Please share this)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade900)),
                                const SizedBox(height: 8),
                                Text('Requested ID: ${widget.initialOrgId}', style: const TextStyle(fontSize: 12)),
                                Text('Fetch Attempted: $_hasAttemptedFetch', style: const TextStyle(fontSize: 12)),
                                Text('Fetch Result: ${_extraOrg == null ? "NULL (DB Read Failed)" : "Success (Found Doc)"}', style: const TextStyle(fontSize: 12)),
                                if (_extraOrg != null) ...[
                                  const Divider(),
                                  Text('User ID: $currentUserId', style: const TextStyle(fontSize: 12)),
                                  Text('Super Admin: ${_extraOrg!['superAdminId']}', style: const TextStyle(fontSize: 12)),
                                  Text('Admins in DB: ${(_extraOrg!['admins'] as List?)?.join(", ")}', style: const TextStyle(fontSize: 12)),
                                  const Text('Status: Permissions check failed.', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                                ]
                              ],
                            ),
                          ),
                       ]
                     ],
                   ),
                 ),
               );
            }
  
            // Default selection if only one
            if (_selectedOrgId == null && allOrgs.isNotEmpty) {
               WidgetsBinding.instance.addPostFrameCallback((_) {
                 if (mounted) {
                    setState(() {
                      _selectedOrgId = allOrgs.first['id'];
                    });
                 }
               });
            }
  
            // If multiple orgs and none selected, show list
            if (allOrgs.length > 1 && _selectedOrgId == null) {
                return ListView.builder(
                  itemCount: allOrgs.length,
                  itemBuilder: (context, index) {
                    final org = allOrgs[index];
                    return ListTile(
                      leading: CircleAvatar(backgroundImage: NetworkImage(org['profileImage'] ?? '')),
                      title: Text(org['businessName'] ?? org['name']),
                      subtitle: Text(org['type'] ?? 'Organization'),
                      onTap: () => setState(() => _selectedOrgId = org['id']),
                    );
                  },
                );
            }
  
            if (_selectedOrgId == null && allOrgs.isNotEmpty) return const SizedBox.shrink();
  
            final selectedOrg = allOrgs.firstWhere((o) => o['id'] == _selectedOrgId, orElse: () => allOrgs.first);
            
            return _buildOrgDetails(selectedOrg, allOrgs.length > 1);
          },
        ),
      ),
    );
  }

  Widget _buildOrgDetails(Map<String, dynamic> org, bool showSwitch) {
    final currentUserId = ref.watch(authRepositoryProvider).currentUser?.uid;
    final isSuperAdmin = org['superAdminId'] == currentUserId;
    final admins = List<String>.from(org['admins'] ?? []);
    final pendingAdmins = List<String>.from(org['pendingAdmins'] ?? []);
    final isPending = pendingAdmins.contains(currentUserId);

    if (isPending) {
       return Center(
         child: Padding(
           padding: const EdgeInsets.all(24.0),
           child: Column(
             mainAxisAlignment: MainAxisAlignment.center,
             children: [
               CircleAvatar(
                 radius: 40,
                 backgroundImage: NetworkImage(org['profileImage'] ?? ''),
                 child: org['profileImage'] == null ? const Icon(LucideIcons.building2, size: 40) : null,
               ),
               const SizedBox(height: 16),
               Text('Invitation to Join', style: Theme.of(context).textTheme.headlineSmall),
               const SizedBox(height: 8),
               Text(
                 'You have been invited to be an admin of ${org['businessName'] ?? org['name']}.',
                 textAlign: TextAlign.center,
               ),
               const SizedBox(height: 32),
               Row(
                 mainAxisAlignment: MainAxisAlignment.center,
                 children: [
                   OutlinedButton(
                     onPressed: () => _handleInviteResponse(org['id'], false),
                     child: const Text('Decline'),
                   ),
                   const SizedBox(width: 16),
                   FilledButton(
                     onPressed: () => _handleInviteResponse(org['id'], true),
                     child: const Text('Accept Invitation'),
                   ),
                 ],
               ),
             ],
           ),
         ),
       );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: OutlinedButton.icon(
                onPressed: () {
                   if (ref.read(userOrganizationsProvider).value?.length == 2) {
                      final orgs = ref.read(userOrganizationsProvider).value!;
                      final other = orgs.firstWhere((o) => o['id'] != _selectedOrgId);
                      setState(() => _selectedOrgId = other['id']);
                   } else {
                      setState(() => _selectedOrgId = null);
                   }
                },
                icon: const Icon(LucideIcons.arrowRightLeft),
                label: Text(ref.read(userOrganizationsProvider).value?.length == 2 ? 'Switch Organization' : 'View All Organizations'),
              ),
            ),
          
          // Header
          Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundImage: NetworkImage(org['profileImage'] ?? 'https://via.placeholder.com/150'),
                child: org['profileImage'] == null ? const Icon(LucideIcons.building2, size: 32) : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(org['businessName'] ?? org['name'] ?? 'Organization', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('${org['type']} \u2022 ${admins.length} Admins', style: const TextStyle(color: Colors.grey)),
                    const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: (org['status'] == 'active') ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: (org['status'] == 'active') ? Colors.green : Colors.orange),
                        ),
                        child: Text(
                          (org['status'] == 'active') ? 'Active' : 'Pending',
                          style: TextStyle(
                            fontSize: 12, 
                            color: (org['status'] == 'active') ? Colors.green : Colors.orange,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 24),

          // Embedded Chat Preview for Admins
          if (org['chatId'] != null) ...[
             OrganizationChatPreview(
               chatId: org['chatId'],
               title: 'Organization Messages',
             ),
             const SizedBox(height: 24),
          ],
          
          const Text('Admins', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Admins can manage the organization and act on its behalf.', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          
          // Admin List
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: admins.length,
            itemBuilder: (context, index) {
              final adminID = admins[index];
              final isMe = adminID == currentUserId;
              final isCreator = adminID == org['superAdminId'];

              return FutureBuilder(
                // We'd ideally need a batched fetch or user provider, but fetching individually for MVP is okay
                future: ref.read(profileRepositoryProvider).getUserProfile(adminID), // [FIX] Use ProfileRepository
                builder: (context, snapshot) {
                  final userData = snapshot.data;
                  final name = userData != null ? '${userData.firstName} ${userData.lastName}' : 'User $adminID';
                  // Email is not available in ProfileData


                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage: (userData?.profileImage != null && userData!.profileImage.isNotEmpty) 
                          ? NetworkImage(userData.profileImage) 
                          : null,
                      child: (userData?.profileImage == null || userData!.profileImage.isEmpty)
                          ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?')
                          : null,
                    ),
                    title: Text(name + (isMe ? ' (You)' : '')),
                    subtitle: Text(isCreator ? 'Super Admin' : 'Admin'),
                    trailing: (isSuperAdmin && !isCreator) // Only Super Admin can remove other admins
                        ? IconButton(
                            icon: const Icon(LucideIcons.trash2, color: Colors.red),
                            onPressed: () => _confirmRemoveAdmin(org['id'], adminID, name),
                          )
                        : null,
                  );
                }
              );
            },
          ),
          
          if (pendingAdmins.isNotEmpty) ...[
             const SizedBox(height: 24),
             const Text('Pending Invites', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
             const SizedBox(height: 8),
             
             ListView.builder(
               shrinkWrap: true,
               physics: const NeverScrollableScrollPhysics(),
               itemCount: pendingAdmins.length,
               itemBuilder: (context, index) {
                 final userId = pendingAdmins[index];
                 return FutureBuilder(
                   future: ref.read(profileRepositoryProvider).getUserProfile(userId),
                   builder: (context, snapshot) {
                     final userData = snapshot.data;
                     final name = userData != null ? '${userData.firstName} ${userData.lastName}' : 'User $userId';
                     
                     return ListTile(
                       contentPadding: EdgeInsets.zero,
                       leading: CircleAvatar(
                         backgroundColor: Colors.grey.shade200,
                         backgroundImage: (userData?.profileImage != null && userData!.profileImage.isNotEmpty) 
                             ? NetworkImage(userData.profileImage) 
                             : null,
                         child: (userData?.profileImage == null || userData!.profileImage.isEmpty)
                             ? const Icon(LucideIcons.clock, color: Colors.orange, size: 20)
                             : null, // Could overlay clock icon if needed, but user just asked for photo
                       ),
                       title: Text(name),
                       subtitle: const Text('Invite Sent'),
                       trailing: isSuperAdmin ? IconButton(
                         icon: const Icon(LucideIcons.x, color: Colors.grey),
                         onPressed: () => _cancelInvite(org['id'], userId),
                       ) : null,
                     );
                   }
                 );
               },
             ),
          ],
          
          if (isSuperAdmin)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              child: FilledButton.icon(
                onPressed: () => _showSelectAdminModal(org['id']),
                icon: const Icon(LucideIcons.plus),
                label: const Text('Add Admin'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
            ),
          const SizedBox(height: 16),

          const SizedBox(height: 32),
          const Text('Board Participants', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('These users can post messages to the organization board.', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),

          // Participants List
          FutureBuilder<List<String>>(
            future: _getParticipants(org['chatId']),
            builder: (context, snapshot) {
              final participants = snapshot.data ?? [];
              if (snapshot.connectionState == ConnectionState.waiting) return const CircularProgressIndicator();

              // Filter out admins from participants list for display if preferred, 
              // or show everyone but disable removal for admins.
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: participants.length,
                itemBuilder: (context, index) {
                  final userId = participants[index];
                  final isMe = userId == currentUserId;
                  final isAdminMember = admins.contains(userId);

                  return FutureBuilder(
                    future: ref.read(profileRepositoryProvider).getUserProfile(userId),
                    builder: (context, profileSnapshot) {
                      final userData = profileSnapshot.data;
                      final name = userData != null ? '${userData.firstName} ${userData.lastName}' : 'User $userId';

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundImage: (userData?.profileImage != null && userData!.profileImage.isNotEmpty) 
                              ? NetworkImage(userData.profileImage) 
                              : null,
                          child: (userData?.profileImage == null || userData!.profileImage.isEmpty)
                              ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?')
                              : null,
                        ),
                        title: Text(name + (isMe ? ' (You)' : '')),
                        subtitle: Text(isAdminMember ? 'Admin' : 'Member'),
                        trailing: (isSuperAdmin && !isAdminMember)
                            ? IconButton(
                                icon: const Icon(LucideIcons.userMinus, color: Colors.red),
                                onPressed: () => _removeChatMember(org['id'], userId, name),
                              )
                            : null,
                      );
                    },
                  );
                },
              );
            },
          ),

          if (isSuperAdmin)
             Padding(
               padding: const EdgeInsets.only(top: 16),
               child: OutlinedButton.icon(
                 onPressed: () => _showAddMemberModal(org),
                 icon: const Icon(LucideIcons.userPlus),
                 label: const Text('Add Participant from Followers'),
                 style: OutlinedButton.styleFrom(
                   minimumSize: const Size(double.infinity, 48),
                 ),
               ),
             ),
        ],
      ),
    );
  }

  Future<void> _showSelectAdminModal(String orgId) async {
    // Show spinner while fetching friends
    showDialog(
      context: context, 
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final friends = await ref.read(chatRepositoryProvider).getDirectChatFriends();
      if (mounted) Navigator.pop(context); // Close loading

      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (context) => DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
             if (friends.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(LucideIcons.users, size: 48, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('No contacts found from DMs.'),
                    ],
                  ),
                );
             }

             return Column(
               children: [
                 const Padding(
                   padding: EdgeInsets.all(16.0),
                   child: Text('Invite Admin', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                 ),
                 Expanded(
                   child: ListView.builder(
                     controller: scrollController,
                     itemCount: friends.length,
                     itemBuilder: (context, index) {
                       final friend = friends[index];
                       return ListTile(
                         leading: CircleAvatar(
                           backgroundImage: friend.profileImage.isNotEmpty ? NetworkImage(friend.profileImage) : null,
                           child: friend.profileImage.isEmpty ? Text(friend.firstName[0]) : null,
                         ),
                         title: Text('${friend.firstName} ${friend.lastName}'),
                         subtitle: Text((friend.profession != null && friend.profession!.isNotEmpty) ? friend.profession!.first : 'User'),
                         trailing: IconButton(
                           icon: const Icon(LucideIcons.send, color: Colors.blue),
                           onPressed: () async {
                              if (friend.uid != null) {
                                await _inviteAdminById(orgId, friend);
                                if (mounted) Navigator.pop(context);
                              }
                           },
                         ),
                       );
                     },
                   ),
                 ),
               ],
             );
          },
        ),
      );

    } catch (e) {
       if (mounted) Navigator.pop(context); // Close loading
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading contacts: $e')));
    }
  }

  Future<void> _inviteAdminById(String orgId, ProfileData friend) async {
    // Get org name
    final orgs = ref.read(userOrganizationsProvider).value ?? [];
    final org = orgs.firstWhere((o) => o['id'] == orgId, orElse: () => {});
    final orgName = org['businessName'] ?? org['name'] ?? 'the organization';

    try {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sending invitation...')));
      
      // 1. Add to pending lists
      await ref.read(organizationRepositoryProvider).inviteAdmin(orgId, friend.uid!);
      
      // 2. Send DM
      final currentUser = ref.read(authRepositoryProvider).currentUser;
      if (currentUser != null) {
         // Create chat logic is needed if doesn't exist, but 'friends' logic implies chat exists. 
         // Assuming getDirectChatFriends implies existing chat, we just send message.
         // But we need chatId. We can pass chatId in friend object or re-fetch.
         // For now, simpler: just create/get direct chat and send.
         
         final chatRepo = ref.read(chatRepositoryProvider);
         // This is blocking UI a bit but acceptable for MVP
         final chat = await chatRepo.createDirectChat(friend.uid!); 
         
         if (chat != null) {
           await chatRepo.sendTextMessage(
             chat.id, 
              'I have invited you to be an admin of "$orgName". Please go to Account > Manage Organizations to accept.',
           );
         }
      }


      ref.refresh(userOrganizationsProvider);
      
      if (mounted) {
         ScaffoldMessenger.of(context).hideCurrentSnackBar();
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invitation sent!')));
      }
    } catch (e) {
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to invite: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _handleInviteResponse(String orgId, bool accept) async {
     try {
       final repo = ref.read(organizationRepositoryProvider);
       final userId = ref.read(authRepositoryProvider).currentUser!.uid;

       if (accept) {
          await repo.acceptInvite(orgId, userId);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invitation accepted!')));
       } else {
          await repo.declineInvite(orgId, userId);
           if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invitation declined.')));
       }
       ref.refresh(userOrganizationsProvider);
     } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
     }
  }

  Future<void> _cancelInvite(String orgId, String userId) async {
      try {
        await ref.read(organizationRepositoryProvider).declineInvite(orgId, userId); // Same as declining
        ref.refresh(userOrganizationsProvider);
      } catch (e) {
        // error
      }
  }

  Future<void> _confirmRemoveAdmin(String orgId, String adminId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Admin?'),
        content: Text('Are you sure you want to remove $name from admins?'),
        actions: [
          TextButton(onPressed: () => context.pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => context.pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red), 
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ref.read(organizationRepositoryProvider).removeAdmin(orgId, adminId);
        ref.refresh(userOrganizationsProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Admin removed.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _removeChatMember(String orgId, String userId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from Chat?'),
        content: Text('Are you sure you want to remove $name from the organization board?'),
        actions: [
          TextButton(onPressed: () => context.pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => context.pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red), 
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ref.read(organizationRepositoryProvider).removeChatMember(orgId, userId);
        if (mounted) {
          setState(() {}); // Refresh future builder
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Member removed from chat.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<List<String>> _getParticipants(String? chatId) async {
    if (chatId == null) return [];
    try {
      final snapshot = await FirebaseDatabase.instance.ref('chats/$chatId/participants').get();
      if (snapshot.exists) {
        return List<String>.from(snapshot.value as List);
      }
    } catch (e) {
      debugPrint('Error fetching participants: $e');
    }
    return [];
  }

  Future<void> _showAddMemberModal(Map<String, dynamic> org) async {
    final followers = List<String>.from(org['followers'] ?? []);
    final chatId = org['chatId'] as String?;
    final existingParticipants = await _getParticipants(chatId);
    
    final potentialMembers = followers.where((f) => !existingParticipants.contains(f)).toList();

    if (!mounted) return;

    if (potentialMembers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No new followers to add.')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('Add Chat Participant', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: potentialMembers.length,
                  itemBuilder: (context, index) {
                    final userId = potentialMembers[index];
                    return FutureBuilder(
                      future: ref.read(profileRepositoryProvider).getUserProfile(userId),
                      builder: (context, snapshot) {
                        final userData = snapshot.data;
                        if (userData == null) return const SizedBox.shrink();
                        
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: userData.profileImage.isNotEmpty ? NetworkImage(userData.profileImage) : null,
                            child: userData.profileImage.isEmpty ? Text(userData.firstName[0]) : null,
                          ),
                          title: Text('${userData.firstName} ${userData.lastName}'),
                          trailing: IconButton(
                            icon: const Icon(LucideIcons.userPlus, color: Colors.blue),
                            onPressed: () async {
                              await ref.read(organizationRepositoryProvider).addChatMember(org['id'], userId);
                              if (mounted) {
                                Navigator.pop(context);
                                setState(() {});
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('User added to chat.')),
                                );
                              }
                            },
                          ),
                        );
                      }
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

