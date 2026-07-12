import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/dsp/models/emergency_fund_model.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/profile/models/relationship.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import 'package:diaspora_nearby/features/trust/repository/trust_repository.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/features/notifications/models/notification_item.dart';
import 'package:diaspora_nearby/features/notifications/repository/notifications_repository.dart';
import 'package:uuid/uuid.dart';

final emergencyFundServiceProvider = Provider<EmergencyFundService>((ref) {
  return EmergencyFundService(
    FirebaseFirestore.instance,
    ref.read(profileRepositoryProvider),
    ref.read(pointsRepositoryProvider),
    ref.read(trustRepositoryProvider),
    ref.read(chatRepositoryProvider),
    ref.read(notificationsRepositoryProvider),
  );
});

class EligibilityResult {
  final bool isProfileComplete;
  final bool hasEnoughQrScans;
  final int qrScanCount;
  static const int requiredQrScans = 10;

  bool get isEligible => isProfileComplete && hasEnoughQrScans;

  EligibilityResult({
    required this.isProfileComplete,
    required this.hasEnoughQrScans,
    required this.qrScanCount,
  });
}

class EmergencyFundService {
  final FirebaseFirestore _firestore;
  final ProfileRepository _profileRepo;
  // ignore: unused_field
  final PointsRepository _pointsRepo;
  final TrustRepository _trustRepo;
  final ChatRepository _chatRepo;
  final NotificationsRepository _notificationsRepo;
  final _uuid = const Uuid();

  /// Set to `false` to enforce eligibility conditions for production.
  /// When `true`, all eligibility checks pass so we can build & test the flow.
  static const bool bypassForTesting = false;

  static const Set<String> _familyTypes = {
    'wife',
    'husband',
    'daughter',
    'son',
    'mother',
    'father',
    'sister',
    'brother',
    'aunt',
    'uncle',
    'nephew',
    'niece',
    'cousin',
  };

  EmergencyFundService(
    this._firestore,
    this._profileRepo,
    this._pointsRepo,
    this._trustRepo,
    this._chatRepo,
    this._notificationsRepo,
  );

  // --- Eligibility ---

