import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';

import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/models/profile_data.dart';
import 'package:diaspora_nearby/features/shared/widgets/user_card.dart';
import 'package:diaspora_nearby/services/google_places_service.dart';
import 'package:flutter_google_places_sdk/flutter_google_places_sdk.dart';
import 'package:diaspora_nearby/data/countries.dart' as country_data;
import 'package:diaspora_nearby/models/location.dart' as loc_model;
import 'package:diaspora_nearby/utils/location_utils.dart';
import 'package:diaspora_nearby/features/community/repository/community_repository.dart';
import 'package:diaspora_nearby/features/organization/repository/organization_repository.dart';
import 'package:diaspora_nearby/features/events/repository/event_repository.dart';
import 'package:diaspora_nearby/models/community_data.dart' as comm_model;
import 'package:diaspora_nearby/models/event_data.dart' as event_model;
import 'package:diaspora_nearby/models/chat.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/services/community_service.dart';
import 'package:diaspora_nearby/features/chat/utils/community_chat_utils.dart';

class UserProfileScreen extends ConsumerStatefulWidget {
  final String userId;
  final bool isEnforced;

  const UserProfileScreen({
    super.key,
    required this.userId,
    this.isEnforced = false,
  });

  @override
  ConsumerState<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends ConsumerState<UserProfileScreen> with WidgetsBindingObserver {
  late List<String> _yearRange;

  // Location Update State
  final _searchController = TextEditingController();
  List<AutocompletePrediction> _predictions = [];
  bool _isUpdatingLocation = false;

  // Inline Editing State
  bool _isEditing = false;
  bool _isSaving = false;
  final TextEditingController _bioController = TextEditingController();
  final TextEditingController _occupationController = TextEditingController();
  
  // Multi-select state
  List<String> _selectedProfessions = [];
  List<String> _selectedIndustries = [];
  List<String> _selectedAvailability = [];
  List<String> _selectedServices = [];
  List<String> _selectedLookingFor = [];
  List<String> _selectedMeetingPreferences = [];
  List<String> _selectedLanguages = [];
  List<String> _selectedInterests = [];

  // Data Fetching State
  late Future<List<comm_model.Community>> _communitiesFuture;
  late Future<List<Chat>> _groupsFuture;
  late Future<List<Map<String, dynamic>>> _orgsFuture;
  late Stream<List<event_model.Event>> _eventsStream;

  // Initialization Tracker
  String? _initializedUserId;
  late Future<ProfileData?> _profileFuture;
  
  // Location Update State
  loc_model.UserLocation? _tempSelectedLocation;
  bool _isLocationVerified = false;
  
  // [NEW] Permission Warning State
  bool _showPermissionWarning = false;

  List<loc_model.PastLocation> _pastLocations = []; 
  String _selectedYearsInHost = ''; 

  static const List<String> _availabilityOptions = [
    'Full-time', 'Part-time', 'Weekends only', 'Evenings only', 'Open to collaborate', 'Remote only', 'Not available',
  ];
  static const List<String> _industryOptions = [
    'Technology', 'Healthcare', 'Finance', 'Education', 'Construction', 'Retail', 'Art & Design', 'Hospitality', 'Legal', 'Government', 'Non-Profit', 'Other',
  ];
  static const List<String> _professionOptions = [
    'Software Engineer', 'Doctor', 'Teacher', 'Lawyer', 'Accountant', 'Nurse', 'Designer', 'Project Manager', 'Marketing Specialist', 'Sales Professional', 'Analyst', 'Entrepreneur', 'Student', 'Researcher', 'Other',
  ];
  static const List<String> _occupationOptions = [
    'Full-time Employee', 'Part-time Employee', 'Self-employed', 'Freelancer', 'Contractor', 'Intern', 'Unemployed', 'Retired', 'Other',
  ];
  static const List<String> _languageOptions = [
    'Amharic', 'Arabic', 'Bengali', 'Chinese (Mandarin)', 'English', 'French', 'German', 'Hausa', 'Hindi', 'Igbo', 
    'Indonesian', 'Italian', 'Japanese', 'Korean', 'Oromo', 'Portuguese', 'Punjabi', 'Russian', 'Somali', 
    'Spanish', 'Swahili', 'Tamil', 'Telugu', 'Turkish', 'Urdu', 'Vietnamese', 'Yoruba', 'Zulu', 'Other'
  ];
  static const List<String> _servicesOptions = [
    'Mentorship', 'Career Advice', 'Legal Assistance', 'Financial Planning', 'Housing Help', 
    'Technical Support', 'Translation', 'Business Partnership', 'Freelancing', 'Other'
  ];
  static const List<String> _lookingForOptions = [
    'Job Opportunities', 'Business Partners', 'Friends', 'Language Exchange', 'Networking', 
    'Local Advice', 'Mentors', 'Events', 'Other'
  ];
  static const List<String> _interestsOptions = [
    'Technology', 'Sports', 'Music', 'Travel', 'Food', 'Art', 'Reading', 'Gaming', 'Fitness', 'Photography', 'Other'
  ];
  static const List<String> _meetingTypeOptions = [
    'Virtual / Online', 'Coffee / In-Person', 'Group Meetup', 'Professional Setting', 'Casual'
  ];
  @override
  void initState() {
    super.initState();
    // Initialize year range properly
    final currentYear = DateTime.now().year;
    _yearRange = List.generate(
      currentYear - 1960 + 1,
      (index) => (currentYear - index).toString(),
    );
    _yearRange.insert(0, 'Since birth');
    
    WidgetsBinding.instance.addObserver(this);
    _refreshProfile();
    _checkLocationPermission();
  }

  void _refreshProfile() {
    _profileFuture = ref.read(profileRepositoryProvider).getUserProfile(widget.userId);
    _communitiesFuture = ref.read(communityRepositoryProvider).getUserCommunities(widget.userId);
    _groupsFuture = ref.read(chatRepositoryProvider).getUserChats().then((chats) => chats.where((c) => c.isGroup).toList());
    _orgsFuture = ref.read(organizationRepositoryProvider).getUserOrganizations(widget.userId);
    _eventsStream = ref.read(eventRepositoryProvider).getJoinedEvents(widget.userId);
  }

  @override
  void didUpdateWidget(UserProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _refreshProfile();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _bioController.dispose();
    _occupationController.dispose();
    super.dispose();
  }

  Future<void> _checkLocationPermission() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      if (mounted) setState(() => _showPermissionWarning = true);
    } else {
      if (mounted && _showPermissionWarning) setState(() => _showPermissionWarning = false);
    }
  }

  void _initializeControllers(ProfileData profile) {
    if (_initializedUserId == profile.uid) return;
    _initializedUserId = profile.uid;
    
    _bioController.text = profile.bio ?? '';
    _occupationController.text = profile.occupation ?? '';
    
    _selectedProfessions = List.from(profile.profession ?? []);
    _selectedIndustries = List.from(profile.industry ?? []);
    _selectedAvailability = List.from(profile.availability ?? []);
    
    _selectedLanguages = List.from(profile.languages ?? []);
    _selectedInterests = List.from(profile.interests ?? []);
    _selectedServices = List.from(profile.servicesOffered ?? []);
    _selectedLookingFor = List.from(profile.lookingFor ?? []);
    _selectedMeetingPreferences = List.from(profile.meetingPreferences ?? []);

    _pastLocations = List.from(profile.pastLocations ?? []); 
    _selectedYearsInHost = profile.yearsInHostCountry ?? ''; 
  }

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);
    try {
      final user = ref.read(authRepositoryProvider).currentUser;
      if (user == null) return;
      
      final currentProfile = await ref.read(profileRepositoryProvider).getUserProfile(user.uid);
      if (currentProfile == null) return;

      final updatedProfile = currentProfile.copyWith(
        bio: _bioController.text.trim(),
        profession: _selectedProfessions,
        industry: _selectedIndustries,
        occupation: _occupationController.text.trim(),
        availability: _selectedAvailability,
        languages: _selectedLanguages,
        interests: _selectedInterests,
        servicesOffered: _selectedServices,
        lookingFor: _selectedLookingFor,
        meetingPreferences: _selectedMeetingPreferences,
        pastLocations: _pastLocations, 
        yearsInHostCountry: _selectedYearsInHost, 
      );

      await ref.read(profileRepositoryProvider).saveUserProfile(user.uid, updatedProfile);
      
      if (mounted) {
        // Update local future immediately to avoid loading spinner
        setState(() {
          _isEditing = false;
          _profileFuture = Future.value(updatedProfile);
        });
        
        // Update global provider
        ref.read(userProfileProvider.notifier).updateProfile(updatedProfile);
        
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated successfully!')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving profile: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _onSearchChanged(String input) async {
    if (input.isEmpty) {
      if (mounted) setState(() => _predictions = []);
      return;
    }
    final places = ref.read(googlePlacesServiceProvider);
    final results = await places.autocomplete(input);
    if (mounted) setState(() => _predictions = results);
  }

  Future<void> _selectPlace(String placeId) async {
    setState(() => _isUpdatingLocation = true);
    try {
      final places = ref.read(googlePlacesServiceProvider);
      final response = await places.getPlaceDetails(placeId);
      final place = response?.place;
      
      if (place == null) throw Exception('Could not fetch place details');

      List<AddressComponent> components = place.addressComponents ?? [];
      final parsedLoc = parseLocationComponents(place.address ?? '', components);
      if (parsedLoc == null) throw Exception('Could not parse location components');

      final newLocation = loc_model.UserLocation(
        formattedAddress: place.address ?? '',
        placeId: place.id ?? placeId,
        city: parsedLoc.city,
        state: parsedLoc.state,
        country: parsedLoc.country,
        countryCode: parsedLoc.countryCode,
        geometry: place.latLng != null ? loc_model.UserLocationGeometry(
          location: loc_model.UserLocationCoordinates(
            lat: place.latLng!.lat,
            lng: place.latLng!.lng,
          ),
        ) : null,
      );

      await _verifyLocation(newLocation, parsedLoc.countryCode);
      
      if (_isLocationVerified) {
         setState(() {
           _tempSelectedLocation = newLocation;
           _predictions = [];
           _searchController.text = newLocation.formattedAddress;
         });
         FocusScope.of(context).unfocus(); 
      }
    } catch (e) {
      if (mounted) {
        if (!e.toString().contains('Verification failed')) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
        setState(() {
          _tempSelectedLocation = null;
          _isLocationVerified = false;
        });
      }
    } finally {
      if (mounted) setState(() => _isUpdatingLocation = false);
    }
  }

  Future<void> _verifyLocation(loc_model.UserLocation newLoc, String? targetCountryCode) async {
    if (targetCountryCode == null) throw Exception('Selected location has no country code');

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) throw Exception('Location permission denied');
    }
    if (permission == LocationPermission.deniedForever) throw Exception('Location permission permanently denied');

    final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
    List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
    if (placemarks.isEmpty) throw Exception('Could not determine your current country');

    final currentCountryCode = placemarks.first.isoCountryCode;
    final normalizedTarget = targetCountryCode.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '').substring(0, 2);
    final normalizedCurrent = currentCountryCode?.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '').substring(0, 2);

    if (normalizedCurrent != normalizedTarget) {
      _showVerificationErrorDialog(newLoc.country ?? 'the target country', normalizedCurrent ?? '??', normalizedTarget);
      throw Exception('Verification failed'); 
    }
    _isLocationVerified = true;
  }

  Future<void> _saveLocationUpdate() async {
    if (_tempSelectedLocation == null || !_isLocationVerified) return;

    setState(() => _isUpdatingLocation = true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Location Update'),
        content: Text('Are you sure you want to update your host town to ${_tempSelectedLocation!.formattedAddress}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Update')),
        ],
      ),
    );

    if (confirmed != true) {
      setState(() => _isUpdatingLocation = false);
      return; 
    }

    try {
      final user = ref.read(authRepositoryProvider).currentUser;
      if (user != null) {
         await ref.read(profileRepositoryProvider).updateHostLocation(
          user.uid, 
          _tempSelectedLocation!, 
          _tempSelectedLocation!.country ?? '', 
          _tempSelectedLocation!.countryCode ?? ''
        );

        final city = _tempSelectedLocation!.city ?? '';
        final countryCode = _tempSelectedLocation!.countryCode ?? '';
        final country = _tempSelectedLocation!.country;
        
        if (city.isNotEmpty && countryCode.isNotEmpty) {
           try {
               final currentProfile = ref.read(userProfileProvider).value;
               if (currentProfile?.homeCountryCode != null) {
                  final locationParsed = LocationParsed(
                    city: city,
                    state: _tempSelectedLocation!.state,
                    country: country ?? '', 
                    countryCode: countryCode, 
                  );

                  final communityIds = await CommunityService().ensureCommunitiesForLocationHierarchy(
                     location: locationParsed,
                     locationType: 'host',
                     userId: user.uid,
                     homeCountryCode: currentProfile!.homeCountryCode!,
                     hostCountryCode: countryCode,
                  );
                  
                  if (communityIds.isNotEmpty) {
                    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
                      'communityMemberships': FieldValue.arrayUnion(communityIds),
                    });
                  }
               }
           } catch (e) {
             debugPrint('Error syncing host community: $e');
           }
        }
        
        _refreshProfile();
         setState(() {
           _tempSelectedLocation = null;
           _isLocationVerified = false;
         });
         
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Host town updated successfully!')));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _isUpdatingLocation = false);
    }
  }

  void _showVerificationErrorDialog(String targetCountry, String currentCode, String targetCode) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Verification Failed'),
        content: Text('You must be physically located in $targetCountry to update your host town to this location.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Understand'))],
      ),
    );
  }

  Future<void> _openSettings() async {
    await Geolocator.openAppSettings();
  }

  // Lifecycle
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
       _checkLocationPermission(); 
       if (widget.isEnforced) {
          _checkAndNavigate();
       }
    }
  }

  Future<void> _checkAndNavigate() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
       if (mounted) context.go('/nearby');
    }
  }

  // --- Past Location ---
  void _showAddPastLocationDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog( 
        insetPadding: const EdgeInsets.symmetric(horizontal: 8),
        child: _AddPastLocationDialog(
          yearRange: _yearRange,
          onAdd: (loc) async {
             setState(() => _pastLocations.add(loc));
             // Sync logic simplified for brevity - assumes saveProfile will persist
          },
          placesService: ref.read(googlePlacesServiceProvider),
        ),
      ),
    );
  }

  Widget _buildSectionContainer({required String title, IconData? icon, required Widget child, Widget? action}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        // Border removed as requested
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              if (action != null) action,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authRepositoryProvider).currentUser;
    final isSelf = user?.uid == widget.userId;

    return Stack(
      children: [
        FutureBuilder<ProfileData?>(
          future: _profileFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
            if (snapshot.data == null) return const Scaffold(body: Center(child: Text('User not found')));

            final profile = snapshot.data!;
            if (isSelf) _initializeControllers(profile);

            return Scaffold(
              appBar: AppBar(
                 title: const Text('My Profile'),
                 actions: [
                   if (isSelf) ...[
                      if (_isEditing) ...[
                         TextButton(onPressed: () => setState(() { _isEditing = false; _initializeControllers(profile); }), child: const Text('Cancel')),
                         TextButton(onPressed: _isSaving ? null : _saveProfile, child: _isSaving ? const CircularProgressIndicator() : const Text('Save')),
                      ] else 
                         TextButton.icon(onPressed: () => setState(() => _isEditing = true), icon: const Icon(LucideIcons.edit, size: 16), label: const Text('Edit')),
                   ]
                 ],
                 leading: widget.isEnforced ? const SizedBox() : null,
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 40, left: 8, right: 8),
                child: Column(
                   children: [
                      UserCardView(
                        user: _tempSelectedLocation != null ? profile.copyWith(hostLocation: _tempSelectedLocation) : profile,
                        isStatic: false,
                        onChatTap: () => context.push('/chat/direct/${profile.uid}'),
                      ),
                      const SizedBox(height: 16),
                      
                      // Residency & Location Section (Moved up)
                      if (_isEditing || (profile.yearsInHostCountry != null && profile.yearsInHostCountry!.isNotEmpty) || _pastLocations.isNotEmpty)
                        _buildSectionContainer(
                           title: 'Residency & Locations',
                           icon: LucideIcons.mapPin,
                           child: Column(
                             crossAxisAlignment: CrossAxisAlignment.start,
                             children: [
                                _buildResidencySection(profile),
                                const SizedBox(height: 12),
                                _buildPastLocationsSection(),
                                if (isSelf && _isEditing) _buildLocationUpdateSection(),
                             ],
                           )
                        ),

                      // Business Profile Card
                      if (profile.businessProfile?.isBusinessVerified == true)
                        _buildBusinessCard(profile.businessProfile!),

                      // Bio Section (Keep as text area)
                      if (_isEditing || (profile.bio != null && profile.bio!.isNotEmpty))
                        _buildSectionContainer(
                          title: 'About Me',
                          icon: LucideIcons.user,
                          child: _isEditing 
                              ? TextField(
                                  controller: _bioController,
                                  maxLines: 4,
                                  textCapitalization: TextCapitalization.sentences,
                                  decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Write something about yourself...'),
                                )
                              : Text(profile.bio!, style: const TextStyle(height: 1.5)),
                        ),

                      // Professional Info
                      if (_isEditing || (profile.profession?.isNotEmpty ?? false) || (profile.industry?.isNotEmpty ?? false))
                        _buildSectionContainer(
                          title: 'Professional Info',
                          icon: LucideIcons.briefcase,
                          child: _isEditing ? _buildProfessionalEditForm() : _buildProfessionalDisplay(profile),
                        ),
                      
                      // Languages
                      if (_isEditing || (profile.languages?.isNotEmpty ?? false))
                         _buildSectionContainer(
                           title: 'Languages',
                           icon: LucideIcons.languages,
                           child: _isEditing 
                             ? _buildMultiSelectDropdown(
                                 title: 'Languages',
                                 options: _languageOptions,
                                 selectedValues: _selectedLanguages,
                                 onChanged: (v) => setState(() => _selectedLanguages = v),
                               )
                             : _buildTagsDisplay(profile.languages ?? []),
                         ),

                      // Education Section
                      if (profile.education != null && profile.education!.isNotEmpty)
                         _buildSectionContainer(
                            title: 'Education',
                            icon: LucideIcons.graduationCap,
                            child: Column(
                              children: profile.education!.map((edu) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(edu.institution, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('${edu.degree} • ${edu.graduationYear}'),
                                leading: const Icon(LucideIcons.school),
                              )).toList(),
                            )
                         ),

                      // Interests
                      if (_isEditing || (profile.interests?.isNotEmpty ?? false))
                        _buildSectionContainer(
                          title: 'Interests',
                          icon: LucideIcons.heart,
                          child: _isEditing
                            ? _buildMultiSelectDropdown(
                                title: 'Interests',
                                options: _interestsOptions,
                                selectedValues: _selectedInterests,
                                onChanged: (v) => setState(() => _selectedInterests = v),
                              )
                            : _buildTagsDisplay(profile.interests ?? []),
                        ),
                      
                      // Community Support (Services & Looking For)
                      if (_isEditing || (profile.servicesOffered?.isNotEmpty ?? false) || (profile.lookingFor?.isNotEmpty ?? false))
                         _buildSectionContainer(
                            title: 'Community Support',
                            icon: LucideIcons.users,
                            child: Column(
                               crossAxisAlignment: CrossAxisAlignment.start,
                               children: [
                                  if (_isEditing || (profile.servicesOffered?.isNotEmpty ?? false)) ...[
                                     const Text('Services I Can Offer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                     const SizedBox(height: 8),
                                     _isEditing 
                                       ? _buildMultiSelectDropdown(
                                           title: 'Services',
                                           options: _servicesOptions,
                                           selectedValues: _selectedServices,
                                           onChanged: (v) => setState(() => _selectedServices = v),
                                         )
                                       : _buildTagsDisplay(profile.servicesOffered ?? [], isOutline: true),
                                     const SizedBox(height: 16),
                                  ],
                                  if (_isEditing || (profile.lookingFor?.isNotEmpty ?? false)) ...[
                                     const Text("What I'm Looking For", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                     const SizedBox(height: 8),
                                     _isEditing 
                                       ? _buildMultiSelectDropdown(
                                           title: "Looking For",
                                           options: _lookingForOptions,
                                           selectedValues: _selectedLookingFor,
                                           onChanged: (v) => setState(() => _selectedLookingFor = v),
                                         )
                                       : _buildTagsDisplay(profile.lookingFor ?? []),
                                  ]
                               ],
                            )
                         ),

                      // Goals/Availability
                      if (_isEditing || (profile.availability?.isNotEmpty ?? false))
                         _buildSectionContainer(
                            title: 'Availability',
                            icon: LucideIcons.clock,
                            child: _isEditing ? _buildGoalsEdit() : _buildGoalsDisplay(profile),
                         ),
                      
                      // Meeting Preferences
                      if (_isEditing || (profile.meetingPreferences?.isNotEmpty ?? false))
                         _buildSectionContainer(
                            title: 'Meeting Preferences',
                            icon: LucideIcons.coffee,
                            child: _isEditing
                              ? _buildMultiSelectDropdown(
                                  title: 'Meeting Preferences',
                                  options: _meetingTypeOptions,
                                  selectedValues: _selectedMeetingPreferences,
                                  onChanged: (v) => setState(() => _selectedMeetingPreferences = v),
                                )
                              : _buildTagsDisplay(profile.meetingPreferences ?? []),
                         ),

                      // Social Links
                      if (profile.socialLinks != null)
                         _buildSectionContainer(
                            title: 'Social Media',
                            icon: LucideIcons.share2,
                            child: Wrap(
                              spacing: 16,
                              children: [
                                if (profile.socialLinks!.instagram?.isNotEmpty ?? false) _buildSocialLink(LucideIcons.instagram, profile.socialLinks!.instagram!),
                                if (profile.socialLinks!.twitter?.isNotEmpty ?? false) _buildSocialLink(LucideIcons.twitter, profile.socialLinks!.twitter!),
                                if (profile.socialLinks!.linkedin?.isNotEmpty ?? false) _buildSocialLink(LucideIcons.linkedin, profile.socialLinks!.linkedin!),
                                if (profile.socialLinks!.facebook?.isNotEmpty ?? false) _buildSocialLink(LucideIcons.facebook, profile.socialLinks!.facebook!),
                              ],
                            ),
                         ),

                      const SizedBox(height: 8),
                      // Removed Communities Section as requested
                      _buildDynamicMembershipSection<Chat>('Groups', LucideIcons.messageCircle, _groupsFuture, (g) => ListTile(title: Text(g.name), dense: true)),
                      _buildDynamicMembershipSection<Map<String, dynamic>>('Organizations', LucideIcons.building, _orgsFuture, (o) => ListTile(title: Text(o['name'] ?? 'Org'), subtitle: Text(o['type'] ?? ''), dense: true)),
                      _buildEventsSection(),
                   ],
                ),
              ),
            );
          },
        ),
        if (_showPermissionWarning)
          Container(
            color: Colors.black54,
            child: Center(
              child: Card(
                color: Colors.red.shade700,
                margin: const EdgeInsets.symmetric(horizontal: 32),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.mapPinOff, color: Colors.white, size: 48),
                      const SizedBox(height: 16),
                      const Text('Location Required', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text('This app requires location permission to function.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _openSettings,
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF9CAF88), foregroundColor: Colors.white),
                        child: const Text('Enable Location Permission'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMultiSelectDropdown({
    required String title,
    required List<String> options,
    required List<String> selectedValues,
    required ValueChanged<List<String>> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () async {
            final List<String>? results = await showDialog(
              context: context,
              builder: (BuildContext context) {
                return _MultiSelectDialog(
                  title: title,
                  items: options,
                  initialSelectedItems: selectedValues,
                );
              },
            );
            if (results != null) {
              onChanged(results);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                 Text('Select $title', style: TextStyle(color: Colors.grey[700])),
                 const Icon(LucideIcons.plus, size: 20, color: Colors.grey),
              ],
            ),
          ),
        ),
        if (selectedValues.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
               spacing: 8,
               runSpacing: 8,
               children: selectedValues.map((t) => Chip(
                  label: Text(t),
                  deleteIcon: const Icon(LucideIcons.x, size: 16),
                  onDeleted: () {
                     final newList = List<String>.from(selectedValues)..remove(t);
                     onChanged(newList);
                  },
               )).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildTagsDisplay(List<String> tags, {bool isOutline = false}) {
     if (tags.isEmpty) return const Text('Not specified', style: TextStyle(color: Colors.grey));
     return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: tags.map((t) => Chip(
           label: Text(t),
           backgroundColor: isOutline ? Colors.transparent : null,
           side: isOutline ? BorderSide(color: Theme.of(context).dividerColor) : null,
        )).toList(),
     );
  }

  Widget _buildLanguagesEdit() => const SizedBox.shrink(); 
  Widget _buildServicesEdit() => const SizedBox.shrink();
  Widget _buildLookingForEdit() => const SizedBox.shrink(); 

  // Placeholders for edit widgets since I'm not implementing full edit logic for these yet, but the sections call them. 
  // I should probably just show "Edit mode not implemented" or similar if I don't implement them, 
  // BUT the user asked to "add all that is missing" assuming the view.
  // If I add `_isEditing` checks, I need to provide the widgets.
  // Given constraints, I will implement basic TextField placeholders or just re-use display for now if editing isn't crucial 
  // OR just implement empty containers with TODOs.
  // However, `_buildInterestsEdit` exists. 
  // I'll make the new edit widgets return a Text("Coming soon") or similar to avoid errors, 
  // OR just assume for this task I am focusing on VIEW restoration.
  // The `user_profile_screen.dart` already has `_buildInterestsEdit`.
  


  Widget _buildBusinessCard(BusinessProfile business) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: Theme.of(context).brightness == Brightness.dark 
            ? [Colors.blue.shade900.withOpacity(0.2), Colors.indigo.shade900.withOpacity(0.2)]
            : [Colors.blue.shade50, Colors.indigo.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.blue.shade600,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(LucideIcons.briefcase, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(business.businessName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark ? Colors.blue.shade900 : Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(business.businessType, style: TextStyle(fontSize: 12, color: Theme.of(context).brightness == Brightness.dark ? Colors.blue.shade300 : Colors.blue.shade700)),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark ? Colors.green.shade900 : Colors.green.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Text('Verified Business', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Theme.of(context).brightness == Brightness.dark ? Colors.green.shade300 : Colors.green.shade700)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(business.businessDescription, style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              if (business.businessEmail.isNotEmpty) _buildBusinessContact(LucideIcons.globe, business.businessEmail, 'mailto:${business.businessEmail}'),
              if (business.businessPhone.isNotEmpty) _buildBusinessContact(LucideIcons.phone, business.businessPhone, 'tel:${business.businessPhone}'),
              if (business.website.isNotEmpty) _buildBusinessContact(LucideIcons.link, business.website, business.website),
            ],
          ),
          if (business.businessAddress.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(LucideIcons.mapPin, size: 14, color: Colors.blue.shade600),
                const SizedBox(width: 4),
                Expanded(child: Text(business.businessAddress, style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor))),
              ],
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildBusinessContact(IconData icon, String text, String url) {
    return InkWell(
      onTap: () => launchUrl(Uri.parse(url)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.blue.shade600),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 12, color: Colors.blue.shade600, decoration: TextDecoration.underline)),
        ],
      ),
    );
  }

  Widget _buildSocialLink(IconData icon, String url) {
     return IconButton(
       icon: Icon(icon), 
       onPressed: () => launchUrl(Uri.parse(url)),
       tooltip: url,
     );
  }
  Widget _buildResidencySection(ProfileData profile) {
     if (_isEditing) {
       return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             Text('Lived in ${profile.hostCountry ?? 'Host Country'} since', style: const TextStyle(fontWeight: FontWeight.bold)),
             const SizedBox(height: 8),
             DropdownButtonFormField<String>(
               value: _selectedYearsInHost.isNotEmpty ? _selectedYearsInHost : null,
               items: _yearRange.map((y) => DropdownMenuItem(value: y, child: Text(y))).toList(),
               onChanged: (v) => setState(() => _selectedYearsInHost = v ?? ''),
               decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
             ),
          ],
       );
     }
     
     if (profile.yearsInHostCountry == null || profile.yearsInHostCountry!.isEmpty) return const SizedBox.shrink();
     
     final isSinceBirth = profile.yearsInHostCountry == 'Since birth';
     final yearText = profile.yearsInHostCountry!;
     String durationText = '';
     
     if (!isSinceBirth) {
        final startYear = int.tryParse(yearText);
        if (startYear != null) {
           final diff = DateTime.now().year - startYear;
           durationText = ' • $diff years';
        }
     }

     return Column(
       crossAxisAlignment: CrossAxisAlignment.start,
       children: [
         // Row 1: Header
         Text('Lived in ${profile.hostCountry ?? 'this country'} since', style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13)),
         const SizedBox(height: 4),
         
         // Row 2: Value
         Row(
           children: [
             Icon(LucideIcons.clock, size: 16, color: Theme.of(context).primaryColor),
             const SizedBox(width: 8),
             Text(
               isSinceBirth ? 'Birth' : '$yearText$durationText', 
               style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)
             ),
           ],
         ),
       ],
     );
  }

  Widget _buildPastLocationsSection() {
    if (!_isEditing && _pastLocations.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_pastLocations.isNotEmpty) ...[
          const Text('Past Locations', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 4),
          ..._pastLocations.map((p) {
             final flag = p.location.countryCode != null 
                 ? country_data.getCountryByCode(p.location.countryCode!)?.flag 
                 : null;
             return ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: flag != null 
                    ? Text(flag, style: const TextStyle(fontSize: 20)) 
                    : const Icon(LucideIcons.mapPin, size: 16),
                title: Text(p.location.formattedAddress),
                subtitle: Text('Until ${p.until}'),
                trailing: _isEditing ? IconButton(icon: const Icon(LucideIcons.trash2, color: Colors.red, size: 16), onPressed: () => setState(() => _pastLocations.remove(p))) : null,
             );
          }),
        ],
        if (_isEditing) 
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              onPressed: _showAddPastLocationDialog, 
              icon: const Icon(LucideIcons.plus, size: 16), 
              label: const Text('Add Location')
            ),
          ),
      ],
    );
  }

  Widget _buildLocationUpdateSection() {
     return Column(
       children: [
          TextField(controller: _searchController, onChanged: _onSearchChanged, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(hintText: 'Update Host City', suffixIcon: _isUpdatingLocation ? const CircularProgressIndicator() : const Icon(LucideIcons.search))),
          if (_predictions.isNotEmpty) Container(
             height: 200, 
             color: Colors.white, 
             child: ListView(children: _predictions.map((p) => ListTile(title: Text(p.primaryText), onTap: () => _selectPlace(p.placeId))).toList())
          ),
       ],
     );
  }

  Widget _buildDynamicMembershipSection<T>(String title, IconData icon, Future<List<T>> future, Widget Function(T) builder) {
    return FutureBuilder<List<T>>(
      future: future,
      builder: (context, snapshot) {
         if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();
         return _buildSectionContainer(
           title: title,
           icon: icon,
           child: Column(
             children: snapshot.data!.map((item) => Padding(
               padding: const EdgeInsets.only(bottom: 8),
               child: _buildRichCard<T>(item, builder),
             )).toList(),
           ),
         );
      },
    );
  }

  // _buildRichCard is unchanged, so I don't need to include it if I stop before it. 
  // checking line numbers: _buildDynamicMembershipSection is 689-713. _buildRichCard is 715.
  // _buildEventsSection is 745.
  // Usage of _buildSectionContainer is in build.
  
  // I will do two replacements or one big one?
  // One big one is safer for consistency.
  
  // StartLine: 454 (Start of _buildSectionContainer in previous edit)
  // EndLine: 761 (End of _buildEventsSection in original)
  
  // Wait, I need to include _buildRichCard in the middle if I go from 454 to 761.
  // _buildRichCard is lines 715-743.
  // I can just copy it into the replacement.

  Widget _buildRichCard<T>(T item, Widget Function(T) contentBuilder) {
      if (item is comm_model.Community) {
         return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12), // Slightly smaller radius for inner cards
              border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.1)),
            ),
            child: Row(
               children: [
                  CommunityChatUtils.getCommunityAvatar(
                    context: context,
                    type: item.type,
                    locationType: item.locationType,
                    flag: item.flag,
                    profileImage: item.profileImage,
                    size: 40 // Slightly smaller
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                     child: Column(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: [
                          Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          if (item.totalMembers != null)
                            Text('${item.totalMembers} members', style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12)),
                       ],
                     )
                  ),
               ],
            ),
         );
      } else if (item is Map<String, dynamic>) { // Organization
         final name = item['name'] ?? 'Organization';
         final type = item['type'] ?? 'Business';
         final image = item['logoUrl'];
         
         return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.1)),
            ),
            child: Row(
               children: [
                  CircleAvatar(
                     radius: 20,
                     backgroundImage: image != null ? CachedNetworkImageProvider(image) : null,
                     child: image == null ? const Icon(LucideIcons.building, color: Colors.white, size: 20) : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                     child: Column(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: [
                          Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          Text(type, style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12)),
                       ],
                     )
                  ),
               ],
            ),
         );
      } else if (item is Chat) { // Groups
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.1)),
            ),
            child: Row(
               children: [
                  CircleAvatar(
                     radius: 20,
                     backgroundImage: item.photoUrl != null ? CachedNetworkImageProvider(item.photoUrl!) : null,
                     child: item.photoUrl == null ? const Icon(LucideIcons.users, color: Colors.white, size: 20) : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                     child: Column(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: [
                          Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          Text('${item.participants.length} members', style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12)),
                       ],
                     )
                  ),
               ],
            ),
         );
      }
      return contentBuilder(item);
  }
  
  Widget _buildEventsSection() {
    return StreamBuilder<List<event_model.Event>>(
      stream: _eventsStream,
      builder: (context, snapshot) {
         if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();
         return _buildSectionContainer(
           title: 'Events',
           icon: LucideIcons.calendar,
           child: Column(
             children: snapshot.data!.map((e) => Padding(
               padding: const EdgeInsets.only(bottom: 12), 
               child: _buildEventCard(e)
             )).toList(),
           ),
         );
      },
    );
  }

  Widget _buildEventCard(event_model.Event event) {
     // Minimalistic Event Card for Profile
     return Container(
       padding: const EdgeInsets.all(12),
       decoration: BoxDecoration(
         color: Theme.of(context).cardColor,
         borderRadius: BorderRadius.circular(16),
         border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.1)),
       ),
       child: Row(
         children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: (event.imageUrl?.isNotEmpty ?? false)
                  ? CachedNetworkImage(imageUrl: event.imageUrl!, width: 60, height: 60, fit: BoxFit.cover)
                  : Container(width: 60, height: 60, color: Colors.grey.withOpacity(0.1), child: const Icon(LucideIcons.calendar)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text('${DateFormat.yMMMd().format(DateTime.parse(event.startDate))} • ${event.venueName ?? "Online"}', style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13)),
                ],
              ),
            ),
         ],
       ),
     );
  }

  Widget _buildProfessionalEditForm() {
    return Column(children: [
       _buildMultiSelectDropdown(
          title: 'Profession',
          options: _professionOptions,
          selectedValues: _selectedProfessions,
          onChanged: (v) => setState(() => _selectedProfessions = v),
       ),
       const SizedBox(height: 16),
       _buildMultiSelectDropdown(
          title: 'Industry',
          options: _industryOptions,
          selectedValues: _selectedIndustries,
          onChanged: (v) => setState(() => _selectedIndustries = v),
       ),
       const SizedBox(height: 16),
       TextField(controller: _occupationController, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Occupation (Specific role)', border: OutlineInputBorder())),
    ]);
  }

  Widget _buildProfessionalDisplay(ProfileData profile) {
     return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
           if (profile.profession?.isNotEmpty ?? false) _buildTagsDisplay(profile.profession!),
           if (profile.industry?.isNotEmpty ?? false) Padding(padding: const EdgeInsets.only(top: 8), child: _buildTagsDisplay(profile.industry!)),
           if (profile.occupation != null && profile.occupation!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(profile.occupation!)),
        ],
     );
  }

  Widget _buildGoalsEdit() {
     return _buildMultiSelectDropdown(
         title: 'Availability',
         options: _availabilityOptions,
         selectedValues: _selectedAvailability,
         onChanged: (v) => setState(() => _selectedAvailability = v),
     );
  }
  
  Widget _buildGoalsDisplay(ProfileData profile) {
     return _buildTagsDisplay(profile.availability ?? []);
  }
}

