import 'package:cloud_firestore/cloud_firestore.dart';

class RelationshipRequest {
  final String id;
  final String fromUserId;
  final String fromUserName;
  final String fromUserFlag; // [NEW] For UI display in notification/list
  final String? fromUserPhoto; // [NEW] Profile photo URL
  final String toUserId;
  final String toUserName; // Optional, helpful for UI
  final String? toUserPhoto; // [NEW] Profile photo URL
  final String relationshipType; // e.g., "Father", "Mother"
  final DateTime timestamp;
  final String status; // 'pending', 'accepted', 'rejected'

  const RelationshipRequest({
    required this.id,
    required this.fromUserId,
    required this.fromUserName,
    required this.fromUserFlag,
    this.fromUserPhoto,
    required this.toUserId,
    required this.toUserName,
    this.toUserPhoto,
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
      'fromUserPhoto': fromUserPhoto,
      'toUserId': toUserId,
      'toUserName': toUserName,
      'toUserPhoto': toUserPhoto,
      'relationshipType': relationshipType,
      'timestamp': Timestamp.fromDate(timestamp),
      'status': status,
    };
  }

  factory RelationshipRequest.fromMap(
    Map<String, dynamic> map, [
    String? docId,
  ]) {
    DateTime parsedTimestamp;
    final rawTimestamp = map['timestamp'];
    if (rawTimestamp is Timestamp) {
      parsedTimestamp = rawTimestamp.toDate();
    } else if (rawTimestamp is int) {
      parsedTimestamp = DateTime.fromMillisecondsSinceEpoch(rawTimestamp);
    } else if (rawTimestamp is String) {
      parsedTimestamp = DateTime.tryParse(rawTimestamp) ?? DateTime.now();
    } else {
      parsedTimestamp = DateTime.now();
    }

    final mapId = (map['id'] as String?)?.trim();
    return RelationshipRequest(
      id: (mapId != null && mapId.isNotEmpty) ? mapId : (docId ?? ''),
      fromUserId: map['fromUserId'] ?? '',
      fromUserName: map['fromUserName'] ?? '',
      fromUserFlag: map['fromUserFlag'] ?? '',
      fromUserPhoto: map['fromUserPhoto'] as String?,
      toUserId: map['toUserId'] ?? '',
      toUserName: map['toUserName'] ?? '',
      toUserPhoto: map['toUserPhoto'] as String?,
      relationshipType: map['relationshipType'] ?? '',
      timestamp: parsedTimestamp,
      status: map['status'] ?? 'pending',
    );
  }
}
