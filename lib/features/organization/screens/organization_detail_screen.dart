import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/organization/repository/organization_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/core/data/countries.dart' as country_data;
import 'package:diaspora_nearby/features/shared/ui/glass_container.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:diaspora_nearby/features/organization/models/chamber_leadership_request.dart';
import 'package:diaspora_nearby/features/organization/models/chamber_roles.dart';
import 'package:diaspora_nearby/features/organization/widgets/chamber_leadership_request_modal.dart';
import 'package:diaspora_nearby/features/organization/widgets/organization_chat_preview.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class OrganizationDetailScreen extends ConsumerStatefulWidget {
  final String orgId;
  final Map<String, dynamic>? initialData;

  const OrganizationDetailScreen({
    super.key,
    required this.orgId,
    this.initialData,
  });

  @override
  ConsumerState<OrganizationDetailScreen> createState() =>
      _OrganizationDetailScreenState();
}

class _OrganizationDetailScreenState
    extends ConsumerState<OrganizationDetailScreen> {
  Map<String, dynamic>? _orgData;
  ProfileData? _superAdminProfile;
  bool _isLoading = true;
  bool _isFollowing = false;
  final bool _isFollowLoading = false;

  // User location for navigation
  double? _userLat;
  double? _userLng;

  // Live subscription to the org doc
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _orgDocSub;

  @override
  void initState() {
    super.initState();
    final repo = ref.read(organizationRepositoryProvider);
    final profileRepo = ref.read(profileRepositoryProvider);
    final currentUser = ref.read(authRepositoryProvider).currentUser;

    _orgData = widget.initialData ?? repo.getCachedOrganization(widget.orgId);
    if (_orgData != null) {
      _isLoading = false;
      final superAdminId = _orgData!['superAdminId'] as String?;
      if (superAdminId != null) {
        _superAdminProfile = profileRepo.getCachedProfile(superAdminId);
      }
      if (currentUser != null) {
        final followers = List<String>.from(_orgData!['followers'] ?? []);
        _isFollowing = followers.contains(currentUser.uid);
      }
    }

    _loadData();
    _loadUserLocation();
    _subscribeToOrgDoc();
  }

  @override
  void dispose() {
    _orgDocSub?.cancel();
    super.dispose();
  }

  void _subscribeToOrgDoc() {
    _orgDocSub = FirebaseFirestore.instance
        .collection('organizations')
        .doc(widget.orgId)
        .snapshots()
        .listen(
          (snap) {
            if (!snap.exists || !mounted) return;
            final data = snap.data();
            if (data == null) return;
            data['id'] = snap.id;
            ref
                .read(organizationRepositoryProvider)
                .cacheOrganization(snap.id, data);
            final currentUser = ref.read(authRepositoryProvider).currentUser;
            final followers = List<String>.from(data['followers'] ?? []);
            setState(() {
              _orgData = data;
              if (currentUser != null && followers.contains(currentUser.uid)) {
                _isFollowing = true;
              }
            });
          },
          onError: (e) {
            debugPrint('Org doc subscription error: $e');
          },
        );
  }

  Future<void> _loadData({bool force = false}) async {
    if (!force && _orgData != null && _orgData!['id'] == widget.orgId) {
      setState(() => _isLoading = false);
      _checkIfFollowing();
      final superAdminId = _orgData!['superAdminId'] as String?;
      if (superAdminId != null && _superAdminProfile == null) {
        ref
            .read(profileRepositoryProvider)
            .getUserProfile(superAdminId)
            .then((profile) {
              if (mounted && profile != null) {
                setState(() => _superAdminProfile = profile);
              }
            })
            .catchError((_) {});
      }
      return;
    }

    try {
      final repo = ref.read(organizationRepositoryProvider);
      var data = await repo.getOrganization(widget.orgId, force: force);
      if (data == null && widget.orgId.startsWith('chamber_')) {
        final parts = widget.orgId.replaceFirst('chamber_', '').split('_');
        if (parts.length >= 2) {
          final host = parts[0].toUpperCase();
          final home = parts[1].toUpperCase();
          final hostCountry = country_data.getCountryByCode(host);
          final homeCountry = country_data.getCountryByCode(home);
          final hostName = hostCountry?.name ?? host;
          final homeName = homeCountry?.name ?? home;
          final chamberName = '$host ⇄ $home Chamber of Commerce';
          data = {
            'id': widget.orgId,
            'kind': 'corridor_chamber',
            'name': chamberName,
            'businessName': chamberName,
            'description':
                'Official public corridor chamber — $hostName (host) ↔ $homeName (home) diaspora.',
            'type': 'Chamber of Commerce',
            'homeCountryCode': home,
            'hostCountryCode': host,
            'chatId': 'org_${widget.orgId}',
            'isPublic': true,
            'status': 'active',
            'members': <String>[],
            'followers': <String>[],
            'memberCount': 0,
            'admins': <String>[],
            'pendingAdmins': <String>[],
            'adminTitles': <String, dynamic>{},
            'gdpTotal': 0,
            'transactionCount': 0,
          };
        }
      }
      if (mounted) {
        setState(() {
          _orgData = data;
          _isLoading = false;
        });
        _checkIfFollowing();

        if (data != null && data['superAdminId'] != null) {
          final superAdminId = data['superAdminId'] as String;
          final cachedAdmin = ref
              .read(profileRepositoryProvider)
              .getCachedProfile(superAdminId);
          if (cachedAdmin != null) {
            setState(() => _superAdminProfile = cachedAdmin);
          } else {
            try {
              final profile = await ref
                  .read(profileRepositoryProvider)
                  .getUserProfile(superAdminId);
              if (mounted) {
                setState(() => _superAdminProfile = profile);
              }
            } catch (e) {
              debugPrint('Error fetching super admin: $e');
            }
          }
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openChat() {
    if (_orgData == null) return;
    final orgId = (_orgData!['id'] as String?) ?? widget.orgId;
    final storedChatId = _orgData!['chatId'] as String?;
    final isCorridorChamber = _orgData!['kind'] == 'corridor_chamber';

    final chatId = (storedChatId != null && storedChatId.isNotEmpty)
        ? storedChatId
        : (isCorridorChamber ? 'org_$orgId' : null);

    if (chatId != null && chatId.isNotEmpty) {
      context.push('/chats/$chatId');
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Chat not available')));
    }
  }

  Future<void> _checkIfFollowing() async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null || _orgData == null) return;

    final followers = List<String>.from(_orgData!['followers'] ?? []);
    if (followers.contains(user.uid)) {
      if (mounted && !_isFollowing) setState(() => _isFollowing = true);
      return;
    }

    try {
      final chatId = _orgData!['chatId'] as String?;
      if (chatId != null) {
        final userChatDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('userChats')
            .doc(chatId)
            .get();
        if (userChatDoc.exists) {
          if (mounted) setState(() => _isFollowing = true);
        }
      }
    } catch (e) {
      debugPrint('Error checking Firestore userChats: $e');
    }
  }

  void _toggleFollow() {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null || _orgData == null) return;

    final repo = ref.read(organizationRepositoryProvider);
    final wasFollowing = _isFollowing;
    final prevFollowers = List<String>.from(_orgData!['followers'] ?? []);
    final updatedFollowers = List<String>.from(prevFollowers);

    if (wasFollowing) {
      updatedFollowers.remove(user.uid);
    } else if (!updatedFollowers.contains(user.uid)) {
      updatedFollowers.add(user.uid);
    }

    setState(() {
      _isFollowing = !wasFollowing;
      _orgData = {..._orgData!, 'followers': updatedFollowers};
    });
    repo.cacheOrganization(widget.orgId, _orgData!);

    final action = wasFollowing
        ? repo.unfollowOrganization(widget.orgId, user.uid)
        : repo.followOrganization(widget.orgId, user.uid);

    unawaited(
      action.catchError((Object e) {
        if (mounted) {
          setState(() {
            _isFollowing = wasFollowing;
            if (_orgData != null) {
              _orgData = {..._orgData!, 'followers': prevFollowers};
              repo.cacheOrganization(widget.orgId, _orgData!);
            }
          });
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }),
    );
  }

  void _launchUrl(String? url) async {
    if (url == null || url.isEmpty) return;

    Uri uri;
    if (url.startsWith('http') ||
        url.startsWith('https') ||
        url.startsWith('tel') ||
        url.startsWith('mailto')) {
      uri = Uri.parse(url);
    } else {
      uri = Uri.parse('https://$url');
    }

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (url.startsWith('tel')) {
          await launchUrl(uri);
        }
      }
    } catch (e) {
      debugPrint('Error launching URL: $e');
    }
  }

  Future<void> _loadUserLocation() async {
    try {
      final userProfile = ref.read(userProfileProvider).value;

      if (userProfile?.hostLocation.geometry?.location != null) {
        if (mounted) {
          setState(() {
            _userLat = userProfile!.hostLocation.geometry!.location.lat;
            _userLng = userProfile.hostLocation.geometry!.location.lng;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading user location: $e');
    }
  }

  Future<void> _openDirections() async {
    if (_orgData == null) return;

    final location = _orgData!['location'] as Map<String, dynamic>?;
    if (location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location coordinates not available')),
      );
      return;
    }

    final lat = location['lat'];
    final lng = location['lng'];

    if (lat == null || lng == null) return;

    String url;
    if (_userLat != null && _userLng != null) {
      url =
          'https://www.google.com/maps/dir/?api=1&origin=$_userLat,$_userLng&destination=$lat,$lng&travelmode=driving';
    } else {
      url = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    }

    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not open maps')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _orgData == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_orgData == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Organization not found')),
      );
    }

    final theme = Theme.of(context);
    final name = _orgData!['businessName'] ?? 'Unknown';
    final description = _orgData!['description'] ?? '';
    final type = _orgData!['type'] ?? 'Organization';
    final website = _orgData!['website'] as String?;
    final phone = _orgData!['phone'] as String?;
    final logoUrl = _orgData!['profileImage'] as String?;
    final city = _orgData!['city'] as String?;
    final state = _orgData!['state'] as String?;
    final country = _orgData!['country'] as String?;

    final currentUserId = ref.watch(authRepositoryProvider).currentUser?.uid;
    final isAdmin =
        (_orgData!['admins'] as List?)?.contains(currentUserId) == true ||
        _orgData!['superAdminId'] == currentUserId;
    final members = List<String>.from(_orgData!['members'] ?? []);
    final followers = List<String>.from(_orgData!['followers'] ?? []);
    final canViewOrgChat =
        currentUserId != null &&
        (isAdmin ||
            _isFollowing ||
            members.contains(currentUserId) ||
            followers.contains(currentUserId));

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            actions: [
              if (isAdmin && _orgData!['kind'] != 'corridor_chamber')
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: CircleAvatar(
                    backgroundColor: Colors.black.withValues(alpha: 0.4),
                    child: IconButton(
                      icon: const Icon(
                        LucideIcons.settings,
                        color: Colors.white,
                        size: 20,
                      ),
                      tooltip: 'Manage Organization',
                      onPressed: () {
                        context.push(
                          '/organization/manage?orgId=${widget.orgId}',
                        );
                      },
                    ),
                  ),
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      theme.colorScheme.primary.withValues(alpha: 0.8),
                      theme.colorScheme.primaryContainer,
                    ],
                  ),
                ),
                child: Center(
                  child: Hero(
                    tag: 'org_logo_${widget.orgId}',
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.white,
                      backgroundImage: (logoUrl != null && logoUrl.isNotEmpty)
                          ? NetworkImage(logoUrl)
                          : null,
                      child: (logoUrl == null || logoUrl.isEmpty)
                          ? Icon(
                              LucideIcons.building2,
                              size: 40,
                              color: theme.colorScheme.primary,
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title and Type
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              type,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Action Buttons Row
                  Row(
                    children: [
                      Expanded(
                        child: _orgData!['kind'] == 'corridor_chamber'
                            ? _buildChamberJoinFollowButton()
                            : isAdmin
                            ? FilledButton.tonalIcon(
                                onPressed: () {
                                  context.push(
                                    '/organization/manage?orgId=${widget.orgId}',
                                  );
                                },
                                icon: const Icon(LucideIcons.settings),
                                label: const Text('Manage'),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(double.infinity, 54),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              )
                            : FilledButton.tonalIcon(
                                onPressed: _isFollowLoading
                                    ? null
                                    : _toggleFollow,
                                icon: Icon(
                                  _isFollowing
                                      ? LucideIcons.check
                                      : LucideIcons.plus,
                                ),
                                label: Text(
                                  _isFollowing ? 'Following' : 'Follow',
                                ),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(double.infinity, 54),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(width: 12),
                      // Message Button
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: canViewOrgChat ? _openChat : null,
                          icon: const Icon(LucideIcons.messageCircle),
                          label: Text(
                            canViewOrgChat ? 'Message' : 'Follow to Message',
                          ),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(double.infinity, 54),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Chamber-of-commerce-specific affordances.
                  if (_orgData!['kind'] == 'corridor_chamber') ...[
                    _buildChamberSecondaryActions(currentUserId),
                    const SizedBox(height: 16),
                    _buildChamberLeadershipCard(theme, currentUserId),
                    const SizedBox(height: 24),
                    _buildLinkedBusinessesCard(theme, currentUserId),
                    const SizedBox(height: 24),
                  ] else ...[
                    _buildAffiliatedChambersCard(theme, currentUserId),
                    const SizedBox(height: 24),
                  ],

                  // Embedded chat preview.
                  if (_orgData!['chatId'] != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24.0),
                      child: OrganizationChatPreview(
                        chatId: _orgData!['chatId'],
                        canViewMessages: canViewOrgChat,
                        title: 'Organization Board',
                      ),
                    ),

                  // Super Admin Card
                  if (_superAdminProfile != null) ...[
                    const Text(
                      'Leadership',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildSuperAdminCard(theme),
                    const SizedBox(height: 32),
                  ],

                  // Products & Services Section
                  _buildProductsListingSection(theme, isAdmin),
                  const SizedBox(height: 32),

                  // Info Cards
                  const Text(
                    'About',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    description.isNotEmpty
                        ? description
                        : 'No description available.',
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                  ),
                  const SizedBox(height: 32),

                  const Text(
                    'Contact & Location',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),

                  if (city != null)
                    _buildInfoTile(
                      LucideIcons.mapPin,
                      'Location',
                      [city, ?state, ?country].join(', '),
                      onTap: () => _openDirections(),
                    ),

                  if (website != null && website.isNotEmpty)
                    _buildInfoTile(
                      LucideIcons.globe,
                      'Website',
                      website,
                      onTap: () => _launchUrl(website),
                    ),

                  if (phone != null && phone.isNotEmpty)
                    _buildInfoTile(
                      LucideIcons.phone,
                      'Phone',
                      phone,
                      onTap: () => _launchUrl('tel:$phone'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(
    IconData icon,
    String label,
    String value, {
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GestureDetector(
        onTap: onTap,
        child: GlassContainer(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 20, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.grey,
                      ),
                    ),
                    Text(
                      value,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: onTap != null ? theme.colorScheme.primary : null,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(
                  LucideIcons.externalLink,
                  size: 14,
                  color: theme.colorScheme.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuperAdminCard(ThemeData theme) {
    if (_superAdminProfile == null) return const SizedBox.shrink();

    String flag = '';
    if (_superAdminProfile!.homeCountryCode != null) {
      final country = country_data.getCountryByCode(
        _superAdminProfile!.homeCountryCode!,
      );
      if (country != null) flag = country.flag;
    }

    String title = 'Super Admin';
    if (_orgData != null && _orgData!['adminTitles'] is Map) {
      final titles = _orgData!['adminTitles'];
      if (titles != null && titles[_superAdminProfile!.uid] != null) {
        title = titles[_superAdminProfile!.uid];
      }
    }

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          context.push('/profile/${_superAdminProfile!.uid}');
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.grey.shade200,
                backgroundImage: _superAdminProfile!.profileImage.isNotEmpty
                    ? CachedNetworkImageProvider(
                        _superAdminProfile!.profileImage,
                      )
                    : null,
                child: _superAdminProfile!.profileImage.isEmpty
                    ? Text(
                        _superAdminProfile!.firstName.isNotEmpty
                            ? _superAdminProfile!.firstName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (flag.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Text(
                              flag,
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                        Flexible(
                          child: Text(
                            '${_superAdminProfile!.firstName} ${_superAdminProfile!.lastName}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                LucideIcons.chevronRight,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChamberSecondaryActions(String? currentUserId) {
    if (currentUserId == null) return const SizedBox.shrink();
    final members = List<String>.from(
      (_orgData?['members'] as List?) ?? const <dynamic>[],
    );
    final followers = List<String>.from(
      (_orgData?['followers'] as List?) ?? const <dynamic>[],
    );
    final isMember = members.contains(currentUserId);
    final isFollower = followers.contains(currentUserId);

    if (isMember) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => _leaveChamber(currentUserId),
          icon: const Icon(LucideIcons.logOut, size: 16),
          label: const Text('Leave chamber'),
          style: TextButton.styleFrom(foregroundColor: AppTheme.error),
        ),
      );
    }
    if (isFollower) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => _joinChamber(currentUserId),
          icon: const Icon(LucideIcons.userPlus),
          label: const Text('Become Member'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
    }
    // Visitor
    return SizedBox(
      width: double.infinity,
      child: FilledButton.tonalIcon(
        onPressed: () => _followChamber(currentUserId),
        icon: const Icon(LucideIcons.eye),
        label: const Text('Follow (read-only)'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildChamberJoinFollowButton() {
    final user = ref.watch(authRepositoryProvider).currentUser;
    if (user == null) {
      return const SizedBox.shrink();
    }
    final members = List<String>.from(
      (_orgData?['members'] as List?) ?? const <dynamic>[],
    );
    final followers = List<String>.from(
      (_orgData?['followers'] as List?) ?? const <dynamic>[],
    );
    final isMember = members.contains(user.uid);
    final isFollower = followers.contains(user.uid);

    if (isMember) {
      return FilledButton.tonalIcon(
        onPressed: null,
        icon: const Icon(LucideIcons.shieldCheck),
        label: const Text('Chamber Member'),
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
    if (isFollower) {
      return FilledButton.tonalIcon(
        onPressed: () => _unfollowChamber(user.uid),
        icon: const Icon(LucideIcons.check),
        label: const Text('Following'),
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
    return FilledButton.icon(
      onPressed: () => _joinChamber(user.uid),
      icon: const Icon(LucideIcons.userPlus),
      label: const Text('Join Chamber'),
      style: FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, 54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _joinChamber(String uid) {
    if (_orgData == null) return;
    final repo = ref.read(organizationRepositoryProvider);
    final prevMembers = List<String>.from(_orgData!['members'] ?? []);
    final prevFollowers = List<String>.from(_orgData!['followers'] ?? []);
    final updatedMembers = List<String>.from(prevMembers);
    final updatedFollowers = List<String>.from(prevFollowers);
    if (!updatedMembers.contains(uid)) updatedMembers.add(uid);
    if (!updatedFollowers.contains(uid)) updatedFollowers.add(uid);

    setState(() {
      _isFollowing = true;
      _orgData = {
        ..._orgData!,
        'members': updatedMembers,
        'followers': updatedFollowers,
        'memberCount': updatedMembers.length,
      };
    });
    repo.cacheOrganization(widget.orgId, _orgData!);

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Joined the chamber.')));

    unawaited(
      repo.joinChamber(orgId: widget.orgId, userId: uid).catchError((Object e) {
        if (mounted) {
          setState(() {
            _isFollowing = prevFollowers.contains(uid);
            if (_orgData != null) {
              _orgData = {
                ..._orgData!,
                'members': prevMembers,
                'followers': prevFollowers,
                'memberCount': prevMembers.length,
              };
              repo.cacheOrganization(widget.orgId, _orgData!);
            }
          });
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Couldn\'t join: $e')));
        }
      }),
    );
  }

  void _followChamber(String uid) {
    if (_orgData == null) return;
    final repo = ref.read(organizationRepositoryProvider);
    final prevFollowers = List<String>.from(_orgData!['followers'] ?? []);
    final updatedFollowers = List<String>.from(prevFollowers);
    if (!updatedFollowers.contains(uid)) updatedFollowers.add(uid);

    setState(() {
      _isFollowing = true;
      _orgData = {..._orgData!, 'followers': updatedFollowers};
    });
    repo.cacheOrganization(widget.orgId, _orgData!);

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Now following the chamber.')));

    unawaited(
      repo.followChamber(orgId: widget.orgId, userId: uid).catchError((
        Object e,
      ) {
        if (mounted) {
          setState(() {
            _isFollowing = prevFollowers.contains(uid);
            if (_orgData != null) {
              _orgData = {..._orgData!, 'followers': prevFollowers};
              repo.cacheOrganization(widget.orgId, _orgData!);
            }
          });
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Couldn\'t follow: $e')));
        }
      }),
    );
  }

  void _unfollowChamber(String uid) {
    if (_orgData == null) return;
    final repo = ref.read(organizationRepositoryProvider);
    final prevFollowers = List<String>.from(_orgData!['followers'] ?? []);
    final prevMembers = List<String>.from(_orgData!['members'] ?? []);
    final updatedFollowers = List<String>.from(prevFollowers)..remove(uid);
    final updatedMembers = List<String>.from(prevMembers)..remove(uid);

    setState(() {
      _isFollowing = false;
      _orgData = {
        ..._orgData!,
        'followers': updatedFollowers,
        'members': updatedMembers,
      };
    });
    repo.cacheOrganization(widget.orgId, _orgData!);

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Unfollowed the chamber.')));

    unawaited(
      repo.unfollowChamber(orgId: widget.orgId, userId: uid).catchError((
        Object e,
      ) {
        if (mounted) {
          setState(() {
            _isFollowing = prevFollowers.contains(uid);
            if (_orgData != null) {
              _orgData = {
                ..._orgData!,
                'followers': prevFollowers,
                'members': prevMembers,
              };
              repo.cacheOrganization(widget.orgId, _orgData!);
            }
          });
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Couldn\'t unfollow: $e')));
        }
      }),
    );
  }

  void _leaveChamber(String uid) {
    if (_orgData == null) return;
    final repo = ref.read(organizationRepositoryProvider);
    final prevMembers = List<String>.from(_orgData!['members'] ?? []);
    final updatedMembers = List<String>.from(prevMembers)..remove(uid);

    setState(() {
      _orgData = {
        ..._orgData!,
        'members': updatedMembers,
        'memberCount': updatedMembers.length,
      };
    });
    repo.cacheOrganization(widget.orgId, _orgData!);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Left the chamber (still following).')),
    );

    unawaited(
      repo.leaveChamber(orgId: widget.orgId, userId: uid).catchError((
        Object e,
      ) {
        if (mounted) {
          setState(() {
            if (_orgData != null) {
              _orgData = {
                ..._orgData!,
                'members': prevMembers,
                'memberCount': prevMembers.length,
              };
              repo.cacheOrganization(widget.orgId, _orgData!);
            }
          });
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Couldn\'t leave: $e')));
        }
      }),
    );
  }

  Widget _buildAffiliatedChambersCard(ThemeData theme, String? currentUserId) {
    final linked = List<String>.from(
      (_orgData?['linkedChamberIds'] as List?) ?? const <dynamic>[],
    );
    if (linked.isEmpty) return const SizedBox.shrink();

    final admins = List<String>.from(
      (_orgData?['admins'] as List?) ?? const <dynamic>[],
    );
    final isBusinessAdmin =
        currentUserId != null &&
        (admins.contains(currentUserId) ||
            _orgData?['superAdminId'] == currentUserId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(LucideIcons.landmark, size: 20, color: AppTheme.accent),
            SizedBox(width: 8),
            Text(
              'Affiliated Chambers',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${linked.length} ${linked.length == 1 ? 'chamber' : 'chambers'}',
          style: TextStyle(
            fontSize: 13,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 12),
        ...linked.map(
          (chamberId) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _AffiliatedChamberTile(
              chamberId: chamberId,
              canUnlink: isBusinessAdmin,
              onUnlink: isBusinessAdmin
                  ? () => _unlinkChamber(chamberId, currentUserId)
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _unlinkChamber(String chamberId, String userId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
          title: const Text('Unlink chamber?'),
          content: const Text(
            'This business will no longer appear in the chamber\'s member directory.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Unlink'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || _orgData == null) return;

    final repo = ref.read(organizationRepositoryProvider);
    final prevLinked = List<String>.from(_orgData!['linkedChamberIds'] ?? []);
    final updatedLinked = List<String>.from(prevLinked)..remove(chamberId);

    setState(() {
      _orgData = {..._orgData!, 'linkedChamberIds': updatedLinked};
    });
    repo.cacheOrganization(widget.orgId, _orgData!);

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Affiliation removed.')));
    }

    unawaited(
      repo
          .unlinkBusinessFromChamber(
            chamberOrgId: chamberId,
            businessOrgId: widget.orgId,
            userId: userId,
          )
          .catchError((Object e) {
            if (mounted) {
              setState(() {
                if (_orgData != null) {
                  _orgData = {..._orgData!, 'linkedChamberIds': prevLinked};
                  repo.cacheOrganization(widget.orgId, _orgData!);
                }
              });
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Couldn\'t unlink: $e')));
            }
          }),
    );
  }

  Widget _buildLinkedBusinessesCard(ThemeData theme, String? currentUserId) {
    final linked = List<String>.from(
      (_orgData?['linkedBusinesses'] as List?) ?? const <dynamic>[],
    );
    final members = List<String>.from(
      (_orgData?['members'] as List?) ?? const <dynamic>[],
    );
    final isMember = currentUserId != null && members.contains(currentUserId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(LucideIcons.briefcase, size: 20, color: AppTheme.accent),
            SizedBox(width: 8),
            Text(
              'Member Businesses',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          linked.isEmpty
              ? 'No businesses linked yet.'
              : '${linked.length} ${linked.length == 1 ? 'business' : 'businesses'} affiliated',
          style: TextStyle(
            fontSize: 13,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 12),
        ...linked.map(
          (bizId) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _LinkedBusinessTile(orgId: bizId),
          ),
        ),
        if (isMember) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              icon: const Icon(LucideIcons.plus),
              label: const Text('Link a Business'),
              onPressed: () => _openBusinessLinker(currentUserId, linked),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ] else if (!isMember && currentUserId != null) ...[
          const SizedBox(height: 8),
          _noteCard(
            theme,
            'Join the chamber to list your business in its directory.',
          ),
        ],
      ],
    );
  }

  Future<void> _openBusinessLinker(
    String currentUserId,
    List<String> alreadyLinked,
  ) async {
    final repo = ref.read(organizationRepositoryProvider);
    final myOrgs =
        ref.read(userOrganizationsProvider).value ??
        repo.getCachedUserOrganizations(currentUserId) ??
        await repo.getUserOrganizations(currentUserId);

    final eligible = myOrgs.where((o) {
      if (o['kind'] == 'corridor_chamber') return false;
      if (alreadyLinked.contains(o['id'])) return false;
      return true;
    }).toList();

    if (!mounted) return;
    if (eligible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'You don\'t have any unlinked businesses you administer. '
            'Register one first.',
          ),
        ),
      );
      return;
    }

    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(ctx).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Text(
                      'Pick a business to link',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  ...eligible.map(
                    (o) => ListTile(
                      leading: const Icon(LucideIcons.briefcase),
                      title: Text(o['businessName'] ?? o['name'] ?? 'Business'),
                      subtitle: Text(o['type'] ?? ''),
                      onTap: () => Navigator.pop(ctx, o['id'] as String),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (picked == null || _orgData == null) return;

    final prevLinked = List<String>.from(_orgData!['linkedBusinesses'] ?? []);
    final updatedLinked = List<String>.from(prevLinked);
    if (!updatedLinked.contains(picked)) updatedLinked.add(picked);

    setState(() {
      _orgData = {..._orgData!, 'linkedBusinesses': updatedLinked};
    });
    repo.cacheOrganization(widget.orgId, _orgData!);

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Business linked.')));
    }

    unawaited(
      repo
          .linkBusinessToChamber(
            chamberOrgId: widget.orgId,
            businessOrgId: picked,
            userId: currentUserId,
          )
          .catchError((Object e) {
            if (mounted) {
              setState(() {
                if (_orgData != null) {
                  _orgData = {..._orgData!, 'linkedBusinesses': prevLinked};
                  repo.cacheOrganization(widget.orgId, _orgData!);
                }
              });
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Couldn\'t link: $e')));
            }
          }),
    );
  }

  Widget _buildChamberLeadershipCard(ThemeData theme, String? currentUserId) {
    final councilRoles = Map<String, String>.from(
      (_orgData!['councilRoles'] as Map?)?.cast<String, String>() ??
          const <String, String>{},
    );
    final homeCC = (_orgData!['homeCountryCode'] as String?) ?? '';
    final hostCC = (_orgData!['hostCountryCode'] as String?) ?? '';
    final chamberName = (_orgData!['name'] as String?) ?? 'Chamber';

    final seatHolders = <String, String?>{};
    for (final r in ChamberRoles.all) {
      seatHolders[r] = null;
    }
    councilRoles.forEach((uid, role) {
      if (seatHolders.containsKey(role)) seatHolders[role] = uid;
    });

    final userIsLeader =
        currentUserId != null && councilRoles.containsKey(currentUserId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(LucideIcons.landmark, size: 20, color: AppTheme.accent),
            SizedBox(width: 8),
            Text(
              'Chamber Council',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          councilRoles.isEmpty
              ? 'Managed by Home & Host Community Councils — 2 Appointed Trade Reps'
              : '${councilRoles.length} of ${ChamberRoles.all.length} trade seats filled',
          style: TextStyle(
            fontSize: 13,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 12),
        ...ChamberRoles.all.map((role) {
          final holderUid = seatHolders[role];
          final isMine = holderUid != null && holderUid == currentUserId;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _ChamberSeatRow(
              role: role,
              holderUid: holderUid,
              isMine: isMine,
            ),
          );
        }),
        const SizedBox(height: 8),

        if (currentUserId != null && !userIsLeader)
          _buildCorridorGatedRequestSection(
            currentUserId: currentUserId,
            chamberName: chamberName,
            homeCC: homeCC,
            hostCC: hostCC,
          ),
      ],
    );
  }

  Widget _buildCorridorGatedRequestSection({
    required String currentUserId,
    required String chamberName,
    required String homeCC,
    required String hostCC,
  }) {
    final theme = Theme.of(context);
    final profile =
        ref.watch(userProfileProvider).value ??
        ref.read(profileRepositoryProvider).getCachedProfile(currentUserId);

    final userHome = (profile?.homeCountryCode ?? '').toUpperCase();
    final userHost = (profile?.hostCountryCode ?? '').toUpperCase();
    final chamberHome = homeCC.toUpperCase();
    final chamberHost = hostCC.toUpperCase();

    final inCorridor =
        userHome == chamberHome &&
        userHost == chamberHost &&
        userHome.isNotEmpty &&
        userHost.isNotEmpty;

    if (!inCorridor) {
      return _noteCard(
        theme,
        'Only diaspora in the $chamberHost ⇄ $chamberHome corridor can request '
        'a seat on this chamber.',
      );
    }

    final members = List<String>.from(
      (_orgData?['members'] as List?) ?? const <dynamic>[],
    );
    if (!members.contains(currentUserId)) {
      return _noteCard(theme, 'Join the chamber to request a leadership seat.');
    }

    return _buildMyRequestStatusOrCta(
      currentUserId: currentUserId,
      chamberName: chamberName,
      homeCC: homeCC,
      hostCC: hostCC,
    );
  }

  Widget _noteCard(ThemeData theme, String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            LucideIcons.info,
            size: 16,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyRequestStatusOrCta({
    required String currentUserId,
    required String chamberName,
    required String homeCC,
    required String hostCC,
  }) {
    final repo = ref.read(organizationRepositoryProvider);
    return StreamBuilder<List<ChamberLeadershipRequest>>(
      initialData: repo.getCachedMyLeadershipRequests(currentUserId),
      stream: repo.watchMyLeadershipRequests(currentUserId),
      builder: (context, snapshot) {
        final all = snapshot.data ?? const <ChamberLeadershipRequest>[];
        final pendingForThis = all
            .where(
              (r) =>
                  r.chamberId == widget.orgId &&
                  r.status == ChamberLeadershipRequest.statusPending,
            )
            .toList();

        if (pendingForThis.isNotEmpty) {
          final req = pendingForThis.first;
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.clock, color: Colors.amber, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pending: ${ChamberRoles.displayName(req.role)} — '
                    'awaiting admin review.',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          );
        }

        return SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            icon: const Icon(LucideIcons.heartHandshake),
            label: const Text('Request Leadership'),
            onPressed: () => ChamberLeadershipRequestModal.show(
              context,
              orgId: widget.orgId,
              chamberName: chamberName,
              homeCountryCode: homeCC,
              hostCountryCode: hostCC,
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildProductsListingSection(ThemeData theme, bool isAdmin) {
    final isEnabled = _orgData!['isListingEnabled'] == true;

    if (!isEnabled) {
      if (!isAdmin) return const SizedBox.shrink();

      return GlassContainer(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Icon(LucideIcons.shoppingBag, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                const Text(
                  'Products & Services',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Showcase your products and services on a dedicated page for your organization. This specialized listing helps you reach more customers.',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => _handleEnableListing(),
                child: const Text('Enable Specialized Listing'),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Products & Services',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (isAdmin)
              TextButton.icon(
                onPressed: () {},
                icon: const Icon(LucideIcons.plus, size: 16),
                label: const Text('Add Item'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Detailed products and services listing is active. You can browse them below.',
          style: TextStyle(fontSize: 14, color: Colors.grey),
        ),
        const SizedBox(height: 16),
        const Center(
          child: Text(
            'Specialized page coming soon!',
            style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  Future<void> _handleEnableListing() async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null || _orgData == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
          title: const Text('Enable Specialized Listing?'),
          content: const Text(
            'This will enable a dedicated products and services page for your organization.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enable'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && _orgData != null) {
      final repo = ref.read(organizationRepositoryProvider);
      setState(() {
        _orgData = {..._orgData!, 'isListingEnabled': true};
      });
      repo.cacheOrganization(widget.orgId, _orgData!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Specialized listing enabled!')),
        );
      }

      unawaited(
        repo.enableProductListing(widget.orgId, user.uid).catchError((
          Object e,
        ) {
          if (mounted) {
            setState(() {
              if (_orgData != null) {
                _orgData = {..._orgData!, 'isListingEnabled': false};
                repo.cacheOrganization(widget.orgId, _orgData!);
              }
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to enable listing: $e')),
            );
          }
        }),
      );
    }
  }
}

class _ChamberSeatRow extends ConsumerWidget {
  final String role;
  final String? holderUid;
  final bool isMine;

  const _ChamberSeatRow({
    required this.role,
    required this.holderUid,
    required this.isMine,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hasHolder = holderUid != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: !hasHolder
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)
            : AppTheme.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            ChamberRoles.icon(role),
            size: 18,
            color: !hasHolder
                ? theme.iconTheme.color?.withValues(alpha: 0.5)
                : AppTheme.accent,
          ),
          const SizedBox(width: 10),
          Expanded(child: _buildLabel(context, ref, theme)),
          if (!hasHolder)
            Text(
              'Open seat',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                fontStyle: FontStyle.italic,
              ),
            )
          else if (isMine)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.accent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'You',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLabel(BuildContext context, WidgetRef ref, ThemeData theme) {
    final roleLabel = ChamberRoles.displayName(role);
    if (holderUid == null) {
      return Text(
        roleLabel,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      );
    }

    final profileAsync = ref.watch(userProfileByIdProvider(holderUid!));
    final profile =
        profileAsync.value ??
        ref.read(profileRepositoryProvider).getCachedProfile(holderUid!);

    if (profile == null && profileAsync.isLoading) {
      return Text(
        roleLabel,
        style: const TextStyle(fontWeight: FontWeight.w600),
      );
    }

    final fullName = profile == null
        ? null
        : '${profile.firstName} ${profile.lastName}'.trim();
    return Row(
      children: [
        if (profile != null && profile.profileImage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: CircleAvatar(
              radius: 14,
              backgroundImage: CachedNetworkImageProvider(profile.profileImage),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: CircleAvatar(
              radius: 14,
              backgroundColor: AppTheme.accent.withValues(alpha: 0.2),
              child: Text(
                (fullName?.isNotEmpty ?? false)
                    ? fullName![0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.accent,
                ),
              ),
            ),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (fullName?.isNotEmpty ?? false) ? fullName! : 'Member',
                style: const TextStyle(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                roleLabel,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AffiliatedChamberTile extends ConsumerWidget {
  final String chamberId;
  final bool canUnlink;
  final VoidCallback? onUnlink;

  const _AffiliatedChamberTile({
    required this.chamberId,
    required this.canUnlink,
    this.onUnlink,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final chamberAsync = ref.watch(organizationByIdProvider(chamberId));
    final org =
        chamberAsync.value ??
        ref.read(organizationRepositoryProvider).getCachedOrganization(chamberId);

    if (org == null) {
      if (chamberAsync.isLoading) {
        return Container(
          height: 56,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.3,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
        );
      }
      return const SizedBox.shrink();
    }

    final host = org['hostCountryCode'] as String?;
    final home = org['homeCountryCode'] as String?;
    Widget avatar = CircleAvatar(
      radius: 16,
      backgroundColor: AppTheme.accent.withValues(alpha: 0.15),
      child: const Icon(
        LucideIcons.landmark,
        size: 14,
        color: AppTheme.accent,
      ),
    );
    if (host != null && home != null) {
      final hostFlag = country_data.getCountryByCode(host)?.flag;
      final homeFlag = country_data.getCountryByCode(home)?.flag;
      if (hostFlag != null && homeFlag != null) {
        avatar = SizedBox(
          width: 32,
          height: 32,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                bottom: 0,
                child: Text(hostFlag, style: const TextStyle(fontSize: 18)),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: Text(homeFlag, style: const TextStyle(fontSize: 14)),
              ),
            ],
          ),
        );
      }
    }
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => context.push('/organization/$chamberId', extra: org),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.3,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            avatar,
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                org['name'] ?? org['businessName'] ?? 'Chamber',
                style: const TextStyle(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (canUnlink)
              IconButton(
                icon: const Icon(LucideIcons.unlink, size: 16),
                color: AppTheme.error,
                tooltip: 'Unlink',
                onPressed: onUnlink,
              )
            else
              Icon(
                LucideIcons.chevronRight,
                size: 16,
                color: theme.iconTheme.color?.withValues(alpha: 0.4),
              ),
          ],
        ),
      ),
    );
  }
}

class _LinkedBusinessTile extends ConsumerWidget {
  final String orgId;
  const _LinkedBusinessTile({required this.orgId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final orgAsync = ref.watch(organizationByIdProvider(orgId));
    final org =
        orgAsync.value ??
        ref.read(organizationRepositoryProvider).getCachedOrganization(orgId);

    if (org == null) {
      if (orgAsync.isLoading) {
        return Container(
          height: 56,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.3,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
        );
      }
      return const SizedBox.shrink();
    }

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => context.push('/organization/$orgId', extra: org),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.3,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            if ((org['profileImage'] as String?)?.isNotEmpty ?? false)
              CircleAvatar(
                radius: 16,
                backgroundImage: CachedNetworkImageProvider(
                  org['profileImage'],
                ),
              )
            else
              CircleAvatar(
                radius: 16,
                backgroundColor: AppTheme.accent.withValues(alpha: 0.15),
                child: const Icon(
                  LucideIcons.briefcase,
                  size: 14,
                  color: AppTheme.accent,
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    org['businessName'] ?? org['name'] ?? 'Business',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if ((org['type'] as String?)?.isNotEmpty ?? false)
                    Text(
                      org['type'],
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: theme.iconTheme.color?.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}
