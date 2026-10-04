import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/dsp/services/emergency_fund_service.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/shared/widgets/user_card.dart';
import 'package:diaspora_nearby/core/data/countries.dart' as country_data;

/// Public transparency dashboard for the Ubuntu Emergency Fund.
/// Shows: treasury $DIASPORA balance, total direct contributions, member
/// & interest counts, and the full on-chain ledger of every contribution
/// and disbursement with recipient info + tx hash.
class EmergencyFundTransparencyScreen extends ConsumerStatefulWidget {
  const EmergencyFundTransparencyScreen({super.key});

  @override
  ConsumerState<EmergencyFundTransparencyScreen> createState() =>
      _EmergencyFundTransparencyScreenState();
}

class _EmergencyFundTransparencyScreenState
    extends ConsumerState<EmergencyFundTransparencyScreen> {
  Map<String, dynamic>? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });

    // Try the Cloud Function first (gives live on-chain treasury balance).
    // Cap the wait so a slow/unreachable function doesn't strand the UI on a spinner.
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('getEmergencyFundStats')
          .call()
          .timeout(const Duration(seconds: 6));
      if (mounted) {
        setState(() {
          _stats = Map<String, dynamic>.from(res.data as Map);
          _loading = false;
        });
      }
      return;
    } catch (e) {
      // Function not deployed yet, slow, or transient failure — fall back
      // to Firestore aggregates so the page is still useful.
      debugPrint('[Transparency] Cloud Function fallback: $e');
    }

    final fs = FirebaseFirestore.instance;
    int interested = 0;
    int members = 0;
    String? treasuryAddr;

    try {
      final interestAgg = await fs
          .collection('emergency_fund_interest')
          .count()
          .get();
      interested = interestAgg.count ?? 0;
    } catch (e) {
      debugPrint('[Transparency] interest fallback: $e');
    }
    try {
      final memberAgg = await fs
          .collection('emergency_fund_memberships')
          .where('status', isEqualTo: 'active')
          .count()
          .get();
      members = memberAgg.count ?? 0;
    } catch (e) {
      debugPrint('[Transparency] members fallback: $e');
    }
    try {
      final cached = await fs
          .collection('system_stats')
          .doc('emergency_fund')
          .get();
      treasuryAddr = cached.data()?['treasuryWallet'] as String?;
    } catch (e) {
      debugPrint('[Transparency] cached treasury fallback: $e');
    }

    if (mounted) {
      setState(() {
        _stats = {
          'treasuryAddress': treasuryAddr,
          'treasuryBalanceDiaspora': '—',
          'totalContributedUsd': members * 100,
          'interestedCount': interested,
          'activeMembers': members,
          'degraded': true,
        };
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final svc = ref.watch(emergencyFundServiceProvider);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Fund Transparency'),
          actions: [
            IconButton(
              icon: const Icon(LucideIcons.refreshCw),
              onPressed: _load,
            ),
          ],
          bottom: TabBar(
            tabs: [
              const Tab(text: 'Overview'),
              _countedTab('Interested', svc.streamInterestedUserIds()),
              _countedTab('Members', svc.streamActiveMemberUserIds()),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildOverviewTab(theme),
            const _CountrySortedUserList(source: _UserListSource.interested),
            const _CountrySortedUserList(source: _UserListSource.members),
          ],
        ),
      ),
    );
  }

  Widget _countedTab(String label, Stream<List<String>> stream) {
    return Tab(
      child: StreamBuilder<List<String>>(
        stream: stream,
        builder: (context, snap) {
          final n = snap.data?.length;
          return Text(n == null ? label : '$label ($n)');
        },
      ),
    );
  }

  Widget _buildOverviewTab(ThemeData theme) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        children: [
          // ── Stats grid ──
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            _statsCard(theme),
            const SizedBox(height: 16),
            if (_stats!['treasuryAddress'] != null)
              _walletRow(theme, _stats!['treasuryAddress'] as String),
            const SizedBox(height: 24),
          ],

          // ── Ledger ──
          Row(
            children: [
              Icon(
                LucideIcons.scrollText,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              const Text(
                'Fund Activities on Blockchain',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('emergency_fund_ledger')
                .orderBy('createdAt', descending: true)
                .limit(100)
                .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'No ledger entries yet.',
                      style: TextStyle(color: theme.hintColor),
                    ),
                  ),
                );
              }
              return Column(
                children: docs
                    .map(
                      (d) =>
                          _ledgerCard(theme, d.data() as Map<String, dynamic>),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _statsCard(ThemeData theme) {
    String fmtNum(dynamic n) {
      final v = (n is num) ? n : num.tryParse(n?.toString() ?? '');
      if (v == null || v == 0) return '—';
      return NumberFormat.compact().format(v);
    }

    final treasuryRaw = _stats!['treasuryBalanceDiaspora']?.toString() ?? '—';
    final treasury = (treasuryRaw == '—' || treasuryRaw.isEmpty)
        ? '—'
        : NumberFormat.compact().format(double.tryParse(treasuryRaw) ?? 0);
    final contributedUsd = fmtNum(_stats!['totalContributedUsd']);
    final interested = fmtNum(_stats!['interestedCount']);
    final members = fmtNum(_stats!['activeMembers']);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _statTile(
                theme,
                null,
                treasury,
                'Treasury \$DIASPORA',
                logoAsset: 'assets/icons/logo-orange-transparent-32.png',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _statTile(
                theme,
                LucideIcons.dollarSign,
                '\$$contributedUsd',
                'Total Contributed',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _statTile(
                theme,
                LucideIcons.heart,
                interested,
                'Interested',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _statTile(
                theme,
                LucideIcons.shieldCheck,
                members,
                'Active Members',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _statTile(
    ThemeData theme,
    IconData? icon,
    String value,
    String label, {
    String? logoAsset,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (logoAsset != null)
            Image.asset(logoAsset, width: 16, height: 16)
          else
            Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text(label, style: TextStyle(fontSize: 11, color: theme.hintColor)),
        ],
      ),
    );
  }

  Widget _walletRow(ThemeData theme, String addr) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.wallet, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          const Text('Treasury: ', style: TextStyle(fontSize: 11)),
          Expanded(
            child: Text(
              addr,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _ledgerCard(ThemeData theme, Map<String, dynamic> e) {
    final kind = e['kind']?.toString() ?? '';
    final isDisbursement = kind == 'disbursement';
    final amount = e['amountDiaspora'] ?? 0;
    final usd = e['amountUsdEquivalent'] ?? 0;
    final txHash = e['txHash']?.toString() ?? '';
    final ts = (e['createdAt'] as Timestamp?)?.toDate();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isDisbursement
                    ? LucideIcons.arrowUpRight
                    : LucideIcons.arrowDownLeft,
                size: 14,
                color: isDisbursement ? Colors.orange : Colors.green,
              ),
              const SizedBox(width: 6),
              Text(
                isDisbursement ? 'Disbursement' : 'Contribution',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Text(
                '$amount \$DIASPORA',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '≈ \$$usd USD',
            style: TextStyle(fontSize: 11, color: theme.hintColor),
          ),
          if (isDisbursement) ...[
            const SizedBox(height: 8),
            _kv(theme, 'Recipient', e['beneficiaryName']?.toString() ?? '—'),
            _kv(theme, 'Country', e['beneficiaryCountry']?.toString() ?? '—'),
            _kv(theme, 'Relationship', e['relationship']?.toString() ?? '—'),
            _kv(theme, 'Type', e['emergencyType']?.toString() ?? '—'),
            if ((e['description']?.toString() ?? '').isNotEmpty)
              _kv(theme, 'Reason', e['description'].toString()),
          ],
          const SizedBox(height: 6),
          _kv(
            theme,
            'To',
            (e['toWallet']?.toString() ?? '').isNotEmpty
                ? _short(e['toWallet'].toString())
                : '—',
          ),
          if (txHash.isNotEmpty) _kv(theme, 'Tx', _short(txHash)),
          if (ts != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                DateFormat.yMMMd().add_jm().format(ts),
                style: TextStyle(fontSize: 10, color: theme.hintColor),
              ),
            ),
        ],
      ),
    );
  }

  Widget _kv(ThemeData theme, String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            k,
            style: TextStyle(fontSize: 11, color: theme.hintColor),
          ),
        ),
        Expanded(
          child: Text(
            v,
            style: const TextStyle(fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );

  String _short(String s) =>
      s.length > 16 ? '${s.substring(0, 8)}…${s.substring(s.length - 6)}' : s;
}

enum _UserListSource { interested, members }

/// Renders a list of users using the shared [UserCardView] (with the
/// current-location row hidden), grouped/sorted alphabetically by the
/// user's host country. The Interested variant is rendered greyed-out.
class _CountrySortedUserList extends ConsumerWidget {
  final _UserListSource source;
  const _CountrySortedUserList({required this.source});

  Stream<List<String>> _idsStream(WidgetRef ref) {
    final svc = ref.read(emergencyFundServiceProvider);
    return source == _UserListSource.interested
        ? svc.streamInterestedUserIds()
        : svc.streamActiveMemberUserIds();
  }

  String _emptyLabel() => source == _UserListSource.interested
      ? 'No interested members yet.'
      : 'No active members yet.';

  Widget _countryHeader(ThemeData theme, String code, int count) {
    final country = code.isEmpty ? null : country_data.getCountryByCode(code);
    final flag = country?.flag ?? '🏳️';
    final name = country?.name ?? 'Unknown';
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(
        children: [
          Text(flag, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Text(
            name,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 1,
              color: theme.dividerColor.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return StreamBuilder<List<String>>(
      stream: _idsStream(ref),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final ids = snap.data ?? const <String>[];
        if (ids.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                _emptyLabel(),
                style: TextStyle(color: theme.hintColor),
              ),
            ),
          );
        }
        final repo = ref.read(profileRepositoryProvider);
        return FutureBuilder<List<ProfileData?>>(
          future: Future.wait(ids.map(repo.getUserProfile)),
          builder: (context, profSnap) {
            if (!profSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final profiles = profSnap.data!.whereType<ProfileData>().toList()
              ..sort((a, b) {
                final ca = (a.homeCountryCode ?? '').toUpperCase();
                final cb = (b.homeCountryCode ?? '').toUpperCase();
                final byCountry = ca.compareTo(cb);
                if (byCountry != 0) return byCountry;
                return '${a.firstName} ${a.lastName}'.toLowerCase().compareTo(
                  '${b.firstName} ${b.lastName}'.toLowerCase(),
                );
              });
            if (profiles.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _emptyLabel(),
                    style: TextStyle(color: theme.hintColor),
                  ),
                ),
              );
            }
            // Group by host country (already sorted alphabetically).
            final groups = <String, List<ProfileData>>{};
            for (final p in profiles) {
              final code = (p.homeCountryCode ?? '').toUpperCase();
              groups.putIfAbsent(code, () => []).add(p);
            }
            final children = <Widget>[];
            groups.forEach((code, list) {
              children.add(_countryHeader(theme, code, list.length));
              for (final p in list) {
                final card = UserCardView(
                  user: p,
                  showCurrentLocation: false,
                  isStatic: true,
                );
                children.add(
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: source == _UserListSource.interested
                        ? Opacity(opacity: 0.55, child: card)
                        : card,
                  ),
                );
              }
            });
            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
              children: children,
            );
          },
        );
      },
    );
  }
}
