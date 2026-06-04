import 'package:diaspora_nearby/features/chat/models/chat.dart';

// [NEW] Import
class HierarchyItem {
  final String id;
  final String name;
  final String type;
  // 'global', 'continent', 'country', 'state', 'city'
  final String? locationType;
  // 'home', 'host', 'global'
  final String? homeCountryCode;
  final String? hostCountryCode;
  final String? flag;
  final String? continent;
  final Map<String, dynamic>? location;
  // [NEW] Added for reconstruction
  final ChatProfileImage? profileImage;
  // [NEW] Rich avatar data
  final int totalMembers;
  final List<HierarchyItem> children;
  final bool isExpandable;
  final bool initiallyExpanded; // [NEW]
  final GlobalStats? globalStats;

  HierarchyItem({
    required this.id,
    required this.name,
    required this.type,
    this.locationType,
    this.homeCountryCode,
    this.hostCountryCode,
    this.flag,
    this.continent,
    this.location,
    this.profileImage,
    required this.totalMembers,
    this.children = const [],
    this.isExpandable = false,
    this.initiallyExpanded = false, // [NEW]
    this.globalStats,
  });

  HierarchyItem copyWith({
    String? id,
    String? name,
    String? type,
    String? locationType,
    String? homeCountryCode,
    String? hostCountryCode,
    String? flag,
    String? continent,
    Map<String, dynamic>? location,
    ChatProfileImage? profileImage,
    int? totalMembers,
    List<HierarchyItem>? children,
    bool? isExpandable,
    bool? initiallyExpanded, // [NEW]
    GlobalStats? globalStats,
  }) {
    return HierarchyItem(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      locationType: locationType ?? this.locationType,
      homeCountryCode: homeCountryCode ?? this.homeCountryCode,
      hostCountryCode: hostCountryCode ?? this.hostCountryCode,
      flag: flag ?? this.flag,
      continent: continent ?? this.continent,
      location: location ?? this.location,
      profileImage: profileImage ?? this.profileImage,
      totalMembers: totalMembers ?? this.totalMembers,
      children: children ?? this.children,
      isExpandable: isExpandable ?? this.isExpandable,
      initiallyExpanded: initiallyExpanded ?? this.initiallyExpanded, // [NEW]
      globalStats: globalStats ?? this.globalStats,
    );
  }
}

class GlobalStats {
  final int totalMembers;
  final int continents;
  final int countries;
  final int cities;

  GlobalStats({
    required this.totalMembers,
    required this.continents,
    required this.countries,
    required this.cities,
  });
}
