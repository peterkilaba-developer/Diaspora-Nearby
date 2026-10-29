import 'package:cloud_firestore/cloud_firestore.dart';

class Relationship {
  final String id; // The related user's ID
  final String type; // e.g., 'Father', 'Mother'
  final String name; // Snapshot of the related user's name at time of creation
  final DateTime createdAt;
  final String status;
  final String? flag; // [NEW] Country flag emoji
  final String? photoUrl;

  Relationship({
    required this.id,
    required this.type,
    required this.name,
    required this.createdAt,
    required this.status,
    this.flag,
    this.photoUrl,
  });

  Relationship copyWith({
    String? id,
    String? type,
    String? name,
    DateTime? createdAt,
    String? status,
    String? flag,
    String? photoUrl,
  }) {
    return Relationship(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      flag: flag ?? this.flag,
      photoUrl: photoUrl ?? this.photoUrl,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'name': name,
      'createdAt': Timestamp.fromDate(createdAt),
      'status': status,
      'flag': flag,
      if (photoUrl != null) 'photoUrl': photoUrl,
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
      photoUrl: map['photoUrl'] as String?,
    );
  }
}
