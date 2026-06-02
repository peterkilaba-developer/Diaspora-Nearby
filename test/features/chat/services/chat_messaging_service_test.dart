import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:diaspora_nearby/features/chat/services/chat_messaging_service.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:image_picker/image_picker.dart';

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
  @override
  Future<TaskSnapshot> get future => Future.value(_snapshot);
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

        when(mockFirestore.collection('chats')).thenReturn(mockChatsCollection);
        when(mockChatsCollection.doc(chatId)).thenReturn(mockChatDocRef);
        when(
          mockChatDocRef.collection('messages'),
        ).thenReturn(mockMessagesCollection);
        when(mockMessagesCollection.doc(any)).thenReturn(mockNewMsgRef);
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
  });
}
