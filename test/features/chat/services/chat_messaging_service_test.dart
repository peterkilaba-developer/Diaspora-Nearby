import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:diaspora_nearby/core/utils/media_upload_helper.dart';
import 'package:diaspora_nearby/features/chat/models/message.dart';
import 'package:diaspora_nearby/features/chat/providers/pending_message_provider.dart';
import 'package:diaspora_nearby/features/chat/services/chat_messaging_service.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

// ignore_for_file: avoid_print

// Must generate nice mocks (returns defaults for unstubbed methods)
@GenerateNiceMocks([
  MockSpec<FirebaseStorage>(),
  MockSpec<Reference>(),
  MockSpec<UploadTask>(),
  MockSpec<TaskSnapshot>(),
  MockSpec<FirebaseFirestore>(),
  MockSpec<CollectionReference<Map<String, dynamic>>>(),
  MockSpec<DocumentReference<Map<String, dynamic>>>(),
  MockSpec<DocumentSnapshot<Map<String, dynamic>>>(),
  MockSpec<User>(),
  MockSpec<FirebaseAuth>(),
  MockSpec<PointsService>(),
])
import 'chat_messaging_service_test.mocks.dart';

class FakeUploadTask extends Fake implements UploadTask {
  final TaskSnapshot _snapshot;

  FakeUploadTask(this._snapshot);

  @override
  Stream<TaskSnapshot> get snapshotEvents => Stream.value(_snapshot);

  @override
  Future<S> then<S>(
    FutureOr<S> Function(TaskSnapshot) onValue, {
    Function? onError,
  }) {
    return Future.value(_snapshot).then(onValue, onError: onError);
  }

  // Make the task awaitable
  Future<TaskSnapshot> get future => Future.value(_snapshot);
}

class FakeWriteBatch extends Fake implements WriteBatch {
  final List<Map<String, dynamic>> recordedPayloads = [];

  @override
  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) {
    if (data is Map<String, dynamic>) {
      recordedPayloads.add(data);
    }
  }

  @override
  Future<void> commit() async {}
}

