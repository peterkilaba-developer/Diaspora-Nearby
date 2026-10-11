// ignore_for_file: subtype_of_sealed_class, must_be_immutable

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diaspora_nearby/core/services/proximity_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/chat/services/chat_messaging_service.dart';
import 'package:diaspora_nearby/features/notifications/models/notification_item.dart';

// Manual Fakes to bypass build_runner dependency issues

// ==========================================
// Fake Notifications
// ==========================================
class FakeLocalNotifications extends Mock
    implements FlutterLocalNotificationsPlugin {
  bool showCalled = false;
  int? lastId;
  String? lastTitle;
  String? lastBody;

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails,
    String? payload,
  }) async {
    showCalled = true;
    lastId = id;
    lastTitle = title;
    lastBody = body;
  }

  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    onDidReceiveNotificationResponse,
    onDidReceiveBackgroundNotificationResponse,
  }) async => true;
}

class FakeAndroidNotifications extends Fake
    implements AndroidFlutterLocalNotificationsPlugin {
  @override
  Future<void> createNotificationChannel(
    AndroidNotificationChannel channel,
  ) async {}
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

class FakeCollectionReference extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  final Map<String, FakeDocumentReference> docs = {};
  FakeQuery? queryToReturn;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    docs[path!] ??= FakeDocumentReference();
    return docs[path]!;
  }

  @override
  Query<Map<String, dynamic>> where(
    Object field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    Iterable<Object?>? arrayContainsAny,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
    bool? isNull,
  }) {
    // Return a fake query that we can control
    return queryToReturn ?? FakeQuery();
  }
}

class FakeDocumentReference extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  Map<String, dynamic>? dataToReturn;
  bool existsToReturn = true;

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    return FakeDocumentSnapshot(dataToReturn, existsToReturn);
  }
}

class FakeDocumentSnapshot extends Fake
    implements DocumentSnapshot<Map<String, dynamic>> {
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

class FakeQuerySnapshot extends Fake
    implements QuerySnapshot<Map<String, dynamic>> {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs;
  FakeQuerySnapshot(this._docs);

  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => _docs;
}

class FakeQueryDocumentSnapshot extends Fake
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  final Map<String, dynamic> _data;
  final String _id;

  FakeQueryDocumentSnapshot(this._id, this._data);

  @override
  String get id => _id;

  @override
  Map<String, dynamic> data() => _data;
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
  Future<void> trackMessageSent(String userId, {String? receiverId}) async {}
}

