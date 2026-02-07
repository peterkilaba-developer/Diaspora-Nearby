import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:json_annotation/json_annotation.dart';

part 'community_data.g.dart';

@JsonSerializable()
class Community {
  final String id;
  final String name;
  final String? description;
  final String? homeCountryCode;
  final String? hostCountryCode;
  final String? locationType; // 'home' | 'host' | 'global'
  final List<String> images;
  final String? profileImage; // Added for chat_repo compatibility
  final String? type; // Added missing type field
  final int memberCount;
  final int? totalMembers;
  final bool isPrivate;
  final Map<String, dynamic>? location;
  final String? chatId;
  final String? flag;
  final List<String> members;
  final List<String> admins;
  final int? createdAt;
  final int? updatedAt;
  final int points; // New: DSP points held by the community
  final int cumulativeEarnings; // New: Tracks aggregate member earnings toward 1M milestone
  final int memberPoints; // [NEW] Total points earned by members (basis for 10% target)
  final double awardedBalance; // [NEW] Track distributed rewards
  final double averagePoCT; // [NEW] Track community average trust score
  final String? walletAddress; // New: Metamask address for $DSP

  Community({
    required this.id,
    required this.name,
    this.description,
    this.homeCountryCode,
    this.hostCountryCode,
    this.type,
    this.locationType,
    this.images = const [],
    this.memberCount = 0,
    this.totalMembers,
    this.isPrivate = false,
    this.location,
    this.profileImage,
    this.chatId,
    this.flag,
    this.members = const [],
    this.admins = const [],
    this.createdAt,
    this.updatedAt,
    this.points = 0,
    this.cumulativeEarnings = 0,
    this.memberPoints = 0, // [NEW]
    this.awardedBalance = 0, // [NEW]
    this.averagePoCT = 0, // [NEW]
    this.walletAddress,
  });

  Community copyWith({
    String? id,
    String? name,
    String? description,
    String? homeCountryCode,
    String? hostCountryCode,
    String? type,
    String? locationType,
    List<String>? images,
    int? memberCount,
    int? totalMembers,
    bool? isPrivate,
    Map<String, dynamic>? location,
    String? profileImage,
    String? chatId,
    String? flag,
    List<String>? members,
    List<String>? admins,
    int? createdAt,
    int? updatedAt,
    int? points,
    int? cumulativeEarnings,
    int? memberPoints, // [NEW]
    double? awardedBalance, // [NEW]
    double? averagePoCT, // [NEW]
    String? walletAddress,
  }) {
    return Community(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      homeCountryCode: homeCountryCode ?? this.homeCountryCode,
      hostCountryCode: hostCountryCode ?? this.hostCountryCode,
      type: type ?? this.type,
      locationType: locationType ?? this.locationType,
      images: images ?? this.images,
      memberCount: memberCount ?? this.memberCount,
      totalMembers: totalMembers ?? this.totalMembers,
      isPrivate: isPrivate ?? this.isPrivate,
      location: location ?? this.location,
      profileImage: profileImage ?? this.profileImage,
      chatId: chatId ?? this.chatId,
      flag: flag ?? this.flag,
      members: members ?? this.members,
      admins: admins ?? this.admins,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      points: points ?? this.points,
      cumulativeEarnings: cumulativeEarnings ?? this.cumulativeEarnings,
      memberPoints: memberPoints ?? this.memberPoints, // [NEW]
      awardedBalance: awardedBalance ?? this.awardedBalance, // [NEW]
      averagePoCT: averagePoCT ?? this.averagePoCT, // [NEW]
      walletAddress: walletAddress ?? this.walletAddress,
    );
  }

  factory Community.fromJson(Map<String, dynamic> json) {
    // Handle Firestore Timestamps for createdAt/updatedAt
    if (json['createdAt'] is Timestamp) {
      json['createdAt'] =
          (json['createdAt'] as Timestamp).millisecondsSinceEpoch;
    }
    if (json['updatedAt'] is Timestamp) {
      json['updatedAt'] =
          (json['updatedAt'] as Timestamp).millisecondsSinceEpoch;
    }

    // [FIX] Robust fallback for required fields to prevent Null cast errors
    json['name'] ??= 'Unknown Community';
    json['images'] ??= [];
    json['members'] ??= [];
    json['admins'] ??= [];
    json['memberCount'] ??= 0;
    json['points'] ??= 0;
    json['cumulativeEarnings'] ??= 0;
    json['memberPoints'] ??= 0;
    json['awardedBalance'] ??= 0.0;
    json['averagePoCT'] ??= 0.0;
    json['isPrivate'] ??= false;

    return _$CommunityFromJson(json);
  }
  Map<String, dynamic> toJson() => _$CommunityToJson(this);
}

@JsonSerializable()
class CommunityData {
  final String id;
  final String name;
  final String? profileImage;

  CommunityData({required this.id, required this.name, this.profileImage});

  factory CommunityData.fromJson(Map<String, dynamic> json) =>
      _$CommunityDataFromJson(json);
  Map<String, dynamic> toJson() => _$CommunityDataToJson(this);
}
