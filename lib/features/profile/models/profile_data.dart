import 'package:json_annotation/json_annotation.dart';
import 'package:diaspora_nearby/features/shared/models/location.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

part 'profile_data.g.dart';

@JsonSerializable(explicitToJson: true)
class ProfileData {
  String? uid;

  // Required fields
  final UserLocation homeLocation;
  final UserLocation hostLocation;
  final String firstName;
  final String lastName;
  final String phone;

  String get fullName => '$firstName $lastName';

  bool get isComplete => getMissingRequiredFields().isEmpty;

  // [NEW] Milestone Tracking
  int get totalMilestoneFields => 12;
  int get completedMilestoneFieldCount {
    int count = 0;
    if (bio != null && bio!.isNotEmpty) count++;
    if (occupation != null && occupation!.isNotEmpty) count++;
    if (yearsInHostCountry != null && yearsInHostCountry!.isNotEmpty) count++;
    if (industry != null && industry!.isNotEmpty) count++;
    if (profession != null && profession!.isNotEmpty) count++;
    if (languages != null && languages!.isNotEmpty) count++;
    if (meetingPreferences != null && meetingPreferences!.isNotEmpty) count++;
    if (availability != null && availability!.isNotEmpty) count++;
    if (interests != null && interests!.isNotEmpty) count++;
    if (servicesOffered != null && servicesOffered!.isNotEmpty) count++;
    if (lookingFor != null && lookingFor!.isNotEmpty) count++;
    if (education != null && education!.isNotEmpty) count++;
    return count;
  }

  List<String> getMissingRequiredFields() {
    final List<String> missing = [];
    // Relaxed requirements: Photo, Name, and Locations are no longer mandatory here
    // as they are captured during registration.
    // if (firstName.isEmpty) missing.add('First Name');
    // if (lastName.isEmpty) missing.add('Last Name');
    // if (profileImage.isEmpty) missing.add('Profile Photo');
    // if (homeLocation.city == null) missing.add('Home Town');
    // if (homeCountryCode == null) missing.add('Home Country');
    // if (hostLocation.city == null) missing.add('Host Town');
    // if (hostCountryCode == null) missing.add('Host Country');
    if (bio == null || bio!.isEmpty) missing.add('Bio');
    if (occupation == null || occupation!.isEmpty) missing.add('Occupation');
    if (yearsInHostCountry == null || yearsInHostCountry!.isEmpty) {
      missing.add('Years in Host Country');
    }
    if (industry == null || industry!.isEmpty) missing.add('Industry');
    if (profession == null || profession!.isEmpty) missing.add('Profession');
    if (languages == null || languages!.isEmpty) missing.add('Languages');
    if (meetingPreferences == null || meetingPreferences!.isEmpty) {
      missing.add('Meeting Preferences');
    }
    if (availability == null || availability!.isEmpty) {
      missing.add('Availability');
    }
    if (interests == null || interests!.isEmpty) missing.add('Interests');
    if (servicesOffered == null || servicesOffered!.isEmpty) {
      missing.add('Services Offered');
    }
    if (lookingFor == null || lookingFor!.isEmpty) missing.add('Looking For');
    if (education == null || education!.isEmpty) missing.add('Education');
    if (pastLocations == null || pastLocations!.isEmpty) {
      // Not required anymore per user request
    }
    return missing;
  }

  @JsonKey(name: 'profilePhoto')
  final String profileImage;

  // Optional fields
  final String? bio;
  final List<String>? interests;
  final String? occupation;
  final String? dateOfBirth;
  final UserLocation? workLocation;
  final List<Education>? education;
  final List<String>? languages;
  final SocialLinks? socialLinks;
  final String? homeCountry;
  final String? hostCountry;
  final String? homeCountryCode;
  final String? hostCountryCode;
  final CurrentLocation? currentLocation;
  final List<String>? communityMemberships;
  final List<String>?
  organizationMemberships; // Orgs where user is admin/superAdmin

  // Extended fields
  final List<String>? profession;
  final List<String>? industry;
  final String? yearsInHostCountry;
  final List<String>? servicesOffered;
  final List<String>? lookingFor;
  final List<String>? availability;
  final List<String>? meetingPreferences;
  final List<PastLocation>? pastLocations;

  // Business profile
  final BusinessProfile? businessProfile;

  // Administrative
  final DateTime? createdAt; // [NEW]
  final int? advertReportCount;
  final int?
  blockedByCount; // [NEW] Track how many users have blocked this user
  final int?
  flaggedMessagesCount; // [NEW] Track how many of this user's messages reached report threshold
  final bool? isBanned;
  final String? bannedAt;
  final String? bannedReason;

  // Radio
  final List<String>? radioFavorites;
  final List<String>? radioRecents;
  final String? radioCurrentStation;
  final bool? radioIsPlaying;

  // Admin
  final bool? isAdmin;

  // Blocking
  final List<String>? blockedUsers;

  // Notifications
  final bool? notificationsEnabled;
  final String? fcmToken;
  final List<String>? fcmTopics;

  // Privacy
  final bool? showCurrentLocationName;

  // [NEW] QR Connection info for verification
  final QRConnectionInfo? firstQrConnection;

