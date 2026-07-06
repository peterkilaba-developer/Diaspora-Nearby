import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:intl/intl.dart';
import '../models/election_result.dart';
import '../repository/governance_repository.dart';
import 'package:diaspora_nearby/features/dsp/services/exploration_registry.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/dsp/widgets/exploration_tracker.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';

class ElectionHistoryScreen extends ConsumerStatefulWidget {
  final String unitId;
  final String unitName;

  const ElectionHistoryScreen({
    super.key,
    required this.unitId,
    required this.unitName,
  });

  @override
  ConsumerState<ElectionHistoryScreen> createState() =>
      _ElectionHistoryScreenState();
}

class _ElectionHistoryScreenState extends ConsumerState<ElectionHistoryScreen> {
  @override
  void initState() {
    super.initState();
    _trackExploration();
  }

  Future<void> _trackExploration() async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user != null) {
      final rewarded = await ref
          .read(pointsServiceProvider)
          .trackExplorationReward(
            user.uid,
            ExplorationAction.governanceElectionHistory,
          );
      if (rewarded && mounted) {
        showExplorationRewardToast(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.unitName} History'),
        backgroundColor: AppTheme.accentDark,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<ElectionResult>>(
        future: ref
            .read(governanceRepositoryProvider)
            .getElectionHistory(widget.unitId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final history = snapshot.data ?? [];
          if (history.isEmpty) {
            return _buildEmptyState();
          }

          return ListView.builder(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.of(context).padding.bottom,
            ),
            itemCount: history.length,
            itemBuilder: (context, index) {
              final result = history[index];
              return _buildResultCard(context, result);
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.history,
            size: 64,
            color: Colors.grey.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          const Text(
            'No History Found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Governance for this unit has just begun.',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(BuildContext context, ElectionResult result) {
    final date = DateTime.fromMillisecondsSinceEpoch(result.timestamp);
    final dateStr = DateFormat('MMM dd, yyyy').format(date);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  dateStr.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.accent,
                    letterSpacing: 1.1,
                  ),
                ),
                Text(
                  '${result.totalVotes} Votes Cast',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'ELECTED SIGNERS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: result.winners
                  .map((id) => _buildSignerChip(id))
                  .toList(),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            _buildTallyPreview(result.tally),
          ],
        ),
      ),
    );
  }

  Widget _buildSignerChip(String id) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.shieldCheck, size: 14, color: AppTheme.accent),
          const SizedBox(width: 6),
          Text(
            'Leader ${id.substring(0, 6).toUpperCase()}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildTallyPreview(Map<String, int> tally) {
    // Show top 3 in the preview
    final sorted = tally.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'TOP CANDIDATES',
          style: TextStyle(fontSize: 10, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        ...sorted.take(3).map((e) {
          final total = tally.values.fold(0, (sum, v) => sum + v);
          final percent = total > 0 ? (e.value / total) : 0.0;

          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'Leader ${e.key.substring(0, 4)}...',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Expanded(
                  flex: 7,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: percent,
                      backgroundColor: Colors.grey[200],
                      color: AppTheme.accent,
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${e.value}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
