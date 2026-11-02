import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/chat/models/message.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/shared/utils/whatsapp_utils.dart';

class VoiceCallMessageContent extends ConsumerWidget {
  final Message message;
  final bool isOwn;

  const VoiceCallMessageContent({
    super.key,
    required this.message,
    required this.isOwn,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final metadataPhone = message.metadata?['phone'] as String?;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        String? phone = metadataPhone;
        if (phone == null || phone.isEmpty) {
          final cachedProfile = ref
              .read(profileRepositoryProvider)
              .getCachedProfile(message.senderId);
          phone = cachedProfile?.phone;
          if (phone == null || phone.isEmpty) {
            final fetched = await ref
                .read(profileRepositoryProvider)
                .getUserProfile(message.senderId);
            phone = fetched?.phone;
          }
        }
        if (phone != null && phone.isNotEmpty) {
          final success = await WhatsAppUtils.launchWhatsApp(phone);
          if (!success && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not launch WhatsApp')),
            );
          }
        }
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 8, 8, 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isOwn
              ? Colors.black.withValues(alpha: 0.12)
              : theme.colorScheme.onSurface.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isOwn
                    ? Colors.white.withValues(alpha: 0.2)
                    : Colors.green.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(
                LucideIcons.phone,
                color: isOwn ? theme.colorScheme.onPrimary : Colors.green,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Voice call',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isOwn
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isOwn
                            ? LucideIcons.arrowUpRight
                            : LucideIcons.arrowDownLeft,
                        size: 13,
                        color: isOwn
                            ? theme.colorScheme.onPrimary.withValues(
                                alpha: 0.85,
                              )
                            : Colors.green,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isOwn ? 'Outgoing' : 'Incoming',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isOwn
                              ? theme.colorScheme.onPrimary.withValues(
                                  alpha: 0.75,
                                )
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
