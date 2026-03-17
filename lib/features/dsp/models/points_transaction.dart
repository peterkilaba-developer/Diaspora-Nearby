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
    // Merge top-level transfer fields into metadata so UI can access them uniformly
    final rawMeta = (map['metadata'] as Map<String, dynamic>?) ?? {};
    final mergedMeta = <String, dynamic>{
      ...rawMeta,
      if (map['txHash'] != null) 'txHash': map['txHash'],
      if (map['toUserId'] != null && !rawMeta.containsKey('toUserId'))
        'toUserId': map['toUserId'],
      if (map['fromUserId'] != null && !rawMeta.containsKey('fromUserId'))
        'fromUserId': map['fromUserId'],
    };

    return PointsTransaction(
      id: id,
      userId: map['userId'] as String? ?? '',
      type: map['type'] as String? ?? 'unknown',
      action: map['action'] as String? ?? 'unknown',
      points: (map['points'] as num? ?? 0).toInt(),
      timestamp: _parseDateTime(map['timestamp']) ?? DateTime.now(),
      metadata: mergedMeta.isNotEmpty ? mergedMeta : null,
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
      case 'welcome_bonus':
        return 'Welcome Bonus';
      case 'referral_signup':
        return 'Referral Signup';
      case 'referral_reward_referrer':
        return 'Referral Reward (Inviter)';
      case 'referral_reward_referee':
        return 'Referral Reward (Signup Bonus)';
      case 'daily_open':
        return 'Maintenance Streak';
      case 'daily_check_in':
        return 'Daily Check-In';
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
      case 'token_transfer_sent':
        return '\$DIASPORA Sent';
      case 'token_transfer_received':
        return '\$DIASPORA Received';
      case 'exploration_reward':
        return 'Exploration Reward';
      case 'exploration':
        return 'Exploration Reward';
      case 'profile_completion':
        return 'Profile Completion Bonus';
      case 'family_connection':
        return 'Family Connection';
      case 'friend_connection':
        return 'Friend Connection';
      case 'qr_connection':
        return 'QR Code Connection';
      case 'trust_vouch_reward':
        return 'Trust Vouch Reward';
      case 'token_welcome_bonus':
        return 'Welcome Bonus — \$DIASPORA';
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
