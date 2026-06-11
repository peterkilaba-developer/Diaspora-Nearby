import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';

class _FakeFirebaseFunctions extends Fake implements FirebaseFunctions {}

void main() {
  test('DSP streams emit safe initial values immediately', () async {
    final repository = PointsRepository(
      FakeFirebaseFirestore(),
      _FakeFirebaseFunctions(),
    );

    expect(await repository.streamUserPoints('user').first, isNull);
    expect(await repository.streamGlobalSupply().first, 0);
    expect(await repository.streamGlobalMemberCount().first, 0);
    expect(await repository.streamInternalGdp().first, 0);
    expect(await repository.streamFiatGdpUsd().first, 0);
    expect(await repository.streamCorridors().first, isEmpty);
    expect(await repository.streamTransactionHistory('user').first, isEmpty);
  });
}
