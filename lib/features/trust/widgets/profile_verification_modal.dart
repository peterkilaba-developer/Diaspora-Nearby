import 'dart:async';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/shared/models/location.dart';
import 'package:diaspora_nearby/features/trust/services/trust_service.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/trust/widgets/verification_alert_modal.dart';
import 'package:diaspora_nearby/features/trust/widgets/trust_slider_widget.dart';

class ProfileVerificationModal extends ConsumerStatefulWidget {
  final ProfileData targetUser;
  final String currentUserId;

  const ProfileVerificationModal({
    super.key,
    required this.targetUser,
    required this.currentUserId,
  });

  @override
  ConsumerState<ProfileVerificationModal> createState() =>
      _ProfileVerificationModalState();
}

class _ProfileVerificationModalState
    extends ConsumerState<ProfileVerificationModal> {
  // Field States: null = neutral, true = verified (green), false = incorrect (red)
  final Map<String, bool?> _fieldVerifications = {};
  final Map<String, String> _fieldValues =
      {}; // Stores actual values for display
  Set<String> _verifiedFields = {}; // Fields already verified by community
  bool _isLoadingEligibility = false;

  @override
  void initState() {
    super.initState();
    _initializeFields();

    final service = ref.read(trustServiceProvider);
    final targetUid = widget.targetUser.uid;
    if (targetUid != null) {
      final cachedVerified = service.getCachedVerifiedFields(targetUid);
      if (cachedVerified != null) {
        _verifiedFields = Set<String>.from(cachedVerified);
      }
    }

    Future.microtask(() => _checkEligibility());
  }

  void _showIneligibleAlert(String reason) {
    VerificationAlertType type = VerificationAlertType.error;
    String title = 'Ineligible';

    if (reason.contains('already verified')) {
      type = VerificationAlertType.alreadyVerified;
      title = 'Already Verified';
    } else if (reason.contains('limit reached')) {
      type = VerificationAlertType.limit;
      title = 'Daily Limit';
    } else if (reason.contains('relative')) {
      type = VerificationAlertType.conflict;
      title = 'Conflict of Interest';
    } else if (reason.contains('complete your profile') ||
        reason.contains('PCT score') ||
        reason.contains('acquired at least')) {
      type = VerificationAlertType.requirements;
      title = 'Requirements Not Met';
    }

    Navigator.pop(context);

    VerificationAlertModal.show(
      context,
      type: type,
      title: title,
      message: reason,
    );
  }

  Future<void> _checkEligibility() async {
    try {
      final targetUid = widget.targetUser.uid;
      if (targetUid == null) return;

      final service = ref.read(trustServiceProvider);
      if (service.hasCachedVerificationEligibility(
        widget.currentUserId,
        targetUid,
      )) {
        final cachedReason = service.getCachedVerificationEligibility(
          widget.currentUserId,
          targetUid,
        );
        if (cachedReason != null && mounted) {
          _showIneligibleAlert(cachedReason);
          return;
        }
      }

      final results = await Future.wait<dynamic>([
        service.checkVerificationEligibility(widget.currentUserId, targetUid),
        service.getVerifiedFields(targetUid),
      ]);

      final reason = results[0] as String?;
      final verified = results[1] as Set<String>;

      if (reason != null && mounted) {
        _showIneligibleAlert(reason);
        return;
      }

      if (mounted) {
        setState(() {
          _verifiedFields = verified;
          _isLoadingEligibility = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingEligibility = false;
        });
      }
    }
  }

  void _initializeFields() {
    final user = widget.targetUser;

    // Helper to add if not empty
    void addField(String key, String? value) {
      if (value != null && value.isNotEmpty) {
        _fieldVerifications[key] = null;
        _fieldValues[key] = value;
      }
    }

    // Helper for formatting location (Town/City only as per requirement)
    String? formatLocation(UserLocation loc) {
      if (loc.city != null && loc.city!.isNotEmpty) {
        return loc.city;
      }
      return null;
    }

    // Photo handled separately in UI, but we track verification state here
    if (user.profileImage.isNotEmpty) {
      _fieldVerifications['Profile Photo'] = null;
      _fieldValues['Profile Photo'] = user.profileImage;
    }

    addField('First Name', user.firstName);
    addField('Last Name', user.lastName);

    // Detailed Locations
    addField('Home Town', formatLocation(user.homeLocation));
    addField('Current Host Town', formatLocation(user.hostLocation));

    if (user.pastLocations != null) {
      for (var location in user.pastLocations!) {
        final locStr = formatLocation(location.location);
        if (locStr != null) {
          addField('Past Host Town (${location.until})', locStr);
        }
      }
    }

    addField('Bio', user.bio);
    if (user.occupation != null) addField('Occupation', user.occupation);

    if (user.education != null && user.education!.isNotEmpty) {
      final eduString = user.education!
          .map((e) => '${e.institution} (${e.degree})')
          .join('\n');
      addField('Education', eduString);
    }

    if (user.profession != null && user.profession!.isNotEmpty) {
      addField('Profession', user.profession!.join(', '));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = widget.targetUser;

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: true,
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.only(
            left: 16.0,
            right: 16.0,
            top: 40.0,
            bottom: 16.0,
          ),
          child: _isLoadingEligibility
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        const Icon(
                          LucideIcons.shieldCheck,
                          color: AppTheme.accent,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Verify ${user.firstName}\'s Profile',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Verify a field you know is true to earn 1,000 DSP. Help build community trust!',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.hintColor,
                      ),
                    ),
                    const Divider(height: 32),

                    // Verification List
                    Expanded(
                      child: ListView(
                        children: [
                          if (_fieldVerifications.containsKey(
                            'Profile Photo',
                          )) ...[
                            _buildPhotoVerificationCard(user),
                            const SizedBox(height: 24),
                          ],

                          ..._fieldVerifications.keys
                              .where((k) => k != 'Profile Photo')
                              .toList() // Important: Create a new list from keys
                              .map((key) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 16.0),
                                  child: _buildTristateField(
                                    key,
                                    _fieldValues[key],
                                  ),
                                );
                              }),

                          // Trust Slider — shared widget so updates flow consistently everywhere
                          const SizedBox(height: 16),
                          if (widget.targetUser.uid != null)
                            TrustSliderWidget(
                              targetUserId: widget.targetUser.uid!,
                              currentUserId: widget.currentUserId,
                              displayName: widget.targetUser.firstName,
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),
                    Builder(
                      builder: (context) {
                        final hasFields = _fieldVerifications.values.any(
                          (v) => v != null,
                        );
                        final buttonLabel = hasFields
                            ? 'Submit Verification (+1,000 DSP)'
                            : 'Verify at least one field';
                        return SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: hasFields ? _submitVerification : null,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: hasFields
                                  ? AppTheme.accent
                                  : null,
                              disabledBackgroundColor: theme
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.12),
                              disabledForegroundColor: theme
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.38),
                            ),
                            child: Text(
                              buttonLabel,
                              style: TextStyle(fontSize: hasFields ? 14 : 12),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildPhotoVerificationCard(ProfileData user) {
    final theme = Theme.of(context);
    const label = 'Profile Photo';

    return Container(
      padding: const EdgeInsets.all(AppTheme.pageHorizontalPadding * 2),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            'Does this look like ${user.firstName}?',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          CircleAvatar(
            radius: 40,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            backgroundImage: NetworkImage(user.profileImage),
          ),
          const SizedBox(height: 16),
          _buildToggleRow(label),
        ],
      ),
    );
  }

  Widget _buildTristateField(String label, String? value) {
    final theme = Theme.of(context);
    final String displayLabel = label;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            displayLabel,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(height: 4),
          Text(
            value ?? 'N/A',
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
          ),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: _buildToggleRow(label)),
        ],
      ),
    );
  }

  Widget _buildToggleRow(String label) {
    final state = _fieldVerifications[label];
    final theme = Theme.of(context);

    final bool isAlreadyVerified = _verifiedFields.contains(label);

    if (isAlreadyVerified) {
      return Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTheme.success.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 18, color: AppTheme.success),
            SizedBox(width: 8),
            Text(
              'Already Verified',
              style: TextStyle(
                color: AppTheme.success,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        // False (Red)
        Expanded(
          child: GestureDetector(
            onTap: () => _setFieldVerification(label, false),
            child: Container(
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: state == false ? AppTheme.error : theme.cardColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.close,
                size: 24,
                color: state == false ? Colors.white : theme.disabledColor,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Neutral (Middle)
        Expanded(
          child: GestureDetector(
            onTap: () => _setFieldVerification(label, null),
            child: Container(
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: state == null ? theme.highlightColor : theme.cardColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                LucideIcons.minus,
                size: 20,
                color: theme.disabledColor,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // True (Green)
        Expanded(
          child: GestureDetector(
            onTap: () => _setFieldVerification(label, true),
            child: Container(
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: state == true ? AppTheme.success : theme.cardColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.check,
                size: 24,
                color: state == true ? Colors.white : theme.disabledColor,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _setFieldVerification(String key, bool? value) {
    setState(() {
      if (value != null) {
        // Reset all others to null (Neutral)
        for (var k in _fieldVerifications.keys) {
          _fieldVerifications[k] = null;
        }
        // Set selected
        _fieldVerifications[key] = value;
      } else {
        // Just clearing this one
        _fieldVerifications[key] = null;
      }
    });
  }

  Future<void> _submitVerification() async {
    bool hasVerifications = false;
    _fieldVerifications.forEach((k, v) {
      if (v != null) hasVerifications = true;
    });

    if (!hasVerifications) {
      VerificationAlertModal.show(
        context,
        type: VerificationAlertType.error,
        title: 'Field Verification Required',
        message: 'Please verify at least one profile field before submitting.',
      );
      return;
    }

    final toUserId = widget.targetUser.uid;
    if (toUserId == null) return;

    final Map<String, bool> submittedFields = {};
    _fieldVerifications.forEach((key, value) {
      if (value != null) {
        if (key.startsWith('Relative:')) {
          submittedFields['Relatives'] = value;
        } else {
          submittedFields[key] = value;
        }
      }
    });

    final trustService = ref.read(trustServiceProvider);
    final updatedVerified = Set<String>.from(_verifiedFields);
    submittedFields.forEach((key, value) {
      if (value) updatedVerified.add(key);
    });
    trustService.cacheVerifiedFields(toUserId, updatedVerified);

    Navigator.pop(context);

    VerificationAlertModal.show(
      context,
      type: VerificationAlertType.success,
      title: 'Verification Success',
      message: 'Thank you for contributing to the community trust.',
    );

    if (submittedFields.isNotEmpty) {
      unawaited(
        trustService
            .saveVerificationEvent(
              fromUserId: widget.currentUserId,
              toUserId: toUserId,
              fields: submittedFields,
            )
            .catchError((Object e) {
              debugPrint('Error saving verification event: $e');
            }),
      );
    }
  }
}
