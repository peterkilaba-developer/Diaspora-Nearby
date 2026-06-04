import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/dsp/models/bereavement_model.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/profile/models/relationship.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import 'package:diaspora_nearby/features/trust/repository/trust_repository.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:uuid/uuid.dart';

final bereavementServiceProvider = Provider<BereavementService>((ref) {
  return BereavementService(
    FirebaseFirestore.instance,
    ref.read(profileRepositoryProvider),
    ref.read(pointsRepositoryProvider),
    ref.read(trustRepositoryProvider),
    ref.read(chatRepositoryProvider),
  );
});

class EligibilityResult {
  final bool isProfileComplete;
  final bool isProfileVerified; // Checked via TrustData
  final bool hasEnoughTrust;
  final bool hasEnoughRelatives;

  bool get isEligible =>
      isProfileComplete && hasEnoughTrust && hasEnoughRelatives;

  EligibilityResult({
    required this.isProfileComplete,
    required this.isProfileVerified,
    required this.hasEnoughTrust,
    required this.hasEnoughRelatives,
  });
}

class BereavementService {
  final FirebaseFirestore _firestore;
  final ProfileRepository _profileRepo;
  // ignore: unused_field
  final PointsRepository _pointsRepo;
  final TrustRepository _trustRepo;
  final ChatRepository _chatRepo;
  final _uuid = const Uuid();

  BereavementService(
    this._firestore,
    this._profileRepo,
    this._pointsRepo,
    this._trustRepo,
    this._chatRepo,
  );

  // --- Eligibility ---

  Future<EligibilityResult> checkEligibility(String userId) async {
    // 1. Profile Check
    final profile = await _profileRepo.getUserProfile(userId);
    final isProfileComplete = profile?.isComplete ?? false;

    // 2. Trust Check (Verified & Score >= 67)
    final trust = await _trustRepo.getTrustData(userId);
    final isVerified = trust?.isVerified ?? false;
    final hasEnoughTrust = (trust?.trustScore ?? 0) >= 67;

    // 3. Relatives Check (>= 2)
    final relationshipsSnap = await _firestore
        .collection('users')
        .doc(userId)
        .collection('relationships')
        .where('status', isEqualTo: 'active')
        .get();

    final hasEnoughRelatives = relationshipsSnap.docs.length >= 2;

    return EligibilityResult(
      isProfileComplete: isProfileComplete,
      isProfileVerified: isVerified,
      hasEnoughTrust: hasEnoughTrust,
      hasEnoughRelatives: hasEnoughRelatives,
    );
  }

  // --- Membership ---

  Stream<BereavementMembership?> streamMembership(String userId) {
    return _firestore
        .collection('bereavement_memberships')
        .doc(userId)
        .snapshots()
        .map((doc) {
          if (doc.exists && doc.data() != null) {
            return BereavementMembership.fromMap(doc.data()!);
          }
          return null;
        });
  }