void main() {
  late MockFirebaseStorage mockStorage;
  late MockFirebaseFirestore mockFirestore;
  late MockFirebaseAuth mockAuth;
  late MockUser mockUser;
  late MockPointsService mockPointsService;
  late ChatMessagingService service;
  late File tempImageFile;

  setUp(() {
    mockStorage = MockFirebaseStorage();
    mockFirestore = MockFirebaseFirestore();
    mockAuth = MockFirebaseAuth();
    mockUser = MockUser();
    mockPointsService = MockPointsService();

    // Default Auth behavior
    when(mockAuth.currentUser).thenReturn(mockUser);
    when(mockUser.uid).thenReturn('test_user_id');

    service = ChatMessagingService(
      storage: mockStorage,
      firestore: mockFirestore,
      auth: mockAuth,
      pointsService: mockPointsService,
    );

    // Create a temporary test image file
    tempImageFile = File(
      '${Directory.systemTemp.path}/test_image_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    tempImageFile.writeAsBytesSync([
      0xFF,
      0xD8,
      0xFF,
      0xE0,
    ]); // minimal JPEG header
  });

  tearDown(() {
    if (tempImageFile.existsSync()) {
      tempImageFile.deleteSync();
    }
  });

  group('ChatMessagingService Media Upload', () {
    test(
      'sendImageMessage should upload file and return optimistic message',
      () async {
        // 1. Setup Data
        final chatId = 'chat_123';
        final imagePath = tempImageFile.path;

        // 2. Setup Mocks for User Data Fetch
        final mockUserDocRef = MockDocumentReference();
        final mockUserDocSnap = MockDocumentSnapshot();

        final mockUsersCollection = MockCollectionReference();
        when(mockFirestore.collection('users')).thenReturn(mockUsersCollection);
        when(mockUsersCollection.doc(any)).thenReturn(mockUserDocRef);
        when(mockUserDocRef.get()).thenAnswer((_) async => mockUserDocSnap);
        when(mockUserDocSnap.data()).thenReturn({
          'firstName': 'Test',
          'lastName': 'User',
          'profileImage': 'http://profile.jpg',
        });

        // 3. Setup Mocks for Storage Upload
        final mockStorageRef = MockReference();
        final mockChildRef = MockReference(); // The file ref
        final mockTaskSnapshot = MockTaskSnapshot();
        when(mockTaskSnapshot.state).thenReturn(TaskState.success);
        when(mockTaskSnapshot.bytesTransferred).thenReturn(4);
        when(mockTaskSnapshot.totalBytes).thenReturn(4);
        final fakeUploadTask = FakeUploadTask(mockTaskSnapshot);

        when(mockStorage.ref()).thenReturn(mockStorageRef);
        when(mockStorageRef.child(any)).thenReturn(mockChildRef);
        when(mockChildRef.putFile(any, any)).thenAnswer((_) => fakeUploadTask);

        // Setup Download URL
        when(mockTaskSnapshot.ref).thenReturn(mockChildRef);
        when(
          mockChildRef.getDownloadURL(),
        ).thenAnswer((_) async => 'http://download.url/image.jpg');

        // 4. Setup Firestore Mocks for message creation
        final mockChatsCollection = MockCollectionReference();
        final mockChatDocRef = MockDocumentReference();
        final mockMessagesCollection = MockCollectionReference();
        final mockNewMsgRef = MockDocumentReference();
        final mockUserChatsCollection = MockCollectionReference();
        final mockUserChatDocRef = MockDocumentReference();

        when(mockFirestore.batch()).thenReturn(FakeWriteBatch());
        when(mockFirestore.collection('chats')).thenReturn(mockChatsCollection);
        when(mockChatsCollection.doc(chatId)).thenReturn(mockChatDocRef);
        when(
          mockChatDocRef.collection('messages'),
        ).thenReturn(mockMessagesCollection);
        when(mockMessagesCollection.doc(any)).thenReturn(mockNewMsgRef);
        when(mockNewMsgRef.id).thenReturn('msg_123');
        when(
          mockUserDocRef.collection('userChats'),
        ).thenReturn(mockUserChatsCollection);
        when(mockUserChatsCollection.doc(any)).thenReturn(mockUserChatDocRef);
        when(mockNewMsgRef.set(any)).thenAnswer((_) async {
          return;
        });

        // 5. Execute
        final result = await service.sendImageMessage(
          chatId,
          XFile(imagePath),
          caption: 'Test Caption',
          onConfirmed: (msg) {
            print('Confirmed: ${msg.id}');
          },
          onError: (e) {
            print('Error: $e');
          },
        );

        // 6. Verify Optimistic Result
        expect(result, isNotNull);
        expect(result!.content, 'Test Caption');
        expect(result.status, 'sending');

        // Wait for async operations to complete
        await Future.delayed(const Duration(milliseconds: 100));

        // Verify interactions
        verify(mockChildRef.putFile(any, any)).called(1);
        verify(mockChildRef.getDownloadURL()).called(1);
      },
    );

    test(
      'sendDocumentMessage preserves clean documentName, size, and PDF contentType',
      () async {
        final chatId = 'chat_doc_1';
        final tempPdf = File(
          '${Directory.systemTemp.path}/Invoice_2026.pdf',
        )..writeAsBytesSync([0x25, 0x50, 0x44, 0x46, 0x2D]);
        addTearDown(() {
          if (tempPdf.existsSync()) tempPdf.deleteSync();
        });

        final mockUserDocRef = MockDocumentReference();
        final mockUserDocSnap = MockDocumentSnapshot();
        final mockUsersCollection = MockCollectionReference();
        when(mockFirestore.collection('users')).thenReturn(mockUsersCollection);
        when(mockUsersCollection.doc(any)).thenReturn(mockUserDocRef);
        when(mockUserDocRef.get()).thenAnswer((_) async => mockUserDocSnap);
        when(mockUserDocSnap.data()).thenReturn({
          'firstName': 'Ada',
          'lastName': 'Lovelace',
        });

        final mockStorageRef = MockReference();
        final mockChildRef = MockReference();
        final mockTaskSnapshot = MockTaskSnapshot();
        when(mockTaskSnapshot.state).thenReturn(TaskState.success);
        when(mockTaskSnapshot.ref).thenReturn(mockChildRef);
        final fakeUploadTask = FakeUploadTask(mockTaskSnapshot);

        SettableMetadata? capturedMetadata;
        when(mockStorage.ref()).thenReturn(mockStorageRef);
        when(mockStorageRef.child(any)).thenReturn(mockChildRef);
        when(mockChildRef.fullPath).thenReturn(
          'chat_documents/chat_doc_1/123_Invoice_2026.pdf',
        );
        when(mockChildRef.putFile(any, any)).thenAnswer((invocation) {
          capturedMetadata =
              invocation.positionalArguments[1] as SettableMetadata?;
          return fakeUploadTask;
        });
        when(
          mockChildRef.getDownloadURL(),
        ).thenAnswer((_) async => 'https://storage.example/Invoice_2026.pdf');

        final fakeBatch = FakeWriteBatch();
        final mockChatsCollection = MockCollectionReference();
        final mockChatDocRef = MockDocumentReference();
        final mockMessagesCollection = MockCollectionReference();
        final mockNewMsgRef = MockDocumentReference();
        final mockUserChatsCollection = MockCollectionReference();
        final mockUserChatDocRef = MockDocumentReference();

        when(mockFirestore.batch()).thenReturn(fakeBatch);
        when(mockFirestore.collection('chats')).thenReturn(mockChatsCollection);
        when(mockChatsCollection.doc(chatId)).thenReturn(mockChatDocRef);
        when(
          mockChatDocRef.collection('messages'),
        ).thenReturn(mockMessagesCollection);
        when(mockMessagesCollection.doc(any)).thenReturn(mockNewMsgRef);
        when(mockNewMsgRef.id).thenReturn('msg_doc_1');
        when(
          mockUserDocRef.collection('userChats'),
        ).thenReturn(mockUserChatsCollection);
        when(mockUserChatsCollection.doc(any)).thenReturn(mockUserChatDocRef);

        final confirmedCompleter = Completer<Message>();
        final optimistic = await service.sendDocumentMessage(
          chatId,
          XFile(tempPdf.path, name: 'Invoice_2026.pdf'),
          onConfirmed: confirmedCompleter.complete,
        );

        expect(optimistic, isNotNull);
        expect(optimistic!.documentName, 'Invoice_2026.pdf');

        final confirmed = await confirmedCompleter.future;
        expect(capturedMetadata?.contentType, 'application/pdf');
        expect(confirmed.documentName, 'Invoice_2026.pdf');
        expect(confirmed.documentSize, 5);
        expect(
          confirmed.documentUrl,
          'https://storage.example/Invoice_2026.pdf',
        );
      },
    );

    test(
      'sendAudioFileMessage forwards onError when local file is missing',
      () async {
        final errorCompleter = Completer<String>();
        final mockUserDocRef = MockDocumentReference();
        final mockUserDocSnap = MockDocumentSnapshot();
        final mockUsersCollection = MockCollectionReference();
        when(mockFirestore.collection('users')).thenReturn(mockUsersCollection);
        when(mockUsersCollection.doc(any)).thenReturn(mockUserDocRef);
        when(mockUserDocRef.get()).thenAnswer((_) async => mockUserDocSnap);
        when(mockUserDocSnap.data()).thenReturn({'firstName': 'Test'});

        final mockStorageRef = MockReference();
        final mockChildRef = MockReference();
        when(mockStorage.ref()).thenReturn(mockStorageRef);
        when(mockStorageRef.child(any)).thenReturn(mockChildRef);

        await service.sendAudioFileMessage(
          'chat_audio_err',
          XFile('${Directory.systemTemp.path}/non_existent_track_999999.mp3'),
          onError: errorCompleter.complete,
        );

        final err = await errorCompleter.future;
        expect(err, contains('File does not exist'));
      },
    );

    test(
      'forwardMessage preserves media URLs, metadata, and canonical lat/lng location',
      () async {
        final chatId = 'chat_forward_target';
        final mockUserDocRef = MockDocumentReference();
        final mockUserDocSnap = MockDocumentSnapshot();
        final mockUsersCollection = MockCollectionReference();
        when(mockFirestore.collection('users')).thenReturn(mockUsersCollection);
        when(mockUsersCollection.doc(any)).thenReturn(mockUserDocRef);
        when(mockUserDocRef.get()).thenAnswer((_) async => mockUserDocSnap);
        when(mockUserDocSnap.data()).thenReturn({
          'firstName': 'Forward',
          'lastName': 'Sender',
        });

        final fakeBatch = FakeWriteBatch();
        final mockChatsCollection = MockCollectionReference();
        final mockChatDocRef = MockDocumentReference();
        final mockMessagesCollection = MockCollectionReference();
        final mockNewMsgRef = MockDocumentReference();
        final mockUserChatsCollection = MockCollectionReference();
        final mockUserChatDocRef = MockDocumentReference();

        when(mockFirestore.batch()).thenReturn(fakeBatch);
        when(mockFirestore.collection('chats')).thenReturn(mockChatsCollection);
        when(mockChatsCollection.doc(chatId)).thenReturn(mockChatDocRef);
        when(
          mockChatDocRef.collection('messages'),
        ).thenReturn(mockMessagesCollection);
        when(mockMessagesCollection.doc(any)).thenReturn(mockNewMsgRef);
        when(mockNewMsgRef.id).thenReturn('msg_fwd_1');
        when(
          mockUserDocRef.collection('userChats'),
        ).thenReturn(mockUserChatsCollection);
        when(mockUserChatsCollection.doc(any)).thenReturn(mockUserChatDocRef);

        const original = Message(
          id: 'orig_1',
          chatId: 'chat_source',
          senderId: 'author_1',
          senderName: 'Original Author',
          content: 'Check this photo',
          type: 'image',
          imageUrl: 'https://storage.example/photo.png',
          location: MessageLocation(
            lat: -6.7924,
            lng: 39.2083,
            address: 'Dar es Salaam',
          ),
          metadata: {'tag': 'important'},
          timestamp: 1700000000000,
        );

        final forwarded = await service.forwardMessage(chatId, original);
        expect(forwarded, isNotNull);
        expect(forwarded!.forwarded, isTrue);
        expect(forwarded.imageUrl, 'https://storage.example/photo.png');
        expect(forwarded.location?.lat, -6.7924);
        expect(forwarded.location?.lng, 39.2083);
        expect(forwarded.metadata?['tag'], 'important');

        final savedMsg = fakeBatch.recordedPayloads.first;
        expect(savedMsg['location'], {
          'lat': -6.7924,
          'lng': 39.2083,
          'address': 'Dar es Salaam',
        });
      },
    );
  });

  group('MediaUploadHelper & PendingMessagesNotifier', () {
    test('resolves PNG, WebM video, MP3 blob, and DOCX MIME types accurately', () {
      final png = MediaUploadHelper.resolve(
        XFile.fromData(
          Uint8List.fromList([1, 2]),
          name: 'screenshot.png',
          mimeType: 'image/png',
        ),
        'image',
      );
      expect(png.extension, '.png');
      expect(png.contentType, 'image/png');

      final mp3OnWeb = MediaUploadHelper.resolve(
        XFile.fromData(
          Uint8List.fromList([1, 2, 3]),
          mimeType: 'audio/mpeg',
        ),
        'audio_file',
        explicitFileName: 'song.mp3',
      );
      expect(mp3OnWeb.extension, '.mp3');
      expect(mp3OnWeb.contentType, 'audio/mpeg');
      expect(mp3OnWeb.cleanFileName, 'song.mp3');

      final svgDisguisedAsDoc = MediaUploadHelper.resolve(
        XFile.fromData(
          Uint8List.fromList([1]),
          name: 'vector.svg',
          mimeType: 'image/svg+xml',
        ),
        'document',
      );
      expect(svgDisguisedAsDoc.contentType, 'application/octet-stream');
    });

    test('PendingMessagesNotifier.migrateMessages preserves bubbles across DM creation', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(pendingMessagesProvider.notifier);

      const pendingMsg = Message(
        id: 'temp_media_1',
        chatId: 'pending_dm_userB',
        senderId: 'userA',
        senderName: 'Me',
        content: '',
        type: 'image',
        imageUrl: '/tmp/pic.jpg',
        timestamp: 100,
        status: 'sending',
      );
      notifier.addMessage('pending_dm_userB', pendingMsg);
      notifier.migrateMessages('pending_dm_userB', 'direct_hash123');

      final state = container.read(pendingMessagesProvider);
      expect(state.containsKey('pending_dm_userB'), isFalse);
      expect(state['direct_hash123'], hasLength(1));
      expect(state['direct_hash123']!.first.chatId, 'direct_hash123');
      expect(state['direct_hash123']!.first.id, 'temp_media_1');
    });
  });
}
