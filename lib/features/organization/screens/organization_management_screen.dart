import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/organization/repository/organization_repository.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/organization/widgets/organization_chat_preview.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class OrganizationManagementScreen extends ConsumerStatefulWidget {
  final String? initialOrgId;
  const OrganizationManagementScreen({super.key, this.initialOrgId});

  @override
  ConsumerState<OrganizationManagementScreen> createState() =>
      _OrganizationManagementScreenState();
}

class _OrganizationManagementScreenState
    extends ConsumerState<OrganizationManagementScreen> {
  static final Map<String, List<String>> _participantsCache = {};
  static List<ProfileData>? _cachedFriends;

  String? _selectedOrgId;
  Map<String, dynamic>? _extraOrg;
  bool _isLoadingExtra = false;
  bool _hasAttemptedFetch = false;

  // Local optimistic overrides per orgId
  final Map<String, Map<String, dynamic>> _optimisticOrgs = {};

  @override
  void initState() {
    super.initState();
    _selectedOrgId = widget.initialOrgId;
    if (widget.initialOrgId != null) {
      final cached = ref
          .read(organizationRepositoryProvider)
          .getCachedOrganization(widget.initialOrgId!);
      if (cached != null) {
        _extraOrg = Map<String, dynamic>.from(cached);
        _hasAttemptedFetch = true;
      }
    }
  }

  Future<void> _fetchInitialOrg() async {
    if (widget.initialOrgId == null || _hasAttemptedFetch || _isLoadingExtra) {
      return;
    }

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

  Map<String, dynamic> _applyOptimisticOrg(Map<String, dynamic> raw) {
    final id = raw['id'] as String?;
    if (id != null && _optimisticOrgs.containsKey(id)) {
      return {...raw, ..._optimisticOrgs[id]!};
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final orgsAsync = ref.watch(userOrganizationsProvider);
    final currentUserId = ref.read(authRepositoryProvider).currentUser?.uid;
    final repo = ref.read(organizationRepositoryProvider);
    final orgsList =
        orgsAsync.value ??
        (currentUserId != null
            ? repo.getCachedUserOrganizations(currentUserId)
            : null);

    return Scaffold(
      appBar: AppBar(title: const Text('Manage Organizations')),
      body: SafeArea(
        child: Builder(
          builder: (context) {
            if (orgsList == null && orgsAsync.isLoading && _extraOrg == null) {
              return const Center(child: CircularProgressIndicator());
            }

            final orgs = orgsList ?? const <Map<String, dynamic>>[];

            if (widget.initialOrgId != null &&
                !orgs.any((o) => o['id'] == widget.initialOrgId) &&
                !_hasAttemptedFetch) {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _fetchInitialOrg(),
              );
            }

            if (_isLoadingExtra && orgs.isEmpty && _extraOrg == null) {
              return const Center(child: CircularProgressIndicator());
            }

            final allOrgs = orgs.map(_applyOptimisticOrg).toList();

            if (_extraOrg != null) {
              final extra = _applyOptimisticOrg(_extraOrg!);
              final admins =
                  (extra['admins'] as List?)
                      ?.map((e) => e.toString())
                      .toList() ??
                  [];
              final pending =
                  (extra['pendingAdmins'] as List?)
                      ?.map((e) => e.toString())
                      .toList() ??
                  [];
              final isSuper = extra['superAdminId'] == currentUserId;

              if (admins.contains(currentUserId) ||
                  pending.contains(currentUserId) ||
                  isSuper) {
                if (!allOrgs.any((o) => o['id'] == extra['id'])) {
                  allOrgs.add(extra);
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
                      const Icon(
                        LucideIcons.building2,
                        size: 64,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No organizations found',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      const Text('You do not manage any organizations yet.'),
                    ],
                  ),
                ),
              );
            }

            final effectiveSelectedId =
                _selectedOrgId ??
                (allOrgs.length == 1 ? allOrgs.first['id'] as String? : null);

            if (allOrgs.length > 1 && effectiveSelectedId == null) {
              return ListView.builder(
                itemCount: allOrgs.length,
                itemBuilder: (context, index) {
                  final org = allOrgs[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: NetworkImage(org['profileImage'] ?? ''),
                    ),
                    title: Text(org['businessName'] ?? org['name']),
                    subtitle: Text(org['type'] ?? 'Organization'),
                    onTap: () => setState(() => _selectedOrgId = org['id']),
                  );
                },
              );
            }

            final selectedOrg = allOrgs.firstWhere(
              (o) => o['id'] == effectiveSelectedId,
              orElse: () => allOrgs.first,
            );

            return _buildOrgDetails(selectedOrg, allOrgs);
          },
        ),
      ),
    );
  }

  Widget _buildOrgDetails(
    Map<String, dynamic> org,
    List<Map<String, dynamic>> allOrgs,
  ) {
    final currentUserId = ref.watch(authRepositoryProvider).currentUser?.uid;
    final isSuperAdmin = org['superAdminId'] == currentUserId;
    final admins = List<String>.from(org['admins'] ?? []);
    final pendingAdmins = List<String>.from(org['pendingAdmins'] ?? []);
    final isPending = pendingAdmins.contains(currentUserId);
    final profileRepo = ref.read(profileRepositoryProvider);

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
                child: org['profileImage'] == null
                    ? const Icon(LucideIcons.building2, size: 40)
                    : null,
              ),
              const SizedBox(height: 16),
              Text(
                'Invitation to Join',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'You have been invited to be an admin of ${org['businessName'] ?? org['name']}.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton.tonal(
                    onPressed: () => _handleInviteResponse(org, false),
                    child: const Text('Decline'),
                  ),
                  const SizedBox(width: 16),
                  FilledButton(
                    onPressed: () => _handleInviteResponse(org, true),
                    child: const Text('Accept Invitation'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final chatId = org['chatId'] as String?;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (allOrgs.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: FilledButton.tonalIcon(
                onPressed: () {
                  if (allOrgs.length == 2) {
                    final other = allOrgs.firstWhere(
                      (o) => o['id'] != org['id'],
                      orElse: () => allOrgs.first,
                    );
                    setState(() => _selectedOrgId = other['id']);
                  } else {
                    setState(() => _selectedOrgId = null);
                  }
                },
                icon: const Icon(LucideIcons.arrowRightLeft),
                label: Text(
                  allOrgs.length == 2
                      ? 'Switch Organization'
                      : 'View All Organizations',
                ),
              ),
            ),

          // Header
          Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundImage: NetworkImage(
                  org['profileImage'] ?? 'https://via.placeholder.com/150',
                ),
                child: org['profileImage'] == null
                    ? const Icon(LucideIcons.building2, size: 32)
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      org['businessName'] ?? org['name'] ?? 'Organization',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${org['type']} \u2022 ${admins.length} Admins',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: (org['status'] == 'active')
                            ? Colors.green.withValues(alpha: 0.1)
                            : Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        (org['status'] == 'active') ? 'Active' : 'Pending',
                        style: TextStyle(
                          fontSize: 12,
                          color: (org['status'] == 'active')
                              ? Colors.green
                              : Colors.orange,
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
          if (chatId != null) ...[
            OrganizationChatPreview(
              chatId: chatId,
              canViewMessages: true,
              title: 'Organization Messages',
            ),
            const SizedBox(height: 24),
          ],

          const Text(
            'Admins',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Admins can manage the organization and act on its behalf.',
            style: TextStyle(color: Colors.grey),
          ),
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

              return FutureBuilder<ProfileData?>(
                initialData: profileRepo.getCachedProfile(adminID),
                future: profileRepo.getUserProfile(adminID),
                builder: (context, snapshot) {
                  final userData = snapshot.data;
                  final name = userData != null
                      ? '${userData.firstName} ${userData.lastName}'
                      : 'User $adminID';

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage:
                          (userData?.profileImage != null &&
                              userData!.profileImage.isNotEmpty)
                          ? NetworkImage(userData.profileImage)
                          : null,
                      child:
                          (userData?.profileImage == null ||
                              userData!.profileImage.isEmpty)
                          ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?')
                          : null,
                    ),
                    title: Text(name + (isMe ? ' (You)' : '')),
                    subtitle: Text(isCreator ? 'Super Admin' : 'Admin'),
                    trailing: (isSuperAdmin && !isCreator)
                        ? IconButton(
                            icon: const Icon(
                              LucideIcons.trash2,
                              color: Colors.red,
                            ),
                            onPressed: () =>
                                _confirmRemoveAdmin(org, adminID, name),
                          )
                        : null,
                  );
                },
              );
            },
          ),

          if (pendingAdmins.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text(
              'Pending Invites',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: pendingAdmins.length,
              itemBuilder: (context, index) {
                final userId = pendingAdmins[index];
                return FutureBuilder<ProfileData?>(
                  initialData: profileRepo.getCachedProfile(userId),
                  future: profileRepo.getUserProfile(userId),
                  builder: (context, snapshot) {
                    final userData = snapshot.data;
                    final name = userData != null
                        ? '${userData.firstName} ${userData.lastName}'
                        : 'User $userId';

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: Colors.grey.shade200,
                        backgroundImage:
                            (userData?.profileImage != null &&
                                userData!.profileImage.isNotEmpty)
                            ? NetworkImage(userData.profileImage)
                            : null,
                        child:
                            (userData?.profileImage == null ||
                                userData!.profileImage.isEmpty)
                            ? const Icon(
                                LucideIcons.clock,
                                color: Colors.orange,
                                size: 20,
                              )
                            : null,
                      ),
                      title: Text(name),
                      subtitle: const Text('Invite Sent'),
                      trailing: isSuperAdmin
                          ? IconButton(
                              icon: const Icon(
                                LucideIcons.x,
                                color: Colors.grey,
                              ),
                              onPressed: () => _cancelInvite(org, userId),
                            )
                          : null,
                    );
                  },
                );
              },
            ),
          ],

          if (isSuperAdmin)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              child: FilledButton.icon(
                onPressed: () => _showSelectAdminModal(org),
                icon: const Icon(LucideIcons.plus),
                label: const Text('Add Admin'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
            ),
          const SizedBox(height: 16),

          const SizedBox(height: 32),
          const Text(
            'Board Participants',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'These users can post messages to the organization board.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),

          // Participants List
          FutureBuilder<List<String>>(
            initialData: chatId != null ? _participantsCache[chatId] : null,
            future: _getParticipants(chatId),
            builder: (context, snapshot) {
              final participants = snapshot.data ?? [];
              if (snapshot.data == null &&
                  snapshot.connectionState == ConnectionState.waiting) {
                return const CircularProgressIndicator();
              }

              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: participants.length,
                itemBuilder: (context, index) {
                  final userId = participants[index];
                  final isMe = userId == currentUserId;
                  final isAdminMember = admins.contains(userId);

                  return FutureBuilder<ProfileData?>(
                    initialData: profileRepo.getCachedProfile(userId),
                    future: profileRepo.getUserProfile(userId),
                    builder: (context, profileSnapshot) {
                      final userData = profileSnapshot.data;
                      final name = userData != null
                          ? '${userData.firstName} ${userData.lastName}'
                          : 'User $userId';

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundImage:
                              (userData?.profileImage != null &&
                                  userData!.profileImage.isNotEmpty)
                              ? NetworkImage(userData.profileImage)
                              : null,
                          child:
                              (userData?.profileImage == null ||
                                  userData!.profileImage.isEmpty)
                              ? Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                                )
                              : null,
                        ),
                        title: Text(name + (isMe ? ' (You)' : '')),
                        subtitle: Text(isAdminMember ? 'Admin' : 'Member'),
                        trailing: (isSuperAdmin && !isAdminMember)
                            ? IconButton(
                                icon: const Icon(
                                  LucideIcons.userMinus,
                                  color: Colors.red,
                                ),
                                onPressed: () =>
                                    _removeChatMember(org, userId, name),
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
              child: FilledButton.tonalIcon(
                onPressed: () => _showAddMemberModal(org),
                icon: const Icon(LucideIcons.userPlus),
                label: const Text('Add Participant from Followers'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showSelectAdminModal(Map<String, dynamic> org) async {
    final orgId = org['id'] as String;
    final friendsFuture = ref
        .read(chatRepositoryProvider)
        .getDirectChatFriends()
        .then((list) {
          _cachedFriends = list;
          return list;
        });

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(sheetCtx).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            expand: false,
            builder: (context, scrollController) {
              return FutureBuilder<List<ProfileData>>(
                initialData: _cachedFriends,
                future: friendsFuture,
                builder: (context, snapshot) {
                  final friends = snapshot.data;
                  if (friends == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (friends.isEmpty) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(LucideIcons.users, size: 48, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('No contacts found from DMs.'),
                        ],
                      ),
                    );
                  }

                  return Column(
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text(
                          'Invite Admin',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          controller: scrollController,
                          itemCount: friends.length,
                          itemBuilder: (context, index) {
                            final friend = friends[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundImage: friend.profileImage.isNotEmpty
                                    ? NetworkImage(friend.profileImage)
                                    : null,
                                child: friend.profileImage.isEmpty
                                    ? Text(friend.firstName[0])
                                    : null,
                              ),
                              title: Text(
                                '${friend.firstName} ${friend.lastName}',
                              ),
                              subtitle: Text(
                                (friend.profession != null &&
                                        friend.profession!.isNotEmpty)
                                    ? friend.profession!.first
                                    : 'User',
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  LucideIcons.send,
                                  color: Colors.blue,
                                ),
                                onPressed: () {
                                  if (friend.uid != null) {
                                    Navigator.pop(sheetCtx);
                                    _inviteAdminById(org, orgId, friend);
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
              );
            },
          ),
        ),
      ),
    );
  }

  void _inviteAdminById(
    Map<String, dynamic> org,
    String orgId,
    ProfileData friend,
  ) {
    final friendUid = friend.uid;
    if (friendUid == null) return;

    final orgName = org['businessName'] ?? org['name'] ?? 'the organization';
    final repo = ref.read(organizationRepositoryProvider);
    final prevPending = List<String>.from(org['pendingAdmins'] ?? []);
    final updatedPending = List<String>.from(prevPending);
    if (!updatedPending.contains(friendUid)) {
      updatedPending.add(friendUid);
    }

    setState(() {
      _optimisticOrgs[orgId] = {...org, 'pendingAdmins': updatedPending};
    });
    repo.cacheOrganization(orgId, _optimisticOrgs[orgId]!);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Invitation sent!')));

    unawaited(() async {
      try {
        await repo.inviteAdmin(orgId, friendUid);
        final currentUser = ref.read(authRepositoryProvider).currentUser;
        if (currentUser != null) {
          final chatRepo = ref.read(chatRepositoryProvider);
          final chat = await chatRepo.createDirectChat(friendUid);
          if (chat != null) {
            await chatRepo.sendTextMessage(
              chat.id,
              'I have invited you to be an admin of "$orgName". Please go to Account > Manage Organizations to accept.',
            );
          }
        }
        ref.invalidate(userOrganizationsProvider);
      } catch (e) {
        if (mounted) {
          setState(() {
            _optimisticOrgs[orgId] = {...org, 'pendingAdmins': prevPending};
          });
          repo.cacheOrganization(orgId, _optimisticOrgs[orgId]!);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to invite: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }());
  }

  void _handleInviteResponse(Map<String, dynamic> org, bool accept) {
    final orgId = org['id'] as String;
    final repo = ref.read(organizationRepositoryProvider);
    final userId = ref.read(authRepositoryProvider).currentUser?.uid;
    if (userId == null) return;

    final prevAdmins = List<String>.from(org['admins'] ?? []);
    final prevPending = List<String>.from(org['pendingAdmins'] ?? []);
    final updatedAdmins = List<String>.from(prevAdmins);
    final updatedPending = List<String>.from(prevPending)..remove(userId);
    if (accept && !updatedAdmins.contains(userId)) {
      updatedAdmins.add(userId);
    }

    setState(() {
      _optimisticOrgs[orgId] = {
        ...org,
        'admins': updatedAdmins,
        'pendingAdmins': updatedPending,
      };
    });
    repo.cacheOrganization(orgId, _optimisticOrgs[orgId]!);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(accept ? 'Invitation accepted!' : 'Invitation declined.'),
      ),
    );

    final action = accept
        ? repo.acceptInvite(orgId, userId)
        : repo.declineInvite(orgId, userId);

    unawaited(
      action
          .then((_) => ref.invalidate(userOrganizationsProvider))
          .catchError((Object e) {
            if (mounted) {
              setState(() {
                _optimisticOrgs[orgId] = {
                  ...org,
                  'admins': prevAdmins,
                  'pendingAdmins': prevPending,
                };
              });
              repo.cacheOrganization(orgId, _optimisticOrgs[orgId]!);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Error: $e')));
            }
          }),
    );
  }

  void _cancelInvite(Map<String, dynamic> org, String userId) {
    final orgId = org['id'] as String;
    final repo = ref.read(organizationRepositoryProvider);
    final prevPending = List<String>.from(org['pendingAdmins'] ?? []);
    final updatedPending = List<String>.from(prevPending)..remove(userId);

    setState(() {
      _optimisticOrgs[orgId] = {...org, 'pendingAdmins': updatedPending};
    });
    repo.cacheOrganization(orgId, _optimisticOrgs[orgId]!);

    unawaited(
      repo
          .declineInvite(orgId, userId)
          .then((_) => ref.invalidate(userOrganizationsProvider))
          .catchError((Object e) {
            if (mounted) {
              setState(() {
                _optimisticOrgs[orgId] = {...org, 'pendingAdmins': prevPending};
              });
              repo.cacheOrganization(orgId, _optimisticOrgs[orgId]!);
            }
          }),
    );
  }

  Future<void> _confirmRemoveAdmin(
    Map<String, dynamic> org,
    String adminId,
    String name,
  ) async {
    final orgId = org['id'] as String;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
          title: const Text('Remove Admin?'),
          content: Text('Are you sure you want to remove $name from admins?'),
          actions: [
            TextButton(
              onPressed: () => context.pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => context.pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Remove'),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      final repo = ref.read(organizationRepositoryProvider);
      final prevAdmins = List<String>.from(org['admins'] ?? []);
      final updatedAdmins = List<String>.from(prevAdmins)..remove(adminId);

      setState(() {
        _optimisticOrgs[orgId] = {...org, 'admins': updatedAdmins};
      });
      repo.cacheOrganization(orgId, _optimisticOrgs[orgId]!);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Admin removed.')));
      }

      unawaited(
        repo
            .removeAdmin(orgId, adminId)
            .then((_) => ref.invalidate(userOrganizationsProvider))
            .catchError((Object e) {
              if (mounted) {
                setState(() {
                  _optimisticOrgs[orgId] = {...org, 'admins': prevAdmins};
                });
                repo.cacheOrganization(orgId, _optimisticOrgs[orgId]!);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }),
      );
    }
  }

  Future<void> _removeChatMember(
    Map<String, dynamic> org,
    String userId,
    String name,
  ) async {
    final orgId = org['id'] as String;
    final chatId = org['chatId'] as String?;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
          title: const Text('Remove from Chat?'),
          content: Text(
            'Are you sure you want to remove $name from the organization board?',
          ),
          actions: [
            TextButton(
              onPressed: () => context.pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => context.pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Remove'),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      final prevParticipants = chatId != null
          ? List<String>.from(_participantsCache[chatId] ?? [])
          : <String>[];
      if (chatId != null && _participantsCache.containsKey(chatId)) {
        setState(() {
          _participantsCache[chatId] = List<String>.from(prevParticipants)
            ..remove(userId);
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Member removed from chat.')),
        );
      }

      unawaited(
        ref
            .read(organizationRepositoryProvider)
            .removeChatMember(orgId, userId)
            .catchError((Object e) {
              if (mounted) {
                if (chatId != null) {
                  setState(() {
                    _participantsCache[chatId] = prevParticipants;
                  });
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }),
      );
    }
  }

  Future<List<String>> _getParticipants(String? chatId) async {
    if (chatId == null) return [];
    try {
      final chatDoc = await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .get();
      if (chatDoc.exists) {
        final list = List<String>.from(chatDoc.data()?['participants'] ?? []);
        _participantsCache[chatId] = list;
        return list;
      }
    } catch (e) {
      debugPrint('Error fetching participants: $e');
    }
    return _participantsCache[chatId] ?? [];
  }

  Future<void> _showAddMemberModal(Map<String, dynamic> org) async {
    final followers = List<String>.from(org['followers'] ?? []);
    final chatId = org['chatId'] as String?;
    final existingParticipants =
        (chatId != null ? _participantsCache[chatId] : null) ??
        await _getParticipants(chatId);

    final potentialMembers = followers
        .where((f) => !existingParticipants.contains(f))
        .toList();

    if (!mounted) return;

    if (potentialMembers.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No new followers to add.')));
      return;
    }

    final profileRepo = ref.read(profileRepositoryProvider);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(sheetCtx).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            expand: false,
            builder: (context, scrollController) {
              return Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text(
                      'Add Chat Participant',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: potentialMembers.length,
                      itemBuilder: (context, index) {
                        final userId = potentialMembers[index];
                        return FutureBuilder<ProfileData?>(
                          initialData: profileRepo.getCachedProfile(userId),
                          future: profileRepo.getUserProfile(userId),
                          builder: (context, snapshot) {
                            final userData = snapshot.data;
                            if (userData == null) {
                              return const SizedBox.shrink();
                            }

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundImage:
                                    userData.profileImage.isNotEmpty
                                    ? NetworkImage(userData.profileImage)
                                    : null,
                                child: userData.profileImage.isEmpty
                                    ? Text(userData.firstName[0])
                                    : null,
                              ),
                              title: Text(
                                '${userData.firstName} ${userData.lastName}',
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  LucideIcons.userPlus,
                                  color: Colors.blue,
                                ),
                                onPressed: () {
                                  Navigator.pop(sheetCtx);
                                  if (chatId != null) {
                                    final current = List<String>.from(
                                      _participantsCache[chatId] ?? [],
                                    );
                                    if (!current.contains(userId)) {
                                      current.add(userId);
                                      setState(() {
                                        _participantsCache[chatId] = current;
                                      });
                                    }
                                  }
                                  ScaffoldMessenger.of(this.context)
                                      .showSnackBar(
                                        const SnackBar(
                                          content: Text('User added to chat.'),
                                        ),
                                      );
                                  unawaited(
                                    ref
                                        .read(organizationRepositoryProvider)
                                        .addChatMember(org['id'], userId)
                                        .catchError((Object e) {
                                          if (mounted && chatId != null) {
                                            setState(() {
                                              _participantsCache[chatId]
                                                  ?.remove(userId);
                                            });
                                          }
                                        }),
                                  );
                                },
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
