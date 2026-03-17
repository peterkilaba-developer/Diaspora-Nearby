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
      lastTransactionAt: json['lastTransactionAt'] != null
          ? DateTime.parse(json['lastTransactionAt'] as String)
          : DateTime.now(),
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
