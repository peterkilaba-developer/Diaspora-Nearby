import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/dsp/widgets/country_leaderboard_item.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import 'package:diaspora_nearby/features/dsp/services/exploration_registry.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/dsp/widgets/exploration_tracker.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';

class CountriesLeaderboardScreen extends ConsumerStatefulWidget {
  const CountriesLeaderboardScreen({super.key});

  @override
  ConsumerState<CountriesLeaderboardScreen> createState() =>
      _CountriesLeaderboardScreenState();
}

class _CountriesLeaderboardScreenState
    extends ConsumerState<CountriesLeaderboardScreen> {
  static List<Map<String, String>>? _cachedCountries;

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
          .trackExplorationReward(user.uid, ExplorationAction.dspLeaderboard);
      if (rewarded && mounted) {
        showExplorationRewardToast(context);
      }
    }
  }

  Widget _buildList(BuildContext context, List<Map<String, String>> countries) {
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        8,
        16,
        8,
        16 + MediaQuery.of(context).padding.bottom,
      ),
      itemCount: countries.length,
      separatorBuilder: (ctx, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        return CountryLeaderboardItem(country: countries[index]);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final leaderboardAsync = ref.watch(countryLeaderboardProvider);
    if (leaderboardAsync.hasValue) {
      _cachedCountries = leaderboardAsync.value;
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Country Epoch Leaderboard',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        centerTitle: true,
      ),
      body: Container(
        decoration: AppTheme.pageDecoration(context),
        child: leaderboardAsync.when(
          data: (countries) => _buildList(context, countries),
          loading: () => _cachedCountries != null
              ? _buildList(context, _cachedCountries!)
              : const Center(child: CircularProgressIndicator()),
          error: (err, stack) => _cachedCountries != null
              ? _buildList(context, _cachedCountries!)
              : Center(child: Text('Error: $err')),
        ),
      ),
    );
  }
}
