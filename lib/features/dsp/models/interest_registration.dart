import 'package:cloud_firestore/cloud_firestore.dart';

class InterestRegistration {
  final String userId;
  final String service; // e.g., 'crypto', 'remittances', 'bereavement', 'airline', 'dfdi'
  final String country;
  final DateTime timestamp;

  InterestRegistration({
    required this.userId,
    required this.service,
    required this.country,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'service': service,
      'country': country,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }

  factory InterestRegistration.fromMap(Map<String, dynamic> map) {
    return InterestRegistration(
      userId: map['userId'] ?? '',
      service: map['service'] ?? '',
      country: map['country'] ?? '',
      timestamp: (map['timestamp'] as Timestamp).toDate(),
    );
  }
}
