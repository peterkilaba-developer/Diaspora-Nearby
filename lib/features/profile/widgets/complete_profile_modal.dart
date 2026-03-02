import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/profile/widgets/user_profile_form.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';

class CompleteProfileModal extends ConsumerWidget {
  final ProfileData profile;
  final List<String> missingFields;
  final VoidCallback? onNavigateToFullEdit;

  const CompleteProfileModal({
    super.key,
    required this.profile,
    required this.missingFields,
    this.onNavigateToFullEdit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 20,
        right: 20,
        top: 20,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.userPlus, color: Colors.orange),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Complete Your Profile',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              if (onNavigateToFullEdit != null)
                TextButton.icon(
                  onPressed: onNavigateToFullEdit,
                  icon: const Icon(LucideIcons.externalLink, size: 14),
                  label: const Text(
                    'Full Edit',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              IconButton(
                icon: const Icon(LucideIcons.x),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'A few more details are needed before you can connect via QR. This helps maintain a high trust environment.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 24),
          Flexible(
            child: UserProfileForm(
              initialProfile: profile,
              highlightFields: missingFields,
              submitLabel: 'Save & Continue Connection',
              showUserCard: false,
              isFinishProfile: true,
              onSave: (updated, newImage) async {
                try {
                  String imageUrl = updated.profileImage;
                  if (newImage != null) {
                    imageUrl = await ref
                        .read(profileRepositoryProvider)
                        .uploadProfileImage(updated.uid!, newImage);
                  }

                  final finalProfile = updated.copyWith(profileImage: imageUrl);
                  await ref
                      .read(profileRepositoryProvider)
                      .saveUserProfile(finalProfile.uid!, finalProfile);

                  if (context.mounted) {
                    Navigator.pop(context, true);
                  }
                } catch (e) {
                  debugPrint('Error saving profile in modal: $e');
                  rethrow;
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