  // Helper to fetch relationships to auto-populate
  Future<List<Relationship>> getQualifiedRelatives(String userId) async {
    try {
      final snap = await _firestore
          .collection('users')
          .doc(userId)
          .collection('relationships')
          .where('status', isEqualTo: 'active')
          .get();

      return snap.docs
          .map((doc) => Relationship.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      return [];
    }
  }

  // Helper to fetch potential proxies from active DM chats (Verified Users Only)
  Future<List<ProfileData>> getPotentialProxies(String userId) async {
    try {
      final chats = await _chatRepo.getUserChats();
      final directChats = chats.where((c) => c.isDirect).toList();

      final potentialIds = directChats
          .map((c) => c.getOtherParticipantId(userId))
          .where((id) => id != null && id.isNotEmpty)
          .cast<String>()
          .toSet() // Unique
          .toList();

      if (potentialIds.isEmpty) return [];

      // Fetch profiles
      final profilesFutures = potentialIds.map(
        (id) => _profileRepo.getUserProfile(id),
      );
      final profiles = await Future.wait(profilesFutures);

      // Filter by Verification (and remove nulls)
      final verifiedProfiles = <ProfileData>[];
      for (final p in profiles) {
        if (p == null || p.uid == null) continue;

        final trust = await _trustRepo.getTrustData(p.uid!);
        if (trust != null && trust.isVerified) {
          verifiedProfiles.add(p);
        }
      }

      return verifiedProfiles;
    } catch (e) {
      return [];
    }
  }

  // Step 1: Request Proxy
  Future<void> requestProxyAndJoin({
    required String userId,
    required String country,
    required String proxyUserId,
    required List<String> coveredFamilyMembers,
  }) async {
    // Check if membership already exists? If so, update.

    final membership = BereavementMembership(
      userId: userId,
      country: country,
      status: MembershipStatus.pending_proxy,
      joinedDate: DateTime.now(),
      annualContribution: 100.00, // Fixed: Corrected value to $100
      supportNumber: 'DN-BER-${_uuid.v4().substring(0, 8).toUpperCase()}',
      proxyUserId: proxyUserId,
      proxyStatus: ProxyStatus.pending,
      coveredFamilyMembers: coveredFamilyMembers,
    );

    await _firestore
        .collection('bereavement_memberships')
        .doc(userId)
        .set(membership.toMap());

    // Logic to notify proxy would go here
  }

  // Step 2: Proxy Accepts (Called by Proxy User)
  Future<void> acceptProxyRequest(
    String memberUserId,
    String proxyUserId,
  ) async {
    // Logic to validate proxy user would go here

    await _firestore
        .collection('bereavement_memberships')
        .doc(memberUserId)
        .update({
          'proxyStatus': ProxyStatus.accepted.name,
          'status': MembershipStatus.pending_payment.name,
        });
  }

  /// Whether payment processing is in beta (free) mode.
  /// Set to `false` once Stripe/M-Pesa integration is complete.
  static const bool isBetaMode = true;

  // Step 3: Process Payment
  // [BETA] Auto-approves membership as Free Beta Access.
  // When isBetaMode is false, this should call a Cloud Function that
  // processes payment via Stripe/M-Pesa before activating membership.
  Future<void> completeMembershipPayment(String userId) async {
    if (!isBetaMode) {
      // TODO: Call Cloud Function to process real payment
      // e.g., final result = await FirebaseFunctions.instance
      //   .httpsCallable('processBereavementPayment')
      //   .call({'userId': userId});
      throw UnimplementedError(
        'Real payment processing not yet integrated. '
        'Set isBetaMode = true for beta access.',
      );
    }

    // Beta mode: auto-approve without payment
    await _firestore.collection('bereavement_memberships').doc(userId).update({
      'status': MembershipStatus.active.name,
      'isBetaAccess': true,
      'nextPaymentDate': Timestamp.fromDate(
        DateTime.now().add(const Duration(days: 365)),
      ),
    });
  }

  // --- Claims ---

  Stream<List<BereavementClaim>> streamUserClaims(String userId) {
    return _firestore
        .collection('bereavement_claims')
        .where('userId', isEqualTo: userId)
        .orderBy('submittedDate', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => BereavementClaim.fromMap(doc.data()))
              .toList();
        });
  }

  Future<void> submitClaim({
    required String userId,
    required String deceasedName,
    required String relationship,
    required DateTime dateOfDeath,
    required String description,
  }) async {
    final claimId = _uuid.v4();
    final claim = BereavementClaim(
      id: claimId,
      userId: userId,
      deceasedName: deceasedName,
      relationship: relationship,
      dateOfDeath: dateOfDeath,
      status: ClaimStatus.submitted,
      submittedDate: DateTime.now(),
      description: description,
    );

    await _firestore
        .collection('bereavement_claims')
        .doc(claimId)
        .set(claim.toMap());
  }

  // --- Helpers ---
  Future<ProfileData?> getUserProfile(String uid) =>
      _profileRepo.getUserProfile(uid);
}
