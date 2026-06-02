import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/core/data/countries.dart';

class BilateralFlagAvatar extends StatelessWidget {
  final String? homeCountryCode;
  final String? hostCountryCode;
  final double size;

  const BilateralFlagAvatar({
    super.key,
    required this.homeCountryCode,
    required this.hostCountryCode,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    final homeFlag = homeCountryCode == null
        ? null
        : getCountryByCode(homeCountryCode!)?.flag;
    final hostFlag = hostCountryCode == null
        ? null
        : getCountryByCode(hostCountryCode!)?.flag;

    if (homeFlag == null || hostFlag == null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(
          LucideIcons.landmark,
          size: size * 0.48,
          color: Theme.of(context).colorScheme.primary,
        ),
      );
    }

    return Semantics(
      label: '$homeCountryCode to $hostCountryCode chamber',
      child: ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipPath(
                clipper: const _FlagHalfClipper(left: true),
                child: Center(
                  child: Text(homeFlag, style: TextStyle(fontSize: size * 0.8)),
                ),
              ),
              ClipPath(
                clipper: const _FlagHalfClipper(left: false),
                child: Center(
                  child: Text(hostFlag, style: TextStyle(fontSize: size * 0.8)),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.45),
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

class _FlagHalfClipper extends CustomClipper<Path> {
  final bool left;

  const _FlagHalfClipper({required this.left});

  @override
  Path getClip(Size size) {
    return Path()..addRect(
      Rect.fromLTWH(left ? 0 : size.width / 2, 0, size.width / 2, size.height),
    );
  }

  @override
  bool shouldReclip(covariant _FlagHalfClipper oldClipper) {
    return oldClipper.left != left;
  }
}
