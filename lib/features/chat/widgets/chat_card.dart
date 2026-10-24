import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/chat/models/chat.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/core/data/countries.dart' as country_data;
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/chat/utils/community_chat_utils.dart'; // [NEW] Import utility
import 'package:cached_network_image/cached_network_image.dart';
import 'package:diaspora_nearby/features/organization/repository/organization_repository.dart'; // [NEW]
import 'package:diaspora_nearby/features/shared/models/location.dart'; // [NEW] Needed for UserLocationGeometry
import 'package:intl/intl.dart';
import 'package:diaspora_nearby/features/shared/utils/search_highlight_utils.dart';

/// Provider for other user's profile in direct chats (or Organization details)
/// Provider for chat partner profile (User or Organization)
/// Keyed by USER ID (String), so it is stable across Chat updates.
final chatPartnerProvider = FutureProvider.family<ProfileData?, String>((
  ref,
  userId,
) async {
  // Keep resolved profiles alive for the app session — prevents re-fetching
  // every time the user navigates away and back to the chats tab.
  ref.keepAlive();

  if (userId.isEmpty) return null;
  // 1. Try fetching User Profile
  final profileRepo = ref.watch(profileRepositoryProvider);
  final userProfile = await profileRepo.getUserProfile(userId);
  if (userProfile != null) return userProfile;

  // 2. Fallback to Organization
  final orgRepo = ref.watch(organizationRepositoryProvider);
  try {
    final org = await orgRepo.getOrganization(userId);
    if (org != null) {
      return ProfileData(
        uid: org['id'],
        firstName: org['businessName'] ?? org['name'] ?? 'Organization',
        lastName: '',
        phone: '',
        profileImage: org['profileImage'] ?? '',
        homeLocation: const UserLocation(
          formattedAddress: '',
          placeId: '',
          geometry: UserLocationGeometry(
            location: UserLocationCoordinates(lat: 0, lng: 0),
          ),
        ),
        hostLocation: const UserLocation(
          formattedAddress: '',
          placeId: '',
          geometry: UserLocationGeometry(
            location: UserLocationCoordinates(lat: 0, lng: 0),
          ),
        ),
        occupation: 'Organization',
      );
    }
  } catch (e) {
    debugPrint('Could not fetch organization profile: $e');
  }

  return null;
});

/// Chat Card Widget
/// Displays a chat preview in the chats list
class ChatCard extends ConsumerWidget {
  final Chat chat;
  final VoidCallback onTap;
  final String? searchQuery;

  const ChatCard({
    super.key,
    required this.chat,
    required this.onTap,
    this.searchQuery,
  });

  /// Whether this chat is an auto-created Family Group Chat
  bool get _isFamilyGroup =>
      chat.metadata?['isFamilyGroupImmediate'] == true ||
      chat.metadata?['isFamilyGroupExtended'] == true;
  bool get _isImmediateFamilyGroup =>
      chat.metadata?['isFamilyGroupImmediate'] == true;

  String _getCountryFlag(String? countryCode) {
    if (countryCode == null || countryCode.isEmpty) return '';
    final country = country_data.getCountryByCode(countryCode);
    return country?.flag ?? '';
  }

  String _formatLastMessageTime(int timestamp) {
    final now = DateTime.now();
    final messageTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final difference = now.difference(messageTime);

    if (difference.inDays == 0) {
      // Today - show time
      return DateFormat('h:mm a').format(messageTime);
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      // This week - show day name
      return DateFormat('EEEE').format(messageTime);
    } else {
      // Older - show date
      return DateFormat('M/d/yy').format(messageTime);
    }
  }

