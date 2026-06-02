import 'package:cloud_firestore/cloud_firestore.dart';

class Corridor {
  final String id; // Format: {senderCountry}_{receiverCountry} (e.g., GB_TZ)
  final String senderCountry;
  final String receiverCountry;
  final int cumulativeGdp;
  final int transactionCount;
  final DateTime lastTransactionAt;

  Corridor({
    required this.id,
    required this.senderCountry,
    required this.receiverCountry,
    this.cumulativeGdp = 0,
    this.transactionCount = 0,
    required this.lastTransactionAt,
  });

  factory Corridor.fromJson(Map<String, dynamic> json) {
    return Corridor(
      id: json['id'] as String? ?? '',
      senderCountry: json['senderCountry'] as String? ?? '',
      receiverCountry: json['receiverCountry'] as String? ?? '',
      cumulativeGdp: json['cumulativeGdp'] as int? ?? 0,
      transactionCount: json['transactionCount'] as int? ?? 0,
      lastTransactionAt: _parseDate(json['lastTransactionAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'senderCountry': senderCountry,
      'receiverCountry': receiverCountry,
      'cumulativeGdp': cumulativeGdp,
      'transactionCount': transactionCount,
      'lastTransactionAt': lastTransactionAt.toIso8601String(),
    };
  }

  static DateTime _parseDate(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return DateTime.now();
  }

  Corridor copyWith({
    String? id,
    String? senderCountry,
    String? receiverCountry,
    int? cumulativeGdp,
    int? transactionCount,
    DateTime? lastTransactionAt,
  }) {
    return Corridor(
      id: id ?? this.id,
      senderCountry: senderCountry ?? this.senderCountry,
      receiverCountry: receiverCountry ?? this.receiverCountry,
      cumulativeGdp: cumulativeGdp ?? this.cumulativeGdp,
      transactionCount: transactionCount ?? this.transactionCount,
      lastTransactionAt: lastTransactionAt ?? this.lastTransactionAt,
    );
  }
}
