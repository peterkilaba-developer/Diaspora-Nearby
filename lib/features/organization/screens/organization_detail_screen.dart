import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/organization/repository/organization_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/data/countries.dart' as country_data;
import 'package:diaspora_nearby/features/chat/providers/chat_identity_provider.dart';
import 'package:diaspora_nearby/features/shared/ui/glass_container.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:diaspora_nearby/features/organization/widgets/organization_chat_preview.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:diaspora_nearby/models/profile_data.dart';

class OrganizationDetailScreen extends ConsumerStatefulWidget {
  final String orgId;
  final Map<String, dynamic>? initialData;

  const OrganizationDetailScreen({
    super.key,
    required this.orgId,
    this.initialData,
  });

  @override
  ConsumerState<OrganizationDetailScreen> createState() => _OrganizationDetailScreenState();
}

class _OrganizationDetailScreenState extends ConsumerState<OrganizationDetailScreen> {
  Map<String, dynamic>? _orgData;
  ProfileData? _superAdminProfile;
  bool _isLoading = true;
  bool _isFollowing = false;
  bool _isFollowLoading = false;
  
  // User location for navigation
  double? _userLat;
  double? _userLng;

  @override
  void initState() {
    super.initState();
    _orgData = widget.initialData;
    _loadData();
    _loadUserLocation();
  }

  Future<void> _loadData() async {
    if (_orgData != null && _orgData!['id'] == widget.orgId) {
       setState(() => _isLoading = false);
    }
    
    try {
      final repo = ref.read(organizationRepositoryProvider);
      final data = await repo.getOrganization(widget.orgId);
      if (mounted) {
        setState(() {
          _orgData = data;
          _isLoading = false;
        });
        _checkIfFollowing();
        
        // Fetch Super Admin Profile
        if (data != null && data['superAdminId'] != null) {
          try {
            final profile = await ref.read(profileRepositoryProvider).getUserProfile(data['superAdminId']);
            if (mounted) {
               setState(() => _superAdminProfile = profile);
            }
          } catch(e) {
             debugPrint('Error fetching super admin: $e');
          }
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openChat() {
    if (_orgData == null) return;
    final chatId = _orgData!['chatId'] as String?;
    if (chatId != null) {
      context.push('/chats/$chatId');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat not available')),
      );
    }
  }

  Future<void> _checkIfFollowing() async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null || _orgData == null) return;
    
    // Check if user is in followers list of org (if we had real-time stream)
    // Or check if userChats contains the org chat ID
    // For now, let's check the local copy of org data if we can trust it? 
    // No, `followers` might not be in the cached view unless we fetched it.
    
    // Better: Check Firestore 'followers' array
    final followers = List<String>.from(_orgData!['followers'] ?? []);
    if (followers.contains(user.uid)) {
       if (mounted) setState(() => _isFollowing = true);
    }
  }

  Future<void> _toggleFollow() async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null) return;
    
    setState(() => _isFollowLoading = true);
    final repo = ref.read(organizationRepositoryProvider);
    
    try {
      if (_isFollowing) {
        await repo.unfollowOrganization(widget.orgId, user.uid);
        if (mounted) setState(() => _isFollowing = false);
      } else {
        await repo.followOrganization(widget.orgId, user.uid);
        if (mounted) setState(() => _isFollowing = true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isFollowLoading = false);
    }
  }

