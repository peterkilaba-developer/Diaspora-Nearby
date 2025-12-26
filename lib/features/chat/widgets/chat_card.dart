import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/models/chat.dart';
import 'package:diaspora_nearby/models/profile_data.dart';
import 'package:diaspora_nearby/data/countries.dart' as country_data;
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/chat/utils/community_chat_utils.dart'; // [NEW] Import utility
import 'package:cached_network_image/cached_network_image.dart';
import 'package:diaspora_nearby/features/organization/repository/organization_repository.dart'; // [NEW]
import 'package:diaspora_nearby/models/location.dart'; // [NEW] Needed for UserLocationGeometry
import 'package:intl/intl.dart';

/// Provider for other user's profile in direct chats (or Organization details)
final chatUserProfileProvider = FutureProvider.family<ProfileData?, Chat>((ref, chat) async {
  if (!chat.isDirect) return null;
  
  // Get the other participant's ID
  final currentUserId = ref.watch(authStateProvider).value?.uid;
  if (currentUserId == null) return null;
  
  final otherUserId = chat.participants.firstWhere(
    (id) => id != currentUserId,
    orElse: () => '',
  );
  
  if (otherUserId.isEmpty) return null;
  
  // 1. Try fetching User Profile
  // 1. Try fetching User Profile
  final profileRepo = ref.watch(profileRepositoryProvider);
  final userProfile = await profileRepo.getUserProfile(otherUserId);
  
  if (userProfile != null) return userProfile;
  // This assumes Organizations are participants in chats with their IDs
  final orgRepo = ref.watch(organizationRepositoryProvider);
  try {
     final org = await orgRepo.getOrganization(otherUserId);
     if (org != null) {
        // Construct a dummy ProfileData for display purposes
        return ProfileData(
           uid: org['id'],
           firstName: org['businessName'] ?? org['name'] ?? 'Organization',
           lastName: '', // Display name often combines first+last, or we handle it
           phone: '',
           profileImage: org['profileImage'] ?? '',
           homeLocation: const UserLocation(formattedAddress: '', placeId: '', geometry: UserLocationGeometry(location: UserLocationCoordinates(lat: 0, lng: 0))), // Dummy
           hostLocation: const UserLocation(formattedAddress: '', placeId: '', geometry: UserLocationGeometry(location: UserLocationCoordinates(lat: 0, lng: 0))), // Dummy
           // Add a flag or specific field? 
           // We can abuse 'profession' or 'occupation' to store 'Organization' or logic check
           occupation: 'Organization', 
        );
     }
  } catch (e) {
     // Not an organization
  }
  
  return null;
});

