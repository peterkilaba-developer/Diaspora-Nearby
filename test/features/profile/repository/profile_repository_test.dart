import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:diaspora_nearby/features/auth/services/session_service.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';

import '../../chat/services/chat_messaging_service_test.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('getUserProfile treats Firestore timeouts as recoverable', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final firestore = MockFirebaseFirestore();
    final users = MockCollectionReference();
    final userDoc = MockDocumentReference();

    when(firestore.collection('users')).thenReturn(users);
    when(users.doc('timeout-user')).thenReturn(userDoc);
    when(userDoc.get(any)).thenAnswer(
      (_) => Future.error(TimeoutException('Firestore unavailable')),
    );

    final repository = ProfileRepository(firestore, SessionService(prefs));

    await expectLater(
      repository.getUserProfile('timeout-user'),
      completion(isNull),
    );
    verify(userDoc.get(any)).called(2);
  });
}