  void _launchUrl(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.parse(url.startsWith('http') ? url : 'https://$url');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _loadUserLocation() async {
    try {
      final userProfile = ref.read(userProfileProvider).value;
      
      if (userProfile?.hostLocation?.geometry?.location != null) {
        if (mounted) {
           setState(() {
              _userLat = userProfile!.hostLocation!.geometry!.location.lat;
              _userLng = userProfile.hostLocation!.geometry!.location.lng;
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
      url = 'https://www.google.com/maps/dir/?api=1&origin=$_userLat,$_userLng&destination=$lat,$lng&travelmode=driving';
    } else {
      url = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    }

    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open maps')),
        );
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
    final isAdmin = (_orgData!['admins'] as List?)?.contains(currentUserId) == true || 
                    _orgData!['superAdminId'] == currentUserId;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      theme.colorScheme.primary.withOpacity(0.8),
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
                          ? Icon(LucideIcons.building2, size: 40, color: theme.colorScheme.primary)
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 100), // Added bottom padding
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
                               style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
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
                       // Follow Button
                       Expanded(
                         child: OutlinedButton.icon(
                           onPressed: _isFollowLoading ? null : _toggleFollow,
                           icon: _isFollowLoading 
                               ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                               : Icon(_isFollowing ? LucideIcons.check : LucideIcons.plus),
                           label: Text(_isFollowing ? 'Following' : 'Follow'),
                           style: OutlinedButton.styleFrom(
                             minimumSize: const Size(double.infinity, 54),
                             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                           ),
                         ),
                       ),
                       const SizedBox(width: 12),
                       // Message Button
                       Expanded(
                         child: FilledButton.icon(
                           onPressed: _openChat,
                           icon: const Icon(LucideIcons.messageCircle),
                           label: const Text('Message'),
                           style: FilledButton.styleFrom(
                             minimumSize: const Size(double.infinity, 54),
                             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                           ),
                         ),
                       ),
                     ],
                   ),
                   const SizedBox(height: 24),

                   // [NEW] Congratulatory Message
                   // Embedded Chat Preview (Visible to all if chatId exists)
                   if (_orgData!['chatId'] != null)
                     Padding(
                       padding: const EdgeInsets.only(bottom: 24.0),
                       child: OrganizationChatPreview(
                         chatId: _orgData!['chatId'],
                         title: 'Organization Board',
                       ),
                     ),

                   // [NEW] Super Admin Card
                   if (_superAdminProfile != null) ...[
                      const Text('Leadership', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      _buildSuperAdminCard(theme),
                      const SizedBox(height: 32),
                   ],

                   // Info Cards
                   const Text('About', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                   const SizedBox(height: 12),
                   Text(
                     description.isNotEmpty ? description : 'No description available.',
                     style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                   ),
                   const SizedBox(height: 32),

                   const Text('Contact & Location', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                   const SizedBox(height: 12),
                   
                   if (city != null)
                     _buildInfoTile(
                        LucideIcons.mapPin, 
                        'Location', 
                        [
                          city,
                          if (state != null) state,
                          if (country != null) country,
                        ].join(', '),
                        onTap: () => _openDirections(),
                     ),
                   
                   if (website != null && website.isNotEmpty)
                     _buildInfoTile(
                        LucideIcons.globe, 
                        'Website', 
                        website,
                        onTap: () => _launchUrl(website)
                     ),
                   
                   if (phone != null && phone.isNotEmpty)
                     _buildInfoTile(
                        LucideIcons.phone, 
                        'Phone', 
                        phone,
                        onTap: () => _launchUrl('tel:$phone')
                     ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String value, {VoidCallback? onTap}) {
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
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 20, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey)),
                    Text(value, style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: onTap != null ? theme.colorScheme.primary : null,
                    )),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(LucideIcons.externalLink, size: 14, color: theme.colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }
  Widget _buildSuperAdminCard(ThemeData theme) {
    if (_superAdminProfile == null) return const SizedBox.shrink();

    // Determine flag (Home Country)
    String flag = '';
    if (_superAdminProfile!.homeCountryCode != null) {
       final country = country_data.getCountryByCode(_superAdminProfile!.homeCountryCode!);
       if (country != null) flag = country.flag;
    }

    // Determine Title
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
               // Avatar
               CircleAvatar(
                 radius: 28,
                 backgroundColor: Colors.grey.shade200,
                 backgroundImage: _superAdminProfile!.profileImage.isNotEmpty
                     ? CachedNetworkImageProvider(_superAdminProfile!.profileImage)
                     : null,
                 child: _superAdminProfile!.profileImage.isEmpty
                     ? Text(
                         _superAdminProfile!.firstName.isNotEmpty ? _superAdminProfile!.firstName[0].toUpperCase() : '?',
                         style: TextStyle(
                           fontSize: 20,
                           fontWeight: FontWeight.bold,
                           color: theme.colorScheme.primary,
                         ),
                       )
                     : null,
               ),
               const SizedBox(width: 12),
               // Info
               Expanded(
                 child: Column(
                   crossAxisAlignment: CrossAxisAlignment.start,
                   children: [
                      // Name + Flag
                      Row(
                        children: [
                           if (flag.isNotEmpty)
                             Padding(
                               padding: const EdgeInsets.only(right: 6),
                               child: Text(flag, style: const TextStyle(fontSize: 16)),
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
                      // Title
                      Text(
                        title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                           color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                   ],
                 ),
               ),
               // Chevron
               Icon(LucideIcons.chevronRight, size: 20, color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5)),
            ],
          ),
        ),
      ),
    );
  }
}

