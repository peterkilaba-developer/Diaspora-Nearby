import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import '../models/governance_unit.dart';
import '../repository/governance_repository.dart';
import 'leader_selection_screen.dart';
import 'package:diaspora_nearby/features/dsp/services/exploration_registry.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/dsp/widgets/exploration_tracker.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';

class ActiveElectionsScreen extends ConsumerStatefulWidget {
  const ActiveElectionsScreen({super.key});

  @override
  ConsumerState<ActiveElectionsScreen> createState() =>
      _ActiveElectionsScreenState();
}

class _ActiveElectionsScreenState extends ConsumerState<ActiveElectionsScreen> {
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
            ExplorationAction.governanceActiveElections,
          );
      if (rewarded && mounted) {
        showExplorationRewardToast(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(governanceRepositoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Active Leader Elections'),
        backgroundColor: AppTheme.accentDark,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<GovernanceUnit>>(
        initialData: repo.getCachedActiveElections(),
        stream: repo.watchActiveElections(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              snapshot.data == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final activeUnits = snapshot.data ?? [];
          if (activeUnits.isEmpty) {
            return _buildEmptyState();
          }

          return ListView.builder(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.of(context).padding.bottom,
            ),
            itemCount: activeUnits.length,
            itemBuilder: (context, index) {
              final unit = activeUnits[index];
              return _buildElectionCard(context, unit);
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
            LucideIcons.vote,
            size: 64,
            color: Colors.grey.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          const Text(
            'No Active Elections',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'The Diaspora is currently in a steady state.',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildElectionCard(BuildContext context, GovernanceUnit unit) {
    final timeLeft = unit.electionEndTime != null
        ? DateTime.fromMillisecondsSinceEpoch(
            unit.electionEndTime!,
          ).difference(DateTime.now())
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => LeaderSelectionScreen(unitId: unit.id),
          ),
        ),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _getUnitIcon(unit.type),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          unit.name.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.accent,
                            letterSpacing: 1.1,
                          ),
                        ),
                        Text(
                          '${unit.type.name.toUpperCase()} LEADER ELECTION',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(LucideIcons.chevronRight, color: Colors.grey),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TIME REMAINING',
                        style: TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                      Text(
                        _formatTimeLeft(timeLeft),
                        style: TextStyle(
                          color: (timeLeft?.inHours ?? 24) < 24
                              ? Colors.red
                              : Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'PRECINCTS',
                        style: TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                      Text(
                        unit.id.startsWith('country_')
                            ? 'National'
                            : 'Sub-National',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _getUnitIcon(GovernanceType type) {
    IconData icon;
    switch (type) {
      case GovernanceType.global:
        icon = LucideIcons.globe;
        break;
      case GovernanceType.continent:
        icon = LucideIcons.map;
        break;
      case GovernanceType.country:
        icon = LucideIcons.flag;
        break;
      case GovernanceType.state:
        icon = LucideIcons.mapPin;
        break;
      case GovernanceType.local:
        icon = LucideIcons.home;
        break;
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: AppTheme.accent, size: 24),
    );
  }

  String _formatTimeLeft(Duration? duration) {
    if (duration == null) return 'Ending soon';
    if (duration.isNegative) return 'Voting closed';

    if (duration.inDays > 0) {
      return '${duration.inDays}d ${duration.inHours % 24}h remaining';
    }
    return '${duration.inHours}h ${duration.inMinutes % 60}m remaining';
  }
}
