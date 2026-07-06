import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import '../../../utils/mocks.mocks.dart';

/// [v8] Treasury distribution math is exercised by `test/dsp_distribution_test.dart`.
/// The actual writes happen server-side in the `syncTreasuryBalances` Cloud
/// Function. The client just routes to the callable.
class RecordingFakeFirebaseFunctions extends Fake implements FirebaseFunctions {
  final List<String> calledNames = [];

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) {
    calledNames.add(name);
    return _FakeHttpsCallable();
  }
}

class _FakeHttpsCallable extends Fake implements HttpsCallable {
  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async =>
      _FakeHttpsCallableResult<T>();
}

class _FakeHttpsCallableResult<T> extends Fake
    implements HttpsCallableResult<T> {
  @override
  T get data => null as T;
}

void main() {
  late PointsRepository repository;
  late RecordingFakeFirebaseFunctions fakeFunctions;

  setUp(() {
    fakeFunctions = RecordingFakeFirebaseFunctions();
    repository = PointsRepository(MockFirebaseFirestore(), fakeFunctions);
  });

  test(
    'syncTreasuryBalances client uses the syncTreasuryBalances callable',
    () async {
      await repository.syncTreasuryBalances();
      expect(fakeFunctions.calledNames, ['syncTreasuryBalances']);
    },
  );
}
