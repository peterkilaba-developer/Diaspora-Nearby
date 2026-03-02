import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/dsp/repository/interest_repository.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/dsp/services/exploration_registry.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/dsp/widgets/exploration_tracker.dart';

class RemittancesScreen extends ConsumerStatefulWidget {
  const RemittancesScreen({super.key});

  @override
  ConsumerState<RemittancesScreen> createState() => _RemittancesScreenState();
}

class _RemittancesScreenState extends ConsumerState<RemittancesScreen> {
  bool _isLoading = false;
  bool _hasRegistered = false;

  @override
  void initState() {
    super.initState();
    _checkStatus();
    _trackExploration();
  }

  Future<void> _trackExploration() async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user != null) {
      final rewarded = await ref
          .read(pointsServiceProvider)
          .trackExplorationReward(user.uid, ExplorationAction.dspRemittances);
      if (rewarded && mounted) {
        showExplorationRewardToast(context);
      }
    }
  }

  Future<void> _checkStatus() async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null) return;

    final hasRegistered = await ref
        .read(interestRepositoryProvider)
        .checkInterest(userId: user.uid, service: 'remittances');

    if (mounted) {
      setState(() {
        _hasRegistered = hasRegistered;
      });
    }
  }

  Future<void> _registerInterest() async {
    final user = ref.read(authRepositoryProvider).currentUser;
    final profile = ref.read(userProfileProvider).value;

    if (user == null || profile == null) return;

    setState(() => _isLoading = true);

    try {
      await ref
          .read(interestRepositoryProvider)
          .registerInterest(
            userId: user.uid,
            service: 'remittances',
            country: profile.homeCountry ?? 'Unknown',
          );

      if (mounted) {
        setState(() {
          _hasRegistered = true;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You have been added to the notification list!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).value;
    final country = profile?.homeCountry ?? 'Your Country';

    return Scaffold(
      appBar: AppBar(title: const Text('International Remittances')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.pageHorizontalPadding,
            vertical: AppTheme.cardPadding,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(LucideIcons.send, size: 80, color: AppTheme.accent),
              const SizedBox(height: 32),
              const Text(
                'Send Money Home',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'Coming Soon',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.accent,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Send money to your home country with near-zero fees using Diaspora (\$DIASPORA). Fast, secure, and built for the community.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey, height: 1.5),
              ),
              const SizedBox(height: 40),

              if (_hasRegistered)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: AppTheme.accent),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        LucideIcons.check,
                        color: AppTheme.accent,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'You are on the list for $country',
                        style: const TextStyle(
                          color: AppTheme.accent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isLoading ? null : _registerInterest,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 16,
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            'Notify Me When Available for $country Community',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