  // Wallet
  final String? walletAddress;

  // Transient/Calculated
  final double? distance;

  ProfileData({
    this.uid,
    required this.homeLocation,
    required this.hostLocation,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.profileImage,
    this.bio,
    this.interests,
    this.occupation,
    this.dateOfBirth,
    this.workLocation,
    this.education,
    this.languages,
    this.socialLinks,
    this.homeCountry,
    this.hostCountry,
    this.homeCountryCode,
    this.hostCountryCode,
    this.currentLocation,
    this.communityMemberships,
    this.organizationMemberships,
    this.profession,
    this.industry,
    this.yearsInHostCountry,
    this.servicesOffered,
    this.lookingFor,
    this.availability,
    this.meetingPreferences,
    this.pastLocations,
    this.businessProfile,
    this.advertReportCount,
    this.blockedByCount,
    this.flaggedMessagesCount,
    this.isBanned,
    this.bannedAt,
    this.bannedReason,
    this.radioFavorites,
    this.radioRecents,
    this.radioCurrentStation,
    this.radioIsPlaying,
    this.notificationsEnabled,
    this.fcmToken,
    this.fcmTopics,
    this.distance,
    this.isAdmin,
    this.blockedUsers,
    this.createdAt,
    this.showCurrentLocationName,

    this.firstQrConnection,
    this.walletAddress,
  });

  factory ProfileData.fromJson(Map<String, dynamic> json) {
    if (json['createdAt'] is Timestamp) {
      json['createdAt'] = (json['createdAt'] as Timestamp)
          .toDate()
          .toIso8601String();
    }
    if (json['firstQrConnection'] != null) {
      final qrConn = json['firstQrConnection'] as Map<String, dynamic>;
      if (qrConn['timestamp'] is Timestamp) {
        qrConn['timestamp'] = (qrConn['timestamp'] as Timestamp)
            .toDate()
            .toIso8601String();
      }
      // Handle case-sensitivity mismatch in Firestore
      if (qrConn['locationaddress'] != null &&
          qrConn['locationAddress'] == null) {
        qrConn['locationAddress'] = qrConn['locationaddress'];
      }
    }

    // [FIX] Ensure country codes are present for querying if location data has them
    // This helps repair old/inconsistent data during loading
    if (json['homeCountryCode'] == null && json['homeLocation'] != null) {
      final loc = json['homeLocation'] as Map<String, dynamic>;
      json['homeCountryCode'] = loc['country_code'];
    }
    if (json['hostCountryCode'] == null && json['hostLocation'] != null) {
      final loc = json['hostLocation'] as Map<String, dynamic>;
      json['hostCountryCode'] = loc['country_code'];
    }

    return _$ProfileDataFromJson(json);
  }
  Map<String, dynamic> toJson() => _$ProfileDataToJson(this);

  // CopyWith Method
  ProfileData copyWith({
    String? uid,
    UserLocation? homeLocation,
    UserLocation? hostLocation,
    String? firstName,
    String? lastName,
    String? phone,
    String? profileImage,
    String? bio,
    List<String>? interests,
    String? occupation,
    String? dateOfBirth,
    UserLocation? workLocation,
    List<Education>? education,
    List<String>? languages,
    SocialLinks? socialLinks,
    String? homeCountry,
    String? hostCountry,
    String? homeCountryCode,
    String? hostCountryCode,
    CurrentLocation? currentLocation,
    List<String>? communityMemberships,
    List<String>? organizationMemberships,
    List<String>? profession,
    List<String>? industry,
    String? yearsInHostCountry,
    List<String>? servicesOffered,
    List<String>? lookingFor,
    List<String>? availability,
    List<String>? meetingPreferences,
    List<PastLocation>? pastLocations,
    BusinessProfile? businessProfile,
    DateTime? createdAt,
    int? advertReportCount,
    int? blockedByCount,
    int? flaggedMessagesCount,
    bool? isBanned,
    String? bannedAt,
    String? bannedReason,
    List<String>? radioFavorites,
    List<String>? radioRecents,
    String? radioCurrentStation,
    bool? radioIsPlaying,
    bool? isAdmin,
    List<String>? blockedUsers,
    bool? notificationsEnabled,
    String? fcmToken,
    List<String>? fcmTopics,
    double? distance,

    String? city,
    String? country,
    bool? showCurrentLocationName,

    QRConnectionInfo? firstQrConnection,
    String? walletAddress,
  }) {
    return ProfileData(
      uid: uid ?? this.uid,
      homeLocation: homeLocation ?? this.homeLocation,
      hostLocation: hostLocation ?? this.hostLocation,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phone: phone ?? this.phone,
      profileImage: profileImage ?? this.profileImage,
      bio: bio ?? this.bio,
      interests: interests ?? this.interests,
      occupation: occupation ?? this.occupation,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      workLocation: workLocation ?? this.workLocation,
      education: education ?? this.education,
      languages: languages ?? this.languages,
      socialLinks: socialLinks ?? this.socialLinks,
      homeCountry: homeCountry ?? this.homeCountry,

      hostCountry: hostCountry ?? this.hostCountry,

      homeCountryCode: homeCountryCode ?? this.homeCountryCode,
      hostCountryCode: hostCountryCode ?? this.hostCountryCode,
      currentLocation: currentLocation ?? this.currentLocation,
      communityMemberships: communityMemberships ?? this.communityMemberships,
      organizationMemberships:
          organizationMemberships ?? this.organizationMemberships,
      profession: profession ?? this.profession,
      industry: industry ?? this.industry,
      yearsInHostCountry: yearsInHostCountry ?? this.yearsInHostCountry,
      servicesOffered: servicesOffered ?? this.servicesOffered,
      lookingFor: lookingFor ?? this.lookingFor,
      availability: availability ?? this.availability,
      meetingPreferences: meetingPreferences ?? this.meetingPreferences,
      pastLocations: pastLocations ?? this.pastLocations,
      businessProfile: businessProfile ?? this.businessProfile,
      createdAt: createdAt ?? this.createdAt,
      advertReportCount: advertReportCount ?? this.advertReportCount,
      blockedByCount: blockedByCount ?? this.blockedByCount,
      flaggedMessagesCount: flaggedMessagesCount ?? this.flaggedMessagesCount,
      isBanned: isBanned ?? this.isBanned,
      bannedAt: bannedAt ?? this.bannedAt,
      bannedReason: bannedReason ?? this.bannedReason,
      radioFavorites: radioFavorites ?? this.radioFavorites,
      radioRecents: radioRecents ?? this.radioRecents,
      radioCurrentStation: radioCurrentStation ?? this.radioCurrentStation,
      radioIsPlaying: radioIsPlaying ?? this.radioIsPlaying,
      isAdmin: isAdmin ?? this.isAdmin,
      blockedUsers: blockedUsers ?? this.blockedUsers,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      fcmToken: fcmToken ?? this.fcmToken,
      fcmTopics: fcmTopics ?? this.fcmTopics,
      distance: distance ?? this.distance,
      showCurrentLocationName:
          showCurrentLocationName ?? this.showCurrentLocationName,
      firstQrConnection: firstQrConnection ?? this.firstQrConnection,
      walletAddress: walletAddress ?? this.walletAddress,
    );
  }
}

