import 'dart:ui';
import 'package:diaspora_nearby/features/travel/utils/geo_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:diaspora_nearby/features/organization/repository/organization_repository.dart';
import 'package:diaspora_nearby/features/shared/ui/glass_container.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';

import 'package:diaspora_nearby/features/more/widgets/business_registration_modal.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';

import 'package:diaspora_nearby/core/data/countries.dart' as country_data;
import 'package:diaspora_nearby/features/shared/utils/search_highlight_utils.dart';
import 'package:diaspora_nearby/core/providers/global_feature_provider.dart';

class OrganizationsListScreen extends ConsumerStatefulWidget {
  const OrganizationsListScreen({super.key});

  @override
  ConsumerState<OrganizationsListScreen> createState() =>
      _OrganizationsListScreenState();
}

class _OrganizationsListScreenState
    extends ConsumerState<OrganizationsListScreen> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _organizations = [];
  List<Map<String, dynamic>> _filteredOrgs = [];
  bool _isLoading = true;
  String _searchQuery = '';
  bool _isGlobalView =
      false; // Toggle: false = My Community Orgs, true = All Orgs
  String? _userHomeCountryCode; // Current user's home country code

  // User location for distance calc
  double? _userLat;
  double? _userLng;

  // Organization types for grouping
  static const _orgTypeOrder = [
    'Business Organization (BO)',
    'Diaspora Organization (DO)',
    'Political Organization (PO)',
    'Faith Organization (FO)',
    'Non Governmental Organization (NGO)',
    'Government Organization (GO)',
  ];

  @override
  void initState() {
    super.initState();

    _loadUserLocationSync();
    _seedCachedOrganizations();
    _loadOrganizations();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadUserLocationSync() {
    try {
      final user = ref.read(authRepositoryProvider).currentUser;
      final userProfile =
          ref.read(userProfileProvider).value ??
          (user != null
              ? ref.read(profileRepositoryProvider).getCachedProfile(user.uid)
              : null);

      _userHomeCountryCode = userProfile?.homeCountryCode;

      if (userProfile?.hostLocation.geometry?.location != null) {
        _userLat = userProfile!.hostLocation.geometry!.location.lat;
        _userLng = userProfile.hostLocation.geometry!.location.lng;
      }
    } catch (e) {
      debugPrint('Error loading user location: $e');
    }
  }

  void _seedCachedOrganizations() {
    final orgRepo = ref.read(organizationRepositoryProvider);
    final user = ref.read(authRepositoryProvider).currentUser;
    final cachedAll = orgRepo.getCachedAllOrganizations();
    final cachedMy = user != null
        ? orgRepo.getCachedUserOrganizations(user.uid)
        : null;

    if (cachedAll != null || cachedMy != null) {
      final merged = <Map<String, dynamic>>[
        ...(cachedAll ?? const <Map<String, dynamic>>[]).map(
          (o) => Map<String, dynamic>.from(o),
        ),
      ];
      if (cachedMy != null) {
        for (final myOrg in cachedMy) {
          if (!merged.any((o) => o['id'] == myOrg['id'])) {
            merged.add(Map<String, dynamic>.from(myOrg));
          }
        }
      }
      _computeDistancesAndSort(merged);
      _organizations = merged;
      _filteredOrgs = _filterOrganizationsList(merged);
      _isLoading = false;
    }
  }

  void _computeDistancesAndSort(List<Map<String, dynamic>> orgs) {
    if (_userLat != null && _userLng != null) {
      for (final org in orgs) {
        final location = org['location'] as Map<String, dynamic>?;
        if (location != null) {
          final lat = (location['lat'] as num?)?.toDouble();
          final lng = (location['lng'] as num?)?.toDouble();
          if (lat != null && lng != null) {
            org['distance'] = GeoUtils.haversine(
              _userLat!,
              _userLng!,
              lat,
              lng,
            );
          }
        }
      }

      orgs.sort((a, b) {
        final distA = a['distance'] as double? ?? double.infinity;
        final distB = b['distance'] as double? ?? double.infinity;
        return distA.compareTo(distB);
      });
    }
  }

  Future<void> _loadOrganizations() async {
    if (_organizations.isEmpty) {
      setState(() => _isLoading = true);
    }

    try {
      final orgRepo = ref.read(organizationRepositoryProvider);
      final user = ref.read(authRepositoryProvider).currentUser;

      final results = await Future.wait<List<Map<String, dynamic>>>([
        orgRepo.getAllOrganizations(),
        if (user != null)
          orgRepo.getUserOrganizations(user.uid)
        else
          Future.value(const <Map<String, dynamic>>[]),
      ]);

      final orgs = results[0].map((o) => Map<String, dynamic>.from(o)).toList();
      final myOrgs = results[1];
      for (final myOrg in myOrgs) {
        if (!orgs.any((o) => o['id'] == myOrg['id'])) {
          orgs.add(Map<String, dynamic>.from(myOrg));
        }
      }

      _computeDistancesAndSort(orgs);

      if (!mounted) return;
      setState(() {
        _organizations = orgs;
        _filteredOrgs = _filterOrganizationsList(orgs);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading organizations: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatDistance(double? distance) {
    if (distance == null) return '';

    final miles = distance * 0.621371;
    String kmStr;
    String miStr;

    if (distance < 1) {
      kmStr = '${(distance * 1000).round()} m';
    } else {
      kmStr = '${distance.round()} km';
    }

    if (miles < 1) {
      miStr = '${(miles * 5280).round()} ft';
    } else {
      miStr = '${miles.round()} mi';
    }

    return '$kmStr / $miStr';
  }

  /// Get country flag emoji from country name
  String _getCountryFlag(String? countryName) {
    if (countryName == null || countryName.isEmpty) return '📍';

    final country = country_data.countries.firstWhere(
      (c) => c.name.toLowerCase() == countryName.toLowerCase(),
      orElse: () => country_data.countries.first,
    );

    if (country.name.toLowerCase() == countryName.toLowerCase()) {
      return country.flag;
    }

    return '📍';
  }

  List<Map<String, dynamic>> _filterOrganizationsList(
    List<Map<String, dynamic>> source,
  ) {
    var result = source;

    if (!_isGlobalView && _userHomeCountryCode != null) {
      result = result.where((org) {
        final orgHomeCountryCode = org['homeCountryCode'] as String?;
        return orgHomeCountryCode == _userHomeCountryCode;
      }).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      result = result.where((org) {
        final name =
            (org['businessName'] as String? ?? org['name'] as String? ?? '')
                .toLowerCase();
        final description = (org['description'] as String? ?? '').toLowerCase();
        final city = (org['city'] as String? ?? '').toLowerCase();
        final state = (org['state'] as String? ?? '').toLowerCase();
        final country = (org['country'] as String? ?? '').toLowerCase();
        final type = (org['type'] as String? ?? '').toLowerCase();

        return name.contains(query) ||
            description.contains(query) ||
            city.contains(query) ||
            state.contains(query) ||
            country.contains(query) ||
            type.contains(query);
      }).toList();
    }

    return result;
  }

  /// Apply search query and home country filter
  void _applyFilters() {
    setState(() => _filteredOrgs = _filterOrganizationsList(_organizations));
  }

  void _toggleGlobalView() {
    setState(() => _isGlobalView = !_isGlobalView);
    _applyFilters();
  }

  Future<void> _searchOrganizations(String query) async {
    setState(() => _searchQuery = query);
    _applyFilters();
  }

  /// Group organizations by type
  Map<String, List<Map<String, dynamic>>> _groupByType(
    List<Map<String, dynamic>> orgs,
  ) {
    final grouped = <String, List<Map<String, dynamic>>>{};

    for (final type in _orgTypeOrder) {
      grouped[type] = [];
    }
    grouped['Other'] = [];

    for (final org in orgs) {
      final type = org['type'] as String? ?? 'Other';
      if (grouped.containsKey(type)) {
        grouped[type]!.add(org);
      } else {
        grouped['Other']!.add(org);
      }
    }

    grouped.removeWhere((key, value) => value.isEmpty);

    return grouped;
  }

  IconData _getOrgTypeIcon(String type) {
    switch (type) {
      case 'Business Organization (BO)':
        return LucideIcons.building2;
      case 'Diaspora Organization (DO)':
        return LucideIcons.heartHandshake;
      case 'Political Organization (PO)':
        return LucideIcons.landmark;
      case 'Faith Organization (FO)':
        return LucideIcons.church;
      case 'Non Governmental Organization (NGO)':
        return LucideIcons.heartHandshake;
      case 'Non-Profit Organization (NPO)':
        return LucideIcons.heart;
      case 'Government Organization (GO)':
        return LucideIcons.building;
      default:
        return LucideIcons.briefcase;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    ref.listen(userProfileProvider, (previous, next) {
      final newProfile = next.value;
      if (newProfile != null &&
          newProfile.homeCountryCode != _userHomeCountryCode) {
        setState(() {
          _userHomeCountryCode = newProfile.homeCountryCode;
        });
        _applyFilters();
      }
    });

    final groupedOrgs = _groupByType(_filteredOrgs);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Organizations'),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search bar with global toggle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: GlassContainer(
                borderRadius: BorderRadius.circular(30),
                padding: EdgeInsets.zero,
                child: TextField(
                  controller: _searchController,
                  onChanged: _searchOrganizations,
                  decoration: InputDecoration(
                    hintText: 'Search for Organization',
                    prefixIcon: const Icon(LucideIcons.search, size: 20),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_searchQuery.isNotEmpty)
                          IconButton(
                            icon: const Icon(LucideIcons.x, size: 20),
                            onPressed: () {
                              _searchController.clear();
                              _searchOrganizations('');
                            },
                            tooltip: 'Clear search',
                          ),
                        if (_searchQuery.isEmpty &&
                            ref.watch(isGlobalUnlockedSyncProvider))
                          IconButton(
                            icon: Icon(
                              LucideIcons.globe,
                              size: 24,
                              color: _isGlobalView
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface,
                            ),
                            onPressed: _toggleGlobalView,
                            tooltip: _isGlobalView
                                ? 'Switch to My Organizations'
                                : 'Switch to All Organizations',
                          ),
                      ],
                    ),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
            ),

            // Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredOrgs.isEmpty
                  ? _buildEmptyState(theme)
                  : RefreshIndicator(
                      onRefresh: _loadOrganizations,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: groupedOrgs.length,
                        itemBuilder: (context, index) {
                          final type = groupedOrgs.keys.elementAt(index);
                          final orgs = groupedOrgs[type]!;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _getOrgTypeIcon(type),
                                      size: 18,
                                      color: theme.colorScheme.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        type,
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                              color: theme.colorScheme.primary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary
                                            .withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '${orgs.length}',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: theme.colorScheme.primary,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              ...orgs.map((org) => _buildOrgCard(org, theme)),
                            ],
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              LucideIcons.building2,
              size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _searchQuery.isNotEmpty
                ? 'No organizations found'
                : 'No active organizations yet',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty
                ? 'Try a different search term'
                : 'Be the first to register your organization!',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
          if (_searchQuery.isEmpty) ...[
            const SizedBox(height: 24),
            FilledButton.tonalIcon(
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  useSafeArea: true,
                  builder: (context) => BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: const BusinessRegistrationModal(),
                  ),
                ).then((_) => _loadOrganizations());
              },
              icon: const Icon(LucideIcons.plus, size: 18),
              label: const Text('Register Organization'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOrgCard(Map<String, dynamic> org, ThemeData theme) {
    final name = org['businessName'] as String? ?? 'Unknown';
    final city = org['city'] as String?;
    final state = org['state'] as String?;
    final country = org['country'] as String?;
    final logoUrl = org['profileImage'] as String?;
    final status = org['status'] as String? ?? 'pending';
    final distance = org['distance'] as double?;

    return GestureDetector(
      onTap: () => context.push('/organization/${org['id']}', extra: org),
      child: GlassContainer(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        child: Row(
          children: [
            // Logo
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 56,
                height: 56,
                color: theme.colorScheme.surfaceContainerHighest,
                child: logoUrl != null && logoUrl.isNotEmpty
                    ? Image.network(
                        logoUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Icon(
                          LucideIcons.building2,
                          size: 24,
                          color: theme.colorScheme.outline,
                        ),
                      )
                    : Icon(
                        LucideIcons.building2,
                        size: 24,
                        color: theme.colorScheme.outline,
                      ),
              ),
            ),
            const SizedBox(width: 8),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: SearchHighlightUtils.highlightText(
                          name,
                          _searchQuery,
                          theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          context,
                        ),
                      ),
                      if (status == 'pending') const SizedBox.shrink(),
                    ],
                  ),

                  // Location row with country flag
                  if (city != null || state != null || country != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          _getCountryFlag(country),
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: SearchHighlightUtils.highlightText(
                            [?city, ?state, ?country].join(', '),
                            _searchQuery,
                            theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                            ),
                            context,
                          ),
                        ),
                      ],
                    ),
                  ],
                  // Distance row
                  if (distance != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          LucideIcons.mapPin,
                          size: 12,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatDistance(distance),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          ' away',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
