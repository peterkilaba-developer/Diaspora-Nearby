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
final _chamberCorridorsProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) {
  return FirebaseFirestore.instance
      .collection('organizations')
      .where('kind', isEqualTo: 'corridor_chamber')
      .snapshots()
      .map((snap) {
    final list = snap.docs
        .map((d) {
          final data = d.data();
          data['id'] = d.id;
          return data;
        })
        .toList();
    list.sort((a, b) {
      final ag = (a['gdpTotal'] as num? ?? 0).toDouble();
      final bg = (b['gdpTotal'] as num? ?? 0).toDouble();
      return bg.compareTo(ag);
    });
    return list;
  });
});

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
    final chambersAsync = ref.watch(_chamberCorridorsProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Bilateral Corridors',
          style: TextStyle(
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
                final filtered = chambers.where((c) {
                  if (_searchQuery.isEmpty) return true;
                  final q = _searchQuery.toLowerCase();
                  final host =
                      (c['hostCountryCode'] as String? ?? '').toLowerCase();
                  final home =
                      (c['homeCountryCode'] as String? ?? '').toLowerCase();
                  final name =
                      (c['name'] as String? ?? '').toLowerCase();
                  return host.contains(q) || home.contains(q) || name.contains(q);
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
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) => _CorridorRow(data: filtered[index]),
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
    final hostFlag = getCountryByCode(host)?.flag ?? '🏳️';
    final homeFlag = getCountryByCode(home)?.flag ?? '🏳️';
    final gdp = (data['gdpTotal'] as num? ?? 0).toInt();
    final txCount = (data['transactionCount'] as num? ?? 0).toInt();
    final members = (data['memberCount'] as num? ?? 0).toInt();
    final orgId = data['id'] as String? ?? '';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      leading: SizedBox(
        width: 40,
        height: 40,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              bottom: 0,
              child: Text(hostFlag, style: const TextStyle(fontSize: 22)),
            ),
            Positioned(
              right: 0,
              top: 0,
              child: Text(homeFlag, style: const TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
      title: Text(
        '$host ⇄ $home',
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
      subtitle: Text(
        '$members members · $txCount tx',
        style: TextStyle(
          fontSize: 12,
          color: Colors.blueGrey.withAlpha(204),
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            NumberFormat.compact().format(gdp),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.accent,
            ),
          ),
          const Text(
            'GDP',
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      onTap: orgId.isNotEmpty ? () => context.push('/organization/$orgId') : null,
    );
  }
}
