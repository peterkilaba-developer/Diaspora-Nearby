import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/trust/services/trust_service.dart';
import 'package:diaspora_nearby/features/trust/repository/trust_repository.dart';
import 'package:diaspora_nearby/features/shared/utils/app_snackbar.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/relationship_repository.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/profile/models/relationship.dart';
import 'package:diaspora_nearby/features/profile/models/relationship_request.dart';

class TrustSliderWidget extends ConsumerStatefulWidget {
  static const Set<String> familyRelationshipTypes = {
    'wife',
    'husband',
    'daughter',
    'son',
    'mother',
    'father',
    'sister',
    'brother',
    'aunt',
    'uncle',
    'nephew',
    'niece',
    'cousin',
    'relative',
  };

  static bool isFamilyRelationshipType(String? type) {
    if (type == null || type.isEmpty) return false;
    return familyRelationshipTypes.contains(type.trim().toLowerCase());
  }

  final String targetUserId;
  final String currentUserId;
  final String? displayName;
  final double? initialRating;
  final VoidCallback? onRated;

  const TrustSliderWidget({
    super.key,
    required this.targetUserId,
    required this.currentUserId,
    this.displayName,
    this.initialRating,
    this.onRated,
  });

  @override
  ConsumerState<TrustSliderWidget> createState() => _TrustSliderWidgetState();
}

class _TrustSliderWidgetState extends ConsumerState<TrustSliderWidget> {
  late double _currentValue;
  double? _previousValue;
  bool _wasFullTrust = false;
  bool _wasNoTrust = false;
  bool _isLoadingPrevious = false;
  bool _isFamilyMember = false;
  bool _isFriendMember = false;
  bool _isOwnProfileIncomplete = false;

  @override
  void initState() {
    super.initState();
    final profileRepo = ref.read(profileRepositoryProvider);
    final relRepo = ref.read(relationshipRepositoryProvider);
    final trustRepo = ref.read(trustRepositoryProvider);

    final cachedMyProfile =
        ref.read(userProfileProvider).value ??
        profileRepo.getCachedProfile(widget.currentUserId);
    if (cachedMyProfile != null && !cachedMyProfile.isComplete) {
      _isOwnProfileIncomplete = true;
    }

    final cachedRel = relRepo.getCachedRelationship(
      widget.currentUserId,
      widget.targetUserId,
    );
    if (cachedRel != null && cachedRel.status == 'active') {
      if (TrustSliderWidget.isFamilyRelationshipType(cachedRel.type)) {
        _isFamilyMember = true;
      } else {
        _isFriendMember = true;
      }
    }

    final cachedPendingSent = relRepo.getCachedPendingSentRequest(
      fromUserId: widget.currentUserId,
      toUserId: widget.targetUserId,
    );
    final cachedPendingIncoming = relRepo.getCachedPendingIncomingRequest(
      userId: widget.currentUserId,
      fromUserId: widget.targetUserId,
    );
    if (TrustSliderWidget.isFamilyRelationshipType(
          cachedPendingSent?.relationshipType,
        ) ||
        TrustSliderWidget.isFamilyRelationshipType(
          cachedPendingIncoming?.relationshipType,
        )) {
      _isFamilyMember = true;
    } else if (cachedPendingSent != null || cachedPendingIncoming != null) {
      _isFriendMember = true;
    }

    final cachedRating =
        widget.initialRating ??
        trustRepo.getCachedRating(
          fromUserId: widget.currentUserId,
          toUserId: widget.targetUserId,
        );
    final initialScore = cachedRating ?? 0.0;
    _currentValue = _isFriendMember && initialScore > 0
        ? initialScore.clamp(11.0, 90.0)
        : initialScore;
    _previousValue = initialScore;
    _wasFullTrust = initialScore > 90;
    _wasNoTrust = initialScore >= 1 && initialScore <= 10;

    _loadPreviousRating();
  }

