# Chat - Interface Documentation

## Overview

The Chat feature provides real-time messaging between users, including text messages, DSP transfers, and system notifications.

## Public Interface

### Services

#### `ChatMessagingService`
**Location:** `lib/features/chat/services/chat_messaging_service.dart`

Primary service for messaging operations.

**Key Methods:**
```dart
// Send a message
Future<void> sendMessage({
  required String chatId,
  required String senderId,
  required String content,
  MessageType type = MessageType.text,
})

// Get messages for a chat
Stream<List<Message>> getMessages(String chatId)

// Mark messages as read
Future<void> markAsRead(String chatId, String userId)
```

#### `ChatService`
**Location:** `lib/features/chat/services/chat_service.dart`

Manages chat creation and metadata.

**Key Methods:**
```dart
// Create or get chat between users
Future<Chat> getOrCreateChat(String userId1, String userId2)

// Get user's chats
Future<List<Chat>> getUserChats(String userId)

// Update chat metadata
Future<void> updateChatMetadata(String chatId, Map<String, dynamic> metadata)
```

### Repository

#### `ChatRepository`
**Location:** `lib/features/chat/repository/chat_repository.dart`

Data access layer for chats.

**Key Methods:**
```dart
// Chat operations
Future<Chat?> getChatById(String chatId)
Future<void> createChat(Chat chat)
Future<void> updateChat(Chat chat)

// Message operations
Future<void> addMessage(String chatId, Message message)
Stream<List<Message>> streamMessages(String chatId)
```

### Providers

```dart
// User's chats
final userChatsProvider = StreamProvider<List<Chat>>((ref) => ...);

// Specific chat
final chatProvider = FutureProvider.family<Chat?, String>((ref, chatId) => ...);

// Chat messages
final chatMessagesProvider = StreamProvider.family<List<Message>, String>((ref, chatId) => ...);
```

## Dependencies

### Required From Other Features

- **Auth** (`lib/features/auth/`)
  - Current user ID
  
- **Profile** (`lib/features/profile/`)
  - User profiles for chat display
  
- **DSP** (`lib/features/dsp/`)
  - Point awards for messaging
  - DSP transfer handling

### Required From Core

- **Firebase** (`lib/core/services/`)
  - Firestore for persistence
  - Cloud Functions for notifications

## Integration Points

### How Other Features Use Chat

**DSP Feature:**
```dart
// Send DSP transfer message
await ref.read(chatMessagingServiceProvider).sendMessage(
  chatId: chatId,
  senderId: senderId,
  content: 'Sent you 10 DSP',
  type: MessageType.dspTransfer,
);
```

**Events Feature:**
```dart
// Send event invitation
await ref.read(chatMessagingServiceProvider).sendMessage(
  chatId: chatId,
  senderId: senderId,
  content: 'Invited you to event',
  type: MessageType.eventInvite,
);
```

## Data Models

### `Chat`
**Location:** `lib/features/chat/models/chat.dart`

```dart
class Chat {
  final String id;
  final List<String> participants;
  final Message? lastMessage;
  final Map<String, int> unreadCounts;
  final DateTime createdAt;
  final DateTime? updatedAt;
}
```

### `Message`
**Location:** `lib/features/chat/models/message.dart`

```dart
class Message {
  final String id;
  final String chatId;
  final String senderId;
  final String content;
  final MessageType type;
  final DateTime timestamp;
  final bool isRead;
  final Map<String, dynamic>? metadata;
}
```

### `MessageType`
**Location:** `lib/features/chat/models/message.dart`

```dart
enum MessageType {
  text,           // Regular text message
  dspTransfer,    // DSP transfer notification
  eventInvite,    // Event invitation
  system,         // System notification
}
```

## Real-Time Updates

Chat uses Firestore streams for real-time updates:
- New messages appear instantly
- Read receipts update in real-time
- Typing indicators (future enhancement)

## Notifications

Cloud Functions trigger push notifications for:
- New messages
- DSP transfers
- Event invitations

## Notes

- Each message awards 1 DSP to sender
- Chats are created on-demand when users first message
- Messages are stored in subcollection under chat document
- Unread counts tracked per participant
- DSP transfer messages include amount in metadata
