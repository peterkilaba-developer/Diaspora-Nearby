import 'package:cloud_firestore/cloud_firestore.dart';

class Relationship {
  final String id; // The related user's ID
  final String type; // e.g., 'Father', 'Mother'
  final String name; // Snapshot of the related user's name at time of creation
  final DateTime createdAt;
  final String status;
  final String? flag; // [NEW] Country flag emoji

  Relationship({
    required this.id,
    required this.type,
    required this.name,
    required this.createdAt,
    required this.status,
    this.flag,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'name': name,
      'createdAt': Timestamp.fromDate(createdAt),
      'status': status,
      'flag': flag,
    };
  }

  factory Relationship.fromMap(Map<String, dynamic> map, String id) {
    DateTime parsedDate;
    try {
      parsedDate = (map['createdAt'] as Timestamp).toDate();
    } catch (_) {
      try {
        parsedDate = DateTime.parse(map['createdAt']);
      } catch (_) {
        parsedDate = DateTime.now();
      }
    }

    return Relationship(
      id: id,
      type: map['type'] ?? '',
      name: map['name'] ?? '',
      createdAt: parsedDate,
      status: map['status'] ?? 'active',
      flag: map['flag'],
    );
  }
}
