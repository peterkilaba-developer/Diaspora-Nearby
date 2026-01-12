class UserPoints {
  final String userId;
  final int totalPoints;
  final int availablePoints;
  final int currentStreak;
  final DateTime? lastActivityDate;
  final int dailyMessageCount;
  final DateTime lastUpdated;
  final List<String> completedExplorationActions; // [NEW]

  UserPoints({
    required this.userId,
    required this.totalPoints,
    required this.availablePoints,
    required this.currentStreak,
    this.lastActivityDate,
    required this.dailyMessageCount,
    required this.lastUpdated,
    this.completedExplorationActions = const [], // [NEW]
  });

  factory UserPoints.fromMap(Map<String, dynamic> map) {
    return UserPoints(
      userId: map['userId'] as String,
      totalPoints: map['totalPoints'] as int,
      availablePoints: map['availablePoints'] as int,
      currentStreak: map['currentStreak'] as int,
      lastActivityDate: map['lastActivityDate'] != null
          ? DateTime.parse(map['lastActivityDate'] as String)
          : null,
      dailyMessageCount: map['dailyMessageCount'] as int,
      lastUpdated: DateTime.parse(map['lastUpdated'] as String),
      completedExplorationActions: (map['completedExplorationActions'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [], // [NEW]
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
      'completedExplorationActions': completedExplorationActions, // [NEW]
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
  }) {
    return UserPoints(
      userId: userId ?? this.userId,
      totalPoints: totalPoints ?? this.totalPoints,
      availablePoints: availablePoints ?? this.availablePoints,
      currentStreak: currentStreak ?? this.currentStreak,
      lastActivityDate: lastActivityDate ?? this.lastActivityDate,
      dailyMessageCount: dailyMessageCount ?? this.dailyMessageCount,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      completedExplorationActions: completedExplorationActions ?? this.completedExplorationActions,
    );
  }
}