/// Provider for chat display name in chat list
final chatCardDisplayNameProvider = FutureProvider.family<String, Chat>((ref, chat) async {
  // [NEW] Use utility for community chats, enriched with user context
  if (chat.isCommunity) {
     // Fetch current user profile to determine their Host Continent
     final currentUser = ref.watch(authStateProvider).value;
     String? hostContinentName;
     
     if (currentUser != null) {
        // We use .read here to avoid rebuilding the chat card simple text just because profile updates elsewhere
        // But for correctness, .watch might be safer if profile is cached. 
        // Given this is a FutureProvider, .read is acceptable if we assume location rarely changes during session.
        // Let's safe-read it from repo or cache.
        final profileRepo = ref.read(profileRepositoryProvider);
        try {
           final profile = await profileRepo.getUserProfile(currentUser.uid);
           if (profile?.currentLocation?.countryCode != null) {
              final continent = country_data.getContinentByCountryCode(profile!.currentLocation!.countryCode!);
              if (continent != null) {
                 hostContinentName = country_data.continentDisplayNames[continent]; // e.g., "North America"
              }
           }
        } catch (e) {
           // Ignore errors, fallback to default naming
        }
     }

     // Logic: If the chat name contains our Host Continent name, Force "Host" logic -> Noun.
     // e.g. Chat Name "North American Community", Host="North America" -> Force "North America Community"
     final generatedName = CommunityChatUtils.generateCommunityName(chat);
     
     if (hostContinentName != null) {
        // Strip "American" vs "America" differences by normalized checking
        // Actually CommunityChatUtils has internal logic if we pass locationType: 'host'
        // Let's try to regenerate with forced host type if we detect a match
        
        // Simple heuristic: If generated default name (likely Adjective) contains the Adjective form of our host continent
        // OR if the chat name itself seems related.
        
        // Better: Check if the chat IS a continent chat for our host continent
        // We can check if the generated name "sounds like" our continent.
        
        // Reverse verification:
        // Generate name as if it was HOST
        final hostFormName = CommunityChatUtils.generateCommunityNameFromParts(
            name: chat.name,
            locationType: 'host',
            id: chat.id
        );
        
        // If the HOST form contains our Host Continent Name (e.g. "North America Community" contains "North America")
        // AND the chat seems to actually BE that continent (not just sharing the name)...
        // The safest way is to check if the result of generateCommunityName (default) is DIFFERENT from hostFormName
        // AND hostFormName represents our actual location.
        
        if (hostFormName.contains(hostContinentName)) {
             return hostFormName;
        }
     }
     
     return generatedName;
  }
  
  final chatRepo = ref.watch(chatRepositoryProvider);
  return chatRepo.getDisplayNameForChat(chat);
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

  Widget _buildLastMessagePreview(ThemeData theme) {
    
    final lastMessage = chat.lastMessage;
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
    
    IconData? icon;
    String text = lastMessage.content;
    bool isMedia = true;

    switch (lastMessage.type) {
      case 'image':
        icon = LucideIcons.image;
        text = 'Photo';
        break;
      case 'video':
        icon = LucideIcons.video;
        text = 'Video';
        break;
      case 'audio':
        // Check if it's a voice message (duration usually implies voice note in this app context, or we can check metadata)
        // For now, if "content" is a URL and type is audio, we assume voice. 
        // We'll use Mic for generic audio if not distinguished, but user asked for "Mic for voice, Music for audio/music".
        // Usually, voice messages have a specific duration or different metadata. 
        // Let's assume 'audio' type is voice message by default in this app's "voice note" feature.
        // If there's a file upload (audio file), we might need to distinguish.
        // Checking if we have a way to distinguish. 
        // In this app, "audio" usually means voice note. If we add "music", it might be a document or a specific "audio_file" type?
        // Let's us Mic for now as typical for voice notes.
        icon = LucideIcons.mic; 
        text = 'Voice message';
        break;
      case 'audio_file': // Hypothetical type if we distinguish
        icon = LucideIcons.music;
        text = 'Audio';
        break;
      case 'location':
        icon = LucideIcons.locateFixed;
        text = 'Location';
        break;
      case 'document':
        icon = LucideIcons.fileText;
         // Try to show filename if content is a URL, or "Document"
        text = 'Document';
        break;
      case 'money-transfer':
        icon = LucideIcons.banknote; // or coins
        text = 'Money transfer';
        break;
      case 'camera': // User mentioned camera? Usually image/video.
         icon = LucideIcons.camera;
         text = 'Photo';
         break;
      default:
        isMedia = false;
        text = lastMessage.content;
    }
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isMedia && icon != null) ...[
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
               color: theme.colorScheme.onSurfaceVariant,
               fontWeight: chat.unreadCount > 0 ? FontWeight.w600 : null,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  IconData _getChatTypeIcon() {
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
    // For direct chats, show profile image with location flag
    if (chat.isDirect) {
      final userProfileAsync = ref.watch(chatUserProfileProvider(chat));
      
      return userProfileAsync.when(
        data: (profile) {
            // Profile photo or initials
          final photoUrl = profile?.profileImage;
          final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
          
          return CircleAvatar(
            radius: 28,
            backgroundColor: theme.colorScheme.primaryContainer,
            backgroundImage: hasPhoto
                ? CachedNetworkImageProvider(photoUrl)
                : null,
              child: !hasPhoto
                  ? (profile?.occupation == 'Organization' // Check if Org for fallback icon
                      ? Icon(LucideIcons.building2, color: theme.colorScheme.onPrimaryContainer)
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
        },
        loading: () => CircleAvatar(
          radius: 28,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            chat.name.isNotEmpty ? chat.name[0].toUpperCase() : '?',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        error: (_, __) => CircleAvatar(
          radius: 28,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            chat.name.isNotEmpty ? chat.name[0].toUpperCase() : '?',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
      );
    }

    // [NEW] Community Avatars using parity utility
    if (chat.isCommunity) {
      return CommunityChatUtils.getCommunityAvatar(
        chat: chat, 
        size: 56,
        context: context
      );
    }

    // For group/org chats, show photo if available, else icon
    if ((chat.type == 'group' || chat.isOrganization) && chat.photoUrl != null && chat.photoUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 28,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        backgroundImage: CachedNetworkImageProvider(chat.photoUrl!),
      );
    }

    // For group/event chats (fallback), show icon
    // [UPDATED] Event with profile image
    if (chat.isEvent && chat.photoUrl != null && chat.photoUrl!.isNotEmpty) {
       return Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
             shape: BoxShape.circle,
             color: theme.colorScheme.surfaceContainerHighest,
             image: DecorationImage(
                image: CachedNetworkImageProvider(chat.photoUrl!),
                fit: BoxFit.cover
             ),
          ),
       );
    }

    return CircleAvatar(
      radius: 28,
      backgroundColor: chat.isEvent
              ? Colors.orange.shade100
              : Colors.green.shade100,
      child: Icon(
        _getChatTypeIcon(),
        size: 24,
        color: chat.isEvent
                ? Colors.orange.shade700
                : (chat.isOrganization ? Colors.blue.shade700 : Colors.green.shade700),
      ),
    );
  }

  Widget _buildHighlightedName(String name, ThemeData theme) {
    if (searchQuery == null || searchQuery!.isEmpty) {
      return Text(
        name,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final query = searchQuery!.toLowerCase();
    final lowerName = name.toLowerCase();
    final matchIndex = lowerName.indexOf(query);

    if (matchIndex == -1) {
      return Text(
        name,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        children: [
          TextSpan(text: name.substring(0, matchIndex)),
          TextSpan(
            text: name.substring(matchIndex, matchIndex + query.length),
            style: TextStyle(
              backgroundColor: Colors.yellow.shade200,
              color: Colors.black,
            ),
          ),
          TextSpan(text: name.substring(matchIndex + query.length)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final lastMessage = chat.lastMessage;
    final hasUnread = chat.unreadCount > 0;
    
    // Get display name (for DM chats, gets the other participant's name)
    final displayNameAsync = ref.watch(chatCardDisplayNameProvider(chat));
    final displayName = displayNameAsync.asData?.value ?? chat.name;

    return Card(
      elevation: 0,
      color: Colors.transparent, // Removed contrast as requested
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Slidable(
        key: ValueKey(chat.id),
        startActionPane: ActionPane(
          motion: const ScrollMotion(),
          dismissible: null,
          children: [
            // Pin / Unpin
            SlidableAction(
              onPressed: (context) {
                ref.read(chatRepositoryProvider).togglePin(chat.id, !chat.isPinned);
              },
              backgroundColor: chat.isPinned 
                  ? theme.colorScheme.surfaceContainerHighest 
                  : theme.colorScheme.primary,
              foregroundColor: chat.isPinned 
                  ? theme.colorScheme.onSurface 
                  : theme.colorScheme.onPrimary,
              icon: chat.isPinned ? LucideIcons.pinOff : LucideIcons.pin,
              label: chat.isPinned ? 'Unpin' : 'Pin',
            ),
          ],
        ),
        endActionPane: ActionPane(
          motion: const ScrollMotion(),
          children: [
            // Pin to Bottom / Unpin from Bottom
            SlidableAction(
              onPressed: (context) {
                ref.read(chatRepositoryProvider).togglePinBottom(chat.id, !chat.isPinnedBottom);
              },
              backgroundColor: chat.isPinnedBottom 
                  ? theme.colorScheme.surfaceContainerHighest
                  : theme.colorScheme.secondary,
              foregroundColor: chat.isPinnedBottom
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSecondary,
              icon: chat.isPinnedBottom ? LucideIcons.arrowUpFromLine : LucideIcons.arrowDownToLine,
              label: chat.isPinnedBottom ? 'Unpin Btm' : 'Pin Btm',
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
                                    final profileAsync = ref.watch(chatUserProfileProvider(chat));
                                    return profileAsync.maybeWhen(
                                      data: (profile) {
                                        // [NEW] Logic: If it is an Organization, show Building Icon
                                        // We used 'occupation' as a flag in the provider above
                                        final isOrganization = profile?.occupation == 'Organization';
                                        
                                        if (isOrganization) {
                                            return const Padding(
                                               padding: EdgeInsets.only(right: 6.0),
                                               child: Icon(LucideIcons.building2, size: 16, color: Colors.blue),
                                            );
                                        }

                                        // Fallback chain: Current GPS -> Top-level Host Country -> Host Location Object
                                        final countryCode = profile?.currentLocation?.countryCode 
                                            ?? profile?.hostCountryCode 
                                            ?? profile?.hostLocation.countryCode;
                                        if (countryCode != null && countryCode.isNotEmpty) {
                                          return Padding(
                                            padding: const EdgeInsets.only(right: 6.0),
                                            child: Text(
                                              _getCountryFlag(countryCode),
                                              style: const TextStyle(fontSize: 16),
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
                                     child: Icon(LucideIcons.calendar, size: 16, color: Colors.orange),
                                  ),
                                if (chat.isOrganization)
                                  const Padding(
                                     padding: EdgeInsets.only(right: 6.0),
                                     child: Icon(LucideIcons.building2, size: 16, color: Colors.blue),
                                  ),
                                if (chat.isGroup)
                                  const Padding(
                                     padding: EdgeInsets.only(right: 6.0),
                                     child: Icon(LucideIcons.users, size: 16, color: Colors.green),
                                  ),
                              Flexible(
                                child: _buildHighlightedName(displayName, theme),
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
                          Icon(
                            LucideIcons.pin,
                            size: 14, // Slightly larger visual weight
                            color: Colors.orange.shade700,
                          ),
                        ],
                        if (chat.isPinnedBottom) ...[
                          const SizedBox(width: 8),
                          Icon(
                            LucideIcons.arrowDownToLine,
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
                        if (lastMessage != null && lastMessage.status != null) ...[
                          _buildStatusIcon(lastMessage.status!, theme),
                          const SizedBox(width: 4),
                        ],
                        // Message preview
                        Expanded(
                          child: _buildLastMessagePreview(theme),
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

  Widget _buildStatusIcon(String status, ThemeData theme) {
    switch (status) {
      case 'read':
        return Icon(
          LucideIcons.checkCheck,
          size: 16,
          color: Colors.blue,
        );
      case 'delivered':
        return Icon(
          LucideIcons.checkCheck,
          size: 16,
          color: Colors.green.shade700,
        );
      case 'sent':
      default:
        return Icon(
          LucideIcons.check,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        );
    }
  }
}




