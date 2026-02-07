import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';

import 'package:diaspora_nearby/models/profile_data.dart';
import 'package:diaspora_nearby/models/chat.dart';
import 'package:diaspora_nearby/models/event_data.dart' as event_model;
import 'package:diaspora_nearby/features/community/models/community_data.dart' as comm_model;
import 'package:diaspora_nearby/features/shared/widgets/user_card.dart';
import 'package:diaspora_nearby/features/chat/utils/community_chat_utils.dart';
import 'package:diaspora_nearby/data/countries.dart' as country_data;
import 'package:diaspora_nearby/utils/location_utils.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import 'package:diaspora_nearby/models/user_points.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';

class UserProfileView extends ConsumerWidget {
  final ProfileData profile;
  final bool isSelf;
  final bool isEnforced;
  final VoidCallback onEdit;
  final Future<List<Chat>> groupsFuture;
  final Future<List<Map<String, dynamic>>> orgsFuture;
  final Stream<List<event_model.Event>> eventsStream;
  final double? distanceKm;

  const UserProfileView({
    super.key,
    required this.profile,
    required this.isSelf,
    this.isEnforced = false,
    required this.onEdit,
    required this.groupsFuture,
    required this.orgsFuture,
    required this.eventsStream,
    this.distanceKm,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isSelf ? 'My Profile' : 'Profile'),
        actions: [
          if (isSelf)
            TextButton.icon(
              onPressed: onEdit,
              icon: const Icon(LucideIcons.edit, size: 16),
              label: const Text('Edit'),
            ),
        ],
        leading: isEnforced ? const SizedBox() : null,
      ),
      body: _safelyBuild(
        () => SingleChildScrollView(
          padding: AppTheme.pagePaddingEdgeInsets.copyWith(bottom: 40),
          child: Column(
            children: [
                // User Card (Safe)
                // User Card (Safe)
                UserCardView(
                  key: const ValueKey('view_UserCard'),
                  user: profile,
                  searchQuery: '',
                  onNameTap: () {},
                  onChatTap: isSelf ? null : () => context.push('/chat/direct/${profile.uid}'),
                  isStatic: true, // We are in View mode
                  distanceKm: distanceKm,
                ),
              
              const SizedBox(height: 16),

              // Diaspora Economy Section (Only for Self)
              // Diaspora Economy Section (Only for Self)
              if (isSelf) ...[
                _safelyBuild(() => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Row(
                    children: [
                      Icon(LucideIcons.wallet, size: 20, color: Theme.of(context).primaryColor),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Diaspora Economy Ecosystem',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ), label: 'EconomyHeader'),
                
                _safelyBuild(() => Column(
                    children: [
                      // Card 1: DSP Points
                      if (isSelf)
                        StreamBuilder<UserPoints?>(
                          stream: ref.watch(pointsRepositoryProvider).streamUserPoints(profile.uid!),
                          builder: (context, snapshot) {
                            final points = snapshot.data?.availablePoints ?? 0;
                            final formattedPoints = NumberFormat('#,###').format(points);
                            return _buildEconomyCard(
                              context,
                              icon: LucideIcons.coins,
                              title: 'Diaspora Social Points - DSP',
                              description: 'Earn & convert to tokens',
                              color: AppTheme.accent,
                              onTap: () => context.push('/dsp/points'),
                              trailing: Text(
                                '$formattedPoints DSP',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.accent,
                                  fontSize: 16,
                                ),
                              ),
                            );
                          },
                        )
                      else
                        _buildEconomyCard(
                          context,
                          icon: LucideIcons.coins,
                          title: 'Diaspora Social Points - DSP',
                          description: 'Earn & convert to tokens',
                          color: AppTheme.accent,
                          onTap: () => context.push('/dsp/points'),
                        ),
                      const SizedBox(height: 12),
                      // Card 1.5: Diaspora Crypto Currency
                      _buildEconomyCard(
                        context,
                        icon: LucideIcons.bitcoin, // Fallback icon
                        imagePath: 'assets/icons/logo-original.png',
                        title: 'Diaspora Crypto Currency - Diaspora \$DSP',
                        description: 'Trade & Exchange',
                        color: AppTheme.accent,
                        isComingSoon: true,
                        onTap: () => context.push('/dsp/crypto'), // Navigate to new screen
                      ),
                      const SizedBox(height: 12),
                      // Card 2: Remittances
                      _buildEconomyCard(
                        context,
                        icon: LucideIcons.send,
                        title: 'International Remittances',
                        description: 'Send money to ${profile.homeCountry ?? 'home'}',
                        color: AppTheme.accent,
                        isComingSoon: true,
                        onTap: () => context.push('/dsp/remittances'),
                      ),
                      const SizedBox(height: 12),
                      // Card 3: Bereavement
                      _buildEconomyCard(
                        context,
                        icon: LucideIcons.heart,
                        title: 'Bereavement Community Fund',
                        description: 'Repatriation to ${profile.homeCountry ?? 'home'}',
                        color: AppTheme.accent, // Standardized to Sage
                        isComingSoon: true,
                        onTap: () => context.push('/dsp/bereavement'),
                      ),
                      const SizedBox(height: 12),
                      // Card 4: Airline Portal
                      _buildEconomyCard(
                        context,
                        icon: LucideIcons.plane,
                        title: 'International Air Flight Portal',
                        description: 'Discounted flights',
                        color: AppTheme.accent, // Standardized to Sage
                        isComingSoon: true,
                        onTap: () => context.push('/dsp/airline'),
                      ),
                      const SizedBox(height: 12),
                      // Card 5: DFDI
                      _buildEconomyCard(
                        context,
                        icon: LucideIcons.trendingUp,
                        title: 'Diaspora Foreign Direct Investments - DFDI',
                        description: 'Invest in ${profile.homeCountry ?? 'home country'}',
                        color: AppTheme.accent, // Standardized to Sage
                        isComingSoon: true,
                        onTap: () => context.push('/dsp/dfdi'),
                      ),
                    ],
                  ), label: 'DiasporaEconomyCards'),
                const SizedBox(height: 16),
              ],
              
              const SizedBox(height: 16),

              // Residency & Location
              if ((profile.yearsInHostCountry != null && profile.yearsInHostCountry!.isNotEmpty) || (profile.pastLocations?.isNotEmpty ?? false))
                _safelyBuild(() => _buildSectionContainer(
                  context,
                  title: 'Residency & Locations',
                  icon: LucideIcons.mapPin,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildResidencySection(context),
                      const SizedBox(height: 12),
                      _buildPastLocationsSection(context),
                    ],
                  ),
                ), label: 'LocationSection'),

              // Business Profile
              if (profile.businessProfile?.isBusinessVerified == true)
                _safelyBuild(() => _buildBusinessCard(context, profile.businessProfile!), label: 'BusinessCard'),

              // Bio
              if (profile.bio != null && profile.bio!.isNotEmpty)
                _safelyBuild(() => _buildSectionContainer(
                  context,
                  title: 'About Me',
                  icon: LucideIcons.user,
                  child: Text(profile.bio!, style: const TextStyle(height: 1.5)),
                ), label: 'Bio'),

              // Professional Info
              if ((profile.profession?.isNotEmpty ?? false) || (profile.industry?.isNotEmpty ?? false))
                _safelyBuild(() => _buildSectionContainer(
                  context,
                  title: 'Professional Info',
                  icon: LucideIcons.briefcase,
                  child: _buildProfessionalDisplay(context),
                ), label: 'Profession'),

              // Languages
              if (profile.languages?.isNotEmpty ?? false)
                _safelyBuild(() => _buildSectionContainer(
                  context,
                  title: 'Languages',
                  icon: LucideIcons.languages,
                  child: _buildTagsDisplay(context, profile.languages!),
                ), label: 'Languages'),

              // Education
              if (profile.education != null && profile.education!.isNotEmpty)
                _safelyBuild(() => _buildSectionContainer(
                  context,
                  title: 'Education',
                  icon: LucideIcons.graduationCap,
                  child: Column(
                    children: profile.education!.map((edu) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(edu.institution, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${edu.degree} • ${edu.graduationYear}'),
                      leading: const Icon(LucideIcons.school),
                    )).toList(),
                  ),
                ), label: 'Education'),

              // Interests
              if (profile.interests?.isNotEmpty ?? false)
                _safelyBuild(() => _buildSectionContainer(
                  context,
                  title: 'Interests',
                  icon: LucideIcons.heart,
                  child: _buildTagsDisplay(context, profile.interests!),
                ), label: 'Interests'),

              // Community Support
              if ((profile.servicesOffered?.isNotEmpty ?? false) || (profile.lookingFor?.isNotEmpty ?? false))
                _safelyBuild(() => _buildSectionContainer(
                  context,
                  title: 'Community Support',
                  icon: LucideIcons.users,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (profile.servicesOffered?.isNotEmpty ?? false) ...[
                         const Text('Services I Can Offer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                         const SizedBox(height: 8),
                         _buildTagsDisplay(context, profile.servicesOffered!, isOutline: true),
                         const SizedBox(height: 16),
                      ],
                      if (profile.lookingFor?.isNotEmpty ?? false) ...[
                         const Text("What I'm Looking For", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                         const SizedBox(height: 8),
                         _buildTagsDisplay(context, profile.lookingFor!),
                      ]
                    ],
                  ),
                ), label: 'CommunitySupport'),

              // Availability
              if (profile.availability?.isNotEmpty ?? false)
                _safelyBuild(() => _buildSectionContainer(
                  context,
                  title: 'Availability',
                  icon: LucideIcons.clock,
                  child: _buildTagsDisplay(context, profile.availability!),
                ), label: 'Availability'),

              // Meeting Preferences
              if (profile.meetingPreferences?.isNotEmpty ?? false)
                _safelyBuild(() => _buildSectionContainer(
                  context,
                  title: 'Meeting Preferences',
                  icon: LucideIcons.coffee,
                  child: _buildTagsDisplay(context, profile.meetingPreferences!),
                ), label: 'MeetingPrefs'),

              // Social Media
              if (profile.socialLinks != null)
                _safelyBuild(() => _buildSectionContainer(
                  context,
                  title: 'Social Media',
                  icon: LucideIcons.share2,
                  child: Wrap(
                    spacing: 16,
                    children: [
                      if (profile.socialLinks!.instagram?.isNotEmpty ?? false) _buildSocialLink(LucideIcons.instagram, profile.socialLinks!.instagram!),
                      if (profile.socialLinks!.twitter?.isNotEmpty ?? false) _buildSocialLink(LucideIcons.twitter, profile.socialLinks!.twitter!),
                      if (profile.socialLinks!.linkedin?.isNotEmpty ?? false) _buildSocialLink(LucideIcons.linkedin, profile.socialLinks!.linkedin!),
                      if (profile.socialLinks!.facebook?.isNotEmpty ?? false) _buildSocialLink(LucideIcons.facebook, profile.socialLinks!.facebook!),
                    ],
                  ),
                ), label: 'SocialMedia'),

              const SizedBox(height: 8),
              _buildDynamicMembershipSection<Chat>(context, 'Groups', LucideIcons.messageCircle, groupsFuture, (g) => ListTile(title: Text(g.name), dense: true)),
              _buildDynamicMembershipSection<Map<String, dynamic>>(context, 'Organizations', LucideIcons.building, orgsFuture, (o) => ListTile(title: Text(o['name'] ?? 'Org'), subtitle: Text(o['type'] ?? ''), dense: true)),
              _buildEventsSection(context),
            ],
          ),
        ),
        label: 'ProfileBody'
      ),
    );
  }

  /// [NEW] Integrity Safety Wrapper
  Widget _safelyBuild(Widget Function() builder, {String label = 'Section'}) {
    try {
      return builder();
    } catch (e, stack) {
      debugPrint('Error rendering $label: $e');
      return const SizedBox.shrink();
    }
  }

  Widget _buildSectionContainer(BuildContext context, {required String title, IconData? icon, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(AppTheme.cardPadding),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildResidencySection(BuildContext context) {
    if (profile.yearsInHostCountry == null || profile.yearsInHostCountry!.isEmpty) return const SizedBox.shrink();

    final isSinceBirth = profile.yearsInHostCountry == 'Since birth';
    final yearText = profile.yearsInHostCountry!;
    String durationText = '';

    if (!isSinceBirth) {
       final startYear = int.tryParse(yearText);
       if (startYear != null) {
          final diff = DateTime.now().year - startYear;
          durationText = ' • $diff years';
       }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Lived in ${profile.hostCountry ?? 'this country'} since', style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13)),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(LucideIcons.clock, size: 16, color: Theme.of(context).primaryColor),
            const SizedBox(width: 8),
            Text(
              isSinceBirth ? 'Birth' : '$yearText$durationText',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPastLocationsSection(BuildContext context) {
    if (profile.pastLocations == null || profile.pastLocations!.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Also lived in', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 4),
        ...profile.pastLocations!.map((p) {
           return (() {
             try {
               String? flag;
               if (p.location.countryCode != null) {
                  flag = country_data.getCountryByCode(p.location.countryCode!)?.flag;
               }
               
               // Fallback: search by country name if code is missing
               if (flag == null && p.location.country != null) {
                  final countries = country_data.countries.where((c) => c.name.toLowerCase() == p.location.country!.toLowerCase() || c.code.toLowerCase() == p.location.country!.toLowerCase()).toList();
                  if (countries.isNotEmpty) flag = countries.first.flag;
               }

               // [STANDARDIZATION] Use full address
               final formattedAddress = formatFullAddress(p.location.formattedAddress);
               
               return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                       const Icon(LucideIcons.mapPin, size: 16),
                       if (flag != null) ...[
                          const SizedBox(width: 8),
                          Text(flag, style: const TextStyle(fontSize: 18)),
                       ],
                    ],
                  ),
                  title: Text(formattedAddress),
                  subtitle: Text('Until ${() {
                      try {
                        final dt = DateTime.parse(p.until);
                        return dt.year.toString();
                      } catch (_) {
                         return p.until;
                      }
                  }()}'),
               );
             } catch (e) {
               debugPrint('Error rendering past location: $e');
               return const SizedBox.shrink();
             }
           })();
        }),
      ],
    );
  }

  Widget _buildBusinessCard(BuildContext context, BusinessProfile business) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: Theme.of(context).brightness == Brightness.dark
            ? [Colors.blue.shade900.withOpacity(0.2), Colors.indigo.shade900.withOpacity(0.2)]
            : [Colors.blue.shade50, Colors.indigo.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.blue.shade600,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(LucideIcons.briefcase, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(business.businessName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark ? Colors.blue.shade900 : Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(business.businessType, style: TextStyle(fontSize: 12, color: Theme.of(context).brightness == Brightness.dark ? Colors.blue.shade300 : Colors.blue.shade700)),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark ? Colors.green.shade900 : Colors.green.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Text('Verified Business', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Theme.of(context).brightness == Brightness.dark ? Colors.green.shade300 : Colors.green.shade700)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(business.businessDescription, style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              if (business.businessEmail.isNotEmpty) _buildBusinessContact(LucideIcons.globe, business.businessEmail, 'mailto:${business.businessEmail}'),
              if (business.businessPhone.isNotEmpty) _buildBusinessContact(LucideIcons.phone, business.businessPhone, 'tel:${business.businessPhone}'),
              if (business.website.isNotEmpty) _buildBusinessContact(LucideIcons.link, business.website, business.website),
            ],
          ),
          if (business.businessAddress.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(LucideIcons.mapPin, size: 14, color: Colors.blue.shade600),
                const SizedBox(width: 4),
                // [STANDARDIZATION] Use full address
                Expanded(child: Text(formatFullAddress(business.businessAddress), style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor))),
              ],
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildBusinessContact(IconData icon, String text, String url) {
    return InkWell(
      onTap: () => launchUrl(Uri.parse(url)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.blue.shade600),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 12, color: Colors.blue.shade600, decoration: TextDecoration.underline)),
        ],
      ),
    );
  }

  Widget _buildTagsDisplay(BuildContext context, List<String> tags, {bool isOutline = false}) {
    // [FIX] Sanitize input list to remove nulls or empty strings
    final validTags = tags.where((t) => t.isNotEmpty).toList();

    if (validTags.isEmpty) return const Text('Not specified', style: TextStyle(color: Colors.grey));

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: validTags.map((tag) => _buildChip(context, tag, isOutline: isOutline)).toList(),
    );
  }

  Widget _buildChip(BuildContext context, String tag, {bool isOutline = false}) {
    return Chip(
      label: Text(tag),
      backgroundColor: isOutline ? Colors.transparent : null,
      side: isOutline ? BorderSide(color: Theme.of(context).dividerColor) : null,
    );
  }

  Widget _buildSocialLink(IconData icon, String url) {
     return IconButton(
       icon: Icon(icon),
       onPressed: () => launchUrl(Uri.parse(url)),
       tooltip: url,
     );
  }

  Widget _buildProfessionalDisplay(BuildContext context) {
     final professions = profile.profession?.where((t) => t.isNotEmpty).toList() ?? [];
     final industries = profile.industry?.where((t) => t.isNotEmpty).toList() ?? [];

     return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
           if (professions.isNotEmpty || industries.isNotEmpty)
             Wrap(
               spacing: 8,
               runSpacing: 8,
               children: [
                  ...professions.map((t) => _buildChip(context, t, isOutline: false)),
                  // Use outline for industries to visually distinguish them in the same flow
                  ...industries.map((t) => _buildChip(context, t, isOutline: true)),
               ],
             ),
           
           if (profile.occupation != null && profile.occupation!.isNotEmpty) ...[
               const SizedBox(height: 12),
               Row(
                 children: [
                   Icon(LucideIcons.briefcase, size: 16, color: Theme.of(context).primaryColor),
                   const SizedBox(width: 8),
                   Expanded(child: Text(profile.occupation!, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15))),
                 ],
               ),
           ]
        ],
     );
  }

  Widget _buildDynamicMembershipSection<T>(BuildContext context, String title, IconData icon, Future<List<T>> future, Widget Function(T) builder) {
    return FutureBuilder<List<T>>(
      future: future,
      builder: (context, snapshot) {
         if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();
         return Column(
           children: [
             // Header
             Padding(
               padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
               child: Row(
                 children: [
                   Icon(icon, size: 20, color: Theme.of(context).primaryColor),
                   const SizedBox(width: 8),
                   Expanded(
                     child: Text(
                       title,
                       style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                     ),
                   ),
                 ],
               ),
             ),
             // Content
             ...snapshot.data!.map((item) => Padding(
               padding: const EdgeInsets.only(bottom: 8),
               child: _safelyBuild(
                 () => _buildRichCard<T>(context, item, builder),
                 label: 'Item ${item.hashCode}'
               ),
             )),
             const SizedBox(height: 8),
           ],
         );
      },
    );
  }

  Widget _buildRichCard<T>(BuildContext context, T item, Widget Function(T) contentBuilder) {
      if (item is comm_model.Community) {
         return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              // Removed Border.all
            ),
            child: Row(
               children: [
                  CommunityChatUtils.getCommunityAvatar(
                    context: context,
                    type: item.type,
                    locationType: item.locationType,
                    flag: item.flag,
                    profileImage: item.profileImage,
                    size: 40
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                     child: Column(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: [
                          Text(
                            item.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (item.totalMembers != null)
                            Text('${item.totalMembers} members', style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12)),
                       ],
                     )
                  ),
               ],
            ),
         );
      } else if (item is Map<String, dynamic>) { // Organization
         final name = item['businessName'] ?? item['name'] ?? 'Organization';
         final type = item['businessType'] ?? item['type'] ?? 'Business';
         final image = item['profileImage'] ?? item['logoUrl'];

         final id = item['id'];

         return InkWell(
            onTap: id != null ? () => context.push('/organization/$id', extra: item) : null,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
                // Removed Border.all
              ),
              child: Row(
                 children: [
                    CircleAvatar(
                       radius: 20,
                       backgroundColor: Theme.of(context).primaryColor,
                       backgroundImage: image != null ? CachedNetworkImageProvider(image) : null,
                       child: image == null ? const Icon(LucideIcons.building, color: Colors.white, size: 20) : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                       child: Column(
                         crossAxisAlignment: CrossAxisAlignment.start,
                         children: [
                            Text(
                              name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              type,
                              style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                         ],
                       )
                    ),
                 ],
              ),
            ),
         );
      } else if (item is Chat) { // Groups
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              // Removed Border.all
            ),
            child: Row(
               children: [
                  CircleAvatar(
                     radius: 20,
                     backgroundImage: item.photoUrl != null ? CachedNetworkImageProvider(item.photoUrl!) : null,
                     child: item.photoUrl == null ? const Icon(LucideIcons.users, color: Colors.white, size: 20) : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                     child: Column(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: [
                          Text(
                            item.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text('${item.participants.length} members', style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12)),
                       ],
                     )
                  ),
               ],
            ),
         );
      }
      return contentBuilder(item);
  }

  Widget _buildEventsSection(BuildContext context) {
    return StreamBuilder<List<event_model.Event>>(
      stream: eventsStream,
      builder: (context, snapshot) {
         if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();
         
         // Filter for upcoming events only
         final now = DateTime.now();
         final today = DateTime(now.year, now.month, now.day);
         final upcomingEvents = snapshot.data!.where((e) {
            try {
              final eventDate = DateTime.parse(e.startDate);
              return !eventDate.isBefore(today);
            } catch (_) {
              return true; // Keep it if we can't parse it
            }
         }).toList();

         if (upcomingEvents.isEmpty) return const SizedBox.shrink();

         return Column(
           children: [
             // Header
             Padding(
               padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
               child: Row(
                 children: [
                   Icon(LucideIcons.calendar, size: 20, color: Theme.of(context).primaryColor),
                   const SizedBox(width: 8),
                   const Expanded(
                     child: Text(
                       'Upcoming Events',
                       style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                     ),
                   ),
                 ],
               ),
             ),
             // Content
             ...upcomingEvents.map((e) => Padding(
               padding: const EdgeInsets.only(bottom: 12),
               child: _buildEventCard(context, e)
             )),
             const SizedBox(height: 8),
           ],
         );
      },
    );
  }

  Widget _buildEventCard(BuildContext context, event_model.Event event) {
     String formatToAmPm(String time) {
       try {
         final parts = time.split(':');
         if (parts.length >= 2) {
           final hour = int.parse(parts[0]);
           final minute = int.parse(parts[1]);
           final dt = DateTime(2000, 1, 1, hour, minute);
           return DateFormat('h:mm a').format(dt);
         }
       } catch (_) {}
       return time;
     }

     final displayStartTime = formatToAmPm(event.startTime);
     final displayEndTime = event.endTime != null ? formatToAmPm(event.endTime!) : "End";

     return InkWell(
       onTap: () => context.push('/events/${event.id}', extra: event),
       borderRadius: BorderRadius.circular(16),
       child: Container(
       padding: const EdgeInsets.all(12),
       decoration: BoxDecoration(
         color: Theme.of(context).cardColor,
         borderRadius: BorderRadius.circular(16),
       ),
       child: Row(
         children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: (event.imageUrl?.isNotEmpty ?? false)
                  ? CachedNetworkImage(imageUrl: event.imageUrl!, width: 60, height: 60, fit: BoxFit.cover)
                  : Container(width: 60, height: 60, color: Colors.grey.withOpacity(0.1), child: const Icon(LucideIcons.calendar)),
            ),
            const SizedBox(width: 12),
             Expanded(
               child: Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                   // Row 1: Title (One line)
                   Text(
                     event.title,
                     style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                     maxLines: 1,
                     overflow: TextOverflow.ellipsis,
                   ),
                   const SizedBox(height: 4),
                   // Row 2: Location/Venue (One line)
                   Text(
                     event.venueName ?? "Online",
                     style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13),
                     maxLines: 1,
                     overflow: TextOverflow.ellipsis,
                   ),
                   const SizedBox(height: 2),
                   // Row 3: Date and Time (One line)
                   Row(
                     children: [
                       Icon(LucideIcons.calendar, size: 12, color: Theme.of(context).primaryColor),
                       const SizedBox(width: 4),
                       Expanded(
                         child: Text(
                           '${DateFormat.yMMMd().format(DateTime.parse(event.startDate))} • $displayStartTime - $displayEndTime',
                           style: TextStyle(
                             color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                             fontSize: 12,
                             fontWeight: FontWeight.w500,
                           ),
                           maxLines: 1,
                           overflow: TextOverflow.ellipsis,
                         ),
                       ),
                     ],
                   ),
                 ],
               ),
             ),
         ],
       ),
      ),
    );
  }

  Widget _buildEconomyCard(
    BuildContext context, {
    required IconData icon,
    String? imagePath, // [NEW] Optional image
    required String title,
    required String description,
    required Color color,
    required VoidCallback onTap,
    bool isComingSoon = false,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: Theme.of(context).brightness == Brightness.dark
                ? [color.withOpacity(0.15), color.withOpacity(0.05)]
                : [color.withOpacity(0.1), color.withOpacity(0.05)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                  Container(
                    padding: imagePath != null ? EdgeInsets.zero : const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: imagePath != null ? Colors.transparent : color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: imagePath != null 
                        ? Image.asset(imagePath, width: 45, height: 45, fit: BoxFit.contain, color: AppTheme.accent)
                        : Icon(icon, color: color, size: 24),
                  ),
                if (isComingSoon)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey.shade800
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Coming Soon',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                    ),
                  )
                else if (trailing != null)
                  trailing,
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).hintColor,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
