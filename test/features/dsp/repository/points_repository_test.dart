import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import '../../../utils/mocks.mocks.dart';
import '../../../utils/test_data.dart';

/// Records every httpsCallable invocation so tests can assert which Cloud
/// Function was called. All callables succeed with empty data.
class RecordingFakeFirebaseFunctions extends Fake implements FirebaseFunctions {
  final List<String> calledNames = [];

  @override
  HttpsCallable httpsCallable(
    String name, {
    HttpsCallableOptions? options,
  }) {
    calledNames.add(name);
    return _FakeHttpsCallable();
  }
}

class _FakeHttpsCallable extends Fake implements HttpsCallable {
  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async {
    return _FakeHttpsCallableResult<T>();
  }
}

class _FakeHttpsCallableResult<T> extends Fake implements HttpsCallableResult<T> {
  @override
  T get data => null as T;
}

void main() {
  late PointsRepository repository;
  late MockFirebaseFirestore mockFirestore;
  late RecordingFakeFirebaseFunctions fakeFunctions;

  setUp(() {
    mockFirestore = MockFirebaseFirestore();
    fakeFunctions = RecordingFakeFirebaseFunctions();
    repository = PointsRepository(mockFirestore, fakeFunctions);
  });

  group('PointsRepository', () {
    const userId = TestData.userId1;

    // [v8] initializeUserPoints no longer writes to Firestore from the client.
    // It routes through the `initializeUserPoints` Cloud Function (which has
    // its own server-side test coverage). These tests verify the client is
    // calling the right callable.

    test('initializeUserPoints invokes the initializeUserPoints Cloud Function', () async {
      await repository.initializeUserPoints(userId);
      expect(fakeFunctions.calledNames, ['initializeUserPoints']);
    });
  });
}
