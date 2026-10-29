import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/dsp/repository/interest_repository.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/dsp/services/exploration_registry.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/dsp/widgets/exploration_tracker.dart';

class AirlinePortalScreen extends ConsumerStatefulWidget {
  const AirlinePortalScreen({super.key});

  @override
  ConsumerState<AirlinePortalScreen> createState() =>
      _AirlinePortalScreenState();
}

class _AirlinePortalScreenState extends ConsumerState<AirlinePortalScreen> {
  static final Set<String> _registeredUsers = {};
  bool _hasRegistered = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user != null && _registeredUsers.contains(user.uid)) {
      _hasRegistered = true;
    }
    unawaited(_checkStatus());
    unawaited(_trackExploration());
  }

  Future<void> _trackExploration() async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user != null) {
      final rewarded = await ref
          .read(pointsServiceProvider)
          .trackExplorationReward(user.uid, ExplorationAction.dspAirlinePortal);
      if (rewarded && mounted) {
        showExplorationRewardToast(context);
      }
    }
  }

  Future<void> _checkStatus() async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('dn_interest_airline_${user.uid}') == true) {
        _registeredUsers.add(user.uid);
        if (mounted && !_hasRegistered) {
          setState(() => _hasRegistered = true);
        }
      }
    } catch (_) {}

    final hasRegistered = await ref
        .read(interestRepositoryProvider)
        .checkInterest(userId: user.uid, service: 'airline');

    if (hasRegistered) {
      _registeredUsers.add(user.uid);
      unawaited(
        SharedPreferences.getInstance().then(
          (p) => p.setBool('dn_interest_airline_${user.uid}', true),
        ),
      );
    }

    if (mounted && _hasRegistered != hasRegistered) {
      setState(() {
        _hasRegistered = hasRegistered;
      });
    }
  }

  Future<void> _registerInterest() async {
    final user = ref.read(authRepositoryProvider).currentUser;
    final profile = ref.read(userProfileProvider).value;

    if (user == null || profile == null) return;

    // 0-Latency optimistic update
    _registeredUsers.add(user.uid);
    setState(() {
      _hasRegistered = true;
    });
    showExplorationRewardToast(
      context,
      message: 'Notification list updated',
      points: 100,
    );
    unawaited(
      SharedPreferences.getInstance().then(
        (p) => p.setBool('dn_interest_airline_${user.uid}', true),
      ),
    );

    try {
      await ref
          .read(interestRepositoryProvider)
          .registerInterest(
            userId: user.uid,
            service: 'airline',
            country: profile.homeCountry ?? 'Unknown',
          );
    } catch (e) {
      _registeredUsers.remove(user.uid);
      if (mounted) {
        setState(() => _hasRegistered = false);
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
      appBar: AppBar(title: const Text('International Air Flight Portal')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.pageHorizontalPadding,
            vertical: AppTheme.cardPadding,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(LucideIcons.plane, size: 80, color: AppTheme.accent),
              const SizedBox(height: 32),
              const Text(
                'Fly For Less',
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
                'Book discounted international flights using Diaspora (\$DIASPORA). Exclusive deals for diaspora members returning home.',
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
                    color: AppTheme.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(30),
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
                    onPressed: _registerInterest,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 16,
                      ),
                    ),
                    child: Text(
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
