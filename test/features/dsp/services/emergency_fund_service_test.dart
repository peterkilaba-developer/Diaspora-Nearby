import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:diaspora_nearby/features/dsp/services/emergency_fund_service.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/dsp/models/user_points.dart';
import 'package:diaspora_nearby/features/trust/models/trust_data.dart';
import 'package:diaspora_nearby/features/dsp/models/emergency_fund_model.dart';
import 'package:diaspora_nearby/features/trust/repository/trust_repository.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/features/chat/models/chat.dart';
import 'package:diaspora_nearby/features/shared/models/location.dart';
import '../../../utils/mocks.mocks.dart';

// Manual Fakes to avoid build_runner issues
class FakeTrustRepository extends Fake implements TrustRepository {
  TrustData? _trustData;
  void setTrustData(TrustData? data) => _trustData = data;

  @override
  Future<TrustData?> getTrustData(String uid) async => _trustData;
}

class FakeChatRepository extends Fake implements ChatRepository {
  List<Chat> _chats = [];
  void setChats(List<Chat> chats) => _chats = chats;

  @override
  Future<List<Chat>> getUserChats() async => _chats;
}

void main() {
  late EmergencyFundService service;
  late MockProfileRepository mockProfileRepo;
  late MockPointsRepository mockPointsRepo;
  late FakeTrustRepository fakeTrustRepo;
  late FakeChatRepository fakeChatRepo;
  late FakeFirebaseFirestore fakeFirestore;

  setUp(() {
    mockProfileRepo = MockProfileRepository();
    mockPointsRepo = MockPointsRepository();
    fakeTrustRepo = FakeTrustRepository();
    fakeChatRepo = FakeChatRepository();
    fakeFirestore = FakeFirebaseFirestore();

    service = EmergencyFundService(
      fakeFirestore,
      mockProfileRepo,
      mockPointsRepo,
      fakeTrustRepo,
      fakeChatRepo,
    );
  });

  ProfileData createValidProfile(String uid) {
    return ProfileData(
      uid: uid,
      firstName: 'Test',
      lastName: 'User',
      phone: '1234567890',
      profileImage: 'http://image.com',
      homeLocation: const UserLocation(formattedAddress: 'Home', placeId: '1', city: 'City', country: 'Country', countryCode: 'US', geometry: UserLocationGeometry(location: UserLocationCoordinates(lat: 0, lng: 0))),
      hostLocation: const UserLocation(formattedAddress: 'Host', placeId: '2', city: 'City', country: 'Country', countryCode: 'US', geometry: UserLocationGeometry(location: UserLocationCoordinates(lat: 0, lng: 0))),
      bio: 'Bio',
      occupation: 'Dev',
      yearsInHostCountry: '5',
      industry: ['Tech'],
      profession: ['Engineer'],
      languages: ['English'],
      meetingPreferences: ['Online'],
      availability: ['Weekends'],
      servicesOffered: ['Coding'],
      lookingFor: ['Networking'],
      education: [Education(institution: 'Uni', degree: 'BS', graduationYear: '2020')],
      homeCountryCode: 'US',
      hostCountryCode: 'US',
    );
  }

  group('checkEligibility', () {
    const userId = 'user123';

    test('should return eligible when all criteria are met', () async {
      // 1. Profile Complete
      when(mockProfileRepo.getUserProfile(userId))
          .thenAnswer((_) async => createValidProfile(userId));

      // 2. Points >= 100,000
      when(mockPointsRepo.getUserPoints(userId)).thenAnswer((_) async =>
          UserPoints(userId: userId, totalPoints: 100000, availablePoints: 100000, currentStreak: 1, dailyMessageCount: 0, lastUpdated: DateTime.now(), signupDate: DateTime.now()));

      // 3. Trust Check (Deprecated - now ignored)
      fakeTrustRepo.setTrustData(
          TrustData(uid: userId, trustScore: 10, isVerified: false, level: TrustLevel.lowTrust, lastUpdated: DateTime.now()));

      // 4. Relationships (10 Family, 10 Friends)
      // Populate Fake Firestore
      final relationshipsRef = fakeFirestore
          .collection('users')
          .doc(userId)
          .collection('relationships');

      for (int i = 0; i < 10; i++) {
        await relationshipsRef.add({'type': 'Brother', 'status': 'active'});
      }
      for (int i = 0; i < 10; i++) {
        await relationshipsRef.add({'type': 'Friend', 'status': 'active'});
      }

      final result = await service.checkEligibility(userId);

      expect(result.isEligible, true);
      expect(result.isProfileComplete, true);
      expect(result.hasEnoughPoints, true);
      expect(result.hasEnoughTrust, true);
      expect(result.hasEnoughFamily, true);
      expect(result.hasEnoughFriends, true);
    });

    test('should return ineligible if points are insufficient', () async {
      when(mockProfileRepo.getUserProfile(userId))
          .thenAnswer((_) async => createValidProfile(userId));

      when(mockPointsRepo.getUserPoints(userId)).thenAnswer((_) async =>
          UserPoints(userId: userId, totalPoints: 50000, availablePoints: 50000, currentStreak: 1, dailyMessageCount: 0, lastUpdated: DateTime.now(), signupDate: DateTime.now()));

      fakeTrustRepo.setTrustData(
          TrustData(uid: userId, trustScore: 70, isVerified: true, vouchCount: 5, lastUpdated: DateTime.now()));

      // Relationships ok
      final relationshipsRef = fakeFirestore.collection('users').doc(userId).collection('relationships');
      for (int i = 0; i < 10; i++) {
        await relationshipsRef.add({'type': 'Sister', 'status': 'active'});
      }
      for (int i = 0; i < 10; i++) {
        await relationshipsRef.add({'type': 'Friend', 'status': 'active'});
      }

      final result = await service.checkEligibility(userId);

      expect(result.isEligible, false);
      expect(result.hasEnoughPoints, false);
    });

    test('should return ineligible if not enough family members', () async {
      when(mockProfileRepo.getUserProfile(userId)).thenAnswer((_) async => createValidProfile(userId));
      when(mockPointsRepo.getUserPoints(userId)).thenAnswer((_) async => UserPoints(userId: userId, totalPoints: 100000, availablePoints: 100000, currentStreak: 1, dailyMessageCount: 0, lastUpdated: DateTime.now(), signupDate: DateTime.now()));
      fakeTrustRepo.setTrustData(TrustData(uid: userId, trustScore: 70, isVerified: true, vouchCount: 5, lastUpdated: DateTime.now()));

      // Only 5 family members
      final relationshipsRef = fakeFirestore.collection('users').doc(userId).collection('relationships');
      for (int i = 0; i < 5; i++) {
        await relationshipsRef.add({'type': 'Sister', 'status': 'active'});
      }
      for (int i = 0; i < 10; i++) {
        await relationshipsRef.add({'type': 'Friend', 'status': 'active'});
      }

      final result = await service.checkEligibility(userId);

      expect(result.isEligible, false);
      expect(result.hasEnoughFamily, false);
    });
  });

  group('Membership', () {
    const userId = 'user123';

    test('streamMembership should emit membership updates', () async {
      final membershipRef = fakeFirestore.collection('emergency_fund_memberships').doc(userId);
      
      final membership = EmergencyFundMembership(
        userId: userId,
        country: 'US',
        status: MembershipStatus.active,
        joinedDate: DateTime.now(),
        annualContribution: 100,
        supportNumber: '12345',
        nextPaymentDate: DateTime.now().add(const Duration(days: 365)), // Ensure this is set for test consistency
      );

      await membershipRef.set(membership.toMap());

      expect(service.streamMembership(userId), emits(isA<EmergencyFundMembership>()));
    });

    test('requestProxyAndJoin should create pending membership', () async {
      await service.requestProxyAndJoin(
        userId: userId,
        country: 'US',
        proxyUserId: 'proxy123',
        coveredFamilyMembers: ['fam1', 'fam2'],
      );

      final doc = await fakeFirestore.collection('emergency_fund_memberships').doc(userId).get();
      expect(doc.exists, true);
      final data = doc.data()!;
      expect(data['status'], MembershipStatus.pending_proxy.name);
      expect(data['proxyUserId'], 'proxy123');
      expect(data['coveredFamilyMembers'], ['fam1', 'fam2']);
    });
    test('submitClaim should create a claim with correct category', () async {
      await service.submitClaim(
        userId: userId,
        type: EmergencyType.medical,
        beneficiaryName: 'Beneficiary',
        relationship: 'Brother',
        incidentDate: DateTime.now(),
        description: 'Medical emergency',
      );

      final snapshot = await fakeFirestore.collection('emergency_fund_claims').get();
      expect(snapshot.docs.length, 1);
      final data = snapshot.docs.first.data();
      expect(data['type'], 'medical'); // stored as string name of enum usually, check model
      expect(data['userId'], userId);
      expect(data['beneficiaryName'], 'Beneficiary');
    });
  });

}
