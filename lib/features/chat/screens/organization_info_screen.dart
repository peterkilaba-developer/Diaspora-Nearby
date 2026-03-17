import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diaspora_nearby/features/organization/repository/organization_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/shared/widgets/user_card.dart';
import 'package:diaspora_nearby/core/utils/location_utils.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart'; // [NEW]

class OrganizationInfoScreen extends ConsumerStatefulWidget {
  final String chatId;
  final String orgName;
  final String? orgImage;
  final String currentUserId;

  const OrganizationInfoScreen({
    super.key,
    required this.chatId,
    required this.orgName,
    this.orgImage,
    required this.currentUserId,
  });

  @override
  ConsumerState<OrganizationInfoScreen> createState() =>
      _OrganizationInfoScreenState();
}

class _OrganizationInfoScreenState
    extends ConsumerState<OrganizationInfoScreen> {
  Map<String, dynamic>? _orgData;
  bool _isLoading = true;
  bool _isFollowing = false;
  bool _isFollowLoading = false;
  List<ProfileData> _participants = [];
  List<ProfileData> _admins = [];
  List<ProfileData> _followers = [];
  bool _isAdmin = false;
  bool _isMuted = false; // [NEW]

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(organizationRepositoryProvider);

      // Extract orgId from chatId (org_ID)
      String orgId = widget.chatId;
      if (orgId.startsWith('org_')) {
        orgId = orgId.substring(4);
      }

      final data = await repo.getOrganization(orgId);
      if (data != null) {
        _orgData = data;
        _isFollowing = List<String>.from(
          data['followers'] ?? [],
        ).contains(widget.currentUserId);
        _isAdmin =
            List<String>.from(
              data['admins'] ?? [],
            ).contains(widget.currentUserId) ||
            data['superAdminId'] == widget.currentUserId;

        // Load Participants and Admins details
        await _loadMembers(data);

        // [NEW] Fetch Mute Status
        try {
          final muteDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(widget.currentUserId)
              .collection('userChats')
              .doc(widget.chatId)
              .get();
          if (muteDoc.exists && muteDoc.data()?['muted'] == true) {
            _isMuted = true;
          }
        } catch (e) {
          debugPrint('Error fetching mute status: $e');
        }
      }
    } catch (e) {
      debugPrint('Error loading organization info: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMembers(Map<String, dynamic> orgData) async {
    final profileRepo = ref.read(profileRepositoryProvider);

    // 1. Helper to get clean IDs
    final superAdminId = orgData['superAdminId'] as String?;
    final adminIds = List<String>.from(orgData['admins'] ?? []);

    // Ensure Super Admin is first
    if (superAdminId != null) {
      adminIds.remove(superAdminId);
      adminIds.insert(0, superAdminId);
    }

    // Fetch Participants from Firestore
    final chatDoc = await FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .get();
    List<String> chatParticipantIds = [];
    if (chatDoc.exists) {
      chatParticipantIds = List<String>.from(
        chatDoc.data()?['participants'] ?? [],
      );
    }

    // Fetch Followers (Org Followers)
    final followerIds = List<String>.from(orgData['followers'] ?? []);

    // Filter Logic to remove duplicates across sections
    final Set<String> processedIds = {};

    // 1. Admins
    final finalAdminIds = <String>[];
    for (var id in adminIds) {
      if (!processedIds.contains(id)) {
        finalAdminIds.add(id);
        processedIds.add(id);
      }
    }

    // 2. Chat Participants (Board) - Exclude Admins
    final finalParticipantIds = <String>[];
    for (var id in chatParticipantIds) {
      if (!processedIds.contains(id)) {
        finalParticipantIds.add(id);
        processedIds.add(id);
      }
    }

    // 3. Followers - Exclude Admins & Participants
    final finalFollowerIds = <String>[];
    for (var id in followerIds) {
      if (!processedIds.contains(id)) {
        finalFollowerIds.add(id);
        processedIds.add(id);
      }
    }

    // Fetch Profiles
    final adminProfiles = await profileRepo.getProfiles(finalAdminIds);
    // Sort admins to match ID order (Super admin first)
    adminProfiles.sort(
      (a, b) => finalAdminIds
          .indexOf(a.uid ?? '')
          .compareTo(finalAdminIds.indexOf(b.uid ?? '')),
    );

    final participantProfiles = await profileRepo.getProfiles(
      finalParticipantIds,
    );
    final followerProfiles = await profileRepo.getProfiles(finalFollowerIds);

    if (mounted) {
      setState(() {
        _admins = adminProfiles;
        _participants = participantProfiles;
        _followers = followerProfiles;
      });
    }
  }

  String? _getAdminTitle(String? uid) {
    if (uid == null || _orgData == null) return null;

    // Don't show title in card for Super Admin, it's in the section header now
    if (uid == _orgData!['superAdminId']) return null;

    final titles = _orgData!['adminTitles'];
    if (titles is Map && titles.containsKey(uid)) {
      return titles[uid].toString();
    }

    return 'Admin';
  }

  String _getAdminsSectionTitle() {
    if (_orgData == null) return 'ADMINS';

    final superAdminId = _orgData!['superAdminId'];
    final titles = _orgData!['adminTitles'];

    String baseTitle = 'SUPER ADMIN';

    if (superAdminId != null &&
        titles is Map &&
        titles.containsKey(superAdminId)) {
      final title = titles[superAdminId].toString().toUpperCase();
      if (title.isNotEmpty) {
        baseTitle = 'SUPER ADMIN: $title';
      }
    }

    if (_admins.length > 1) {
      return '$baseTitle & ADMINS';
    }
    return baseTitle;
  }

  Future<void> _toggleFollow() async {
    if (_orgData == null) return;
    setState(() => _isFollowLoading = true);

    try {
      final repo = ref.read(organizationRepositoryProvider);
      final orgId = _orgData!['id'];

      if (_isFollowing) {
        await repo.unfollowOrganization(orgId, widget.currentUserId);
      } else {
        await repo.followOrganization(orgId, widget.currentUserId);
      }

      setState(() {
        _isFollowing = !_isFollowing;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isFollowLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUserProfile = ref.watch(userProfileProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Organization Info'),
        actions: [
          if (_isAdmin)
            IconButton(
              icon: const Icon(LucideIcons.settings),
              onPressed: () =>
                  context.push('/organization/manage?orgId=${_orgData!['id']}'),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _orgData == null
          ? const Center(child: Text('Organization not found'))
          : SingleChildScrollView(
              padding: EdgeInsets.only(
                top: 16,
                bottom: 16 + MediaQuery.of(context).padding.bottom,
              ),
              child: Column(
                children: [
                  // Logo & Details
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.pageHorizontalPadding,
                    ),
                    child: Center(
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 48,
                            backgroundImage: (_orgData!['profileImage'] != null)
                                ? CachedNetworkImageProvider(
                                    _orgData!['profileImage'],
                                  )
                                : widget.orgImage != null
                                ? CachedNetworkImageProvider(widget.orgImage!)
                                : null,
                            child:
                                (_orgData!['profileImage'] == null &&
                                    widget.orgImage == null)
                                ? const Icon(LucideIcons.building2, size: 48)
                                : null,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _orgData!['businessName'] ?? widget.orgName,
                            style: theme.textTheme.headlineSmall,
                          ),
                          Text(
                            _orgData!['type'] ?? 'Organization',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Follow Button
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.pageHorizontalPadding,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isFollowLoading ? null : _toggleFollow,
                        icon: _isFollowLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                _isFollowing
                                    ? LucideIcons.check
                                    : LucideIcons.plus,
                              ),
                        label: Text(
                          _isFollowing ? 'Following' : 'Follow Organization',
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // [NEW] Mute Notifications Switch
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.pageHorizontalPadding,
                    ),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _isMuted,
                      onChanged: (value) async {
                        setState(() => _isMuted = value);
                        await ref
                            .read(chatRepositoryProvider)
                            .toggleMute(widget.chatId, value);
                      },
                      title: const Text('Mute Notifications'),
                      secondary: Icon(
                        _isMuted ? LucideIcons.bellOff : LucideIcons.bell,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      activeThumbColor: theme.colorScheme.primary,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // About Section
                  if (_orgData!['description'] != null &&
                      _orgData!['description'].isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.pageHorizontalPadding,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('ABOUT', style: theme.textTheme.labelSmall),
                            const SizedBox(height: 8),
                            Text(
                              _orgData!['description'],
                              style: theme.textTheme.bodyMedium,
                              textAlign: TextAlign.left,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Admins Section (First)
                  if (_admins.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.pageHorizontalPadding,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${_getAdminsSectionTitle()} (${_admins.length})',
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._admins.map((p) {
                      double? distanceKm;
                      if (currentUserProfile
                                  ?.currentLocation
                                  ?.geometry
                                  .location !=
                              null &&
                          p.hostLocation.geometry?.location != null) {
                        distanceKm = calculateDistance(
                          currentUserProfile!
                              .currentLocation!
                              .geometry
                              .location
                              .lat,
                          currentUserProfile
                              .currentLocation!
                              .geometry
                              .location
                              .lng,
                          p.hostLocation.geometry!.location.lat,
                          p.hostLocation.geometry!.location.lng,
                        );
                      }
                      return UserCardView(
                        user: p,
                        distanceKm: distanceKm,
                        titleSuffix: _getAdminTitle(p.uid),
                        onNameTap: () => context.push('/profile/${p.uid}'),
                      );
                    }),
                    const SizedBox(height: 24),
                  ],

                  // Board Participants Section (Second)
                  if (_participants.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.pageHorizontalPadding,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'BOARD PARTICIPANTS (${_participants.length})',
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._participants.map((p) {
                      double? distanceKm;
                      if (currentUserProfile
                                  ?.currentLocation
                                  ?.geometry
                                  .location !=
                              null &&
                          p.hostLocation.geometry?.location != null) {
                        distanceKm = calculateDistance(
                          currentUserProfile!
                              .currentLocation!
                              .geometry
                              .location
                              .lat,
                          currentUserProfile
                              .currentLocation!
                              .geometry
                              .location
                              .lng,
                          p.hostLocation.geometry!.location.lat,
                          p.hostLocation.geometry!.location.lng,
                        );
                      }
                      return UserCardView(
                        user: p,
                        distanceKm: distanceKm,
                        onNameTap: () => context.push('/profile/${p.uid}'),
                      );
                    }),
                    if (_isAdmin) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.pageHorizontalPadding,
                        ),
                        child: TextButton.icon(
                          onPressed: () => context.push(
                            '/organization/manage?orgId=${_orgData!['id']}',
                          ),
                          icon: const Icon(LucideIcons.userPlus, size: 16),
                          label: const Text('Add Participants'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],

                  // Followers Section (Last)
                  if (_followers.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.pageHorizontalPadding,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'ORG FOLLOWERS (${_followers.length})',
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._followers.map((p) {
                      double? distanceKm;
                      if (currentUserProfile
                                  ?.currentLocation
                                  ?.geometry
                                  .location !=
                              null &&
                          p.hostLocation.geometry?.location != null) {
                        distanceKm = calculateDistance(
                          currentUserProfile!
                              .currentLocation!
                              .geometry
                              .location
                              .lat,
                          currentUserProfile
                              .currentLocation!
                              .geometry
                              .location
                              .lng,
                          p.hostLocation.geometry!.location.lat,
                          p.hostLocation.geometry!.location.lng,
                        );
                      }
                      return UserCardView(
                        user: p,
                        distanceKm: distanceKm,
                        onNameTap: () => context.push('/profile/${p.uid}'),
                      );
                    }),
                    const SizedBox(height: 24),
                  ],
                ],
              ),
            ),
    );
  }
}
