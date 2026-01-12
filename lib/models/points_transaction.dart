class PointsTransaction {
  final String id;
  final String userId;
  final String type; // 'earn', 'redeem', 'bonus'
  final String action; // 'referral_signup', 'daily_open', 'message_sent', 'streak_7', 'streak_30'
  final int points;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  PointsTransaction({
    required this.id,
    required this.userId,
    required this.type,
    required this.action,
    required this.points,
    required this.timestamp,
    this.metadata,
  });

  factory PointsTransaction.fromMap(Map<String, dynamic> map, String id) {
    return PointsTransaction(
      id: id,
      userId: map['userId'] as String,
      type: map['type'] as String,
      action: map['action'] as String,
      points: map['points'] as int,
      timestamp: DateTime.parse(map['timestamp'] as String),
      metadata: map['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'type': type,
      'action': action,
      'points': points,
      'timestamp': timestamp.toIso8601String(),
      'metadata': metadata,
    };
  }

  String get displayAction {
    switch (action) {
      case 'referral_signup':
        return 'Referral Signup';
      case 'daily_open':
        return 'Daily App Open';
      case 'message_sent':
        return 'Message Sent';
      case 'streak_7':
        return '7-Day Streak Bonus';
      case 'streak_30':
        return '30-Day Streak Bonus';
      default:
        return action;
    }
  }
}
