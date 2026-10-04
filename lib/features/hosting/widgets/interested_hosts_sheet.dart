import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/features/hosting/models/hosting_request.dart';
import 'package:diaspora_nearby/features/hosting/services/hosting_service.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

/// Bottom sheet that shows all interested hosts for a hosting request.
/// The traveler can view each host's profile and select one to confirm
/// the arrangement, which creates a hosting session and opens a DM.
class InterestedHostsSheet extends ConsumerStatefulWidget {
  final HostingRequest request;

  const InterestedHostsSheet({super.key, required this.request});

  @override
  ConsumerState<InterestedHostsSheet> createState() =>
      _InterestedHostsSheetState();
}

class _InterestedHostsSheetState extends ConsumerState<InterestedHostsSheet> {
  bool _isSelecting = false;
  String? _selectingHostId;

  @override
  Widget build(BuildContext context) {
    final hostIds = widget.request.interestedHostIds;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // ── Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Icon(LucideIcons.users, size: 20, color: AppTheme.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Interested Hosts',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${hostIds.length} host${hostIds.length == 1 ? '' : 's'} responded',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Divider(
            height: 1,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.08),
          ),

          // ── Host List
          if (hostIds.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                children: [
                  Icon(
                    LucideIcons.heartOff,
                    size: 48,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No hosts have shown interest yet',
                    style: TextStyle(
                      fontSize: 15,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: hostIds.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.05),
                ),
                itemBuilder: (context, index) {
                  return _HostTile(
                    hostId: hostIds[index],
                    request: widget.request,
                    isSelecting:
                        _isSelecting && _selectingHostId == hostIds[index],
                    isDisabled: _isSelecting,
                    onSelect: () => _handleSelectHost(hostIds[index]),
                    onViewProfile: () {
                      context.push('/profile/${hostIds[index]}');
                    },
                  );
                },
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _handleSelectHost(String hostId) async {
    setState(() {
      _isSelecting = true;
      _selectingHostId = hostId;
    });

    try {
      debugPrint('🏠 [SelectHost] Step 1: Fetching host profile for $hostId');
      // 1. Fetch host profile
      final hostProfile = await ref
          .read(profileRepositoryProvider)
          .getUserProfile(hostId);

      if (hostProfile == null) {
        throw Exception('Could not load host profile');
      }
      debugPrint('🏠 [SelectHost] Step 1 ✅ Host: ${hostProfile.fullName}');

      // 2. Create/find DM between traveler and host
      debugPrint('🏠 [SelectHost] Step 2: Creating/finding DM with host');
      final chatRepo = ref.read(chatRepositoryProvider);
      final chat = await chatRepo.createDirectChat(hostId);

      if (chat == null) {
        throw Exception('Could not create chat');
      }
      debugPrint('🏠 [SelectHost] Step 2 ✅ Chat ID: ${chat.id}');

      // 3. Confirm arrangement (creates session, updates request to matched)
      debugPrint(
        '🏠 [SelectHost] Step 3: Confirming arrangement for request ${widget.request.id}',
      );
      final session = await ref
          .read(hostingServiceProvider)
          .confirmArrangement(
            request: widget.request,
            hostId: hostId,
            hostName: hostProfile.fullName,
            hostPhoto: hostProfile.profileImage,
            chatId: chat.id,
          );

      if (session == null) {
        throw Exception(
          'Could not create hosting session — check if the hosting request still exists in Firestore',
        );
      }
      debugPrint('🏠 [SelectHost] Step 3 ✅ Session ID: ${session.id}');

      // 4. Send arrangement system message to the DM
      debugPrint(
        '🏠 [SelectHost] Step 4: Sending system message to DM ${chat.id}',
      );
      final message = await chatRepo.sendTextMessage(
        chat.id,
        '🏠 Hosting arrangement confirmed! '
        '${widget.request.travelerName} will be hosted by ${hostProfile.fullName} '
        'from ${_formatDate(widget.request.arrivalDate)} to ${_formatDate(widget.request.departureDate)}. '
        'Use this chat to coordinate the details.',
        type: 'system',
        senderIdOverride: 'system',
        senderNameOverride: 'Hosting',
        metadata: {
          'systemType': 'hosting_arrangement',
          'sessionId': session.id,
          'requestId': widget.request.id,
          'travelerId': widget.request.travelerId,
          'travelerName': widget.request.travelerName,
          'travelerPhoto': widget.request.travelerPhoto,
          'hostId': hostId,
          'hostName': hostProfile.fullName,
          'hostPhoto': hostProfile.profileImage,
          'communityName': widget.request.communityName,
          'arrivalDate': widget.request.arrivalDate.toIso8601String(),
          'departureDate': widget.request.departureDate.toIso8601String(),
          'stayDuration': widget.request.stayDuration,
        },
      );
      debugPrint(
        '🏠 [SelectHost] Step 4 ${message != null ? '✅' : '❌'} Message sent: ${message?.id}',
      );

      if (mounted) {
        // 5. Close sheet and navigate to the DM
        debugPrint('🏠 [SelectHost] Step 5: Navigating to DM');
        Navigator.of(context).pop();
        context.push('/chats/${chat.id}');
      }
    } catch (e) {
      debugPrint('🏠 [SelectHost] ❌ Error: $e');
      if (mounted) {
        final message = e is Exception
            ? e.toString().replaceFirst('Exception: ', '')
            : 'Something went wrong. Please try again.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSelecting = false;
          _selectingHostId = null;
        });
      }
    }
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

/// Individual host tile showing profile info with view + select actions.
class _HostTile extends ConsumerWidget {
  final String hostId;
  final HostingRequest request;
  final bool isSelecting;
  final bool isDisabled;
  final VoidCallback onSelect;
  final VoidCallback onViewProfile;

  const _HostTile({
    required this.hostId,
    required this.request,
    required this.isSelecting,
    required this.isDisabled,
    required this.onSelect,
    required this.onViewProfile,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileByIdProvider(hostId));

    return profileAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, _) => ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.08),
          child: const Icon(LucideIcons.user),
        ),
        title: Text('Host $hostId'),
        subtitle: const Text('Could not load profile'),
      ),
      data: (profile) {
        if (profile == null) {
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.08),
              child: const Icon(LucideIcons.user),
            ),
            title: const Text('Unknown Host'),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              // Avatar
              GestureDetector(
                onTap: onViewProfile,
                child: CircleAvatar(
                  radius: 24,
                  backgroundColor: AppTheme.accent.withValues(alpha: 0.1),
                  backgroundImage: profile.profileImage.isNotEmpty
                      ? CachedNetworkImageProvider(profile.profileImage)
                      : null,
                  child: profile.profileImage.isEmpty
                      ? Text(
                          profile.firstName.isNotEmpty
                              ? profile.firstName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.accent,
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 12),

              // Name + info
              Expanded(
                child: GestureDetector(
                  onTap: onViewProfile,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.fullName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tap to view profile',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.accent.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Select button
              SizedBox(
                height: 36,
                child: ElevatedButton(
                  onPressed: isDisabled ? null : onSelect,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.1),
                    disabledForegroundColor: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.3),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  child: isSelecting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Select',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
