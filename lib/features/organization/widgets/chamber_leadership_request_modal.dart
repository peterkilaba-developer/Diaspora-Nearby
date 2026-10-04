import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/organization/models/chamber_roles.dart';
import 'package:diaspora_nearby/features/organization/repository/organization_repository.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

/// Bottom-sheet modal that lets a chamber member request a leadership seat.
///
/// Open via [ChamberLeadershipRequestModal.show]. Submission calls
/// [OrganizationRepository.requestChamberLeadership]; the server-side
/// pre-flight checks handle nationality pins, membership, and duplicate
/// guards. Errors are surfaced inline (red banner) rather than via a snack
/// bar so the user can correct and resubmit without re-opening the sheet.
class ChamberLeadershipRequestModal extends ConsumerStatefulWidget {
  final String orgId;
  final String chamberName;
  final String homeCountryCode;
  final String hostCountryCode;

  const ChamberLeadershipRequestModal({
    super.key,
    required this.orgId,
    required this.chamberName,
    required this.homeCountryCode,
    required this.hostCountryCode,
  });

  static Future<void> show(
    BuildContext context, {
    required String orgId,
    required String chamberName,
    required String homeCountryCode,
    required String hostCountryCode,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChamberLeadershipRequestModal(
        orgId: orgId,
        chamberName: chamberName,
        homeCountryCode: homeCountryCode,
        hostCountryCode: hostCountryCode,
      ),
    );
  }

  @override
  ConsumerState<ChamberLeadershipRequestModal> createState() =>
      _ChamberLeadershipRequestModalState();
}

class _ChamberLeadershipRequestModalState
    extends ConsumerState<ChamberLeadershipRequestModal> {
  String? _selectedRole;
  final _messageController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  String _pinHint(String role) {
    if (ChamberRoles.homePinned.contains(role)) {
      return 'Requires candidate residing in ${widget.homeCountryCode} (1+ year tenure)';
    }
    if (ChamberRoles.hostPinned.contains(role)) {
      return 'Requires candidate residing in ${widget.hostCountryCode} (1+ year tenure)';
    }
    return ChamberRoles.description(role);
  }

  Future<void> _submit() async {
    if (_selectedRole == null) {
      setState(() => _error = 'Pick a role first.');
      return;
    }
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid == null) {
      setState(() => _error = 'You must be signed in.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await ref
          .read(organizationRepositoryProvider)
          .requestChamberLeadership(
            orgId: widget.orgId,
            userId: uid,
            role: _selectedRole!,
            message: _messageController.text.trim(),
          );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Request submitted. An admin will review your pitch for '
            '${ChamberRoles.displayName(_selectedRole!)}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        // Strip Dart's "Bad state: " / "Invalid argument(s): " prefixes
        // for a cleaner inline error.
        _error = e.toString().replaceFirst(
          RegExp(r'^(Bad state|Invalid argument(?:\(s\))?|Exception): '),
          '',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
        // Bottom padding must account for BOTH the keyboard (viewInsets) and
        // the system gesture/nav bar (viewPadding). Using only viewInsets
        // hides the submit button behind the system nav.
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom:
              MediaQuery.of(context).viewInsets.bottom +
              MediaQuery.of(context).viewPadding.bottom +
              16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  const Icon(
                    LucideIcons.heartHandshake,
                    color: AppTheme.accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Request Leadership',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                widget.chamberName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 20),

              Text(
                'Pick a seat',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              ...ChamberRoles.all.map(_buildRoleTile),

              const SizedBox(height: 20),
              Text(
                'Your pitch (optional)',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _messageController,
                maxLines: 3,
                maxLength: 400,
                decoration: InputDecoration(
                  hintText:
                      'Why are you the right person for this seat? '
                      'Mention lived experience, B2B track record, etc.',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.error),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        LucideIcons.alertCircle,
                        size: 16,
                        color: AppTheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: AppTheme.error,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(LucideIcons.send),
                  label: Text(_submitting ? 'Submitting…' : 'Submit Request'),
                  onPressed: _submitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
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

  Widget _buildRoleTile(String role) {
    final theme = Theme.of(context);
    final selected = _selectedRole == role;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() {
          _selectedRole = role;
          _error = null;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.accent.withValues(alpha: 0.1)
                : theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.3,
                  ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? AppTheme.accent
                  : theme.dividerColor.withValues(alpha: 0.5),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                ChamberRoles.icon(role),
                size: 22,
                color: selected ? AppTheme.accent : theme.iconTheme.color,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ChamberRoles.displayName(role),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: selected ? AppTheme.accent : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _pinHint(role),
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(LucideIcons.check, color: AppTheme.accent, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
