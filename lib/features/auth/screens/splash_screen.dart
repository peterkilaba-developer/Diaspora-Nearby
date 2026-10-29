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
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAuth());
  }

  void _checkAuth() {
    if (!mounted) return;
    final authState = ref.read(authStateProvider);
    final currentUser =
        authState.value ?? ref.read(authRepositoryProvider).currentUser;

    if (currentUser != null) {
      context.go('/nearby');
    } else if (!authState.isLoading) {
      context.go('/auth/phone');
    }
  }

  @override
  Widget build(BuildContext context) {
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
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
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
