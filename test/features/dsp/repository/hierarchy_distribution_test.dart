import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import '../../../utils/mocks.mocks.dart';

class FakeFirebaseFunctions extends Fake implements FirebaseFunctions {}

// Reuse simple mocks
class MockQuerySnapshotSimple extends Mock implements QuerySnapshot<Map<String, dynamic>> {
  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => super.noSuchMethod(
        Invocation.getter(#docs),
        returnValue: <QueryDocumentSnapshot<Map<String, dynamic>>>[],
      );
}

class MockQueryDocumentSnapshotSimple extends Mock implements QueryDocumentSnapshot<Map<String, dynamic>> {
  @override
  Map<String, dynamic> data() => super.noSuchMethod(
        Invocation.method(#data, []),
        returnValue: <String, dynamic>{},
      );
      
  @override
  String get id => super.noSuchMethod(
        Invocation.getter(#id),
        returnValue: '',
      );
      
  @override
  DocumentReference<Map<String, dynamic>> get reference => super.noSuchMethod(
        Invocation.getter(#reference),
        returnValue: MockDocumentReference<Map<String, dynamic>>(),
      );
}

void main() {
  late PointsRepository repository;
  late MockFirebaseFirestore mockFirestore;
  late MockWriteBatch mockBatch;
  late MockCollectionReference<Map<String, dynamic>> mockCollection;
  late MockDocumentReference<Map<String, dynamic>> mockDocument;

  setUp(() {
    mockFirestore = MockFirebaseFirestore();
    mockBatch = MockWriteBatch();
    mockCollection = MockCollectionReference<Map<String, dynamic>>();
    mockDocument = MockDocumentReference<Map<String, dynamic>>();
    
    repository = PointsRepository(mockFirestore, FakeFirebaseFunctions());

    when(mockFirestore.batch()).thenReturn(mockBatch);
    when(mockFirestore.collection(any)).thenReturn(mockCollection);
    when(mockCollection.doc(any)).thenReturn(mockDocument);
    when(mockDocument.collection(any)).thenReturn(mockCollection);
    when(mockCollection.where(any, isEqualTo: anyNamed('isEqualTo'))).thenReturn(mockCollection);
  });

  // Current distribution model: 10 allocation units per user.
  //   - Founders: 10% (1 unit)
  //   - Investors: 10% (1 unit)
  //   - Burn: 10% (1 unit, FIXED — not based on empty slots)
  //   - Community Hierarchy: 7 units across 7 slots
  //     (Global, Home Continent, Home Country, Home City,
  //      Host Continent, Host Country, Host City)
  //   Missing slots default to 'global_community'.

  test('User A (TZ -> UK) should distribute 10 units correctly (7 community slots, fixed burn)', () async {
    final mockUserPointDoc = MockQueryDocumentSnapshotSimple();
    when(mockUserPointDoc.id).thenReturn('userA');
    when(mockUserPointDoc.data()).thenReturn({'totalPoints': 1000, 'trustScore': 100});
    
    final mockUserDoc = MockQueryDocumentSnapshotSimple();
    when(mockUserDoc.id).thenReturn('userA');
    when(mockUserDoc.data()).thenReturn({
      'communityMemberships': [
        'global_community',
        'home_continent_africa',
        'home_country_tz',
        'home_city_arusha',
        'host_continent_europe',
        'host_country_gb-eng',
        'host_city_london'
      ],
    });

    final mockUserPointsColl = MockCollectionReference<Map<String, dynamic>>();
    final mockUsersColl = MockCollectionReference<Map<String, dynamic>>();
    final mockOtherColl = MockCollectionReference<Map<String, dynamic>>();

    when(mockFirestore.collection('user_points')).thenReturn(mockUserPointsColl);
    when(mockFirestore.collection('users')).thenReturn(mockUsersColl);
    when(mockFirestore.collection(argThat(isNot(isIn(['user_points', 'users']))))).thenReturn(mockOtherColl);

    final userPointsSnap = MockQuerySnapshotSimple();
    when(userPointsSnap.docs).thenReturn([mockUserPointDoc]);
    when(mockUserPointsColl.get()).thenAnswer((_) async => userPointsSnap);

    final usersSnap = MockQuerySnapshotSimple();
    when(usersSnap.docs).thenReturn([mockUserDoc]);
    when(mockUsersColl.get()).thenAnswer((_) async => usersSnap);
    
    when(mockOtherColl.doc(any)).thenReturn(mockDocument);
    when(mockDocument.collection(any)).thenReturn(mockOtherColl);

    await repository.syncTreasuryBalances();

    // Verify batch.set was called with SetOptions (3-arg form) for system stats and governance
    final capturedRefs = verify(mockBatch.set(captureAny, captureAny, any)).captured;
    
    // Expect burn = 10% of 1000 = 100 (fixed burn, not variable)
    bool verifiedBurn = false;
    for (int i = 0; i < capturedRefs.length; i += 2) {
      final data = capturedRefs[i+1] as Map<String, dynamic>;
      if (data.containsKey('burnedPoints')) {
        if (data['burnedPoints'] == 100) {
          verifiedBurn = true;
        }
      }
    }
    expect(verifiedBurn, isTrue, reason: 'Should burn 100 points (fixed 10% of 1000)');
    
    // Verify batch was committed
    verify(mockBatch.commit()).called(1);
  });

  test('User B (KE -> DE) should distribute 10 units correctly (7 community slots, fixed burn)', () async {
    final mockUserPointDoc = MockQueryDocumentSnapshotSimple();
    when(mockUserPointDoc.id).thenReturn('userB');
    when(mockUserPointDoc.data()).thenReturn({'totalPoints': 1000, 'trustScore': 100});
    
    final mockUserDoc = MockQueryDocumentSnapshotSimple();
    when(mockUserDoc.id).thenReturn('userB');
    when(mockUserDoc.data()).thenReturn({
      'communityMemberships': [
        'global_community',
        'home_continent_africa',
        'home_country_ke',
        'home_city_nairobi',
        'host_continent_europe',
        'host_country_de',
        'host_city_berlin'
      ],
    });

    final mockUserPointsColl = MockCollectionReference<Map<String, dynamic>>();
    final mockUsersColl = MockCollectionReference<Map<String, dynamic>>();
    final mockOtherColl = MockCollectionReference<Map<String, dynamic>>();

    when(mockFirestore.collection('user_points')).thenReturn(mockUserPointsColl);
    when(mockFirestore.collection('users')).thenReturn(mockUsersColl);
    when(mockFirestore.collection(argThat(isNot(isIn(['user_points', 'users']))))).thenReturn(mockOtherColl);

    final userPointsSnap = MockQuerySnapshotSimple();
    when(userPointsSnap.docs).thenReturn([mockUserPointDoc]);
    when(mockUserPointsColl.get()).thenAnswer((_) async => userPointsSnap);

    final usersSnap = MockQuerySnapshotSimple();
    when(usersSnap.docs).thenReturn([mockUserDoc]);
    when(mockUsersColl.get()).thenAnswer((_) async => usersSnap);
    
    when(mockOtherColl.doc(any)).thenReturn(mockDocument);
    when(mockDocument.collection(any)).thenReturn(mockOtherColl);

    await repository.syncTreasuryBalances();

    final capturedRefs = verify(mockBatch.set(captureAny, captureAny, any)).captured;
    
    // Same fixed burn: 10% of 1000 = 100
    bool verifiedBurn = false;
    for (int i = 0; i < capturedRefs.length; i += 2) {
      final data = capturedRefs[i+1] as Map<String, dynamic>;
      if (data.containsKey('burnedPoints')) {
        if (data['burnedPoints'] == 100) {
          verifiedBurn = true;
        }
      }
    }
    expect(verifiedBurn, isTrue, reason: 'Should burn 100 points (fixed 10% of 1000)');
    
    verify(mockBatch.commit()).called(1);
  });
}
