import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/core/data/countries.dart' as data;
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/dsp/widgets/country_leaderboard_item.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import 'package:diaspora_nearby/features/dsp/services/epoch_service.dart'; // [FIX] Added import
import 'package:diaspora_nearby/features/community/repository/community_repository.dart'; // [FIX] Added import
import 'package:diaspora_nearby/features/community/models/community_data.dart'; // [FIX] Added import

class CountriesLeaderboardScreen extends ConsumerWidget {
  const CountriesLeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {

    final leaderboardAsync = ref.watch(countryLeaderboardProvider);
    
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Country Epoch DSP Leaderboard',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        centerTitle: true,
      ),
      body: leaderboardAsync.when(
        data: (countries) => ListView.separated(
          padding: EdgeInsets.fromLTRB(
            8, 
            16, 
            8, 
            16 + MediaQuery.of(context).padding.bottom
          ),
          itemCount: countries.length,
          separatorBuilder: (ctx, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            return CountryLeaderboardItem(
              country: countries[index],
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }
}
