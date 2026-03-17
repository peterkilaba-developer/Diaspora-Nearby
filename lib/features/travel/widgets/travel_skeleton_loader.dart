import 'package:flutter/material.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

/// Shimmer skeleton loader for travel listing cards.
/// Shows animated placeholder cards while data is loading.
class TravelSkeletonLoader extends StatefulWidget {
  final int itemCount;
  final IconData icon;
  final String label;

  const TravelSkeletonLoader({
    super.key,
    this.itemCount = 5,
    this.icon = Icons.hourglass_empty,
    this.label = 'Loading...',
  });

  @override
  State<TravelSkeletonLoader> createState() => _TravelSkeletonLoaderState();
}

class _TravelSkeletonLoaderState extends State<TravelSkeletonLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      children: [
        // Loading label with icon
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.accent.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
        // Skeleton cards
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: widget.itemCount,
            itemBuilder: (context, index) => AnimatedBuilder(
              animation: _shimmerController,
              builder: (context, child) => _SkeletonCard(
                shimmerProgress: _shimmerController.value,
                isDark: isDark,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  final double shimmerProgress;
  final bool isDark;

  const _SkeletonCard({required this.shimmerProgress, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: icon placeholder + title lines
          Row(
            children: [
              _shimmerBox(40, 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _shimmerBox(double.infinity, 14, borderRadius: 6),
                    const SizedBox(height: 8),
                    _shimmerBox(160, 10, borderRadius: 4),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Middle: image placeholder
          _shimmerBox(double.infinity, 120, borderRadius: 12),

          const SizedBox(height: 12),

          // Bottom: price + location
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _shimmerBox(80, 16, borderRadius: 6),
              _shimmerBox(120, 12, borderRadius: 4),
            ],
          ),
        ],
      ),
    );
  }

  Widget _shimmerBox(double width, double height, {double borderRadius = 8}) {
    final baseColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.06);
    final highlightColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.10);

    // Calculate gradient position based on shimmer progress
    final gradientStart = shimmerProgress - 0.3;
    final gradientEnd = shimmerProgress + 0.3;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [baseColor, highlightColor, baseColor],
          stops: [
            gradientStart.clamp(0.0, 1.0),
            shimmerProgress.clamp(0.0, 1.0),
            gradientEnd.clamp(0.0, 1.0),
          ],
        ),
      ),
    );
  }
}

/// A compact skeleton for hotel/flight cards that auto-load from API
class TravelApiSkeletonLoader extends StatefulWidget {
  final int itemCount;
  final String label;

  const TravelApiSkeletonLoader({
    super.key,
    this.itemCount = 4,
    this.label = 'Searching nearby...',
  });

  @override
  State<TravelApiSkeletonLoader> createState() =>
      _TravelApiSkeletonLoaderState();
}

class _TravelApiSkeletonLoaderState extends State<TravelApiSkeletonLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      children: [
        // Loading header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppTheme.accent,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
        // Skeleton cards
        Expanded(
          child: ListView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: widget.itemCount,
            itemBuilder: (context, index) => AnimatedBuilder(
              animation: _controller,
              builder: (context, child) => _ApiSkeletonCard(
                shimmerProgress: _controller.value,
                isDark: isDark,
                index: index,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ApiSkeletonCard extends StatelessWidget {
  final double shimmerProgress;
  final bool isDark;
  final int index;

  const _ApiSkeletonCard({
    required this.shimmerProgress,
    required this.isDark,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    // Stagger the shimmer slightly by card index
    final adjustedProgress = (shimmerProgress + index * 0.15) % 1.0;

    return Opacity(
      opacity: 0.7 + (0.3 * (1 - index / 5).clamp(0.0, 1.0)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: AppTheme.cardDecoration(context),
        child: Row(
          children: [
            // Image placeholder
            _box(72, 72, adjustedProgress, borderRadius: 10),
            const SizedBox(width: 12),
            // Text Lines
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _box(double.infinity, 13, adjustedProgress, borderRadius: 5),
                  const SizedBox(height: 8),
                  _box(140, 10, adjustedProgress, borderRadius: 4),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _box(60, 16, adjustedProgress, borderRadius: 6),
                      const Spacer(),
                      _box(50, 10, adjustedProgress, borderRadius: 4),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _box(double w, double h, double progress, {double borderRadius = 8}) {
    final baseColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.06);
    final highlightColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.10);

    final start = (progress - 0.3).clamp(0.0, 1.0);
    final mid = progress.clamp(0.0, 1.0);
    final end = (progress + 0.3).clamp(0.0, 1.0);

    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          colors: [baseColor, highlightColor, baseColor],
          stops: [start, mid, end],
        ),
      ),
    );
  }
}
