import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import '../../../utils/mocks.mocks.dart';

class FakeFirebaseFunctions extends Fake implements FirebaseFunctions {}

// Create a simple mock for QuerySnapshot since generated mocks might carry generics baggage
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
  late MockQuerySnapshotSimple mockUserPointsSnapshot;
  late MockQuerySnapshotSimple mockUsersSnapshot;
  late MockQueryDocumentSnapshotSimple mockUserPointDoc;
  late MockQueryDocumentSnapshotSimple mockUserDoc;

  setUp(() {
    mockFirestore = MockFirebaseFirestore();
    mockBatch = MockWriteBatch();
    mockCollection = MockCollectionReference<Map<String, dynamic>>();
    mockDocument = MockDocumentReference<Map<String, dynamic>>();
    mockUserPointsSnapshot = MockQuerySnapshotSimple();
    mockUsersSnapshot = MockQuerySnapshotSimple();
    mockUserPointDoc = MockQueryDocumentSnapshotSimple();
    mockUserDoc = MockQueryDocumentSnapshotSimple();

    repository = PointsRepository(mockFirestore, FakeFirebaseFunctions());

    when(mockFirestore.batch()).thenReturn(mockBatch);
    // Generic matchers for ALL collections
    when(mockFirestore.collection(any)).thenReturn(mockCollection);
    when(mockCollection.doc(any)).thenReturn(mockDocument);
    // Nested collections (e.g. communities/ID/treasury/current)
    when(mockDocument.collection(any)).thenReturn(mockCollection);
    
    when(mockCollection.where(any, isEqualTo: anyNamed('isEqualTo'))).thenReturn(mockCollection);
  });

  test('syncTreasuryBalances calculates correct expansion (1:1 model)', () async {
    // 1. Setup Data
    // User has 1000 points
    when(mockUserPointDoc.id).thenReturn('user1');
    when(mockUserPointDoc.data()).thenReturn({
      'totalPoints': 1000,
      'trustScore': 100,
    });
    
    // User belongs to Global + TZ
    when(mockUserDoc.id).thenReturn('user1');
    when(mockUserDoc.data()).thenReturn({
      'communityMemberships': ['global_community', 'home_country_tz'],
    });

    // Mock Specific Returns
    // We need to distinguish between user_points/users get() calls and other calls.
    // Since mockFirestore.collection(any) returns the SAME mockCollection object,
    // we can control what mockCollection.get() returns.
    
    // BUT syncTreasuryBalances calls get() on 'users', then get() on 'user_points'.
    // If we return mockUsersSnapshot first, then mockUserPointsSnapshot second?
    // This is brittle.
    
    // Better approach: Stub specific collections. 
    final mockUserPointsColl = MockCollectionReference<Map<String, dynamic>>();
    final mockUsersColl = MockCollectionReference<Map<String, dynamic>>();
    final mockOtherColl = MockCollectionReference<Map<String, dynamic>>();
    
    // We must stub the specific string args to take precedence over 'any'
    when(mockFirestore.collection('user_points')).thenReturn(mockUserPointsColl);
    when(mockFirestore.collection('users')).thenReturn(mockUsersColl);
    
    // For all other collections (system_stats, communities, governance), use generic mockOtherColl
    when(mockFirestore.collection(argThat(isNot(isIn(['user_points', 'users']))))).thenReturn(mockOtherColl);
    // Actually, just let 'any' handle them if we don't define specific ones, but we defined 'any' in setUp.
    // Overriding specific args works in Mockito.
    
    // Setup get() returns
    when(mockUserPointsColl.get()).thenAnswer((_) async => mockUserPointsSnapshot);
    when(mockUsersColl.get()).thenAnswer((_) async => mockUsersSnapshot);
    
    when(mockUserPointsSnapshot.docs).thenReturn([mockUserPointDoc]);
    when(mockUsersSnapshot.docs).thenReturn([mockUserDoc]); // This list is used for the lookup map
    
    // Prepare nested mocks for writes
    when(mockOtherColl.doc(any)).thenReturn(mockDocument);
    when(mockDocument.collection(any)).thenReturn(mockOtherColl);

    // 2. Run Sync
    await repository.syncTreasuryBalances();

    // 3. Verify
    
    // A. Verify Total Minted = 2000 (1000 User + 1000 Treasury) in system_stats/dsp_supply
    // We capture all batch.set calls
    
    final capturedRefs = verify(mockBatch.set(captureAny, captureAny, any)).captured;
    
    bool foundSupplyUpdate = false;
    bool foundGlobalTreasuryUpdate = false;
    
    for (int i = 0; i < capturedRefs.length; i += 2) {
      // final ref = capturedRefs[i]; 
      final data = capturedRefs[i+1] as Map<String, dynamic>;
      
      if (data.containsKey('totalMinted')) {
         print('Found Supply Update: $data');
         if (data['totalMinted'] == 2000) foundSupplyUpdate = true;
      }
      
      // B. Verify Community Treasury Logic
      // Slot Match = 1000 * 0.1 = 100 per slot
      // Member Points = 1000
      // Cumulative Earnings = 1000 (Member) + 100 (Treasury) = 1100
      
      if (data.containsKey('cumulativeEarnings')) {
        print('Found Treasury Update: $data');
        if (data['cumulativeEarnings'] == 1100 && 
            data['memberPoints'] == 1000 && 
            data['points'] == 100) {
             foundGlobalTreasuryUpdate = true;
        }
      }
    }
    
    expect(foundSupplyUpdate, isTrue, reason: 'Should update totalMinted to 2000');
    expect(foundGlobalTreasuryUpdate, isTrue, reason: 'Should update treasury with 1.1x cumulative earnings');
  });
}
