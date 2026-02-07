import 'package:cloud_firestore/cloud_firestore.dart';

class RelationshipRequest {
  final String id;
  final String fromUserId;
  final String fromUserName;
  final String fromUserFlag; // [NEW] For UI display in notification/list
  final String toUserId;
  final String toUserName; // Optional, helpful for UI
  final String relationshipType; // e.g., "Father", "Mother"
  final DateTime timestamp;
  final String status; // 'pending', 'accepted', 'rejected'

  const RelationshipRequest({
    required this.id,
    required this.fromUserId,
    required this.fromUserName,
    required this.fromUserFlag,
    required this.toUserId,
    required this.toUserName,
    required this.relationshipType,
    required this.timestamp,
    required this.status,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fromUserId': fromUserId,
      'fromUserName': fromUserName,
      'fromUserFlag': fromUserFlag,
      'toUserId': toUserId,
      'toUserName': toUserName,
      'relationshipType': relationshipType,
      'timestamp': Timestamp.fromDate(timestamp),
      'status': status,
    };
  }

  factory RelationshipRequest.fromMap(Map<String, dynamic> map) {
    return RelationshipRequest(
      id: map['id'] ?? '',
      fromUserId: map['fromUserId'] ?? '',
      fromUserName: map['fromUserName'] ?? '',
      fromUserFlag: map['fromUserFlag'] ?? 'ðŸŒ',
      toUserId: map['toUserId'] ?? '',
      toUserName: map['toUserName'] ?? '',
      relationshipType: map['relationshipType'] ?? '',
      timestamp: (map['timestamp'] as Timestamp).toDate(),
      status: map['status'] ?? 'pending',
    );
  }
}
