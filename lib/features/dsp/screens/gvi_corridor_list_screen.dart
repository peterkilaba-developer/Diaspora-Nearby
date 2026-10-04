import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:diaspora_nearby/core/data/countries.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

/// Streams every corridor chamber, ordered by cumulative GDP descending.
/// Returns the raw doc data so the UI can pull host/home country codes,
/// chamber id (for navigation), and the GDP/tx counters.
final chamberCorridorsProvider = StreamProvider<List<Map<String, dynamic>>>((
  ref,
) {
  return FirebaseFirestore.instance
      .collection('organizations')
      .where('kind', isEqualTo: 'corridor_chamber')
      .limit(200)
      .snapshots()
      .map((snap) {
        final list = snap.docs.map((d) {
          final data = d.data();
          data['id'] = d.id;
          return data;
        }).toList();
        list.sort((a, b) {
          final ag = (a['gdpTotal'] as num? ?? 0).toDouble();
          final bg = (b['gdpTotal'] as num? ?? 0).toDouble();
          return bg.compareTo(ag);
        });
        return list;
      });
});

Country? _resolveCountry(String input) {
  if (input.isEmpty) return null;
  final trimmed = input.trim();
  final byCode = getCountryByCode(trimmed);
  if (byCode != null) return byCode;
  try {
    return countries.firstWhere(
      (c) => c.name.toLowerCase() == trimmed.toLowerCase(),
    );
  } catch (_) {
    return null;
  }
}

/// Bilateral corridor browser. Each row is one chamber-of-commerce
/// (host ⇄ home) showing real GDP from the unified rollup. Tapping a
/// row opens the chamber detail screen.
class GviCorridorListScreen extends ConsumerStatefulWidget {
  final String homeCountry;
  const GviCorridorListScreen({super.key, required this.homeCountry});

  @override
  ConsumerState<GviCorridorListScreen> createState() =>
      _GviCorridorListScreenState();
}

