import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diaspora_nearby/core/services/proximity_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart'; 
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart'; 
import 'package:firebase_database/firebase_database.dart' hide Query; 
import 'package:firebase_storage/firebase_storage.dart'; // [NEW]
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/chat/services/chat_messaging_service.dart'; 

// Manual Fakes to bypass build_runner dependency issues

// ==========================================
// Fake Notifications
// ==========================================
class FakeLocalNotifications extends Mock implements FlutterLocalNotificationsPlugin {
  bool showCalled = false;
  int? lastId;
  String? lastTitle;
  String? lastBody;

  @override
  Future<void> show(
    int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails, {
    String? payload,
  }) async {
    showCalled = true;
    lastId = id;
    lastTitle = title;
    lastBody = body;
  }

  @override
  Future<bool> initialize(
    InitializationSettings initializationSettings, {
    onDidReceiveNotificationResponse,
    onDidReceiveBackgroundNotificationResponse,
  }) async => true;
}

class FakeAndroidNotifications extends Fake implements AndroidFlutterLocalNotificationsPlugin {
  @override
  Future<void> createNotificationChannel(AndroidNotificationChannel channel) async {}
}

// ==========================================
// Fake SharedPreferences
// ==========================================
class FakeSharedPreferences extends Fake implements SharedPreferences {
  final Map<String, Object> _cache = {};

  @override
  int? getInt(String key) => _cache[key] as int?;

  @override
  Future<bool> setInt(String key, int value) async {
    _cache[key] = value;
    return true;
  }
}

// ==========================================
// Fake Firestore
// ==========================================
class FakeFirestore extends Fake implements FirebaseFirestore {
  final FakeCollectionReference usersCollection = FakeCollectionReference();

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    if (collectionPath == 'users') {
      return usersCollection;
    }
    throw UnimplementedError('Only users collection mocked');
  }
}

class FakeCollectionReference extends Fake implements CollectionReference<Map<String, dynamic>> {
  final Map<String, FakeDocumentReference> docs = {};
  FakeQuery? queryToReturn;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    docs[path!] ??= FakeDocumentReference();
    return docs[path]!;
  }

  @override
  Query<Map<String, dynamic>> where(Object field, {Object? isEqualTo, Object? isNotEqualTo, Object? isLessThan, Object? isLessThanOrEqualTo, Object? isGreaterThan, Object? isGreaterThanOrEqualTo, Object? arrayContains, Iterable<Object?>? arrayContainsAny, Iterable<Object?>? whereIn, Iterable<Object?>? whereNotIn, bool? isNull}) {
    // Return a fake query that we can control
    return queryToReturn ?? FakeQuery();
  }
}

class FakeDocumentReference extends Fake implements DocumentReference<Map<String, dynamic>> {
  Map<String, dynamic>? dataToReturn;
  bool existsToReturn = true;

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    return FakeDocumentSnapshot(dataToReturn, existsToReturn);
  }
}

class FakeDocumentSnapshot extends Fake implements DocumentSnapshot<Map<String, dynamic>> {
  final Map<String, dynamic>? _data;
  final bool _exists;

  FakeDocumentSnapshot(this._data, this._exists);

  @override
  bool get exists => _exists;

  @override
  Map<String, dynamic>? data() => _data;
}

class FakeQuery extends Fake implements Query<Map<String, dynamic>> {
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docsToReturn = [];

  @override
  Query<Map<String, dynamic>> limit(int limit) => this; // Ignore limit

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    return FakeQuerySnapshot(docsToReturn);
  }
}

class FakeQuerySnapshot extends Fake implements QuerySnapshot<Map<String, dynamic>> {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs;
  FakeQuerySnapshot(this._docs);

  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => _docs;
}

class FakeQueryDocumentSnapshot extends Fake implements QueryDocumentSnapshot<Map<String, dynamic>> {
  final Map<String, dynamic> _data;
  final String _id;

  FakeQueryDocumentSnapshot(this._id, this._data);

  @override
  String get id => _id;

  @override
  Map<String, dynamic> data() => _data;
}

// ==========================================
// Fake RTDB (FirebaseDatabase)
// ==========================================
class FakeFirebaseDatabase extends Fake implements FirebaseDatabase {
  final FakeDatabaseReference root = FakeDatabaseReference();