class _AddPastLocationDialog extends StatefulWidget {
  final List<String> yearRange;
  final Function(loc_model.PastLocation) onAdd;
  final GooglePlacesService placesService;

  const _AddPastLocationDialog({required this.yearRange, required this.onAdd, required this.placesService});

  @override
  State<_AddPastLocationDialog> createState() => _AddPastLocationDialogState();
}

class _AddPastLocationDialogState extends State<_AddPastLocationDialog> {
  final _searchController = TextEditingController();
  List<AutocompletePrediction> _predictions = [];
  loc_model.UserLocation? _selectedLocation;
  String? _selectedYear;
  bool _isLoading = false;

  void _onSearchChanged(String v) async {
    if (v.isEmpty) { setState(() => _predictions = []); return; }
    final res = await widget.placesService.autocomplete(v);
    if (mounted) setState(() => _predictions = res);
  }

  Future<void> _selectPlace(String id) async {
    setState(() => _isLoading = true);
    final res = await widget.placesService.getPlaceDetails(id);
    if (res?.place != null && mounted) {
       final place = res!.place!;
       setState(() {
         _selectedLocation = loc_model.UserLocation(
            formattedAddress: place.address ?? '', 
            placeId: id, 
            countryCode: null,
            geometry: loc_model.UserLocationGeometry(location: loc_model.UserLocationCoordinates(lat: place.latLng?.lat ?? 0, lng: place.latLng?.lng ?? 0))
         );
         _predictions = [];
         _searchController.text = place.address ?? '';
         _isLoading = false;
       });
    } else {
       if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
       insetPadding: const EdgeInsets.symmetric(horizontal: 16),
       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
       child: Padding(
         padding: const EdgeInsets.all(16),
         child: Column(
           mainAxisSize: MainAxisSize.min,
           crossAxisAlignment: CrossAxisAlignment.stretch,
           children: [
              const Text('Add Past Location', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              TextField(
                controller: _searchController, 
                onChanged: _onSearchChanged, 
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'City/Location',
                  hintText: 'Search city...',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  prefixIcon: const Icon(LucideIcons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  suffixIcon: _isLoading ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2)) : null
                )
              ),
              if (_predictions.isNotEmpty) 
                Container(
                  constraints: const BoxConstraints(maxHeight: 150),
                  margin: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                  child: ListView(
                    shrinkWrap: true,
                    children: _predictions.map((p) => ListTile(
                      title: Text(p.primaryText),
                      subtitle: Text(p.secondaryText),
                      onTap: () => _selectPlace(p.placeId)
                    )).toList()
                  )
                ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedYear, 
                items: widget.yearRange.map((y) => DropdownMenuItem(value: y, child: Text(y))).toList(), 
                onChanged: (v) => setState(() => _selectedYear = v),
                decoration: InputDecoration(
                   labelText: 'Lived until', 
                   contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                   border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))
                ),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                   TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                   const SizedBox(width: 8),
                   ElevatedButton(
                     onPressed: (_selectedLocation != null && _selectedYear != null) 
                         ? () { widget.onAdd(loc_model.PastLocation(location: _selectedLocation!, until: _selectedYear!)); Navigator.pop(context); } 
                         : null, 
                     child: const Text('Add')
                   ),
                ],
              )
           ],
         ),
       ),
    );
  }
}

