import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/shared/models/location.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:diaspora_nearby/features/auth/services/session_service.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';

import '../../chat/services/chat_messaging_service_test.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'signup saves rule-compatible public summaries and private locations',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final firestore = FakeFirebaseFirestore();
      final repository = ProfileRepository(firestore, SessionService(prefs));
      const location = UserLocation(
        formattedAddress: 'Dar es Salaam, Tanzania',
        placeId: 'private-place-id',
        city: 'Dar es Salaam',
        country: 'Tanzania',
        countryCode: 'TZ',
        geometry: UserLocationGeometry(
          location: UserLocationCoordinates(lat: -6.8, lng: 39.2),
        ),
      );
      final profile = ProfileData(
        uid: 'signup-user',
        firstName: 'Test',
        lastName: 'User',
        phone: '+255123456789',
        profileImage: 'https://example.com/photo.jpg',
        homeLocation: location,
        hostLocation: location,
        showCurrentLocationName: true,
      );
      await repository.saveUserProfile('signup-user', profile);
      final publicData = (await firestore.doc('users/signup-user').get())
          .data()!;
      final privateData =
          (await firestore.doc('user_private/signup-user').get()).data()!;
      for (final key in ['homeLocation', 'hostLocation']) {
        final summary = publicData[key] as Map<String, dynamic>;
        expect(summary.containsKey('place_id'), isFalse);
        expect(summary.containsKey('geometry'), isFalse);
        expect(UserLocation.fromJson(summary).city, location.city);
        expect(UserLocation.fromJson(summary).placeId, isEmpty);
        expect(privateData[key], location.toJson());
      }
      expect(publicData.containsKey('businessProfile'), isFalse);
      expect(publicData.containsKey('cityVisibilityForfeited'), isFalse);
      expect(publicData.containsKey('phone'), isFalse);
      expect(publicData.containsKey('isBanned'), isFalse);
      expect(privateData['phone'], profile.phone);

      // Repeated completion must preserve server-owned state on existing users.
      await firestore.doc('users/signup-user').update({
        'trustScore': 42,
        'cityVisibilityForfeited': true,
      });
      await repository.saveUserProfile('signup-user', profile);
      final saved = (await firestore.doc('users/signup-user').get()).data()!;
      expect(saved['trustScore'], 42);
      expect(saved['cityVisibilityForfeited'], isTrue);
    },
  );

  test(
    'signup with city visibility off and legacy field cleanup on merged writes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final firestore = FakeFirebaseFirestore();
      final repository = ProfileRepository(firestore, SessionService(prefs));

      // Seed a legacy document containing place_id, geometry, currentLocation, and explicit nulls
      await firestore.doc('users/legacy-user').set({
        'firstName': 'Legacy',
        'lastName': 'User',
        'businessProfile': null,
        'cityVisibilityForfeited': null,
        'currentCity': 'Dar es Salaam',
        'currentState': 'Dar es Salaam',
        'currentCountryCode': 'TZ',
        'currentLocation': {
          'formatted_address': 'Dar es Salaam, Tanzania',
          'city': 'Dar es Salaam',
          'country': 'Tanzania',
          'country_code': 'TZ',
          'place_id': 'legacy-current-id',
          'geometry': {
            'location': {'lat': -6.8, 'lng': 39.2},
          },
        },
        'homeLocation': {
          'formatted_address': 'Dar es Salaam, Tanzania',
          'city': 'Dar es Salaam',
          'country': 'Tanzania',
          'country_code': 'TZ',
          'place_id': 'legacy-place-id',
          'geometry': {
            'location': {'lat': -6.8, 'lng': 39.2},
          },
        },
        'hostLocation': {
          'formatted_address': 'Nairobi, Kenya',
          'city': 'Nairobi',
          'country': 'Kenya',
          'country_code': 'KE',
          'place_id': '',
          'geometry': {
            'location': {'lat': -1.29, 'lng': 36.82},
          },
        },
      });

      const homeLoc = UserLocation(
        formattedAddress: 'Dar es Salaam, Tanzania',
        placeId: 'private-home-id',
        city: 'Dar es Salaam',
        country: 'Tanzania',
        countryCode: 'TZ',
        geometry: UserLocationGeometry(
          location: UserLocationCoordinates(lat: -6.8, lng: 39.2),
        ),
      );
      const hostLoc = UserLocation(
        formattedAddress: 'Nairobi, Kenya',
        placeId: 'private-host-id',
        city: 'Nairobi',
        country: 'Kenya',
        countryCode: 'KE',
        geometry: UserLocationGeometry(
          location: UserLocationCoordinates(lat: -1.29, lng: 36.82),
        ),
      );

      final profile = ProfileData(
        uid: 'legacy-user',
        firstName: 'Legacy',
        lastName: 'User',
        phone: '+255987654321',
        profileImage: 'https://example.com/photo.jpg',
        homeLocation: homeLoc,
        hostLocation: hostLoc,
        showCurrentLocationName: false,
      );

      await repository.saveUserProfile('legacy-user', profile);
      final publicData = (await firestore.doc('users/legacy-user').get())
          .data()!;
      final privateData =
          (await firestore.doc('user_private/legacy-user').get()).data()!;

      expect(publicData.containsKey('businessProfile'), isFalse);
      expect(publicData.containsKey('cityVisibilityForfeited'), isFalse);
      expect(publicData.containsKey('currentLocation'), isFalse);
      expect(publicData['showCurrentLocationName'], isFalse);
      expect(publicData.containsKey('currentCity'), isFalse);
      expect(publicData.containsKey('currentState'), isFalse);
      expect(publicData.containsKey('currentCountryCode'), isFalse);

      for (final key in ['homeLocation', 'hostLocation']) {
        final summary = publicData[key] as Map<String, dynamic>;
        expect(summary.containsKey('place_id'), isFalse);
        expect(summary.containsKey('geometry'), isFalse);
      }
      expect(privateData['homeLocation'], homeLoc.toJson());
      expect(privateData['hostLocation'], hostLoc.toJson());

      // Verify updateHostLocation also splits public summary vs private pastLocations
      const newHost = UserLocation(
        formattedAddress: 'Kampala, Uganda',
        placeId: 'private-kampala-id',
        city: 'Kampala',
        country: 'Uganda',
        countryCode: 'UG',
        geometry: UserLocationGeometry(
          location: UserLocationCoordinates(lat: 0.34, lng: 32.58),
        ),
      );
      await repository.updateHostLocation(
        'legacy-user',
        newHost,
        'Uganda',
        'UG',
      );
      final updatedPublic = (await firestore.doc('users/legacy-user').get())
          .data()!;
      final updatedPrivate =
          (await firestore.doc('user_private/legacy-user').get()).data()!;
      final updatedHostSummary =
          updatedPublic['hostLocation'] as Map<String, dynamic>;
      expect(updatedHostSummary.containsKey('place_id'), isFalse);
      expect(updatedHostSummary.containsKey('geometry'), isFalse);
      expect(updatedHostSummary['city'], 'Kampala');
      expect(updatedPublic.containsKey('pastLocations'), isFalse);
      expect(updatedPrivate['hostLocation'], newHost.toJson());
      expect((updatedPrivate['pastLocations'] as List).length, 1);
    },
  );

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
