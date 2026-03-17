import 'package:cloud_firestore/cloud_firestore.dart';

// ignore: constant_identifier_names
enum MembershipStatus {
  active,
  inactive,
  // ignore: constant_identifier_names
  pending_proxy, // Waiting for proxy to accept
  // ignore: constant_identifier_names
  pending_payment, // Proxy accepted, waiting for payment
  // ignore: constant_identifier_names
  grace_period,
}

enum ProxyStatus { none, pending, accepted, rejected }

enum EmergencyType { medical, legal, bereavement, repatriation }

class EmergencyFundMembership {
  final String userId;
  final String country;
  final MembershipStatus status;
  final DateTime joinedDate;
  final DateTime? nextPaymentDate;
  final double annualContribution;
  final String supportNumber;
  final String? proxyUserId;
  final ProxyStatus proxyStatus;
  final List<String> coveredFamilyMembers;

  EmergencyFundMembership({
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

  factory EmergencyFundMembership.fromMap(Map<String, dynamic> map) {
    return EmergencyFundMembership(
      userId: map['userId'] ?? '',
      country: map['country'] ?? '',
      status: MembershipStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => MembershipStatus.inactive,
      ),
      joinedDate: (map['joinedDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      nextPaymentDate: (map['nextPaymentDate'] as Timestamp?)?.toDate(),
      annualContribution:
          (map['annualContribution'] as num?)?.toDouble() ??
          (map['monthlyPremium'] as num?)?.toDouble() ??
          0.0,
      supportNumber: map['supportNumber'] ?? map['policyNumber'] ?? '',
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

enum ClaimStatus {
  submitted,
  // ignore: constant_identifier_names
  under_review,
  approved,
  rejected,
  paid,
}

class EmergencyFundClaim {
  final String id;
  final String userId;
  final EmergencyType type;
  final String beneficiaryName; // Renamed from deceasedName for generality
  final String relationship;
  final DateTime incidentDate; // Renamed from dateOfDeath
  final ClaimStatus status;
  final DateTime submittedDate;
  final String? documentUrl;
  final String description;

  EmergencyFundClaim({
    required this.id,
    required this.userId,
    required this.type,
    required this.beneficiaryName,
    required this.relationship,
    required this.incidentDate,
    required this.status,
    required this.submittedDate,
    this.documentUrl,
    required this.description,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'type': type.name,
      'beneficiaryName': beneficiaryName,
      'relationship': relationship,
      'incidentDate': Timestamp.fromDate(incidentDate),
      'status': status.name,
      'submittedDate': Timestamp.fromDate(submittedDate),
      'documentUrl': documentUrl,
      'description': description,
    };
  }

  factory EmergencyFundClaim.fromMap(Map<String, dynamic> map) {
    return EmergencyFundClaim(
      id: map['id'] ?? '',
      userId: map['userId'] ?? '',
      type: EmergencyType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => EmergencyType.bereavement, // Default fallback
      ),
      beneficiaryName: map['beneficiaryName'] ?? map['deceasedName'] ?? '',
      relationship: map['relationship'] ?? '',
      incidentDate:
          (map['incidentDate'] as Timestamp?)?.toDate() ??
          (map['dateOfDeath'] as Timestamp).toDate(),
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
