import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    // Artificial delay for splash effect
    await Future.delayed(const Duration(seconds: 2));

    // Auth state is handled by the router redirect usually, but for explicit splash logic:
    final authState = ref.read(authStateProvider);

    authState.when(
      data: (user) {
        if (user != null) {
          if (mounted) context.go('/nearby');
        } else {
          if (mounted) context.go('/auth/phone');
        }
      },
      loading: () {
        // Wait and retry or let stream listener handle it.
        // Better pattern: Listen to the provider in build or use a listener
      },
      error: (err, stack) {
        if (mounted) context.go('/auth/phone');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Listener to react to state changes if the initial check was loading
    ref.listen(authStateProvider, (prev, next) {
      next.whenData((user) {
        if (user != null) {
          context.go('/nearby');
        } else {
          context.go('/auth/phone');
        }
      });
    });

    return Scaffold(
      backgroundColor: Colors.white, // Or brand color
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo
            Image.asset(
              'assets/icons/logo-transparent-128.png',
              width: 150,
              height: 150,
              errorBuilder: (c, o, s) =>
                  const Icon(Icons.public, size: 100, color: Colors.blue),
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
