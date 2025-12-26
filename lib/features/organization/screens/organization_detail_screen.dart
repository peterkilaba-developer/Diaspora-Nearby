import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/organization/repository/organization_repository.dart';
import 'package:diaspora_nearby/features/chat/providers/chat_identity_provider.dart';
import 'package:diaspora_nearby/features/shared/ui/glass_container.dart';
import 'package:url_launcher/url_launcher.dart';

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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _orgData = widget.initialData;
    _loadData();
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

  void _launchUrl(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.parse(url.startsWith('http') ? url : 'https://$url');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
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

                   // Action Button
                   FilledButton.icon(
                     onPressed: _openChat,
                     icon: const Icon(LucideIcons.messageCircle),
                     label: const Text('Message Organization'),
                     style: FilledButton.styleFrom(
                       minimumSize: const Size(double.infinity, 54),
                       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                     ),
                   ),
                   const SizedBox(height: 24),

                   // [NEW] Congratulatory Message
                   if (isAdmin && ((_orgData!['admins'] as List?)?.length ?? 0) <= 1)
                     Padding(
                       padding: const EdgeInsets.only(bottom: 24.0),
                       child: Container(
                         padding: const EdgeInsets.all(16),
                         decoration: BoxDecoration(
                           color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                           borderRadius: BorderRadius.circular(12),
                           border: Border.all(color: theme.colorScheme.primaryContainer),
                         ),
                         child: Row(
                           children: [
                             const Icon(LucideIcons.partyPopper, size: 32, color: Colors.amber),
                             const SizedBox(width: 16),
                             Expanded(
                               child: Column(
                                 crossAxisAlignment: CrossAxisAlignment.start,
                                 children: [
                                   const Text(
                                     'Congratulations!',
                                     style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                   ),
                                   const SizedBox(height: 4),
                                   Text(
                                     'You are the first member of this organization.',
                                     style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[700]),
                                   ),
                                 ],
                               ),
                             ),
                           ],
                         ),
                       ),
                     ),

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
                        ].join(', ')
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
}