class _GviCorridorListScreenState extends ConsumerState<GviCorridorListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chambersAsync = ref.watch(chamberCorridorsProvider);
    final resolvedCountry = _resolveCountry(widget.homeCountry);
    final homeCountryCode =
        resolvedCountry?.code.toUpperCase() ??
        (widget.homeCountry.trim().length == 2
            ? widget.homeCountry.trim().toUpperCase()
            : '');
    final homeCountryName = resolvedCountry?.name ?? widget.homeCountry.trim();
    final homeFlag =
        resolvedCountry?.flag ??
        (homeCountryCode.isNotEmpty
            ? (getCountryByCode(homeCountryCode)?.flag ?? '🇹🇿')
            : '🇹🇿');

    final screenTitle = homeCountryName.isNotEmpty
        ? '${homeCountryName.toUpperCase()} Chambers of Commerce'
        : 'Bilateral Chambers of Commerce';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          screenTitle,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppTheme.accentDark,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: AppTheme.accentDark,
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search corridors...',
                hintStyle: TextStyle(color: Colors.white.withAlpha(153)),
                prefixIcon: const Icon(
                  LucideIcons.search,
                  color: Colors.white70,
                  size: 20,
                ),
                filled: true,
                fillColor: Colors.white.withAlpha(26),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 0,
                ),
              ),
            ),
          ),
          Expanded(
            child: chambersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Error loading corridors: $e'),
                ),
              ),
              data: (chambers) {
                final Map<String, Map<String, dynamic>> existingChambersByHost =
                    {};
                for (final c in chambers) {
                  final home = (c['homeCountryCode'] as String? ?? '')
                      .toUpperCase();
                  final host = (c['hostCountryCode'] as String? ?? '')
                      .toUpperCase();
                  if (homeCountryCode.isNotEmpty) {
                    if (home == homeCountryCode && host.isNotEmpty) {
                      existingChambersByHost[host] = c;
                    } else if (host == homeCountryCode && home.isNotEmpty) {
                      existingChambersByHost[home] = c;
                    }
                  }
                }

                final List<Map<String, dynamic>> allCorridors = [];

                if (homeCountryCode.isNotEmpty) {
                  for (final country in countries) {
                    if (country.code.toUpperCase() == homeCountryCode) continue;

                    final hostCode = country.code.toUpperCase();
                    final existing = existingChambersByHost[hostCode];

                    if (existing != null) {
                      allCorridors.add({
                        ...existing,
                        'hostCountryCode': hostCode,
                        'homeCountryCode': homeCountryCode,
                        'hostName': country.name,
                        'hostFlag': country.flag,
                        'homeFlag': homeFlag,
                        'gdpTotal': (existing['gdpTotal'] as num? ?? 0).toInt(),
                        'transactionCount':
                            (existing['transactionCount'] as num? ?? 0).toInt(),
                        'memberCount': (existing['memberCount'] as num? ?? 0)
                            .toInt(),
                        'id':
                            existing['id'] as String? ??
                            'chamber_${hostCode.toLowerCase()}_${homeCountryCode.toLowerCase()}',
                      });
                    } else {
                      allCorridors.add({
                        'id':
                            'chamber_${hostCode.toLowerCase()}_${homeCountryCode.toLowerCase()}',
                        'hostCountryCode': hostCode,
                        'homeCountryCode': homeCountryCode,
                        'hostName': country.name,
                        'hostFlag': country.flag,
                        'homeFlag': homeFlag,
                        'name':
                            '$hostCode ⇄ $homeCountryCode Chamber of Commerce',
                        'gdpTotal': 0,
                        'transactionCount': 0,
                        'memberCount': 0,
                      });
                    }
                  }
                } else {
                  for (final c in chambers) {
                    final host = (c['hostCountryCode'] as String? ?? '')
                        .toUpperCase();
                    final home = (c['homeCountryCode'] as String? ?? '')
                        .toUpperCase();
                    final hostCountry = getCountryByCode(host);
                    final homeCountry = getCountryByCode(home);
                    allCorridors.add({
                      ...c,
                      'hostCountryCode': host,
                      'homeCountryCode': home,
                      'hostName': hostCountry?.name ?? host,
                      'hostFlag': hostCountry?.flag ?? '🏳️',
                      'homeFlag': homeCountry?.flag ?? '🏳️',
                      'gdpTotal': (c['gdpTotal'] as num? ?? 0).toInt(),
                      'transactionCount': (c['transactionCount'] as num? ?? 0)
                          .toInt(),
                      'memberCount': (c['memberCount'] as num? ?? 0).toInt(),
                      'id':
                          c['id'] as String? ??
                          'chamber_${host.toLowerCase()}_${home.toLowerCase()}',
                    });
                  }
                }

                // Sort: GDP descending (corridors with GDP > 0 first), then txCount desc, memberCount desc, then hostName asc
                allCorridors.sort((a, b) {
                  final int ag = (a['gdpTotal'] as num? ?? 0).toInt();
                  final int bg = (b['gdpTotal'] as num? ?? 0).toInt();
                  if (ag != bg) return bg.compareTo(ag);

                  final int atx = (a['transactionCount'] as num? ?? 0).toInt();
                  final int btx = (b['transactionCount'] as num? ?? 0).toInt();
                  if (atx != btx) return btx.compareTo(atx);

                  final int am = (a['memberCount'] as num? ?? 0).toInt();
                  final int bm = (b['memberCount'] as num? ?? 0).toInt();
                  if (am != bm) return bm.compareTo(am);

                  final String an = (a['hostName'] as String? ?? '');
                  final String bn = (b['hostName'] as String? ?? '');
                  return an.compareTo(bn);
                });

                final filtered = allCorridors.where((c) {
                  if (_searchQuery.isEmpty) return true;
                  final q = _searchQuery.toLowerCase().trim();
                  final host = (c['hostCountryCode'] as String? ?? '')
                      .toLowerCase();
                  final home = (c['homeCountryCode'] as String? ?? '')
                      .toLowerCase();
                  final hostName = (c['hostName'] as String? ?? '')
                      .toLowerCase();
                  final name = (c['name'] as String? ?? '').toLowerCase();
                  final homeName = homeCountryName.toLowerCase();

                  return host.contains(q) ||
                      home.contains(q) ||
                      hostName.contains(q) ||
                      name.contains(q) ||
                      homeName.contains(q);
                }).toList();

                if (filtered.isEmpty) {
                  return _buildEmpty();
                }

                return ListView.separated(
                  padding: AppTheme.pagePaddingEdgeInsets.copyWith(
                    top: 16,
                    bottom: 32 + MediaQuery.of(context).padding.bottom,
                  ),
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) =>
                      _CorridorRow(data: filtered[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.activity,
              size: 48,
              color: theme.iconTheme.color?.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isEmpty
                  ? 'No corridors active yet'
                  : 'No corridors match',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              _searchQuery.isEmpty
                  ? 'Corridors appear as users start transacting across borders.'
                  : 'Try a different search term.',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _CorridorRow extends StatelessWidget {
  final Map<String, dynamic> data;
  const _CorridorRow({required this.data});

  @override
  Widget build(BuildContext context) {
    final host = (data['hostCountryCode'] as String?) ?? '';
    final home = (data['homeCountryCode'] as String?) ?? '';
    final hostName =
        data['hostName'] as String? ?? (getCountryByCode(host)?.name ?? host);
    final hostFlag =
        data['hostFlag'] as String? ?? (getCountryByCode(host)?.flag ?? '🏳️');
    final homeFlag =
        data['homeFlag'] as String? ?? (getCountryByCode(home)?.flag ?? '🏳️');
    final gdp = (data['gdpTotal'] as num? ?? 0).toInt();
    final txCount = (data['transactionCount'] as num? ?? 0).toInt();
    final members = (data['memberCount'] as num? ?? 0).toInt();
    final orgId =
        data['id'] as String? ??
        'chamber_${host.toLowerCase()}_${home.toLowerCase()}';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: SizedBox(
        width: 44,
        height: 44,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              bottom: 0,
              child: Text(hostFlag, style: const TextStyle(fontSize: 24)),
            ),
            Positioned(
              right: 0,
              top: 0,
              child: Text(homeFlag, style: const TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
      title: Row(
        children: [
          Text(
            '$host ⇄ $home',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hostName,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
      subtitle: Text(
        '$members members · $txCount tx',
        style: TextStyle(fontSize: 12, color: Colors.blueGrey.withAlpha(204)),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            gdp > 0 ? NumberFormat.compact().format(gdp) : '0',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.accent,
            ),
          ),
          const Text(
            'GDP (DSP)',
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      onTap: orgId.isNotEmpty
          ? () => context.push('/organization/$orgId')
          : null,
    );
  }
}
