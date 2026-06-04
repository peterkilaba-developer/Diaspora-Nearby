class TravelSearchResult {
  final String id;
  final String title;
  final String subtitle;
  final String price;
  final String? imageUrl;
  final Map<String, dynamic> metadata;

  TravelSearchResult({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.price,
    this.imageUrl,
    this.metadata = const {},
  });
}
