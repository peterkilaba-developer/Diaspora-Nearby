import 'package:cloud_firestore/cloud_firestore.dart';

enum MembershipStatus {
  active,
  inactive,
  pending_proxy, // Waiting for proxy to accept
  pending_payment, // Proxy accepted, waiting for payment
  grace_period,
}

enum ProxyStatus { none, pending, accepted, rejected }

class BereavementMembership {
  final String userId;
  final String country;
  final MembershipStatus status;
  final DateTime joinedDate;
  final DateTime? nextPaymentDate;
  final double annualContribution; // Renamed from monthlyPremium
  final String supportNumber; // Renamed from policyNumber
  final String? proxyUserId; // [NEW]
  final ProxyStatus proxyStatus; // [NEW]
  final List<String> coveredFamilyMembers; // [NEW] List of related User IDs

  BereavementMembership({
    required this.userId,
    required this.country,
    required this.status,
    required this.joinedDate,
    this.nextPaymentDate,
    required this.annualContribution,
    required this.supportNumber,
    this.proxyUserId,
    this.proxyStatus = ProxyStatus.none,
    this.coveredFamilyMembers = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'country': country,
      'status': status.name,
      'joinedDate': Timestamp.fromDate(joinedDate),
      'nextPaymentDate': nextPaymentDate != null
          ? Timestamp.fromDate(nextPaymentDate!)
          : null,
      'annualContribution': annualContribution,
      'supportNumber': supportNumber,
      'proxyUserId': proxyUserId,
      'proxyStatus': proxyStatus.name,
      'coveredFamilyMembers': coveredFamilyMembers,
    };
  }

  factory BereavementMembership.fromMap(Map<String, dynamic> map) {
    return BereavementMembership(
      userId: map['userId'] ?? '',
      country: map['country'] ?? '',
      status: MembershipStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => MembershipStatus.inactive,
      ),
      joinedDate: (map['joinedDate'] as Timestamp).toDate(),
      nextPaymentDate: (map['nextPaymentDate'] as Timestamp?)?.toDate(),
      annualContribution:
          (map['annualContribution'] as num?)?.toDouble() ??
          (map['monthlyPremium'] as num?)?.toDouble() ??
          0.0, // Fallback for old data
      supportNumber:
          map['supportNumber'] ?? map['policyNumber'] ?? '', // Fallback
      proxyUserId: map['proxyUserId'],
      proxyStatus: ProxyStatus.values.firstWhere(
        (e) => e.name == map['proxyStatus'],
        orElse: () => ProxyStatus.none,
      ),
      coveredFamilyMembers:
          (map['coveredFamilyMembers'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }
}

enum ClaimStatus { submitted, under_review, approved, rejected, paid }

class BereavementClaim {
  final String id;
  final String userId;
  final String deceasedName;
  final String relationship;
  final DateTime dateOfDeath;
  final ClaimStatus status;
  final DateTime submittedDate;
  final String? documentUrl; // URL to death certificate etc.
  final String description;

  BereavementClaim({
    required this.id,
    required this.userId,
    required this.deceasedName,
    required this.relationship,
    required this.dateOfDeath,
    required this.status,
    required this.submittedDate,
    this.documentUrl,
    required this.description,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'deceasedName': deceasedName,
      'relationship': relationship,
      'dateOfDeath': Timestamp.fromDate(dateOfDeath),
      'status': status.name,
      'submittedDate': Timestamp.fromDate(submittedDate),
      'documentUrl': documentUrl,
      'description': description,
    };
  }

  factory BereavementClaim.fromMap(Map<String, dynamic> map) {
    return BereavementClaim(
      id: map['id'] ?? '',
      userId: map['userId'] ?? '',
      deceasedName: map['deceasedName'] ?? '',
      relationship: map['relationship'] ?? '',
      dateOfDeath: (map['dateOfDeath'] as Timestamp).toDate(),
      status: ClaimStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => ClaimStatus.submitted,
      ),
      submittedDate: (map['submittedDate'] as Timestamp).toDate(),
      documentUrl: map['documentUrl'],
      description: map['description'] ?? '',
    );
  }
}