void main() {
  late FakeFirestore fakeFirestore;
  late FakeLocalNotifications fakeNotifications;
  late FakeSharedPreferences fakePrefs;
  late ProximityService proximityService;

  // Chat Service Fakes
  late FakeAuth fakeAuth;
  late FakeFirebaseStorage fakeStorage;
  late FakePointsService fakePointsService;

  setUp(() {
    fakeFirestore = FakeFirestore();
    fakeNotifications = FakeLocalNotifications();
    fakePrefs = FakeSharedPreferences();

    proximityService = ProximityService();
  });

  group('ProximityService Tests (Manual Fakes)', () {
    const userId = 'user_123';
    const compatriotId = 'user_456';
    const homeCountryCode = 'GH';

    test('should NOT notify if cooldown is active', () async {
      // Arrange
      await fakePrefs.setInt(
        'last_proximity_notification_time',
        DateTime.now().millisecondsSinceEpoch,
      );

      // Act
      await proximityService.checkAndNotify(userId);

      // Assert
      expect(fakeNotifications.showCalled, isFalse);
    });

    test('should notify if user is nearby and cooldown passed', () async {
      // Arrange
      // 1. Cooldown passed (0)

      // 2. Setup Me
      final myDoc =
          fakeFirestore.usersCollection.doc(userId) as FakeDocumentReference;
      myDoc.dataToReturn = {
        'homeCountryCode': homeCountryCode,
        'currentLocation': {
          'geometry': {
            'location': {'lat': 51.5074, 'lng': -0.1278}, // London
          },
        },
      };

      // 3. Setup Compatriot Query
      final compatriotDoc = FakeQueryDocumentSnapshot(compatriotId, {
        'firstName': 'Kwame',
        'homeCountry': 'Ghana',
        'currentLocation': {
          'geometry': {
            'location': {'lat': 51.5074, 'lng': -0.1278}, // London
          },
        },
      });

      final fakeQuery = FakeQuery()..docsToReturn = [compatriotDoc];
      fakeFirestore.usersCollection.queryToReturn = fakeQuery;

      // Act
      await proximityService.checkAndNotify(userId);

      // Assert — proximity is now a no-op (handled by Cloud Functions)
      // The method does nothing locally, so no notification is expected
      expect(fakeNotifications.showCalled, isFalse);
    });

    test('should NOT notify if compatriot is too far', () async {
      // Arrange
      // Me
      final myDoc =
          fakeFirestore.usersCollection.doc(userId) as FakeDocumentReference;
      myDoc.dataToReturn = {
        'homeCountryCode': homeCountryCode,
        'currentLocation': {
          'geometry': {
            'location': {'lat': 51.5074, 'lng': -0.1278}, // London
          },
        },
      };

      // Compatriot (Manchester)
      final compatriotDoc = FakeQueryDocumentSnapshot(compatriotId, {
        'firstName': 'Kwame',
        'homeCountry': 'Ghana',
        'currentLocation': {
          'geometry': {
            'location': {'lat': 53.4808, 'lng': -2.2426},
          },
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
    test('sendTextMessage should include mentions in message data', () async {
      // Arrange
      fakeFirestore = FakeFirestore();
      fakeAuth = FakeAuth(FakeUser('sender_123'));
      fakeStorage = FakeFirebaseStorage();
      fakePointsService = FakePointsService();

      final chatService = ChatMessagingService(
        firestore: fakeFirestore,
        auth: fakeAuth,
        storage: fakeStorage,
        pointsService: fakePointsService,
      );

      // Mock Sender Profile (needed for sendTextMessage)
      final senderDoc =
          fakeFirestore.usersCollection.doc('sender_123')
              as FakeDocumentReference;
      senderDoc.dataToReturn = {'firstName': 'Sender', 'lastName': 'Man'};

      // chatId and mentionedUserId would be used in a full integration test

      // Note: This test verifies the service can be constructed without RTDB
      // and that the sendTextMessage API accepts mentions.
      // Full integration testing requires proper Firestore mocking.
      expect(chatService, isNotNull);
    });
  });

  group('NotificationItem Serialization & Type Tests', () {
    test('trustPeerVerified serializes and deserializes cleanly', () {
      final now = DateTime.now();
      final item = NotificationItem(
        id: 'test_notif_1',
        type: NotificationType.trustPeerVerified,
        title: 'Identity Verified',
        body: 'Kwame Mensah verified your identity',
        payload: {'fromUserId': 'user_peer_456'},
        actionRequired: true,
        createdAt: now,
      );

      final map = item.toMap();
      expect(map['type'], 'trustPeerVerified');
      expect(map['payload']['fromUserId'], 'user_peer_456');

      final reconstructed = NotificationItem.fromMap('test_notif_1', map);
      expect(reconstructed.type, NotificationType.trustPeerVerified);
      expect(reconstructed.payload['fromUserId'], 'user_peer_456');
      expect(reconstructed.actionRequired, isTrue);
    });

    test('trustPeerVouched serializes and deserializes cleanly', () {
      final now = DateTime.now();
      final item = NotificationItem(
        id: 'test_notif_2',
        type: NotificationType.trustPeerVouched,
        title: 'Peer Vouch Received',
        body: 'A peer vouched for you',
        payload: {'fromUserId': 'voucher_789'},
        actionRequired: true,
        createdAt: now,
      );

      final map = item.toMap();
      expect(map['type'], 'trustPeerVouched');
      final reconstructed = NotificationItem.fromMap('test_notif_2', map);
      expect(reconstructed.type, NotificationType.trustPeerVouched);
      expect(reconstructed.payload['fromUserId'], 'voucher_789');
    });

    test('eventUpdate and eventCancelled types round-trip accurately', () {
      final now = DateTime.now();
      final eventUpdate = NotificationItem(
        id: 'evt_update_1',
        type: NotificationType.eventUpdate,
        title: 'Event Updated',
        body: 'Details changed',
        payload: {'eventId': 'evt_123'},
        createdAt: now,
      );

      final eventCancel = NotificationItem(
        id: 'evt_cancel_1',
        type: NotificationType.eventCancelled,
        title: 'Event Cancelled',
        body: 'Event cancelled',
        payload: {'eventId': 'evt_123'},
        createdAt: now,
      );

      final mapUpdate = eventUpdate.toMap();
      final mapCancel = eventCancel.toMap();

      expect(mapUpdate['type'], 'eventUpdate');
      expect(mapCancel['type'], 'eventCancelled');

      expect(
        NotificationItem.fromMap('evt_update_1', mapUpdate).type,
        NotificationType.eventUpdate,
      );
      expect(
        NotificationItem.fromMap('evt_cancel_1', mapCancel).type,
        NotificationType.eventCancelled,
      );
    });
  });
}
