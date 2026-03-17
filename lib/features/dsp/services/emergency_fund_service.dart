import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
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
  final bool hasEnoughFamily;
  final bool hasEnoughFriends;
  final int familyCount;
  final int friendCount;

  bool get isEligible =>
      isProfileComplete && hasEnoughFamily && hasEnoughFriends;

  EligibilityResult({
    required this.isProfileComplete,
    required this.hasEnoughFamily,
    required this.hasEnoughFriends,
    required this.familyCount,
    required this.friendCount,
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
        hasEnoughFamily: true,
        hasEnoughFriends: true,
        familyCount: 1,
        friendCount: 1,
      );
    }

    // 1. Profile Check
    final profile = await _profileRepo.getUserProfile(userId);
    final isProfileComplete = profile?.isComplete ?? false;

    // 2. Relationships Check (1 Family, 1 Friend)
    final relationshipsSnap = await _firestore
        .collection('users')
        .doc(userId)
        .collection('relationships')
        .where('status', isEqualTo: 'active')
        .get();

    int familyCount = 0;
    int friendCount = 0;

    for (var doc in relationshipsSnap.docs) {
      final type = doc.data()['type'] as String? ?? '';
      if (_familyTypes.contains(type.toLowerCase())) {
        familyCount++;
      } else if (type.toLowerCase() == 'friend') {
        friendCount++;
      }
    }

    final hasEnoughFamily = familyCount >= 1;
    final hasEnoughFriends = friendCount >= 1;

    return EligibilityResult(
      isProfileComplete: isProfileComplete,
      hasEnoughFamily: hasEnoughFamily,
      hasEnoughFriends: hasEnoughFriends,
      familyCount: familyCount,
      friendCount: friendCount,
    );
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

  /// Whether payment processing is in beta (free) mode.
  /// Set to `false` once Stripe/M-Pesa integration is complete.
  static const bool isBetaMode = false;

  // --- Inline Card Payment (embedded CardFormField) ---

  /// Fetches a PaymentIntent client secret for inline card payment.
  Future<String> fetchPaymentIntentSecret({String? email}) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('createEmergencyFundCheckout')
        .call({'email': email});

    final clientSecret = result.data['paymentIntentClientSecret'] as String;
    debugPrint('✅ [EmergencyFund] PaymentIntent fetched for inline payment');
    return clientSecret;
  }

  /// Confirms inline card payment and activates membership.
  Future<void> confirmInlinePayment(String clientSecret, String userId) async {
    // Confirm the payment using the card details from CardFormField
    await Stripe.instance.confirmPayment(
      paymentIntentClientSecret: clientSecret,
      data: const PaymentMethodParams.card(
        paymentMethodData: PaymentMethodData(),
      ),
    );

    debugPrint('✅ [EmergencyFund] Inline payment confirmed!');

    // Activate membership with all required fields
    await _firestore.collection('emergency_fund_memberships').doc(userId).set({
      'userId': userId,
      'country': 'US',
      'status': MembershipStatus.active.name,
      'joinedDate': Timestamp.fromDate(DateTime.now()),
      'annualContribution': 100.0,
      'supportNumber': 'EF-${DateTime.now().millisecondsSinceEpoch}',
      'proxyStatus': ProxyStatus.none.name,
      'coveredFamilyMembers': [],
      'isBetaAccess': false,
      'nextPaymentDate': Timestamp.fromDate(
        DateTime.now().add(const Duration(days: 365)),
      ),
    }, SetOptions(merge: true));

    // Fire notifications for payment + membership
    try {
      await _notificationsRepo.addNotification(
        userId,
        NotificationItem(
          id: '',
          type: NotificationType.emergencyFundPaymentSuccess,
          title: 'Payment Successful',
          body:
              'Your \$100 annual contribution to the Community Emergency Fund has been processed.',
          createdAt: DateTime.now(),
        ),
      );
      await _notificationsRepo.addNotification(
        userId,
        NotificationItem(
          id: '',
          type: NotificationType.emergencyFundMembershipActive,
          title: 'Membership Activated! 🎉',
          body:
              'Welcome to the Community Emergency Fund! Your family is now covered for emergency support.',
          createdAt: DateTime.now(),
        ),
      );
      // Notify DSP refund (stake returned after payment)
      await _notificationsRepo.addNotification(
        userId,
        NotificationItem(
          id: '',
          type: NotificationType.emergencyFundDspRefunded,
          title: '1,000 DSP Refunded',
          body:
              'Your staked DSP promissory has been returned to your balance now that your annual contribution is confirmed.',
          createdAt: DateTime.now(),
        ),
      );
    } catch (e) {
      debugPrint(
        '⚠️ [EmergencyFund] Failed to create payment notifications: $e',
      );
    }

    // Refund DSP stake (mark as refunded)
    try {
      await _firestore.collection('emergency_fund_stakers').doc(userId).update({
        'status': 'refunded',
      });
    } catch (e) {
      debugPrint('⚠️ [EmergencyFund] Failed to update staker status: $e');
    }
  }

  // Step 3: Process Payment (Payment Sheet fallback)
  // When isBetaMode is false, shows Stripe's in-app Payment Sheet.
  // The user pays without leaving the app.
  Future<void> completeMembershipPayment(String userId, {String? email}) async {
    if (!isBetaMode) {
      // --- Production: Stripe Payment Sheet (in-app) ---
      try {
        // 1. Fetch user profile for billing details pre-fill (non-blocking)
        ProfileData? profile;
        try {
          profile = await _profileRepo.getUserProfile(userId);
        } catch (e) {
          debugPrint('▶ [EmergencyFund] Profile fetch skipped: $e');
        }
        final hostCountryCode = profile?.hostCountryCode?.toUpperCase();
        final userName = profile != null
            ? '${profile.firstName} ${profile.lastName}'.trim()
            : null;
        final userEmail = email;

        debugPrint(
          '▶ [EmergencyFund] Billing pre-fill — '
          'country: $hostCountryCode, name: $userName',
        );

        // 2. Get PaymentIntent from Cloud Function
        final result = await FirebaseFunctions.instance
            .httpsCallable('createEmergencyFundCheckout')
            .call({'email': userEmail});

        final clientSecret = result.data['paymentIntentClientSecret'] as String;
        final ephemeralKey = result.data['ephemeralKey'] as String;
        final customerId = result.data['customerId'] as String;

        debugPrint('✅ [EmergencyFund] PaymentIntent received');

        // 3. Build default billing details from user profile
        BillingDetails? defaultBilling;
        if (hostCountryCode != null || userName != null) {
          defaultBilling = BillingDetails(
            name: userName,
            email: userEmail,
            address: Address(
              country: hostCountryCode,
              city: null,
              line1: null,
              line2: null,
              postalCode: null,
              state: null,
            ),
          );
        }

        // 4. Initialize the Payment Sheet with custom appearance
        const sageGreen = Color(0xFF7CAE7A);
        const darkSurface = Color(0xFF1A1A2E);
        const darkCard = Color(0xFF252540);

        await Stripe.instance.initPaymentSheet(
          paymentSheetParameters: SetupPaymentSheetParameters(
            paymentIntentClientSecret: clientSecret,
            customerEphemeralKeySecret: ephemeralKey,
            customerId: customerId,
            merchantDisplayName: 'Diaspora Nearby',
            style: ThemeMode.dark,
            billingDetails: defaultBilling,
            billingDetailsCollectionConfiguration:
                const BillingDetailsCollectionConfiguration(
                  name: CollectionMode.automatic,
                  email: CollectionMode.never,
                  phone: CollectionMode.always,
                  address: AddressCollectionMode.never,
                  attachDefaultsToPaymentMethod: true,
                ),
            appearance: const PaymentSheetAppearance(
              colors: PaymentSheetAppearanceColors(
                primary: sageGreen,
                background: darkSurface,
                componentBackground: darkCard,
                componentBorder: Color(0xFF3A3A5C),
                componentDivider: Color(0xFF3A3A5C),
                componentText: Colors.white,
                primaryText: Colors.white,
                secondaryText: Color(0xFFB0B0C0),
                placeholderText: Color(0xFF6A6A80),
                icon: sageGreen,
                error: Color(0xFFFF6B6B),
              ),
              shapes: PaymentSheetShape(
                borderWidth: 1.0,
                borderRadius: 12.0,
                shadow: PaymentSheetShadowParams(color: Colors.transparent),
              ),
              primaryButton: PaymentSheetPrimaryButtonAppearance(
                colors: PaymentSheetPrimaryButtonTheme(
                  dark: PaymentSheetPrimaryButtonThemeColors(
                    background: sageGreen,
                    text: Colors.white,
                    border: Colors.transparent,
                  ),
                  light: PaymentSheetPrimaryButtonThemeColors(
                    background: sageGreen,
                    text: Colors.white,
                    border: Colors.transparent,
                  ),
                ),
              ),
            ),
            googlePay: const PaymentSheetGooglePay(
              merchantCountryCode: 'US',
              testEnv: true,
            ),
            // Only allow card payments (removes Affirm, Klarna, Amazon Pay, Link)
            paymentMethodOrder: const ['card', 'google_pay'],
            allowsDelayedPaymentMethods: false,
          ),
        );

        // 5. Present the Payment Sheet
        await Stripe.instance.presentPaymentSheet();

        debugPrint('✅ [EmergencyFund] Payment succeeded!');

        // 6. Immediately activate membership (webhook is backup)
        await _firestore
            .collection('emergency_fund_memberships')
            .doc(userId)
            .set({
              'status': MembershipStatus.active.name,
              'isBetaAccess': false,
              'nextPaymentDate': Timestamp.fromDate(
                DateTime.now().add(const Duration(days: 365)),
              ),
            }, SetOptions(merge: true));

        return;
      } on StripeException catch (e) {
        if (e.error.code == FailureCode.Canceled) {
          debugPrint('[EmergencyFund] Payment canceled by user');
          throw Exception('Payment was canceled');
        }
        debugPrint(
          '❌ [EmergencyFund] Stripe error: ${e.error.localizedMessage}',
        );
        rethrow;
      } catch (e) {
        debugPrint('❌ [EmergencyFund] Payment error: $e');
        rethrow;
      }
    }

    // Beta mode: auto-approve without payment
    await _firestore.collection('emergency_fund_memberships').doc(userId).set({
      'status': MembershipStatus.active.name,
      'isBetaAccess': true,
      'nextPaymentDate': Timestamp.fromDate(
        DateTime.now().add(const Duration(days: 365)),
      ),
    }, SetOptions(merge: true));
  }

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
