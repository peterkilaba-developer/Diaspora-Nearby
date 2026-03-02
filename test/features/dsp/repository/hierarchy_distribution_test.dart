import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import '../../../utils/mocks.mocks.dart';

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
  
  // Data Snapshots
  late MockQuerySnapshotSimple mockUserPointsSnapshot;
  late MockQuerySnapshotSimple mockUsersSnapshot;

  setUp(() {
    mockFirestore = MockFirebaseFirestore();
    mockBatch = MockWriteBatch();
    mockCollection = MockCollectionReference<Map<String, dynamic>>();
    mockDocument = MockDocumentReference<Map<String, dynamic>>();
    
    repository = PointsRepository(mockFirestore);

    when(mockFirestore.batch()).thenReturn(mockBatch);
    when(mockFirestore.collection(any)).thenReturn(mockCollection);
    when(mockCollection.doc(any)).thenReturn(mockDocument);
    when(mockDocument.collection(any)).thenReturn(mockCollection);
    when(mockCollection.where(any, isEqualTo: anyNamed('isEqualTo'))).thenReturn(mockCollection);
  });

  test('User A (TZ -> UK) should have 2 burnt slots (No State levels)', () async {
    // Scenario: Arusha, Tanzania (2-level) -> London, England (2-level)
    // 1000 User Points. 100 per slot. 9 Slots Total.
    // Slots: Global, Africa, Tanzania, [EMPTY STATE], Arusha, Europe, England, [EMPTY STATE], London.
    // filledSlots = 7. emptySlots = 2.
    // totalBurned = 2 * 100 = 200.
    
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
        // NO home_state
        'home_city_arusha',
        
        'host_continent_europe',
        'host_country_gb-eng', // England
        // NO host_state
        'host_city_london'
      ],
    });

    // Mocks for get()
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
    
    // Writes Mocking
    when(mockOtherColl.doc(any)).thenReturn(mockDocument);
    when(mockDocument.collection(any)).thenReturn(mockOtherColl);

    await repository.syncTreasuryBalances();

    // Verify System Stats Update uses totalBurnedPoints correctly
    final capturedRefs = verify(mockBatch.set(captureAny, captureAny, any)).captured;
    
    bool verifiedBurn = false;
    for (int i = 0; i < capturedRefs.length; i += 2) {
      final data = capturedRefs[i+1] as Map<String, dynamic>;
      if (data.containsKey('totalBurnedPoints')) {
        // We expect totalBurnedPoints to be 200 for this user
        // Note: system_stats/dsp_supply updates 'totalBurnedPoints'
        if (data['totalBurnedPoints'] == 200) {
           verifiedBurn = true;
        }
      }
    }
    expect(verifiedBurn, isTrue, reason: 'Should burn 200 points for User A (2 empty slots)');
  });

  test('User B (KE -> DE) should have 1 burnt slot (Home State missing, Host State present)', () async {
     // Scenario: Nairobi, Kenya (2-level) -> Berlin, Germany (3-level)
     // 1000 User Points. 100 per slot.
     // Slots: Global, Africa, Kenya, [EMPTY STATE], Nairobi, Europe, Germany, Berlin (State), Berlin (City).
     // filledSlots = 8. emptySlots = 1.
     // totalBurned = 100.

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
        // NO home_state
        'home_city_nairobi',
        
        'host_continent_europe',
        'host_country_de',
        'host_state_berlin', // HAS State
        'host_city_berlin'
      ],
    });

    // Mocks
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
    
     // Writes Mocking
    when(mockOtherColl.doc(any)).thenReturn(mockDocument);
    when(mockDocument.collection(any)).thenReturn(mockOtherColl);

    await repository.syncTreasuryBalances();

    final capturedRefs = verify(mockBatch.set(captureAny, captureAny, any)).captured;
    
    bool verifiedBurn = false;
    for (int i = 0; i < capturedRefs.length; i += 2) {
      final data = capturedRefs[i+1] as Map<String, dynamic>;
      if (data.containsKey('totalBurnedPoints')) {
        if (data['totalBurnedPoints'] == 100) {
           verifiedBurn = true;
        }
      }
    }
    expect(verifiedBurn, isTrue, reason: 'Should burn 100 points for User B (1 empty slot)');
  });
}
