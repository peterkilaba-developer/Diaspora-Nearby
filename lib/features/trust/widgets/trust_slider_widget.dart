import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/trust/services/trust_service.dart';
import 'package:diaspora_nearby/features/trust/repository/trust_repository.dart';
import 'package:diaspora_nearby/features/shared/utils/app_snackbar.dart';
import 'package:diaspora_nearby/features/shared/utils/loading_mixin.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';

class TrustSliderWidget extends ConsumerStatefulWidget {
  final String targetUserId;
  final String currentUserId;
  final String? displayName;
  final double? initialRating;

  const TrustSliderWidget({
    super.key,
    required this.targetUserId,
    required this.currentUserId,
    this.displayName,
    this.initialRating,
  });

  @override
  ConsumerState<TrustSliderWidget> createState() => _TrustSliderWidgetState();
}

class _TrustSliderWidgetState extends ConsumerState<TrustSliderWidget>
    with ConsumerLoadingMixin {
  late double _currentValue;
  double? _previousValue;
  bool _wasFullTrust = false;
  bool _wasNoTrust = false;
  bool _isLoadingPrevious = true;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.initialRating ?? 0.0;
    _previousValue = _currentValue;
    _wasFullTrust = _currentValue > 90;
    _loadPreviousRating();
  }

  Future<void> _loadPreviousRating() async {
    try {
      final existingScore = await ref
          .read(trustRepositoryProvider)
          .getRating(
            fromUserId: widget.currentUserId,
            toUserId: widget.targetUserId,
          );
      if (existingScore != null && mounted) {
        setState(() {
          _currentValue = existingScore;
          _previousValue = existingScore;
          _wasFullTrust = existingScore > 90;
          _wasNoTrust = existingScore >= 1 && existingScore <= 10;
          _isLoadingPrevious = false;
        });
        return;
      }
    } catch (e) {
      debugPrint('Error loading previous rating: $e');
    }
    if (mounted) {
      setState(() => _isLoadingPrevious = false);
    }
  }

  Color _getColor(BuildContext context, double value) {
    if (value == 0) return Theme.of(context).colorScheme.onSurface;
    if (value >= 1 && value <= 10) return AppTheme.error;
    if (value > 90) return AppTheme.accent;
    return Colors.amber;
  }

  String _getLabel(double value) {
    if (value == 0) return 'Not Rated';
    if (value >= 1 && value <= 10) return 'No Trust (Staked)';
    if (value > 90) return 'Full Trust (Staked)';
    return 'Standard Trust (Free)';
  }

  bool get _isFullTrust => _currentValue > 90;
  bool get _isNoTrust => _currentValue >= 1 && _currentValue <= 10;
  bool get _isStaked => _isFullTrust || _isNoTrust;

  /// Decile band index: [1-10]=0, [11-20]=1, ..., [91-100]=9. Value 0 = -1 (no vote).
  int _getDecile(double value) {
    if (value <= 0) return -1;
    return ((value - 1) / 10).floor();
  }

  /// Button is enabled only when the slider is in a DIFFERENT decile band
  /// from the previously stored rating. Prevents duplicate same-range submissions.
  bool get _canSubmit {
    if (_currentValue == 0) return false;
    // First-time vote — any value > 0 is fine
    if (_previousValue == null || _previousValue == 0) return true;
    return _getDecile(_currentValue) != _getDecile(_previousValue!);
  }

  Future<void> _submitRating({bool isStakeConfirm = false}) => withLoading(
    () async {
      // Gate: must have a fully completed profile to vouch/verify
      final myProfile = await ref
          .read(profileRepositoryProvider)
          .getUserProfile(widget.currentUserId);
      if (myProfile == null || !myProfile.isComplete) {
        if (mounted) {
          setState(() => _currentValue = _previousValue ?? 0.0);
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              icon: Icon(
                LucideIcons.shieldAlert,
                size: 40,
                color: Theme.of(
                  ctx,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              title: const Text('Profile Incomplete'),
              content: const Text(
                'You must fully complete your profile before you can vouch for or verify other community members.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return;
      }

      final isNowStaked = _isStaked;
      final wasStakedLocal = _wasFullTrust || _wasNoTrust;

      // If transitioning to a staked tier but NOT from the stake confirm button, just wait
      if (isNowStaked && !wasStakedLocal && !isStakeConfirm) {
        return;
      }

      // Show exit confirmation if leaving a staked tier
      if (!isNowStaked && wasStakedLocal) {
        final confirmed = await _showExitConfirmation(_wasFullTrust);
        if (!confirmed) {
          // Revert slider to previous value
          setState(() => _currentValue = _previousValue ?? 50.0);
          return;
        }
      }

      await ref
          .read(trustServiceProvider)
          .rateUser(
            fromUserId: widget.currentUserId,
            toUserId: widget.targetUserId,
            score: _currentValue,
          );

      _previousValue = _currentValue;
      _wasFullTrust = _isFullTrust;
      _wasNoTrust = _isNoTrust;

      if (mounted) {
        if (isStakeConfirm) {
          AppSnackbar.success(context, 'Full trust staked! 1,000 DSP locked.');
        } else {
          AppSnackbar.success(context, 'Trust rating updated');
        }
      }
    },
    onError: (e, _) {
      if (mounted) AppSnackbar.error(context, 'Error: $e');
    },
  );

  Future<bool> _showExitConfirmation(bool wasFullTrustLocal) async {
    final title = wasFullTrustLocal ? 'Remove Full Trust' : 'Remove No Trust';
    final keepText = wasFullTrustLocal ? 'Keep Full Trust' : 'Keep No Trust';
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(LucideIcons.shieldOff, color: Colors.amber.shade700),
                const SizedBox(width: 8),
                Text(title),
              ],
            ),
            content: const Text(
              'Your remaining staked DSP will be refunded to your balance.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(keepText),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.amber.shade700,
                ),
                child: const Text('Remove & Refund'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingPrevious) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.pageHorizontalPadding * 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Community Trust',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Container(
                    width: 80,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const LinearProgressIndicator(minHeight: 2),
              const SizedBox(height: 12),
            ],
          ),
        ),
      );
    }

    final color = _getColor(context, _currentValue);
    final isStaked = _isStaked;
    final canSubmit = _canSubmit;
    final isAtZero = _currentValue == 0;
    final firstName = widget.displayName?.split(' ').first;
    final String buttonText;
    final wasStakedLocal = _wasFullTrust || _wasNoTrust;

    if (isAtZero && firstName != null) {
      buttonText = 'Vouch for $firstName Trustworthy';
    } else if (isAtZero) {
      buttonText = 'Vouch Trustworthy';
    } else if (!canSubmit) {
      buttonText = 'Slide to a different range to update';
    } else if (isStaked && !wasStakedLocal) {
      buttonText = _isNoTrust
          ? 'Distrust & Stake 1,000 DSP'
          : 'Trust & Stake 1,000 DSP';
    } else {
      buttonText = 'Update Trust';
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.pageHorizontalPadding * 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Community Trust',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isStaked
                        ? color.withValues(alpha: 0.15)
                        : color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: isStaked
                        ? Border.all(color: color, width: 1.5)
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isStaked) ...[
                        Icon(
                          _isNoTrust
                              ? LucideIcons.shieldAlert
                              : LucideIcons.shieldCheck,
                          size: 14,
                          color: color,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        _getLabel(_currentValue),
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: color,
                thumbColor: color,
                inactiveTrackColor: color.withValues(alpha: 0.2),
                overlayColor: color.withValues(alpha: 0.1),
                trackHeight: 8.0,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 12.0,
                ),
              ),
              child: Slider(
                value: _currentValue,
                min: 0.0,
                max: 100.0,
                divisions: 100,
                label: _currentValue.round().toString(),
                onChanged: (value) {
                  setState(() {
                    _currentValue = value;
                  });
                },
              ),
            ),
            if (isLoading)
              const Center(child: LinearProgressIndicator(minHeight: 2))
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_currentValue.round()}%',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  if (wasStakedLocal && isStaked)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            LucideIcons.coins,
                            size: 14,
                            color: Color(0xFF7A9E7E),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '1,000 DSP staked',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.6),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: canSubmit
                          ? () => _submitRating(
                              isStakeConfirm: isStaked && !wasStakedLocal,
                            )
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: canSubmit
                            ? color
                            : Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.12),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        buttonText,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: canSubmit ? 14 : 12,
                          color: canSubmit
                              ? null
                              : Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.38),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
