import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:diaspora_nearby/features/chat/services/chat_messaging_service.dart';
import 'package:diaspora_nearby/features/chat/models/message.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:image_picker/image_picker.dart';

// Must generate mocks for these classes
@GenerateMocks([
  FirebaseStorage,
  Reference,
  UploadTask,
  TaskSnapshot,
  FirebaseDatabase,
  DatabaseReference,
  FirebaseFirestore,
  CollectionReference,
  DocumentReference,
  DocumentSnapshot,
  User,
  FirebaseAuth,
  DataSnapshot,
  PointsService,
])
import 'chat_messaging_service_test.mocks.dart';

class FakeUploadTask extends Fake implements UploadTask {
  final TaskSnapshot _snapshot;
  
  FakeUploadTask(this._snapshot);

  @override
  Future<S> then<S>(FutureOr<S> Function(TaskSnapshot) onValue, {Function? onError}) async {
    return Future.value(onValue(_snapshot));
  }
}

void main() {
  late MockFirebaseDatabase mockRtdb;
  late MockFirebaseStorage mockStorage;
  late MockFirebaseFirestore mockFirestore;
  late MockFirebaseAuth mockAuth;
  late MockUser mockUser;
  late MockPointsService mockPointsService;
  late ChatMessagingService service;

  setUp(() {
    mockRtdb = MockFirebaseDatabase();
    mockStorage = MockFirebaseStorage();
    mockFirestore = MockFirebaseFirestore();
    mockAuth = MockFirebaseAuth();
    mockUser = MockUser();
    mockPointsService = MockPointsService();

    // Default Auth behavior
    when(mockAuth.currentUser).thenReturn(mockUser);
    when(mockUser.uid).thenReturn('test_user_id');

    service = ChatMessagingService(
      rtdb: mockRtdb,
      storage: mockStorage,
      firestore: mockFirestore,
      auth: mockAuth,
      pointsService: mockPointsService,
    );
  });

  group('ChatMessagingService Media Upload', () {
    test('sendImageMessage should upload file and return optimistic message', () async {
      // 1. Setup Data
      final chatId = 'chat_123';
      final imagePath = 'test_image.jpg';
      
      // 2. Setup Mocks for User Data Fetch
      final mockUserDocRef = MockDocumentReference<Map<String, dynamic>>();
      final mockUserDocSnap = MockDocumentSnapshot<Map<String, dynamic>>();
      
      final mockUsersCollection = MockCollectionReference<Map<String, dynamic>>();
      when(mockFirestore.collection('users')).thenReturn(mockUsersCollection);
      when(mockUsersCollection.doc(any)).thenReturn(mockUserDocRef);
      when(mockUserDocRef.get()).thenAnswer((_) async => mockUserDocSnap);
      when(mockUserDocSnap.data()).thenReturn({
        'firstName': 'Test',
        'lastName': 'User',
        'profileImage': 'http://profile.jpg'
      });

      // 3. Setup Mocks for Storage Upload
      final mockStorageRef = MockReference();
      final mockChildRef = MockReference(); // The file ref
      final mockTaskSnapshot = MockTaskSnapshot();
      final fakeUploadTask = FakeUploadTask(mockTaskSnapshot);
      
      when(mockStorage.ref()).thenReturn(mockStorageRef);
      when(mockStorageRef.child(any)).thenReturn(mockChildRef);
      when(mockChildRef.putFile(any, any)).thenAnswer((_) => fakeUploadTask);
      
      // Setup Download URL
      when(mockTaskSnapshot.ref).thenReturn(mockChildRef); // Corrected: ref is on snapshot
      when(mockChildRef.getDownloadURL()).thenAnswer((_) async => 'http://download.url/image.jpg');
      
      // 4. Setup RTDB Mocks
      final mockMessagesRef = MockDatabaseReference();
      final mockNewMessageRef = MockDatabaseReference();
      final mockLastMessageRef = MockDatabaseReference();
      final mockUpdatedAtRef = MockDatabaseReference();
      
      when(mockRtdb.ref(any)).thenReturn(mockMessagesRef); // Default catch all
      // We need precise paths
      when(mockRtdb.ref('chats/$chatId/messages')).thenReturn(mockMessagesRef);
      when(mockMessagesRef.push()).thenReturn(mockNewMessageRef);
      when(mockNewMessageRef.key).thenReturn('new_msg_id');
      when(mockNewMessageRef.set(any)).thenAnswer((_) async {});
      // Stub update for the catch-all mock used for userChats
      when(mockMessagesRef.update(any)).thenAnswer((_) async {});

      when(mockRtdb.ref('chats/$chatId/lastMessage')).thenReturn(mockLastMessageRef);
      when(mockLastMessageRef.set(any)).thenAnswer((_) async {});
      
      when(mockRtdb.ref('chats/$chatId/updatedAt')).thenReturn(mockUpdatedAtRef);
      when(mockUpdatedAtRef.set(any)).thenAnswer((_) async {});
      
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
        }
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
      verify(mockNewMessageRef.set(any)).called(1);
    });
  });

  group('ChatMessagingService Group Invitations', () {
    test('sendGroupInvitation should update userChats for all invited users', () async {
      final groupId = 'group_123';
      final groupName = 'Test Group';
      final invitedIds = ['user_A', 'user_B'];

      // Setup Mocks
      final mockUserDocRef = MockDocumentReference<Map<String, dynamic>>();
      final mockUserDocSnap = MockDocumentSnapshot<Map<String, dynamic>>();
      
      final mockUsersCollection = MockCollectionReference<Map<String, dynamic>>();
      when(mockFirestore.collection('users')).thenReturn(mockUsersCollection);
      when(mockUsersCollection.doc(any)).thenReturn(mockUserDocRef);
      when(mockUserDocRef.get()).thenAnswer((_) async => mockUserDocSnap);
      when(mockUserDocSnap.data()).thenReturn({
        'firstName': 'Sender',
        'lastName': 'User',
      });

      final mockRootRef = MockDatabaseReference();
      final mockInvRefA = MockDatabaseReference();
      final mockInvRefB = MockDatabaseReference();
      
      when(mockRtdb.ref(any)).thenReturn(mockRootRef);
      when(mockRtdb.ref('userChats/user_A/group_123')).thenReturn(mockInvRefA);
      when(mockRtdb.ref('userChats/user_B/group_123')).thenReturn(mockInvRefB);
      
      when(mockInvRefA.update(any)).thenAnswer((_) async {});
      when(mockInvRefB.update(any)).thenAnswer((_) async {});
      when(mockRootRef.update(any)).thenAnswer((_) async {});

      // Execute
      await service.sendGroupInvitation(groupId, groupName, invitedIds);

      // Verify
      for (final userId in invitedIds) {
        verify(mockRtdb.ref('userChats/$userId/$groupId')).called(1);
      }
      verify(mockInvRefA.update(any)).called(1);
      verify(mockInvRefB.update(any)).called(1);
    });
  });
}
