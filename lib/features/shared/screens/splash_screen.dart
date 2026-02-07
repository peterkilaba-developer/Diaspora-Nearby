import 'package:flutter/material.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Simple splash - matches native Android splash
    // Uses white background to match Android's launch_background.xml
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo (no color filter needed - logo is already sage green)
            Image.asset(
              'assets/icons/logo-original.png',
              width: 128,
              height: 128,
            ),
            const SizedBox(height: 24),
            const Text(
              'Diaspora Nearby',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: AppTheme.accent,
              ),
            ),
            const SizedBox(height: 32),
            const CircularProgressIndicator(color: AppTheme.accent),
          ],
        ),
      ),
    );
  }
}