  @override
  DatabaseReference ref([String? path]) {
    if (path == null) return root;
    // Simple path navigation for verification
    final parts = path.split('/');
    FakeDatabaseReference current = root;
    for (final part in parts) {
      current = current.child(part) as FakeDatabaseReference;
    }
    return current;
  }
}

class FakeDatabaseReference extends Fake implements DatabaseReference {
  final Map<String, FakeDatabaseReference> children = {};
  final List<Map<String, dynamic>> setCalls = [];
  final List<Map<String, dynamic>> updateCalls = [];
  Object? valueToReturn;

  @override
  DatabaseReference child(String path) {
    if (!children.containsKey(path)) {
      children[path] = FakeDatabaseReference();
    }
    return children[path]!;
  }

  @override
  DatabaseReference push() {
    // Return a child with a random fake ID
    return child('push_id_${DateTime.now().microsecondsSinceEpoch}');
  }

  @override
  Future<void> set(Object? value) async {
    if (value is Map<String, dynamic>) {
      setCalls.add(value);
    }
  }

  @override
  Future<void> update(Map<String, Object?> value) async {
    updateCalls.add(Map<String, dynamic>.from(value));
  }

  @override
  Future<DataSnapshot> get() async {
    return FakeDataSnapshot(valueToReturn);
  }

  @override
  String? get key => 'fake_key';
}

class FakeDataSnapshot extends Fake implements DataSnapshot {
  final Object? _value;
  FakeDataSnapshot(this._value);

  @override
  Object? get value => _value;

  @override
  bool get exists => _value != null;
}

// ==========================================
// Fake Storage (FirebaseStorage)
// ==========================================
class FakeFirebaseStorage extends Fake implements FirebaseStorage {
  // Minimal implementation to satisfy constructor types
}

// ==========================================
// Fake Auth
// ==========================================
class FakeAuth extends Fake implements FirebaseAuth {
  final FakeUser? _currentUser;
  FakeAuth(this._currentUser);

  @override
  User? get currentUser => _currentUser;
}

class FakeUser extends Fake implements User {
  final String _uid;
  FakeUser(this._uid);
  @override
  String get uid => _uid;
}



// ==========================================
// Fake Points Service
// ==========================================
class FakePointsService extends Fake implements PointsService {
  @override
  Future<void> trackMessageSent(String userId) async {}
}

