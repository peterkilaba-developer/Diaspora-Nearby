import 'package:cloud_firestore/cloud_firestore.dart';

class PointsTransaction {
  final String id;
  final String userId;
  final String type; // 'earn', 'spend', 'redeem', 'bonus'
  final String
  action; // 'referral_signup', 'daily_open', 'message_sent', 'streak_10', 'streak_30', 'community_tribute'
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
      userId: map['userId'] as String? ?? '',
      type: map['type'] as String? ?? 'unknown',
      action: map['action'] as String? ?? 'unknown',
      points: (map['points'] as num? ?? 0).toInt(),
      timestamp: _parseDateTime(map['timestamp']) ?? DateTime.now(),
      metadata: map['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'type': type,
      'action': action,
      'points': points,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'metadata': metadata,
    };
  }

  String get displayAction {
    // 1. Check Metadata for human-readable overrides
    if (metadata != null) {
      if (metadata!.containsKey('description')) {
        String desc = metadata!['description'];
        // Fix for "Exploration Reward: [ID]"
        if (desc.startsWith('Exploration Reward:')) {
          final idPart = desc.replaceFirst('Exploration Reward:', '').trim();
          final humanized = idPart
              .split('_')
              .map((word) {
                if (word.isEmpty) return '';
                return '${word[0].toUpperCase()}${word.substring(1)}';
              })
              .join(' ');
          return 'Exploration Reward: $humanized';
        }
        return desc;
      }
      if (metadata!.containsKey('communityName')) {
        return 'Joined ${metadata!['communityName']}';
      }
      if (metadata!.containsKey('eventName')) {
        return 'Event: ${metadata!['eventName']}';
      }
      if (metadata!.containsKey('title')) {
        return metadata!['title'];
      }
    }

    // 2. Specific System Actions
    switch (action) {
      case 'referral_signup':
        return 'Referral Signup';
      case 'daily_open':
        return 'Maintenance Streak'; // [UPDATED] Rebranded from "Daily App Open"
      case 'daily_share':
        return 'Daily Share';
      case 'message_sent':
        return 'Message Sent';
      case 'streak_10':
        return 'Maintenance Streak Bonus';
      case 'streak_100':
        return 'Legendary Streak Bonus';
      case 'dsp_transfer_sent':
        return 'DSP Sent';
      case 'dsp_transfer_received':
        return 'DSP Received';
    }

    // 3. Fallback: Humanize Snake Case (e.g. 'joined_community' -> 'Joined Community')
    return action
        .split('_')
        .map((word) {
          if (word.isEmpty) return '';
          return '${word[0].toUpperCase()}${word.substring(1)}';
        })
        .join(' ');
  }

  static DateTime? _parseDateTime(dynamic val) {
    if (val is Timestamp) return val.toDate();
    if (val is String) return DateTime.tryParse(val);
    if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
    return null;
  }
}