  Future<EligibilityResult> checkEligibility(String userId) async {
    if (bypassForTesting) {
      return EligibilityResult(
        isProfileComplete: true,
        hasEnoughQrScans: true,
        qrScanCount: 10,
      );
    }

    // 1. Profile Check
    final profile = await _profileRepo.getUserProfile(userId);
    final isProfileComplete = profile?.isComplete ?? false;

    // 2. In-person QR scan check — read P.o.C.T trust data
    int qrScanCount = 0;
    try {
      final trustDoc = await _firestore
          .collection('trust_scores')
          .doc(userId)
          .get();
      if (trustDoc.exists) {
        qrScanCount = (trustDoc.data()?['uniqueQrCount'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {}

    return EligibilityResult(
      isProfileComplete: isProfileComplete,
      hasEnoughQrScans: qrScanCount >= EligibilityResult.requiredQrScans,
      qrScanCount: qrScanCount,
    );
  }

  // --- $DIASPORA Contribution ---

  /// Quotes how many $DIASPORA tokens are required to cover the $100 contribution
  /// at the current implied price. Returns `{ amountDiaspora, pricePerToken, usd }`.
  Future<Map<String, dynamic>> quoteDiasporaContribution() async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('getEmergencyFundContributionQuote')
        .call();
    return Map<String, dynamic>.from(result.data as Map);
  }

  /// Pays the $100-equivalent contribution in $DIASPORA tokens.
  /// Server-side: quotes price, transfers from user's smart wallet
  /// to the fund treasury, activates membership, refunds DSP promissory.
  Future<Map<String, dynamic>> payContributionInDiaspora() async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('payEmergencyFundInDiaspora')
        .call();
    return Map<String, dynamic>.from(result.data as Map);
  }

  // --- Interest List (insufficient-balance waiting list) ---

  /// Record this user's interest in joining the fund.
  /// Used when balance is too low to contribute right now.
  Future<void> expressInterest(String userId) async {
    await _firestore.collection('emergency_fund_interest').doc(userId).set({
      'userId': userId,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Whether the user has already expressed interest.
  Stream<bool> streamMyInterest(String userId) {
    return _firestore
        .collection('emergency_fund_interest')
        .doc(userId)
        .snapshots()
        .map((d) => d.exists);
  }

  /// All users who have expressed interest (ordered newest first).
  Stream<List<String>> streamInterestedUserIds() {
    return _firestore
        .collection('emergency_fund_interest')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => d.id).toList());
  }

  /// All active fund members.
  Stream<List<String>> streamActiveMemberUserIds() {
    return _firestore
        .collection('emergency_fund_memberships')
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((s) => s.docs.map((d) => d.id).toList());
  }

  // --- Membership ---

  Stream<EmergencyFundMembership?> streamMembership(String userId) {
    return _firestore
        .collection('emergency_fund_memberships')
        .doc(userId)
        .snapshots()
        .map((doc) {
          if (doc.exists && doc.data() != null) {
            return EmergencyFundMembership.fromMap(doc.data()!);
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
          .where((r) => _familyTypes.contains(r.type.toLowerCase()))
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
    final membership = EmergencyFundMembership(
      userId: userId,
      country: country,
      status: MembershipStatus.pending_proxy,
      joinedDate: DateTime.now(),
      annualContribution: 100.0, // Fixed: Standardized to $100
      supportNumber: 'DN-EMG-${_uuid.v4().substring(0, 8).toUpperCase()}',
      proxyUserId: proxyUserId,
      proxyStatus: ProxyStatus.pending,
      coveredFamilyMembers: coveredFamilyMembers,
    );

    await _firestore
        .collection('emergency_fund_memberships')
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
        .collection('emergency_fund_memberships')
        .doc(memberUserId)
        .update({
          'proxyStatus': ProxyStatus.accepted.name,
          'status': MembershipStatus.pending_payment.name,
        });
  }

  // Stripe payment flows removed: fund membership is paid in $DIASPORA only.
  // See [quoteDiasporaContribution] and [payContributionInDiaspora] above.

  // Update proxy designation — creates a request that the proxy must accept
  Future<void> updateProxy({
    required String userId,
    required String userName,
    required String proxyUserId,
  }) async {
    // 1. Save proxy as pending on the membership doc
    await _firestore.collection('emergency_fund_memberships').doc(userId).set({
      'proxyUserId': proxyUserId,
      'proxyStatus': ProxyStatus.pending.name,
    }, SetOptions(merge: true));

    // 2. Write a proxy_requests doc so the proxy user gets notified
    final requestId = '${userId}_$proxyUserId';
    await _firestore.collection('proxy_requests').doc(requestId).set({
      'fromUserId': userId,
      'fromUserName': userName,
      'toUserId': proxyUserId,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });

    debugPrint('✅ [EmergencyFund] Proxy request created: $requestId');
  }

  // Proxy user responds to the request (accept or reject)
  Future<void> respondToProxyRequest({
    required String requestId,
    required String fromUserId,
    required bool accepted,
  }) async {
    final newStatus = accepted ? 'accepted' : 'rejected';

    // 1. Update the proxy_requests doc
    await _firestore.collection('proxy_requests').doc(requestId).update({
      'status': newStatus,
      'respondedAt': FieldValue.serverTimestamp(),
    });

    // 2. Update the membership doc
    final proxyStatus = accepted ? ProxyStatus.accepted : ProxyStatus.rejected;
    final updateData = <String, dynamic>{'proxyStatus': proxyStatus.name};
    if (!accepted) {
      updateData['proxyUserId'] = null;
    }
    await _firestore
        .collection('emergency_fund_memberships')
        .doc(fromUserId)
        .set(updateData, SetOptions(merge: true));

    debugPrint('✅ [EmergencyFund] Proxy request $requestId $newStatus');
  }

  // Stream pending proxy requests for a given user (they are the proxy)
  Stream<QuerySnapshot> streamPendingProxyRequests(String proxyUserId) {
    return _firestore
        .collection('proxy_requests')
        .where('toUserId', isEqualTo: proxyUserId)
        .where('status', isEqualTo: 'pending')
        .snapshots();
  }

  // --- Claims ---

  Stream<List<EmergencyFundClaim>> streamUserClaims(String userId) {
    return _firestore
        .collection('emergency_fund_claims')
        .where('userId', isEqualTo: userId)
        .orderBy('submittedDate', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => EmergencyFundClaim.fromMap(doc.data()))
              .toList();
        });
  }

  Future<void> submitClaim({
    required String userId,
    required EmergencyType type,
    required String beneficiaryName,
    required String relationship,
    required DateTime incidentDate,
    required String description,
  }) async {
    final claimId = _uuid.v4();
    final claim = EmergencyFundClaim(
      id: claimId,
      userId: userId,
      type: type,
      beneficiaryName: beneficiaryName,
      relationship: relationship,
      incidentDate: incidentDate,
      status: ClaimStatus.submitted,
      submittedDate: DateTime.now(),
      description: description,
    );

    await _firestore
        .collection('emergency_fund_claims')
        .doc(claimId)
        .set(claim.toMap());
  }

  // --- Helpers ---
  Future<ProfileData?> getUserProfile(String uid) =>
      _profileRepo.getUserProfile(uid);

  // --- Promissory Staking ---

  /// Persists this user as a promissory staker.
  /// Collection: `emergency_fund_stakers/{userId}`
  /// When the fund opens, all docs in this collection represent users
  /// who already staked and can proceed directly to payment.
  Future<void> stakePromissory(String userId) async {
    await _firestore.collection('emergency_fund_stakers').doc(userId).set({
      'userId': userId,
      'stakedAt': FieldValue.serverTimestamp(),
      'amountDSP': 1000,
      'status': 'staked', // staked → contributed → refunded
    });
    debugPrint('✅ [EmergencyFund] User $userId staked 1,000 DSP promissory');

    // Fire notification
    try {
      await _notificationsRepo.addNotification(
        userId,
        NotificationItem(
          id: '',
          type: NotificationType.emergencyFundStaked,
          title: 'DSP Staked Successfully',
          body:
              'You staked 1,000 DSP promissory for the Community Emergency Fund. Complete your annual contribution to activate membership.',
          createdAt: DateTime.now(),
        ),
      );
    } catch (e) {
      debugPrint('⚠️ [EmergencyFund] Failed to create stake notification: $e');
    }
  }

  /// Checks whether a user has already staked their DSP promissory.
  Future<bool> hasStaked(String userId) async {
    final doc = await _firestore
        .collection('emergency_fund_stakers')
        .doc(userId)
        .get();
    return doc.exists;
  }

  /// Returns the total number of users who have staked.
  Future<int> getStakerCount() async {
    final agg = await _firestore
        .collection('emergency_fund_stakers')
        .count()
        .get();
    return agg.count ?? 0;
  }
}
