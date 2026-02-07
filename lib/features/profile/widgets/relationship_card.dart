import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:diaspora_nearby/features/profile/models/relationship.dart';
import 'package:diaspora_nearby/features/profile/widgets/bereavement_announcement_modal.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/core/data/countries.dart';
import 'package:lucide_icons/lucide_icons.dart';

class RelationshipCard extends ConsumerWidget {
  final Relationship relationship;
  final bool enableActions;

  const RelationshipCard({
    super.key,
    required this.relationship,
    this.enableActions = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileByIdProvider(relationship.id));

    return profileAsync.when(
      data: (profile) {
        if (profile == null) return const SizedBox.shrink(); // User deleted?

        final name = '${profile.firstName} ${profile.lastName}'.trim();
        final photoUrl = profile.profileImage;

        // Host Country Flag Logic
        final flag = profile.hostCountryCode != null
            ? (getCountryByCode(profile.hostCountryCode!)?.flag ?? '')
            : (relationship.flag ?? '');

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 0,
              vertical: 0,
            ),
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: GestureDetector(
              onTap: () => context.push('/profile/${relationship.id}'),
              child: CircleAvatar(
                radius: 20,
                backgroundColor: Colors.grey.shade300,
                backgroundImage: CachedNetworkImageProvider(photoUrl),
                child: null,
              ),
            ),
            title: Row(
              children: [
                if (flag.isNotEmpty) ...[
                  Text(
                    flag,
                    style: const TextStyle(fontSize: 16),
                  ), // Flag first
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (relationship.status == 'deceased') ...[
                  const Spacer(),
                  Text(
                    'Passed Away',
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontStyle: FontStyle.italic,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
            subtitle: Text(
              relationship.type,
              style: const TextStyle(color: Colors.grey),
            ),
            trailing: enableActions
                ? IconButton(
                    icon: const Icon(
                      LucideIcons.moreVertical,
                      size: 20,
                      color: Colors.grey,
                    ),
                    onPressed: () => _showActions(context, relationship),
                  )
                : null,
            onTap: () => context.push('/profile/${relationship.id}'),
          ),
        );
      },
      loading: () => const SizedBox(
        height: 60,
        child: Center(child: LinearProgressIndicator()),
      ),
      error: (_, __) => const SizedBox.shrink(), // Hides error items
    );
  }

  void _showActions(BuildContext context, Relationship rel) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              if (rel.status != 'deceased')
                ListTile(
                  leading: const Icon(LucideIcons.flag, color: Colors.black),
                  title: const Text('Announce Passing'),
                  subtitle: const Text('Create memorial group'),
                  onTap: () {
                    Navigator.pop(context);
                    showDialog(
                      context: context,
                      builder: (context) =>
                          BereavementAnnouncementModal(relationship: rel),
                    );
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