void main() {
  late FakeFirestore fakeFirestore;
  late FakeLocalNotifications fakeNotifications;
  late FakeSharedPreferences fakePrefs;
  late ProximityService proximityService;

  // Chat Service Fakes
  late FakeFirebaseDatabase fakeRtdb;
  late FakeAuth fakeAuth;
  late FakeFirebaseStorage fakeStorage;
  late FakePointsService fakePointsService;

  setUp(() {
    fakeFirestore = FakeFirestore();
    fakeNotifications = FakeLocalNotifications();
    fakePrefs = FakeSharedPreferences();
    fakeRtdb = FakeFirebaseDatabase();
    
    proximityService = ProximityService(
      firestore: fakeFirestore,
      rtdb: fakeRtdb,
      notificationsPlugin: fakeNotifications,
      prefs: fakePrefs,
    );
  });

  group('ProximityService Tests (Manual Fakes)', () {
    const userId = 'user_123';
    const compatriotId = 'user_456';
    const homeCountryCode = 'GH';

    test('should NOT notify if cooldown is active', () async {
      // Arrange
      await fakePrefs.setInt('last_proximity_notification_time', DateTime.now().millisecondsSinceEpoch);

      // Act
      await proximityService.checkAndNotify(userId);

      // Assert
      expect(fakeNotifications.showCalled, isFalse);
    });

    test('should notify if user is nearby and cooldown passed', () async {
      // Arrange
      // 1. Cooldown passed (0)
      
      // 2. Setup Me
      final myDoc = fakeFirestore.usersCollection.doc(userId) as FakeDocumentReference;
      myDoc.dataToReturn = {
        'homeCountryCode': homeCountryCode,
        'currentLocation': {
          'geometry': {
            'location': {'lat': 51.5074, 'lng': -0.1278} // London
          }
        },
      };

      // 3. Setup Compatriot Query
      final compatriotDoc = FakeQueryDocumentSnapshot(compatriotId, {
        'firstName': 'Kwame',
        'homeCountry': 'Ghana',
        'currentLocation': {
          'geometry': {
            'location': {'lat': 51.5074, 'lng': -0.1278} // London
          }
        },
      });
      
      final fakeQuery = FakeQuery()..docsToReturn = [compatriotDoc];
      fakeFirestore.usersCollection.queryToReturn = fakeQuery;


      // Act
      await proximityService.checkAndNotify(userId);

      // Assert
      expect(fakeNotifications.showCalled, isTrue);
      expect(fakeNotifications.lastBody, contains('Kwame'));
      expect(fakePrefs.getInt('last_proximity_notification_time'), isNotNull);
      expect(fakePrefs.getInt('last_proximity_notification_time'), isNot(0));
    });

    test('should NOT notify if compatriot is too far', () async {
      // Arrange
      // Me
      final myDoc = fakeFirestore.usersCollection.doc(userId) as FakeDocumentReference;
      myDoc.dataToReturn = {
        'homeCountryCode': homeCountryCode,
        'currentLocation': {
          'geometry': {
            'location': {'lat': 51.5074, 'lng': -0.1278} // London
          }
        },
      };

      // Compatriot (Manchester)
      final compatriotDoc = FakeQueryDocumentSnapshot(compatriotId, {
        'firstName': 'Kwame',
        'homeCountry': 'Ghana',
        'currentLocation': {
          'geometry': {
            'location': {'lat': 53.4808, 'lng': -2.2426} 
          }
        },
      });
      
      final fakeQuery = FakeQuery()..docsToReturn = [compatriotDoc];
      fakeFirestore.usersCollection.queryToReturn = fakeQuery;

      // Act
      await proximityService.checkAndNotify(userId);

      // Assert
      expect(fakeNotifications.showCalled, isFalse);
    });
  });

  group('ChatMessagingService Notification Tests', () {
    test('sendTextMessage should include mentions in userChats update', () async {
      // Arrange
      fakeRtdb = FakeFirebaseDatabase();
      fakeFirestore = FakeFirestore();
      fakeAuth = FakeAuth(FakeUser('sender_123'));
      fakeStorage = FakeFirebaseStorage();
      fakePointsService = FakePointsService();
      
      final chatService = ChatMessagingService(
        rtdb: fakeRtdb, 
        firestore: fakeFirestore,
        auth: fakeAuth,
        storage: fakeStorage, // Fake storage to prevent DefaultBinaryMessenger error
        pointsService: fakePointsService,
      );

      // Mock Sender Profile (needed for sendTextMessage)
      final senderDoc = fakeFirestore.usersCollection.doc('sender_123') as FakeDocumentReference;
      senderDoc.dataToReturn = {
        'firstName': 'Sender',
        'lastName': 'Man',
      };

      const chatId = 'chat_abc';
      const mentionedUserId = 'mentioned_user_999';

      // Act
      await chatService.sendTextMessage(
        chatId, 
        'Hello @User', 
        mentions: [mentionedUserId],
        participants: ['sender_123', 'other_user']
      );

      // Assert
      // We need to verify that userChats/mentioned_user_999/chat_abc was updated
      // And specifically that the update contained 'mentions': [mentionedUserId]
      
      // Navigate to the FakeDatabaseReference for the mentioned user
      // Path: userChats/mentioned_user_999/chat_abc
      final userChatRef = fakeRtdb.root.children['userChats']?.children[mentionedUserId]?.children[chatId];
      
      expect(userChatRef, isNotNull, reason: 'userChats node for mentioned user should be created/accessed');
      expect(userChatRef!.updateCalls, isNotEmpty, reason: 'update should be called on userChats');
      
      final lastUpdate = userChatRef.updateCalls.last;
      final lastMessage = lastUpdate['lastMessage'] as Map<dynamic, dynamic>;
      
      expect(lastMessage['mentions'], isNotNull, reason: 'lastMessage should contain mentions field');
      expect(lastMessage['mentions'], contains(mentionedUserId), reason: 'mentions field should contain the mentioned user ID');
    });
  });
}
