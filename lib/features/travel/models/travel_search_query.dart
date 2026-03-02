class TravelSearchQuery {
  final String? origin;
  final String? destination;
  final DateTime? departDate;
  final DateTime? returnDate;
  final int passengers;
  final String? travelClass;

  TravelSearchQuery({
    this.origin,
    this.destination,
    this.departDate,
    this.returnDate,
    this.passengers = 1,
    this.travelClass,
  });

  TravelSearchQuery copyWith({
    String? origin,
    String? destination,
    DateTime? departDate,
    DateTime? returnDate,
    int? passengers,
    String? travelClass,
  }) {
    return TravelSearchQuery(
      origin: origin ?? this.origin,
      destination: destination ?? this.destination,
      departDate: departDate ?? this.departDate,
      returnDate: returnDate ?? this.returnDate,
      passengers: passengers ?? this.passengers,
      travelClass: travelClass ?? this.travelClass,
    );
  }
}
