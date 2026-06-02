import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
// ignore: unused_import
import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import '../../../utils/mocks.mocks.dart';
import '../../../utils/test_data.dart';

class FakeFirebaseFunctions extends Fake implements FirebaseFunctions {}

void main() {
  late PointsRepository repository;
  late MockFirebaseFirestore mockFirestore;
  late MockWriteBatch mockBatch;
  late MockCollectionReference<Map<String, dynamic>> mockCollection;
  late MockDocumentReference<Map<String, dynamic>> mockDocument;
  late MockDocumentSnapshot<Map<String, dynamic>> mockSnapshot;

  setUp(() {
    mockFirestore = MockFirebaseFirestore();
    mockBatch = MockWriteBatch();
    mockCollection = MockCollectionReference<Map<String, dynamic>>();
    mockDocument = MockDocumentReference<Map<String, dynamic>>();
    mockSnapshot = MockDocumentSnapshot<Map<String, dynamic>>();

    repository = PointsRepository(mockFirestore, FakeFirebaseFunctions());

    when(mockFirestore.batch()).thenReturn(mockBatch);
    when(mockFirestore.collection(any)).thenReturn(mockCollection);
    when(mockCollection.doc(any)).thenReturn(mockDocument);
    when(mockCollection.doc()).thenReturn(mockDocument);
    when(mockDocument.collection(any)).thenReturn(mockCollection);
    when(mockDocument.id).thenReturn('mock-id');
  });

  group('PointsRepository', () {
    const userId = TestData.userId1;

    test(
      'initializeUserPoints should create points doc and award welcome bonus when missing',
      () async {
        // 1. First call: user_points/{userId}.get() -> exists: false
        // 2. Second call: users/{userId}.get() -> data: {'homeCountryCode': 'TZ'}

        when(mockDocument.get()).thenAnswer((_) async => mockSnapshot);
        when(mockSnapshot.exists).thenReturn(false);
        when(mockSnapshot.data()).thenReturn({'homeCountryCode': 'TZ'});

        await repository.initializeUserPoints(userId);

        // Verify batch was committed
        verify(mockBatch.commit()).called(1);

        // Verify batch.set was called for user_points and welcome bonus
        verify(mockBatch.set(any, any)).called(2);
      },
    );

    test('initializeUserPoints should skip if already initialized', () async {
      when(mockDocument.get()).thenAnswer((_) async => mockSnapshot);
      when(mockSnapshot.exists).thenReturn(true);

      await repository.initializeUserPoints(userId);

      // Verify no batch operations or commit
      verifyNever(mockFirestore.batch());
      verifyNever(mockBatch.commit());
    });
  });
}
