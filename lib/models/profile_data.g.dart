// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'profile_data.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProfileData _$ProfileDataFromJson(Map<String, dynamic> json) => ProfileData(
  uid: json['uid'] as String?,
  homeLocation: UserLocation.fromJson(
    json['homeLocation'] as Map<String, dynamic>,
  ),
  hostLocation: UserLocation.fromJson(
    json['hostLocation'] as Map<String, dynamic>,
  ),
  firstName: json['firstName'] as String,
  lastName: json['lastName'] as String,
  phone: json['phone'] as String,
  profileImage: json['profilePhoto'] as String,
  bio: json['bio'] as String?,
  interests: (json['interests'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  occupation: json['occupation'] as String?,
  dateOfBirth: json['dateOfBirth'] as String?,
  workLocation: json['workLocation'] == null
      ? null
      : UserLocation.fromJson(json['workLocation'] as Map<String, dynamic>),
  education: (json['education'] as List<dynamic>?)
      ?.map((e) => Education.fromJson(e as Map<String, dynamic>))
      .toList(),
  languages: (json['languages'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  socialLinks: json['socialLinks'] == null
      ? null
      : SocialLinks.fromJson(json['socialLinks'] as Map<String, dynamic>),
  homeCountry: json['homeCountry'] as String?,
  hostCountry: json['hostCountry'] as String?,
  homeCountryCode: json['homeCountryCode'] as String?,
  hostCountryCode: json['hostCountryCode'] as String?,
  currentLocation: json['currentLocation'] == null
      ? null
      : CurrentLocation.fromJson(
          json['currentLocation'] as Map<String, dynamic>,
        ),
  communityMemberships: (json['communityMemberships'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  organizationMemberships: (json['organizationMemberships'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  profession: (json['profession'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  industry: (json['industry'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  yearsInHostCountry: json['yearsInHostCountry'] as String?,
  servicesOffered: (json['servicesOffered'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  lookingFor: (json['lookingFor'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  availability: (json['availability'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  meetingPreferences: (json['meetingPreferences'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  pastLocations: (json['pastLocations'] as List<dynamic>?)
      ?.map((e) => PastLocation.fromJson(e as Map<String, dynamic>))
      .toList(),
  businessProfile: json['businessProfile'] == null
      ? null
      : BusinessProfile.fromJson(
          json['businessProfile'] as Map<String, dynamic>,
        ),
  advertReportCount: (json['advertReportCount'] as num?)?.toInt(),
  isBanned: json['isBanned'] as bool?,
  bannedAt: json['bannedAt'] as String?,
  bannedReason: json['bannedReason'] as String?,
  radioFavorites: (json['radioFavorites'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  radioRecents: (json['radioRecents'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  radioCurrentStation: json['radioCurrentStation'] as String?,
  radioIsPlaying: json['radioIsPlaying'] as bool?,
  notificationsEnabled: json['notificationsEnabled'] as bool?,
  fcmToken: json['fcmToken'] as String?,
  fcmTopics: (json['fcmTopics'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  distance: (json['distance'] as num?)?.toDouble(),
  isAdmin: json['isAdmin'] as bool?,
  blockedUsers: (json['blockedUsers'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  createdAt: json['createdAt'] == null
      ? null
      : DateTime.parse(json['createdAt'] as String),
  showCurrentLocationName: json['showCurrentLocationName'] as bool?,
);

Map<String, dynamic> _$ProfileDataToJson(ProfileData instance) =>
    <String, dynamic>{
      'uid': instance.uid,
      'homeLocation': instance.homeLocation.toJson(),
      'hostLocation': instance.hostLocation.toJson(),
      'firstName': instance.firstName,
      'lastName': instance.lastName,
      'phone': instance.phone,
      'profilePhoto': instance.profileImage,
      'bio': instance.bio,
      'interests': instance.interests,
      'occupation': instance.occupation,
      'dateOfBirth': instance.dateOfBirth,
      'workLocation': instance.workLocation?.toJson(),
      'education': instance.education?.map((e) => e.toJson()).toList(),
      'languages': instance.languages,
      'socialLinks': instance.socialLinks?.toJson(),
      'homeCountry': instance.homeCountry,
      'hostCountry': instance.hostCountry,
      'homeCountryCode': instance.homeCountryCode,
      'hostCountryCode': instance.hostCountryCode,
      'currentLocation': instance.currentLocation?.toJson(),
      'communityMemberships': instance.communityMemberships,
      'organizationMemberships': instance.organizationMemberships,
      'profession': instance.profession,
      'industry': instance.industry,
      'yearsInHostCountry': instance.yearsInHostCountry,
      'servicesOffered': instance.servicesOffered,
      'lookingFor': instance.lookingFor,
      'availability': instance.availability,
      'meetingPreferences': instance.meetingPreferences,
      'pastLocations': instance.pastLocations?.map((e) => e.toJson()).toList(),
      'businessProfile': instance.businessProfile?.toJson(),
      'createdAt': instance.createdAt?.toIso8601String(),
      'advertReportCount': instance.advertReportCount,
      'isBanned': instance.isBanned,
      'bannedAt': instance.bannedAt,
      'bannedReason': instance.bannedReason,
      'radioFavorites': instance.radioFavorites,
      'radioRecents': instance.radioRecents,
      'radioCurrentStation': instance.radioCurrentStation,
      'radioIsPlaying': instance.radioIsPlaying,
      'isAdmin': instance.isAdmin,
      'blockedUsers': instance.blockedUsers,
      'notificationsEnabled': instance.notificationsEnabled,
      'fcmToken': instance.fcmToken,
      'fcmTopics': instance.fcmTopics,
      'showCurrentLocationName': instance.showCurrentLocationName,
      'distance': instance.distance,
    };

Education _$EducationFromJson(Map<String, dynamic> json) => Education(
  institution: json['institution'] as String,
  degree: json['degree'] as String,
  graduationYear: json['graduationYear'] as String,
);

Map<String, dynamic> _$EducationToJson(Education instance) => <String, dynamic>{
  'institution': instance.institution,
  'degree': instance.degree,
  'graduationYear': instance.graduationYear,
};

SocialLinks _$SocialLinksFromJson(Map<String, dynamic> json) => SocialLinks(
  instagram: json['instagram'] as String?,
  twitter: json['twitter'] as String?,
  linkedin: json['linkedin'] as String?,
  facebook: json['facebook'] as String?,
);

Map<String, dynamic> _$SocialLinksToJson(SocialLinks instance) =>
    <String, dynamic>{
      'instagram': instance.instagram,
      'twitter': instance.twitter,
      'linkedin': instance.linkedin,
      'facebook': instance.facebook,
    };

CurrentLocation _$CurrentLocationFromJson(Map<String, dynamic> json) =>
    CurrentLocation(
      formattedAddress: json['formatted_address'] as String,
      placeId: json['place_id'] as String,
      geometry: UserLocationGeometry.fromJson(
        json['geometry'] as Map<String, dynamic>,
      ),
      city: json['city'] as String?,
      state: json['state'] as String?,
      countryCode: json['countryCode'] as String?,
      timestamp: (json['timestamp'] as num).toInt(),
    );

Map<String, dynamic> _$CurrentLocationToJson(CurrentLocation instance) =>
    <String, dynamic>{
      'formatted_address': instance.formattedAddress,
      'place_id': instance.placeId,
      'geometry': instance.geometry.toJson(),
      'city': instance.city,
      'state': instance.state,
      'countryCode': instance.countryCode,
      'timestamp': instance.timestamp,
    };

BusinessProfile _$BusinessProfileFromJson(Map<String, dynamic> json) =>
    BusinessProfile(
      businessName: json['businessName'] as String,
      businessType: json['businessType'] as String,
      businessDescription: json['businessDescription'] as String,
      businessEmail: json['businessEmail'] as String,
      businessPhone: json['businessPhone'] as String,
      businessAddress: json['businessAddress'] as String,
      taxId: json['taxId'] as String,
      website: json['website'] as String,
      isBusinessVerified: json['isBusinessVerified'] as bool,
      registeredAt: json['registeredAt'] as String,
      status: json['status'] as String,
    );

Map<String, dynamic> _$BusinessProfileToJson(BusinessProfile instance) =>
    <String, dynamic>{
      'businessName': instance.businessName,
      'businessType': instance.businessType,
      'businessDescription': instance.businessDescription,
      'businessEmail': instance.businessEmail,
      'businessPhone': instance.businessPhone,
      'businessAddress': instance.businessAddress,
      'taxId': instance.taxId,
      'website': instance.website,
      'isBusinessVerified': instance.isBusinessVerified,
      'registeredAt': instance.registeredAt,
      'status': instance.status,
    };