  Future<void> _loadPreviousRating() async {
    try {
      final profileRepo = ref.read(profileRepositoryProvider);
      final relRepo = ref.read(relationshipRepositoryProvider);
      final trustRepo = ref.read(trustRepositoryProvider);

      final results = await Future.wait<dynamic>([
        profileRepo.getUserProfile(widget.currentUserId),
        relRepo.getRelationship(
          userId: widget.currentUserId,
          relatedUserId: widget.targetUserId,
        ),
        relRepo.getPendingSentRequest(
          fromUserId: widget.currentUserId,
          toUserId: widget.targetUserId,
        ),
        relRepo.getPendingIncomingRequest(
          userId: widget.currentUserId,
          fromUserId: widget.targetUserId,
        ),
        trustRepo.getRating(
          fromUserId: widget.currentUserId,
          toUserId: widget.targetUserId,
        ),
      ]);

      if (!mounted) return;

      final myProfile = results[0] as ProfileData?;
      final existingRel = results[1] as Relationship?;
      final pendingSent = results[2] as RelationshipRequest?;
      final pendingIncoming = results[3] as RelationshipRequest?;
      final existingScore = results[4] as double?;

      bool isFamily = false;
      bool isFriend = false;

      if (existingRel != null && existingRel.status == 'active') {
        if (TrustSliderWidget.isFamilyRelationshipType(existingRel.type)) {
          isFamily = true;
        } else {
          isFriend = true;
        }
      }

      if (TrustSliderWidget.isFamilyRelationshipType(
            pendingSent?.relationshipType,
          ) ||
          TrustSliderWidget.isFamilyRelationshipType(
            pendingIncoming?.relationshipType,
          )) {
        isFamily = true;
      } else if (pendingSent != null || pendingIncoming != null) {
        isFriend = true;
      }

      setState(() {
        _isOwnProfileIncomplete = myProfile == null || !myProfile.isComplete;
        _isFamilyMember = isFamily;
        _isFriendMember = isFriend;
        if (existingScore != null) {
          final clampedScore = isFriend && existingScore > 0
              ? existingScore.clamp(11.0, 90.0)
              : existingScore;
          // Only overwrite _currentValue if the user hasn't actively dragged it
          if (_currentValue == (_previousValue ?? 0.0)) {
            _currentValue = clampedScore;
          }
          _previousValue = existingScore;
          _wasFullTrust = existingScore > 90;
          _wasNoTrust = existingScore >= 1 && existingScore <= 10;
        }
        _isLoadingPrevious = false;
      });
    } catch (e) {
      debugPrint('Error loading previous rating: $e');
      if (mounted) {
        setState(() => _isLoadingPrevious = false);
      }
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

  Future<void> _submitRating({bool isStakeConfirm = false}) async {
    final profileRepo = ref.read(profileRepositoryProvider);
    final myProfile =
        ref.read(userProfileProvider).value ??
        profileRepo.getCachedProfile(widget.currentUserId) ??
        await profileRepo.getUserProfile(widget.currentUserId);

    if (myProfile == null || !myProfile.isComplete) {
      if (mounted) {
        setState(() => _currentValue = _previousValue ?? 0.0);
        await showDialog(
          context: context,
          builder: (ctx) => BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AlertDialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 24,
              ),
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
        setState(() => _currentValue = _previousValue ?? 50.0);
        return;
      }
    }

    final prevVal = _previousValue;
    final prevFull = _wasFullTrust;
    final prevNo = _wasNoTrust;
    final submittedScore = _currentValue;

    setState(() {
      _previousValue = submittedScore;
      _wasFullTrust = _isFullTrust;
      _wasNoTrust = _isNoTrust;
    });

    widget.onRated?.call();

    if (mounted) {
      if (isStakeConfirm) {
        AppSnackbar.success(
          context,
          _isNoTrust
              ? 'No trust staked! 1,000 DSP locked.'
              : 'Full trust staked! 1,000 DSP locked.',
        );
      } else {
        AppSnackbar.success(context, 'Trust rating updated');
      }
    }

    unawaited(
      ref
          .read(trustServiceProvider)
          .rateUser(
            fromUserId: widget.currentUserId,
            toUserId: widget.targetUserId,
            score: submittedScore,
          )
          .catchError((Object e) {
            if (mounted) {
              setState(() {
                _previousValue = prevVal;
                _wasFullTrust = prevFull;
                _wasNoTrust = prevNo;
              });
              AppSnackbar.error(context, 'Error: $e');
            }
          }),
    );
  }

  Future<bool> _showExitConfirmation(bool wasFullTrustLocal) async {
    final title = wasFullTrustLocal ? 'Remove Full Trust' : 'Remove No Trust';
    final keepText = wasFullTrustLocal ? 'Keep Full Trust' : 'Keep No Trust';
    return await showDialog<bool>(
          context: context,
          builder: (context) => BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AlertDialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 24,
              ),
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
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.currentUserId.isEmpty ||
        widget.targetUserId.isEmpty ||
        widget.currentUserId == widget.targetUserId) {
      return const SizedBox.shrink();
    }

    final relationshipsAsync = ref.watch(
      userRelationshipsProvider(widget.currentUserId),
    );
    final trustAsync = ref.watch(userTrustProvider(widget.currentUserId));

    final isFamilyFromRelationships =
        relationshipsAsync.value?.any(
          (r) =>
              r.id == widget.targetUserId &&
              r.status == 'active' &&
              TrustSliderWidget.isFamilyRelationshipType(r.type),
        ) ??
        false;

    final isFamilyFromTrust = TrustSliderWidget.isFamilyRelationshipType(
      trustAsync.value?.relationshipTypes[widget.targetUserId],
    );

    if (_isFamilyMember || isFamilyFromRelationships || isFamilyFromTrust) {
      return const SizedBox.shrink();
    }

    final isFriendFromRelationships =
        relationshipsAsync.value?.any(
          (r) =>
              r.id == widget.targetUserId &&
              r.status == 'active' &&
              !TrustSliderWidget.isFamilyRelationshipType(r.type),
        ) ??
        false;

    final relTypeFromTrust =
        trustAsync.value?.relationshipTypes[widget.targetUserId];
    final isFriendFromTrust =
        relTypeFromTrust != null &&
        relTypeFromTrust.isNotEmpty &&
        !TrustSliderWidget.isFamilyRelationshipType(relTypeFromTrust);

    final isFriend =
        _isFriendMember || isFriendFromRelationships || isFriendFromTrust;

    final myProfileAsync = ref.watch(userProfileProvider);
    final isProfileIncomplete =
        (myProfileAsync.value != null && !myProfileAsync.value!.isComplete) ||
        (myProfileAsync.value == null && _isOwnProfileIncomplete);

    if (_isLoadingPrevious) {
      return const SizedBox.shrink();
    }

    final effectiveValue = isFriend && _currentValue > 0
        ? _currentValue.clamp(11.0, 90.0)
        : _currentValue;
    final color = _getColor(context, effectiveValue);
    final isStaked = !isFriend && _isStaked;
    final canSubmit = !isProfileIncomplete && _canSubmit;
    final isAtZero = effectiveValue == 0;
    final firstName = widget.displayName?.split(' ').first;
    final String buttonText;
    final wasStakedLocal = _wasFullTrust || _wasNoTrust;

    if (isProfileIncomplete) {
      buttonText = 'Complete your profile to vouch';
    } else if (isAtZero && firstName != null) {
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
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
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
                        isFriend && effectiveValue > 0
                            ? 'Friend · Standard Trust (11–90)'
                            : _getLabel(effectiveValue),
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
                value: effectiveValue,
                min: 0.0,
                max: isFriend ? 90.0 : 100.0,
                divisions: isFriend ? 90 : 100,
                label: effectiveValue.round().toString(),
                onChanged: isProfileIncomplete
                    ? null
                    : (value) {
                        setState(() {
                          if (isFriend && value > 0 && value < 11) {
                            _currentValue = 11.0;
                          } else if (isFriend && value > 90) {
                            _currentValue = 90.0;
                          } else {
                            _currentValue = value;
                          }
                        });
                      },
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${effectiveValue.round()}%',
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