  Widget _buildLastMessagePreview(
    BuildContext context,
    ThemeData theme,
    WidgetRef ref,
    LastMessage? lastMessage,
  ) {
    // 1. Check for typing status (Direct chats only in list to avoid opening
    // 50+ subcollection listeners across community/event/org chats).
    final typingUsers = chat.isDirect
        ? (ref.watch(typingIndicatorsProvider(chat.id)).value ?? const <String>[])
        : const <String>[];

    if (typingUsers.isNotEmpty) {
      if (typingUsers.length == 1 && !chat.isDirect) {
        // Multiple people chat, try to show name
        final profileAsync = ref.watch(
          userProfileByIdProvider(typingUsers.first),
        );
        return profileAsync.when(
          data: (profile) => Text(
            '${profile?.firstName ?? 'Someone'} is typing...',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
              fontStyle: FontStyle.italic,
            ),
          ),
          loading: () => Text(
            'typing...',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontStyle: FontStyle.italic,
            ),
          ),
          error: (_, _) => Text(
            'typing...',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontStyle: FontStyle.italic,
            ),
          ),
        );
      }

      return Text(
        typingUsers.length > 1
            ? '${typingUsers.length} people typing...'
            : 'typing...',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    if (lastMessage == null) {
      return Text(
        'No messages yet',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    if (lastMessage.isDeleted) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.ban,
            size: 14,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 4),
          Text(
            'Message deleted',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      );
    }

    IconData? icon;
    String text = lastMessage.content;
    bool isMedia = true;
    Color?
    customIconColor; // [NEW] Allow custom color for specific message types

    // Check for hosting request/arrangement system messages
    final systemType = lastMessage.metadata?['systemType'] as String?;
    if (lastMessage.type == 'system' &&
        (systemType == 'hosting_request' ||
            systemType == 'hosting_arrangement')) {
      icon = LucideIcons.plane;
      text = lastMessage.content;
      customIconColor = AppTheme.accent;
    } else if (lastMessage.type == 'system') {
      isMedia = false;
      final senderName = lastMessage.senderName.trim();
      var content = lastMessage.content.trim();
      if (content == 'Group created') {
        if (chat.isListingChat) {
          content = 'Shop created';
        } else if (chat.isEvent) {
          content = 'Event created';
        } else if (chat.isOrganization) {
          content = 'Organization created';
        } else if (chat.isCommunity) {
          content = 'Community created';
        }
      }
      if (senderName.isNotEmpty &&
          senderName.toLowerCase() != 'system' &&
          !content.toLowerCase().startsWith(senderName.toLowerCase())) {
        text = '$senderName $content';
      } else {
        text = content;
      }
    } else {
      switch (lastMessage.type) {
        case 'image':
          icon = LucideIcons.image;
          text = 'Photo message';
          break;
        case 'video':
          icon = LucideIcons.video;
          text = 'Video message';
          break;
        case 'audio':
          icon = LucideIcons.mic;
          text = 'Voice message';
          break;
        case 'audio_file':
          icon = LucideIcons.music;
          text = 'Audio message';
          break;
        case 'location':
          icon = LucideIcons.mapPin;
          text = 'Location message';
          break;
        case 'document':
          icon = LucideIcons.fileText;
          text = 'Document message';
          break;
        case 'dsp_transfer': // [NEW]
          final assetType = lastMessage.metadata?['assetType'] as String?;
          final isTokenTransfer = assetType == 'token';
          final amount = lastMessage.metadata?['amount']?.toString() ?? '';
          final currentUserId = ref.watch(authStateProvider).value?.uid;
          final isSent = lastMessage.senderId == currentUserId;
          final direction = isSent ? 'Sent' : 'Received';
          final assetLabel = isTokenTransfer ? r'$DIASPORA' : 'DSP';
          final assetColor = isTokenTransfer
              ? AppTheme.tokenColor
              : AppTheme.dspColor;

          // Build a rich Row widget directly for transfers
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isTokenTransfer)
                Image.asset(
                  'assets/icons/logo-orange-transparent-32.png',
                  width: 28,
                  height: 28,
                  color: assetColor,
                )
              else
                Icon(LucideIcons.coins, size: 20, color: assetColor),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '$amount $assetLabel $direction',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: assetColor,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
        case 'money-transfer':
          final meta = lastMessage.metadata ?? {};
          final amount = meta['amount'] != null ? '${meta['amount']}' : '';
          final currency = meta['currency'] as String? ?? 'USD';
          final currentUserId = ref.watch(authStateProvider).value?.uid;
          final isSent = lastMessage.senderId == currentUserId;
          final direction = isSent ? 'sent' : 'received';
          final fiatColor = AppTheme.fiatColor;

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.banknote, size: 18, color: fiatColor),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Remittance $currency $amount $direction',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: fiatColor,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
        default:
          isMedia = false;
          text = lastMessage.content;
      }
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (lastMessage.metadata?['isShared'] == true) ...[
          Icon(
            LucideIcons.forward,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
        ],
        if (isMedia && icon != null) ...[
          Icon(
            icon,
            size: 16,
            color: customIconColor ?? theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
        ] else if (isMedia && icon == null && customIconColor != null) ...[
          // Token transfer — show logo image
          Image.asset(
            'assets/icons/logo-orange-transparent-24.png',
            width: 16,
            height: 16,
            color: customIconColor,
          ),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: SearchHighlightUtils.highlightText(
            text,
            searchQuery,
            theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: chat.unreadCount > 0 ? FontWeight.w600 : null,
            ),
            context,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusIcon(ThemeData theme, String? status) {
    Color color;
    bool isDouble = false;

    switch (status) {
      case 'read':
        color = theme.colorScheme.primary;
        isDouble = true;
        break;
      case 'delivered':
        color = theme.colorScheme.onSurfaceVariant;
        isDouble = true;
        break;
      case 'sent':
      default:
        color = theme.colorScheme.onSurfaceVariant;
        isDouble = false;
        break;
    }

    // Pending state (if status is null or unknown, though strictly covered by default above if passed)
    if (status != 'sent' && status != 'delivered' && status != 'read') {
      return Icon(
        LucideIcons.clock,
        size: 14,
        color: theme.colorScheme.onSurfaceVariant,
      );
    }

    if (isDouble) {
      return SizedBox(
        width: 17, // Tighter width for overlapping
        height: 16,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              child: Icon(LucideIcons.check, size: 16, color: color),
            ),
            Positioned(
              left: 5, // Overlap
              child: Icon(LucideIcons.check, size: 16, color: color),
            ),
          ],
        ),
      );
    }

    return Icon(LucideIcons.check, size: 16, color: color);
  }

  IconData _getChatTypeIcon() {
    if (chat.isListingChat) {
      return LucideIcons.shoppingCart;
    }
    switch (chat.type) {
      case 'community':
        return LucideIcons.users;
      case 'group':
        return LucideIcons.users2;
      case 'event':
        return LucideIcons.calendar;
      default:
        return LucideIcons.user;
    }
  }

  Widget _buildAvatar(BuildContext context, ThemeData theme, WidgetRef ref) {
    // [NEW] Bereavement Chat Styling
    final isBereavement =
        chat.metadata?['isBereavement'] == true ||
        chat.name.startsWith('Bereaving ');

    if (isBereavement) {
      return Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.grey.shade200, // Neutral background
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: Icon(
            LucideIcons.heartCrack, // Broken heart
            color: Colors.black, // Black icon
            size: 24,
          ),
        ),
      );
    }

    // For direct chats, show profile image with location flag
    if (chat.isDirect) {
      final currentUserId = ref.watch(authStateProvider).value?.uid;
      final otherUserId = chat.getOtherParticipantId(currentUserId ?? '') ?? '';
      final cachedPartner = otherUserId.isNotEmpty
          ? ref.read(profileRepositoryProvider).getCachedProfile(otherUserId)
          : null;
      final userProfileAsync = ref.watch(chatPartnerProvider(otherUserId));
      final resolvedProfile = userProfileAsync.value ?? cachedPartner;

      if (resolvedProfile != null || !userProfileAsync.isLoading) {
        final photoUrl = resolvedProfile?.profileImage;
        final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;

        return CircleAvatar(
          radius: 28,
          backgroundColor: Colors.transparent,
          backgroundImage: hasPhoto
              ? CachedNetworkImageProvider(photoUrl)
              : null,
          child: !hasPhoto
              ? (resolvedProfile?.occupation == 'Organization'
                    ? Icon(
                        LucideIcons.building2,
                        color: theme.colorScheme.onPrimaryContainer,
                      )
                    : Text(
                        chat.name.isNotEmpty ? chat.name[0].toUpperCase() : '?',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ))
              : null,
        );
      }

      return CircleAvatar(
        radius: 28,
        backgroundColor: Colors.transparent,
        child: Icon(
          LucideIcons.user,
          size: 24,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      );
    }

    // [NEW] Community Avatars using parity utility
    if (chat.isCommunity) {
      final viewerHomeCountryCode = ref
          .watch(userProfileProvider)
          .value
          ?.homeCountryCode;
      return CommunityChatUtils.getCommunityAvatar(
        chat: chat,
        viewerHomeCountryCode: viewerHomeCountryCode,
        size: 56,
        context: context,
      );
    }

    // Family Group Chat — heartHandshake avatar
    if (_isFamilyGroup) {
      return Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: _isImmediateFamilyGroup
              ? Colors.blue.shade50
              : Colors.teal.shade50,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Icon(
            _isImmediateFamilyGroup
                ? LucideIcons.heartHandshake
                : LucideIcons.trees,
            color: _isImmediateFamilyGroup
                ? Colors.blue.shade600
                : Colors.teal.shade600,
            size: 26,
          ),
        ),
      );
    }

    // Corridor Chamber of Commerce — dual-flag avatar (host first, home second)
    if (chat.isOrganization && chat.id.startsWith('org_chamber_')) {
      final host = chat.hostCountryCode;
      final home = chat.homeCountryCode;
      if (host != null && home != null) {
        final hostFlag = country_data.getCountryByCode(host)?.flag;
        final homeFlag = country_data.getCountryByCode(home)?.flag;
        if (hostFlag != null && homeFlag != null) {
          return SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              children: [
                // Host country flag — bottom-left, slightly larger (leads)
                Positioned(
                  left: 0,
                  bottom: 0,
                  child: Text(hostFlag, style: const TextStyle(fontSize: 34)),
                ),
                // Home country flag — top-right, slightly smaller
                Positioned(
                  right: 0,
                  top: 0,
                  child: Text(homeFlag, style: const TextStyle(fontSize: 26)),
                ),
              ],
            ),
          );
        }
      }
    }

    // For group/event/org chats, show photo if available, else icon
    if ((chat.isEvent || chat.isGroup || chat.isOrganization) &&
        chat.photoUrl != null &&
        chat.photoUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 28,
        backgroundColor: Colors.transparent,
        backgroundImage: CachedNetworkImageProvider(chat.photoUrl!),
      );
    }

    return CircleAvatar(
      radius: 28,
      backgroundColor: Colors.transparent,
      child: Icon(
        _getChatTypeIcon(),
        size: 24,
        color: chat.isEvent
            ? Colors.orange.shade700
            : (chat.isOrganization
                  ? Colors.blue.shade700
                  : Colors.green.shade700),
      ),
    );
  }

  Widget _buildHighlightedName(
    String name,
    ThemeData theme,
    BuildContext context,
  ) {
    return SearchHighlightUtils.highlightText(
      name,
      searchQuery,
      theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      context,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // [PERF] Only open a separate chat-doc listener for community chats where
    // userChats may not receive every fan-out update. Standard DMs, groups,
    // events, and orgs already receive live lastMessage updates via userChats.
    final lastMessage = chat.isCommunity
        ? (ref.watch(chatLastMessageStreamProvider(chat.id)).value ??
              chat.lastMessage)
        : chat.lastMessage;
    final hasUnread = chat.unreadCount > 0;

    // Get display name (for DM chats, gets the other participant's name)
    // Get display name
    String displayName = chat.name;
    if (chat.isCommunity) {
      final viewerHomeCountryCode = ref
          .watch(userProfileProvider)
          .value
          ?.homeCountryCode;
      displayName = CommunityChatUtils.generateCommunityName(
        chat,
        viewerHomeCountryCode: viewerHomeCountryCode,
      );
    } else if (chat.isDirect) {
      final currentUserId = ref.watch(authStateProvider).value?.uid;
      final otherUserId = chat.getOtherParticipantId(currentUserId ?? '') ?? '';
      final cachedPartner = otherUserId.isNotEmpty
          ? ref.read(profileRepositoryProvider).getCachedProfile(otherUserId)
          : null;
      final partnerAsync = ref.watch(chatPartnerProvider(otherUserId));
      final resolvedPartner = partnerAsync.value ?? cachedPartner;

      if (resolvedPartner != null) {
        final fullName =
            '${resolvedPartner.firstName} ${resolvedPartner.lastName}'.trim();
        if (fullName.isNotEmpty) {
          displayName = fullName;
        }
      }
    }

    return Card(
      elevation: 0,
      color: Colors.transparent, // Removed contrast as requested
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Slidable(
        key: ValueKey(chat.id),
        // Swipe Right -> Pin to Bottom
        startActionPane: ActionPane(
          motion: const ScrollMotion(),
          children: [
            CustomSlidableAction(
              onPressed: (context) {
                ref
                    .read(chatRepositoryProvider)
                    .togglePinBottom(chat.id, !chat.isPinnedBottom);
              },
              backgroundColor: chat.isPinnedBottom
                  ? theme.colorScheme.surfaceContainerHighest
                  : theme.colorScheme.secondary,
              foregroundColor: chat.isPinnedBottom
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSecondary,
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // "Pin Upright" -> Standard Pin icon
                  Icon(LucideIcons.pin, size: 24),
                  SizedBox(height: 4),
                  Text(
                    'Pin', // User requested just "Pin"
                    style: TextStyle(
                      fontSize: 12,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        // Swipe Left -> Pin to Top (Upside Down Pin)
        endActionPane: ActionPane(
          motion: const ScrollMotion(),
          children: [
            // Mute/Unmute Action
            CustomSlidableAction(
              onPressed: (context) {
                ref
                    .read(chatRepositoryProvider)
                    .toggleMute(chat.id, !chat.isMuted);
              },
              backgroundColor: chat.isMuted
                  ? theme.colorScheme.surfaceContainerHighest
                  : theme
                        .colorScheme
                        .tertiary, // Sage-like color for active action
              foregroundColor: chat.isMuted
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onTertiary,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    chat.isMuted ? LucideIcons.bell : LucideIcons.bellOff,
                    size: 24,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    chat.isMuted ? 'Unmute' : 'Mute',
                    style: const TextStyle(
                      fontSize: 12,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            // Pin Action
            CustomSlidableAction(
              onPressed: (context) {
                ref
                    .read(chatRepositoryProvider)
                    .togglePin(chat.id, !chat.isPinned);
              },
              backgroundColor: chat.isPinned
                  ? theme.colorScheme.surfaceContainerHighest
                  : theme.colorScheme.primary,
              foregroundColor: chat.isPinned
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onPrimary,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // "Pin Upside Down" -> Rotated 180 degrees
                  Transform.rotate(
                    angle: 3.14159, // 180 degrees in radians
                    child: const Icon(LucideIcons.pin, size: 24),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Pin', // User requested just "Pin"
                    style: TextStyle(
                      fontSize: 12,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Row(
              children: [
                // Avatar
                _buildAvatar(context, theme, ref),
                const SizedBox(width: 12),
                // Chat info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name and time
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                if (chat.isDirect)
                                  Consumer(
                                    builder: (context, ref, child) {
                                      final currentUserId = ref
                                          .watch(authStateProvider)
                                          .value
                                          ?.uid;
                                      final otherUserId = chat
                                          .getOtherParticipantId(
                                            currentUserId ?? '',
                                          );
                                      final profileAsync = ref.watch(
                                        chatPartnerProvider(otherUserId ?? ''),
                                      );
                                      return profileAsync.maybeWhen(
                                        data: (profile) {
                                          // [NEW] Logic: If it is an Organization, show Building Icon
                                          // We used 'occupation' as a flag in the provider above
                                          final isOrganization =
                                              profile?.occupation ==
                                              'Organization';

                                          if (isOrganization) {
                                            return const Padding(
                                              padding: EdgeInsets.only(
                                                right: 6.0,
                                              ),
                                              child: Icon(
                                                LucideIcons.building2,
                                                size: 16,
                                                color: Colors.blue,
                                              ),
                                            );
                                          }

                                          // Fallback chain: Current GPS -> Top-level Host Country -> Host Location Object
                                          final countryCode =
                                              profile
                                                  ?.currentLocation
                                                  ?.countryCode ??
                                              profile?.hostCountryCode ??
                                              profile?.hostLocation.countryCode;
                                          if (countryCode != null &&
                                              countryCode.isNotEmpty) {
                                            return Padding(
                                              padding: const EdgeInsets.only(
                                                right: 6.0,
                                              ),
                                              child: Text(
                                                _getCountryFlag(countryCode),
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                ),
                                              ),
                                            );
                                          }
                                          return const SizedBox.shrink();
                                        },
                                        orElse: () => const SizedBox.shrink(),
                                      );
                                    },
                                  ),
                                // [NEW] Event Icon Check
                                if (chat.isEvent)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 6.0),
                                    child: Icon(
                                      LucideIcons.calendar,
                                      size: 16,
                                      color: Colors.orange,
                                    ),
                                  ),
                                if (chat.isOrganization)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 6.0),
                                    child: Icon(
                                      LucideIcons.building2,
                                      size: 16,
                                      color: Colors.blue,
                                    ),
                                  ),
                                if (chat.isCommunity &&
                                    CommunityChatUtils.isBilateral(chat: chat))
                                  const Padding(
                                    padding: EdgeInsets.only(right: 6.0),
                                    child: Icon(
                                      LucideIcons.heartHandshake,
                                      size: 16,
                                      color: AppTheme.accent,
                                    ),
                                  ),
                                if (chat.isGroup)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6.0),
                                    child: Icon(
                                      chat.isListingChat
                                          ? LucideIcons.shoppingCart
                                          : _isFamilyGroup
                                          ? (_isImmediateFamilyGroup
                                                ? LucideIcons.heartHandshake
                                                : LucideIcons.trees)
                                          : LucideIcons.users,
                                      size: 16,
                                      color: chat.isListingChat
                                          ? Colors.green.shade700
                                          : _isFamilyGroup
                                          ? (_isImmediateFamilyGroup
                                                ? Colors.blue.shade600
                                                : Colors.teal.shade600)
                                          : Colors.green,
                                    ),
                                  ),
                                Flexible(
                                  child: _buildHighlightedName(
                                    displayName,
                                    theme,
                                    context,
                                  ),
                                ),
                                if (chat.isMuted) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    LucideIcons.bellOff,
                                    size: 14,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (chat.isPinned) ...[
                            const SizedBox(width: 8),
                            Transform.rotate(
                              angle: 3.14159, // Upside down pin for Top
                              child: Icon(
                                LucideIcons.pin,
                                size: 14,
                                color: Colors.orange.shade700,
                              ),
                            ),
                          ] else if (chat.isPinnedBottom) ...[
                            const SizedBox(width: 8),
                            Icon(
                              LucideIcons.pin, // Upright pin for Bottom
                              size: 14,
                              color: Colors.orange.shade700,
                            ),
                          ],
                          if (lastMessage != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              _formatLastMessageTime(lastMessage.timestamp),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: hasUnread
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                                fontWeight: hasUnread ? FontWeight.w600 : null,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Last message preview
                      Row(
                        children: [
                          // Message status icon (for own messages)
                          if (lastMessage != null &&
                              lastMessage.status != null &&
                              chat.isDirect &&
                              lastMessage.senderId ==
                                  ref.watch(authStateProvider).value?.uid) ...[
                            _buildStatusIcon(theme, lastMessage.status),
                            const SizedBox(width: 4),
                          ],
                          // Message preview
                          Expanded(
                            child: _buildLastMessagePreview(
                              context,
                              theme,
                              ref,
                              lastMessage,
                            ),
                          ),
                          // Unread badge
                          if (hasUnread) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                chat.unreadCount > 99
                                    ? '99+'
                                    : chat.unreadCount.toString(),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
