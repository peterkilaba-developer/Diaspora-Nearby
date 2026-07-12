import 'package:cloud_firestore/cloud_firestore.dart';

class TgeDistributionRecord {
  final int epoch;
  final int tgeNumber;
  final double amount;
  final double efficiency;
  final DateTime date;
  final String? txHash; // On-chain transaction hash for Basescan

  TgeDistributionRecord({
    required this.epoch,
    required this.tgeNumber,
    required this.amount,
    required this.efficiency,
    required this.date,
    this.txHash,
  });

  factory TgeDistributionRecord.fromMap(Map<String, dynamic> map) {
    return TgeDistributionRecord(
      epoch: (map['epoch'] as num? ?? 0).toInt(),
      tgeNumber: (map['tgeNumber'] as num? ?? 0).toInt(),
      amount: (map['amount'] as num? ?? 0).toDouble(),
      efficiency: (map['efficiency'] as num? ?? 0).toDouble(),
      date: _parseDateTime(map['date']) ?? DateTime.now(),
      txHash: map['txHash'] as String?,
    );
  }

  static DateTime? _parseDateTime(dynamic val) {
    if (val is Timestamp) return val.toDate();
    if (val is String) return DateTime.tryParse(val);
    if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
    return null;
  }

  Map<String, dynamic> toMap() {
    return {
      'epoch': epoch,
      'tgeNumber': tgeNumber,
      'amount': amount,
      'efficiency': efficiency,
      'date': date.toIso8601String(),
      if (txHash != null) 'txHash': txHash,
    };
  }
}

class UserPoints {
  final String userId;
  final int totalPoints;
  final int availablePoints;
  final int currentStreak;
  final DateTime? lastActivityDate;
  final int dailyMessageCount;
  final DateTime lastUpdated;
  final DateTime signupDate; // Used for "Days Active" status calculation
  final int dailyShareCount; // [NEW] max 12/day
  final List<String>
  dailyCommunitiesMessaged; // [NEW] track per-community daily msg
  final List<String> completedExplorationActions; // [FIX] Added missing field
  final String? walletAddress; // [NEW] User's Crypto Wallet Address
  final DateTime? lastCheckInDate; // [NEW]
  final int? trustScore; // [NEW] Proof of Community Trust (P.o.C.T)
  final String? homeCountryCode; // [NEW] For community aggregation
  final Map<String, int>
  lifetimeEarnings; // [NEW] Track total DSP earned per activity
  final List<TgeDistributionRecord>
  tgeHistory; // [NEW] Track historical TGE distributions
  final int verifiedCount; // [NEW] Track number of verified peers
  final int familyConnectionCount; // [NEW] Track number of family connections
  final int qrConnectionCount; // [NEW] Track number of QR connections
  final DateTime? firstTgeReceivedAt; // Set by the TGE oracle after the
  // user's first TGE distribution. Subsequent TGEs skip the 10-QR gate.

  UserPoints({
    required this.userId,
    required this.totalPoints,
    required this.availablePoints,
    required this.currentStreak,
    this.lastActivityDate,
    required this.dailyMessageCount,
    required this.lastUpdated,
    this.completedExplorationActions = const [],
    required this.signupDate,
    this.dailyShareCount = 0,
    this.dailyCommunitiesMessaged = const [],
    this.walletAddress,
    this.lastCheckInDate,
    this.trustScore = 0,
    this.homeCountryCode,
    this.lifetimeEarnings = const {},
    this.tgeHistory = const [],
    this.verifiedCount = 0,
    this.familyConnectionCount = 0,
    this.qrConnectionCount = 0,
    this.firstTgeReceivedAt,
  });

  int get totalDsp => totalPoints;

