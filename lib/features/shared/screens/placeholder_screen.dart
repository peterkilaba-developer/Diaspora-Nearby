import 'package:flutter/material.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

class PlaceholderScreen extends StatelessWidget {
  final String title;
  final String? message;
  final IconData? icon;

  const PlaceholderScreen({
    super.key,
    required this.title,
    this.message,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.pageHorizontalPadding),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
              ],
              Text(
                message ?? title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