class _MultiSelectDialog extends StatefulWidget {
  final String title;
  final List<String> items;
  final List<String> initialSelectedItems;

  const _MultiSelectDialog({
    required this.title,
    required this.items,
    required this.initialSelectedItems,
  });

  @override
  State<_MultiSelectDialog> createState() => _MultiSelectDialogState();
}

class _MultiSelectDialogState extends State<_MultiSelectDialog> {
  late List<String> _selectedItems;
  late List<String> _currentItems;
  final TextEditingController _customController = TextEditingController();
  bool _isAddingCustom = false;

  @override
  void initState() {
    super.initState();
    _selectedItems = List.from(widget.initialSelectedItems);
    _currentItems = List.from(widget.items);
    if (!_currentItems.contains('Other')) {
       _currentItems.add('Other');
    }
  }
  
  void _addCustomItem(String value) {
     if (value.isNotEmpty && !_currentItems.contains(value)) {
        setState(() {
           // Insert before 'Other'
           final otherIndex = _currentItems.indexOf('Other');
           if (otherIndex != -1) {
              _currentItems.insert(otherIndex, value);
           } else {
              _currentItems.add(value);
           }
           _selectedItems.add(value);
           _isAddingCustom = false;
           _customController.clear();
        });
     }
  }

  void _onItemCheckedChange(String item, bool checked) {
    if (item == 'Other' && checked) {
       setState(() => _isAddingCustom = true);
    } else {
       setState(() {
         if (checked) {
           _selectedItems.add(item);
         } else {
           _selectedItems.remove(item);
         }
       });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Select ${widget.title}'),
      content: SingleChildScrollView(
        child: Column(
           mainAxisSize: MainAxisSize.min,
           children: [
              if (_isAddingCustom)
                 Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                       children: [
                          Expanded(child: TextField(controller: _customController, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Specify Other', border: OutlineInputBorder()), autofocus: true)),
                          IconButton(icon: const Icon(LucideIcons.check), onPressed: () => _addCustomItem(_customController.text.trim())),
                       ],
                    ),
                 ),
              ListBody(
                children: _currentItems.map((item) {
                  final checked = _selectedItems.contains(item);
                  return CheckboxListTile(
                    value: checked,
                    title: Text(item),
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (checked) => _onItemCheckedChange(item, checked!),
                  );
                }).toList(),
              ),
           ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _selectedItems),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