  factory UserPoints.fromMap(Map<String, dynamic> map) {
    return UserPoints(
      userId: map['userId'] as String? ?? '',
      totalPoints: (map['totalPoints'] as num? ?? 0).toInt(),
      availablePoints: (map['availablePoints'] as num? ?? 0).toInt(),
      currentStreak: (map['currentStreak'] as num? ?? 0).toInt(),
      lastActivityDate: _parseDateTime(map['lastActivityDate']),
      dailyMessageCount: (map['dailyMessageCount'] as num? ?? 0).toInt(),
      lastUpdated: _parseDateTime(map['lastUpdated']) ?? DateTime.now(),
      completedExplorationActions:
          (map['completedExplorationActions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      signupDate:
          _parseDateTime(map['signupDate']) ??
          DateTime.now(), // Fallback for existing users
      dailyShareCount: (map['dailyShareCount'] as num? ?? 0).toInt(),
      dailyCommunitiesMessaged:
          (map['dailyCommunitiesMessaged'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      walletAddress: map['walletAddress'] as String?,
      lastCheckInDate: _parseDateTime(map['lastCheckInDate']),
      trustScore: (map['trustScore'] as num? ?? 0).toInt(),
      homeCountryCode: map['homeCountryCode'] as String?,
      lifetimeEarnings:
          (map['lifetimeEarnings'] as Map<String, dynamic>?)?.map(
            (key, value) => MapEntry(key, (value as num?)?.toInt() ?? 0),
          ) ??
          {},
      tgeHistory:
          (map['tgeHistory'] as List<dynamic>?)
              ?.map(
                (e) => TgeDistributionRecord.fromMap(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
      verifiedCount: (map['verifiedCount'] as num? ?? 0).toInt(),
      familyConnectionCount: (map['familyConnectionCount'] as num? ?? 0)
          .toInt(),
      qrConnectionCount: (map['qrConnectionCount'] as num? ?? 0).toInt(),
      firstTgeReceivedAt: _parseDateTime(map['firstTgeReceivedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'totalPoints': totalPoints,
      'availablePoints': availablePoints,
      'currentStreak': currentStreak,
      'lastActivityDate': lastActivityDate?.toIso8601String(),
      'dailyMessageCount': dailyMessageCount,
      'lastUpdated': lastUpdated.toIso8601String(),
      'completedExplorationActions': completedExplorationActions,
      'signupDate': signupDate.toIso8601String(),
      'dailyShareCount': dailyShareCount,
      'dailyCommunitiesMessaged': dailyCommunitiesMessaged,
      'walletAddress': walletAddress,
      'lastCheckInDate': lastCheckInDate?.toIso8601String(),
      'trustScore': trustScore,
      'homeCountryCode': homeCountryCode,
      'lifetimeEarnings': lifetimeEarnings,
      'tgeHistory': tgeHistory.map((e) => e.toMap()).toList(),
      'verifiedCount': verifiedCount,
      'familyConnectionCount': familyConnectionCount,
      'qrConnectionCount': qrConnectionCount,
      'firstTgeReceivedAt': firstTgeReceivedAt?.toIso8601String(),
    };
  }

  UserPoints copyWith({
    String? userId,
    int? totalPoints,
    int? availablePoints,
    int? currentStreak,
    DateTime? lastActivityDate,
    int? dailyMessageCount,
    DateTime? lastUpdated,
    List<String>? completedExplorationActions,
    DateTime? signupDate,
    int? dailyShareCount,
    List<String>? dailyCommunitiesMessaged,
    String? walletAddress,
    DateTime? lastCheckInDate,
    int? trustScore,
    String? homeCountryCode,
    Map<String, int>? lifetimeEarnings,
    List<TgeDistributionRecord>? tgeHistory,
    int? verifiedCount,
    int? familyConnectionCount,
    int? qrConnectionCount,
    DateTime? firstTgeReceivedAt,
  }) {
    return UserPoints(
      userId: userId ?? this.userId,
      totalPoints: totalPoints ?? this.totalPoints,
      availablePoints: availablePoints ?? this.availablePoints,
      currentStreak: currentStreak ?? this.currentStreak,
      lastActivityDate: lastActivityDate ?? this.lastActivityDate,
      dailyMessageCount: dailyMessageCount ?? this.dailyMessageCount,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      completedExplorationActions:
          completedExplorationActions ?? this.completedExplorationActions,
      signupDate: signupDate ?? this.signupDate,
      dailyShareCount: dailyShareCount ?? this.dailyShareCount,
      dailyCommunitiesMessaged:
          dailyCommunitiesMessaged ?? this.dailyCommunitiesMessaged,
      walletAddress: walletAddress ?? this.walletAddress,
      lastCheckInDate: lastCheckInDate ?? this.lastCheckInDate,
      trustScore: trustScore ?? this.trustScore,
      homeCountryCode: homeCountryCode ?? this.homeCountryCode,
      lifetimeEarnings: lifetimeEarnings ?? this.lifetimeEarnings,
      tgeHistory: tgeHistory ?? this.tgeHistory,
      verifiedCount: verifiedCount ?? this.verifiedCount,
      familyConnectionCount:
          familyConnectionCount ?? this.familyConnectionCount,
      qrConnectionCount: qrConnectionCount ?? this.qrConnectionCount,
      firstTgeReceivedAt: firstTgeReceivedAt ?? this.firstTgeReceivedAt,
    );
  }

  static DateTime? _parseDateTime(dynamic val) {
    if (val is Timestamp) return val.toDate();
    if (val is String) return DateTime.tryParse(val);
    if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
    return null;
  }
}