@JsonSerializable(explicitToJson: true)
class Education {
  final String institution;
  final String degree;
  final String graduationYear;

  Education({
    required this.institution,
    required this.degree,
    required this.graduationYear,
  });

  factory Education.fromJson(Map<String, dynamic> json) =>
      _$EducationFromJson(json);
  Map<String, dynamic> toJson() => _$EducationToJson(this);
}

@JsonSerializable(explicitToJson: true)
class SocialLinks {
  final String? instagram;
  final String? twitter;
  final String? linkedin;
  final String? facebook;

  SocialLinks({this.instagram, this.twitter, this.linkedin, this.facebook});

  factory SocialLinks.fromJson(Map<String, dynamic> json) =>
      _$SocialLinksFromJson(json);
  Map<String, dynamic> toJson() => _$SocialLinksToJson(this);
}

@JsonSerializable(explicitToJson: true)
class CurrentLocation {
  @JsonKey(name: 'formatted_address')
  final String formattedAddress;

  @JsonKey(name: 'place_id')
  final String placeId;

  final UserLocationGeometry geometry;
  final String? city;
  final String? state;
  final String? countryCode;
  final int timestamp;

  CurrentLocation({
    required this.formattedAddress,
    required this.placeId,
    required this.geometry,
    this.city,
    this.state,
    this.countryCode,
    required this.timestamp,
  });

  factory CurrentLocation.fromJson(Map<String, dynamic> json) =>
      _$CurrentLocationFromJson(json);
  Map<String, dynamic> toJson() => _$CurrentLocationToJson(this);
}

@JsonSerializable(explicitToJson: true)
class BusinessProfile {
  final String businessName;
  final String businessType;
  final String businessDescription;
  final String businessEmail;
  final String businessPhone;
  final String businessAddress;
  final String taxId;
  final String website;
  final bool isBusinessVerified;
  final String registeredAt;
  final String status;

  BusinessProfile({
    required this.businessName,
    required this.businessType,
    required this.businessDescription,
    required this.businessEmail,
    required this.businessPhone,
    required this.businessAddress,
    required this.taxId,
    required this.website,
    required this.isBusinessVerified,
    required this.registeredAt,
    required this.status,
  });

  factory BusinessProfile.fromJson(Map<String, dynamic> json) =>
      _$BusinessProfileFromJson(json);
  Map<String, dynamic> toJson() => _$BusinessProfileToJson(this);
}

@JsonSerializable(explicitToJson: true)
class QRConnectionInfo {
  final String otherUid;
  final String otherName;
  final String? locationAddress;
  final String timestamp; // ISO8601

  QRConnectionInfo({
    required this.otherUid,
    required this.otherName,
    this.locationAddress,
    required this.timestamp,
  });

  factory QRConnectionInfo.fromJson(Map<String, dynamic> json) =>
      _$QRConnectionInfoFromJson(json);
  Map<String, dynamic> toJson() => _$QRConnectionInfoToJson(this);
}
