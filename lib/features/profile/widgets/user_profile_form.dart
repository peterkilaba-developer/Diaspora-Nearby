import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import 'package:diaspora_nearby/features/shared/models/google_places_models.dart';
import 'package:diaspora_nearby/features/shared/models/location.dart'
    as loc_model;
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/core/services/google_places_service.dart';
import 'package:diaspora_nearby/core/data/countries.dart' as country_data;
import 'package:diaspora_nearby/core/utils/location_utils.dart' as loc_utils;
import 'package:diaspora_nearby/features/shared/widgets/multi_select_dialog.dart';
import 'package:diaspora_nearby/features/shared/widgets/user_card.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/dsp/services/exploration_registry.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/dsp/widgets/exploration_tracker.dart';
import 'package:diaspora_nearby/features/shared/widgets/google_places_autocomplete_field.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

import '../widgets/add_past_location_dialog.dart';

class UserProfileForm extends ConsumerStatefulWidget {
  final ProfileData initialProfile;
  final Future<void> Function(ProfileData updatedProfile, XFile? newImage)
  onSave;
  final VoidCallback? onCancel;
  final List<String>? highlightFields;
  final bool showUserCard;
  final String? submitLabel;
  final ValueChanged<bool>? onSavingStateChanged;
  final bool isFinishProfile;

  const UserProfileForm({
    super.key,
    required this.initialProfile,
    required this.onSave,
    this.onCancel,
    this.highlightFields,
    this.showUserCard = true,
    this.submitLabel,
    this.onSavingStateChanged,
    this.isFinishProfile = false,
  });

  @override
  ConsumerState<UserProfileForm> createState() => UserProfileFormState();
}

class UserProfileFormState extends ConsumerState<UserProfileForm> {
  final _formKey = GlobalKey<FormState>();
  late List<String> _yearRange;
  bool isSaving = false;

  // Controllers
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  final TextEditingController _occupationController = TextEditingController();
  final TextEditingController _searchController =
      TextEditingController(); // For Host Location

  // Education Controllers
  final TextEditingController _eduInstController = TextEditingController();
  final TextEditingController _eduDegController = TextEditingController();
  final TextEditingController _eduYearController = TextEditingController();

  // State
  List<String> _selectedProfessions = [];
  List<String> _selectedIndustries = [];
  List<String> _selectedAvailability = [];
  List<String> _selectedServices = [];
  List<String> _selectedLookingFor = [];
  List<String> _selectedMeetingPreferences = [];
  List<String> _selectedLanguages = [];
  List<String> _selectedInterests = [];
  List<loc_model.PastLocation> _pastLocations = [];
  String _selectedYearsInHost = '';
  bool _showCurrentLocationName = true;
  XFile? _newProfileImage;
  late Set<String> _activeHighlights;

  // Host Location Update State
  List<AutocompletePrediction> _predictions = [];
  loc_model.UserLocation? _tempSelectedLocation;
  bool _isUpdatingLocation = false;

  static const List<String> _availabilityOptions = [
    'Full-time',
    'Part-time',
    'Weekends only',
    'Evenings only',
    'Open to collaborate',
    'Remote only',
    'Not available',
  ];
  static const List<String> _industryOptions = [
    'Technology',
    'Healthcare',
    'Finance',
    'Education',
    'Construction',
    'Retail',
    'Art & Design',
    'Hospitality',
    'Legal',
    'Government',
    'Non-Profit',
    'Other',
  ];
  static const List<String> _professionOptions = [
    'Software Engineer',
    'Doctor',
    'Teacher',
    'Lawyer',
    'Accountant',
    'Nurse',
    'Designer',
    'Project Manager',
    'Marketing Specialist',
    'Sales Professional',
    'Analyst',
    'Entrepreneur',
    'Student',
    'Researcher',
    'Other',
  ];
  static const List<String> _languageOptions = [
    'Amharic',
    'Arabic',
    'Bengali',
    'Chinese (Mandarin)',
    'English',
    'French',
    'German',
    'Hausa',
    'Hindi',
    'Igbo',
    'Indonesian',
    'Italian',
    'Japanese',
    'Korean',
    'Oromo',
    'Portuguese',
    'Punjabi',
    'Russian',
    'Somali',
    'Spanish',
    'Swahili',
    'Tamil',
    'Telugu',
    'Turkish',
    'Urdu',
    'Vietnamese',
    'Yoruba',
    'Zulu',
    'Other',
  ];
  static const List<String> _servicesOptions = [
    'Mentorship',
    'Career Advice',
    'Legal Assistance',
    'Financial Planning',
    'Housing Help',
    'Technical Support',
    'Translation',
    'Business Partnership',
    'Freelancing',
    'Other',
  ];
  static const List<String> _lookingForOptions = [
    'Job Opportunities',
    'Business Partners',
    'Friends',
    'Language Exchange',
    'Networking',
    'Local Advice',
    'Mentors',
    'Events',
    'Other',
  ];
  static const List<String> _interestsOptions = [
    'Technology',
    'Sports',
    'Music',
    'Travel',
    'Food',
    'Art',
    'Reading',
    'Gaming',
    'Fitness',
    'Photography',
    'Other',
  ];
  static const List<String> _meetingTypeOptions = [
    'Virtual / Online',
    'Coffee / In-Person',
    'Group Meetup',
    'Professional Setting',
    'Casual',
    'Other',
  ];

  static const List<String> _degreeOptions = [
    'High School Diploma',
    'Associate\'s Degree',
    'Bachelor\'s Degree',
    'Master\'s Degree',
    'Doctoral Degree (PhD)',
    'Professional Degree (MD, JD, etc.)',
    'Vocational/Technical Certificate',
    'Other',
  ];

  late List<String> _gradYearRange;
  bool _noSchool = false;

  @override
  void initState() {
    super.initState();
    _activeHighlights = Set.from(widget.highlightFields ?? []);
    _initializeData();
    _setupListeners();
  }

  void _setupListeners() {
    void remove(String field) {
      if (_activeHighlights.contains(field)) {
        setState(() => _activeHighlights.remove(field));
      }
    }

    _firstNameController.addListener(() => remove('First Name'));
    _lastNameController.addListener(() => remove('Last Name'));
    _bioController.addListener(() => remove('Bio'));
    _occupationController.addListener(() => remove('Occupation'));
    _eduInstController.addListener(
      () {if (mounted) setState(() {}); if (!_noSchool) remove('Education');},
    );
  }

  void _initializeData() {
    final currentYear = DateTime.now().year;
    _yearRange = List.generate(
      currentYear - 1960 + 1,
      (index) => (currentYear - index).toString(),
    );
    _yearRange.insert(0, 'Since birth');

    _gradYearRange = List.from(_yearRange)..remove('Since birth');

    final p = widget.initialProfile;
    _firstNameController.text = p.firstName;
    _lastNameController.text = p.lastName;
    _bioController.text = p.bio ?? '';
    _occupationController.text = p.occupation ?? '';
    if (p.education != null && p.education!.isNotEmpty) {
      _eduInstController.text = p.education!.first.institution;
      _eduDegController.text = p.education!.first.degree;
      _eduYearController.text = p.education!.first.graduationYear;
    } else {
      _eduInstController.text = '';
      _eduDegController.text = '';
      _eduYearController.text = '';
    }

    if (_eduInstController.text == 'No School') {
      _noSchool = true;
    }

    _selectedProfessions = List.from(p.profession ?? []);
    _selectedIndustries = List.from(p.industry ?? []);
    _selectedAvailability = List.from(p.availability ?? []);
    _selectedLanguages = List.from(p.languages ?? []);
    _selectedInterests = List.from(p.interests ?? []);
    _selectedServices = List.from(p.servicesOffered ?? []);
    _selectedLookingFor = List.from(p.lookingFor ?? []);
    _selectedMeetingPreferences = List.from(p.meetingPreferences ?? []);
    _pastLocations = List.from(p.pastLocations ?? []);
    _selectedYearsInHost = p.yearsInHostCountry ?? '';
    _showCurrentLocationName = p.showCurrentLocationName ?? true;

    if (p.education != null && p.education!.isNotEmpty) {
      _eduInstController.text = p.education!.first.institution;
      _eduDegController.text = p.education!.first.degree;
      _eduYearController.text = p.education!.first.graduationYear;
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _bioController.dispose();
    _occupationController.dispose();
    _searchController.dispose();
    _eduInstController.dispose();
    _eduDegController.dispose();
    _eduYearController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    FocusScope.of(context).unfocus();
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (pickedFile != null) {
      setState(() {
        _newProfileImage = pickedFile;
      });
    }
  }

  Future<void> submit() async {
    debugPrint('UserProfileForm: submit() called');
    if (isSaving) {
      debugPrint('UserProfileForm: Already saving, returning');
      return;
    }

    bool hasError = false;

    // Validate Form Fields
    if (!_formKey.currentState!.validate()) {
      hasError = true;
    }

    // Validate Select/Chip Fields
    if (_selectedProfessions.isEmpty) {
      setState(() => _activeHighlights.add('Profession'));
      hasError = true;
    }
    if (_selectedIndustries.isEmpty) {
      setState(() => _activeHighlights.add('Industry'));
      hasError = true;
    }
    if (_selectedAvailability.isEmpty) {
      setState(() => _activeHighlights.add('Availability'));
      hasError = true;
    }
    if (_selectedLanguages.isEmpty) {
      setState(() => _activeHighlights.add('Languages'));
      hasError = true;
    }
    if (_selectedInterests.isEmpty) {
      setState(() => _activeHighlights.add('Interests'));
      hasError = true;
    }
    if (_selectedServices.isEmpty) {
      setState(() => _activeHighlights.add('Services Offered'));
      hasError = true;
    }
    if (_selectedLookingFor.isEmpty) {
      setState(() => _activeHighlights.add('Looking For'));
      hasError = true;
    }
    if (_selectedMeetingPreferences.isEmpty) {
      setState(() => _activeHighlights.add('Meeting Preferences'));
      hasError = true;
    }
    if (_selectedYearsInHost.isEmpty) {
      setState(() => _activeHighlights.add('Years in Host Country'));
      hasError = true;
    }

    if (hasError) {
      debugPrint('UserProfileForm: Validation FAILED');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all required fields marked in red.'),
          backgroundColor: Colors.red,
        ),
      );
      // Ensure editor knows we stopped (though we never technically started async)
      widget.onSavingStateChanged?.call(false);
      return;
    }

    debugPrint('UserProfileForm: Validation PASSED, starting save...');
    setState(() => isSaving = true);
    widget.onSavingStateChanged?.call(true);

    try {
      List<Education>? education;
      if (_eduInstController.text.isNotEmpty) {
        education = [
          Education(
            institution: _eduInstController.text.trim(),
            degree: _eduDegController.text.trim(),
            graduationYear: _eduYearController.text.trim(),
          ),
        ];
      }

      final updatedProfile = widget.initialProfile.copyWith(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
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
        education: education,
        hostLocation:
            _tempSelectedLocation ?? widget.initialProfile.hostLocation,
        hostCountry:
            _tempSelectedLocation?.country ?? widget.initialProfile.hostCountry,
        hostCountryCode:
            _tempSelectedLocation?.countryCode ??
            widget.initialProfile.hostCountryCode,
        // [FIX] Synchronize homeCountryCode too if it's missing but in location
        homeCountryCode:
            widget.initialProfile.homeCountryCode ??
            widget.initialProfile.homeLocation.countryCode,
        showCurrentLocationName: _showCurrentLocationName,
      );

      await widget.onSave(updatedProfile, _newProfileImage);
      await _trackCompletionRewards(updatedProfile);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving profile: $e')));
      }
      rethrow;
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
        widget.onSavingStateChanged?.call(false);
      }
    }
  }

  Future<void> _trackCompletionRewards(ProfileData profile) async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null) return;
    final uid = user.uid;
    final points = ref.read(pointsServiceProvider);

    bool anyRewarded = false;
    Future<void> check(String actionId, bool condition) async {
      if (condition) {
        final rewarded = await points.trackExplorationReward(uid, actionId);
        if (rewarded) anyRewarded = true;
      }
    }

    await check(
      ExplorationAction.profileSetupBio,
      (profile.bio?.isNotEmpty ?? false),
    );
    await check(
      ExplorationAction.profileSetupOccupation,
      (profile.occupation?.isNotEmpty ?? false),
    );
    await check(
      ExplorationAction.profileSetupProfession,
      (profile.profession?.isNotEmpty ?? false),
    );
    await check(
      ExplorationAction.profileSetupIndustry,
      (profile.industry?.isNotEmpty ?? false),
    );
    await check(
      ExplorationAction.profileSetupLanguages,
      (profile.languages?.isNotEmpty ?? false),
    );
    await check(
      ExplorationAction.profileSetupInterests,
      (profile.interests?.isNotEmpty ?? false),
    );
    await check(
      ExplorationAction.profileSetupServices,
      (profile.servicesOffered?.isNotEmpty ?? false),
    );
    await check(
      ExplorationAction.profileSetupLookingFor,
      (profile.lookingFor?.isNotEmpty ?? false),
    );
    await check(
      ExplorationAction.profileSetupAvailability,
      (profile.availability?.isNotEmpty ?? false),
    );
    await check(
      ExplorationAction.profileSetupMeetingPrefs,
      (profile.meetingPreferences?.isNotEmpty ?? false),
    );
    await check(
      ExplorationAction.profileSetupPastLocations,
      (profile.pastLocations?.isNotEmpty ?? false),
    );

    bool hasPhoto =
        (profile.profileImage.isNotEmpty || _newProfileImage != null) &&
        !profile.profileImage.contains('ui-avatars.com');
    await check(ExplorationAction.profileSetupPhoto, hasPhoto);

    if (anyRewarded && mounted) {
      showExplorationRewardToast(context, message: 'Profile complete bonus!');
    }

    // [NEW] Check for 10-field milestone
    await points.trackProfileCompletion(uid, profile);
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

      final targetLat = place.latLng?.lat;
      final targetLng = place.latLng?.lng;
      if (targetLat == null || targetLng == null) {
        throw Exception('Selected place has no coordinates');
      }

      List<AddressComponent> components = place.addressComponents ?? [];
      final parsedLoc = loc_utils.parseLocationComponents(
        place.address ?? '',
        components,
      );
      if (parsedLoc == null) {
        throw Exception('Could not parse location components');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permission denied');
        }
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      final distanceKm = loc_utils.calculateDistance(
        position.latitude,
        position.longitude,
        targetLat,
        targetLng,
      );

      const double maxDistanceKm = 50.0;
      if (distanceKm > maxDistanceKm) {
        _showVerificationErrorDialog(
          parsedLoc.city ?? 'Selected City',
          distanceKm,
        );
        setState(() {
          _predictions = [];
          _searchController.clear();
        });
        return;
      }

      final newLocation = loc_model.UserLocation(
        formattedAddress: place.address ?? '',
        placeId: place.id ?? placeId,
        city: parsedLoc.city,
        state: parsedLoc.state,
        country: parsedLoc.country,
        countryCode: parsedLoc.countryCode,
        geometry: loc_model.UserLocationGeometry(
          location: loc_model.UserLocationCoordinates(
            lat: targetLat,
            lng: targetLng,
          ),
        ),
      );

      if (mounted) {
        setState(() {
          _tempSelectedLocation = newLocation;
          _predictions = [];
          _searchController.text = newLocation.formattedAddress;
        });
        FocusScope.of(context).unfocus();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _tempSelectedLocation = null);
      }
    } finally {
      if (mounted) setState(() => _isUpdatingLocation = false);
    }
  }

  void _showVerificationErrorDialog(String targetCity, double distanceKm) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location Verification Failed'),
        content: Text(
          'You are ${distanceKm.round()}km away from $targetCity.\n\nTo ensure community integrity, you must be physically located in/near your host city to update it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Understand'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.pageHorizontalPadding,
          vertical: 16,
        ),
        child: GestureDetector(
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!widget.isFinishProfile) ...[
                if (widget.showUserCard) ...[
                  Stack(
                    children: [
                      UserCardView(
                        user: widget.initialProfile,
                        localImage: _newProfileImage,
                        isStatic: true,
                        onImageTap: _pickImage,
                      ),
                      Positioned(left: 24, top: 80, child: _buildCameraBadge()),
                    ],
                  ),
                  const SizedBox(height: 16),
                ] else
                  _buildPhotoPickerSection(),
              ],

              if (!widget.isFinishProfile) ...[
                _buildSectionHeader('Basic Info'),
                _buildSectionContainer(
                  child: Column(
                    children: [
                      _buildTextField('First Name', _firstNameController),
                      const SizedBox(height: 12),
                      _buildTextField('Last Name', _lastNameController),
                    ],
                  ),
                ),
              ],

              _buildSectionHeader('Residency & Locations'),
              _buildSectionContainer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildResidencyEdit(),
                    if (!widget.isFinishProfile ||
                        _activeHighlights.contains('Host Town')) ...[
                      const SizedBox(height: 12),
                      _buildPastLocationsEdit(),
                      const SizedBox(height: 12),
                      _buildLocationPrivacyToggle(),
                      _buildLocationUpdateSection(),
                    ],
                  ],
                ),
              ),

              _buildSectionHeader('About Me'),
              _buildSectionContainer(
                child: _buildTextField(
                  'Bio',
                  _bioController,
                  hintText: 'Write something about yourself...',
                  maxLines: 4,
                ),
              ),

              _buildSectionHeader('Professional Info'),
              _buildSectionContainer(
                child: Column(
                  children: [
                    _buildMultiSelectDropdown(
                      title: 'Profession',
                      options: _professionOptions,
                      selectedValues: _selectedProfessions,
                      onChanged: (v) =>
                          setState(() => _selectedProfessions = v),
                    ),
                    const SizedBox(height: 16),
                    _buildMultiSelectDropdown(
                      title: 'Industry',
                      options: _industryOptions,
                      selectedValues: _selectedIndustries,
                      onChanged: (v) => setState(() => _selectedIndustries = v),
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      'Occupation',
                      _occupationController,
                      hintText: 'Current job title or role',
                    ),
                  ],
                ),
              ),

              _buildSectionHeader('Education'),
              _buildSectionContainer(
                child: Column(
                  children: [
                    if (_eduInstController.text.isEmpty || _noSchool)
                      CheckboxListTile(
                        title: const Text('No School'),
                        value: _noSchool,
                        onChanged: (v) {
                          setState(() {
                            _noSchool = v ?? false;
                            if (_noSchool) {
                              _eduInstController.text = 'No School';
                              _eduDegController.clear();
                              _eduYearController.clear();
                              _activeHighlights.remove('Education');
                            } else {
                              _eduInstController.clear();
                            }
                          });
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                    if (!_noSchool) ...[
                      GooglePlacesAutocompleteField(
                        label: 'School/College/University',
                        controller: _eduInstController,
                        isHighlighted: _activeHighlights.contains('Education'),
                        filter: PlaceTypeFilter.SCHOOLS,
                        onSelected: (desc, id) {
                          setState(() {
                            _eduInstController.text = desc;
                            _noSchool = false;
                            _activeHighlights.remove('Education');
                          });
                        },
                        validator: (v) =>
                            (!_noSchool && (v == null || v.trim().isEmpty))
                            ? 'Required'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildValueDropdown(
                              label: 'Degree',
                              value: _eduDegController.text.isNotEmpty
                                  ? _eduDegController.text
                                  : null,
                              options: _degreeOptions,
                              onChanged: (v) => setState(
                                () => _eduDegController.text = v ?? '',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildValueDropdown(
                              label: 'Year',
                              value: _eduYearController.text.isNotEmpty
                                  ? _eduYearController.text
                                  : null,
                              options: _gradYearRange,
                              onChanged: (v) {
                                setState(() {
                                  _eduYearController.text = v ?? '';
                                  if (_eduInstController.text.isNotEmpty &&
                                      _eduDegController.text.isNotEmpty) {
                                    _activeHighlights.remove('Education');
                                  }
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              _buildSectionHeader('Languages'),
              _buildSectionContainer(
                child: _buildMultiSelectDropdown(
                  title: 'Languages',
                  options: _languageOptions,
                  selectedValues: _selectedLanguages,
                  onChanged: (v) => setState(() => _selectedLanguages = v),
                ),
              ),

              _buildSectionHeader('Interests'),
              _buildSectionContainer(
                child: _buildMultiSelectDropdown(
                  title: 'Interests',
                  options: _interestsOptions,
                  selectedValues: _selectedInterests,
                  onChanged: (v) => setState(() => _selectedInterests = v),
                ),
              ),

              _buildSectionHeader('Community Support'),
              _buildSectionContainer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Services I Can Offer',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildMultiSelectDropdown(
                      title: 'Services Offered',
                      options: _servicesOptions,
                      selectedValues: _selectedServices,
                      onChanged: (v) => setState(() => _selectedServices = v),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "What I'm Looking For",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildMultiSelectDropdown(
                      title: "Looking For",
                      options: _lookingForOptions,
                      selectedValues: _selectedLookingFor,
                      onChanged: (v) => setState(() => _selectedLookingFor = v),
                    ),
                  ],
                ),
              ),

              _buildSectionHeader('Availability'),
              _buildSectionContainer(
                child: _buildMultiSelectDropdown(
                  title: 'Availability',
                  options: _availabilityOptions,
                  selectedValues: _selectedAvailability,
                  onChanged: (v) => setState(() => _selectedAvailability = v),
                ),
              ),

              _buildSectionHeader('Meeting Preferences'),
              _buildSectionContainer(
                child: _buildMultiSelectDropdown(
                  title: 'Meeting Preferences',
                  options: _meetingTypeOptions,
                  selectedValues: _selectedMeetingPreferences,
                  onChanged: (v) =>
                      setState(() => _selectedMeetingPreferences = v),
                ),
              ),

              if (widget.submitLabel != null) ...[
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: isSaving ? null : submit,
                    child: isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            widget.submitLabel!,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
              const SizedBox(height: 32),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraBadge() {
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.camera, color: Colors.white, size: 12),
            SizedBox(width: 4),
            Text(
              'Change',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoPickerSection() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Center(
        child: GestureDetector(
          onTap: _pickImage,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border:
                      widget.highlightFields?.contains('Profile Photo') == true
                      ? Border.all(color: Colors.red, width: 2)
                      : null,
                ),
                child: CircleAvatar(
                  radius: 50,
                  backgroundColor: Theme.of(
                    context,
                  ).primaryColor.withOpacity(0.1),
                  backgroundImage: _newProfileImage != null
                      ? FileImage(File(_newProfileImage!.path)) as ImageProvider
                      : (widget.initialProfile.profileImage.isNotEmpty
                            ? NetworkImage(widget.initialProfile.profileImage)
                            : null),
                  child:
                      (_newProfileImage == null &&
                          widget.initialProfile.profileImage.isEmpty)
                      ? const Icon(LucideIcons.camera, size: 32)
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Update Profile Photo',
                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 8, right: 16, top: 16),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7),
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildSectionContainer({required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: AppTheme.cardDecoration(context),
      child: child,
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    String? hintText,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    final bool isHighlighted = _activeHighlights.contains(label);
    if (label == 'Education' && _noSchool) return const SizedBox.shrink();

    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      textCapitalization: TextCapitalization.sentences,
      validator:
          validator ??
          (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        // filled/fillColor removed to use AppTheme defaults
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
    );
  }

  Widget _buildValueDropdown({
    required String label,
    required String? value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    final bool isHighlighted = _activeHighlights.contains(label);

    return DropdownButtonFormField<String>(
      isExpanded: true,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      initialValue: (value != null && options.contains(value)) ? value : null,
      items: options
          .map(
            (y) => DropdownMenuItem(
              value: y,
              child: Text(y, overflow: TextOverflow.ellipsis, maxLines: 1),
            ),
          )
          .toList(),
      onChanged: onChanged,
      validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
      decoration: InputDecoration(
        labelText: label,
        // filled/fillColor removed to use AppTheme defaults
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        errorBorder: isHighlighted
            ? OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.red, width: 1.5),
              )
            : InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
    );
  }

  Widget _buildResidencyEdit() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Lived in ${widget.initialProfile.hostCountry ?? 'Host Country'} since',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: AppTheme.innerDecoration(context),
          child: DropdownButtonFormField<String>(
            initialValue: _selectedYearsInHost.isNotEmpty ? _selectedYearsInHost : null,
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            items: _yearRange
                .map((y) => DropdownMenuItem(value: y, child: Text(y)))
                .toList(),
            onChanged: (v) {
              setState(() {
                _selectedYearsInHost = v ?? '';
                _activeHighlights.remove('Years in Host Country');
              });
            },
            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            decoration: InputDecoration(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: _activeHighlights.contains('Years in Host Country')
                  ? OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.red, width: 1.5),
                    )
                  : InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPastLocationsEdit() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Also lived in',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ..._pastLocations.map((p) {
              String? flag;
              if (p.location.countryCode != null) {
                flag = country_data
                    .getCountryByCode(p.location.countryCode!)
                    ?.flag;
              }
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: AppTheme.innerDecoration(context),
                child: Row(
                  children: [
                    const Icon(LucideIcons.mapPin, size: 16, color: Colors.grey),
                    if (flag != null) ...[
                      const SizedBox(width: 8),
                      Text(flag, style: const TextStyle(fontSize: 18)),
                    ],
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.location.formattedAddress,
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Until ${p.until}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
            Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton.icon(
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  showDialog(
                    context: context,
                    builder: (ctx) => AddPastLocationDialog(
                      yearRange: _yearRange,
                      onAdd: (loc) {
                        setState(() {
                          _pastLocations.add(loc);
                          _activeHighlights.remove('Lived in');
                        });
                      },
                      placesService: ref.read(googlePlacesServiceProvider),
                      homeCountryCode: widget.initialProfile.homeCountryCode,
                    ),
                  );
                },
                icon: const Icon(LucideIcons.plus, size: 16),
                label: const Text('Add Location'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLocationUpdateSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Text(
          'Update to new host location',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            hintText: 'Search Host City (GPS Verified)',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            errorBorder: _activeHighlights.contains('Host Town')
                ? OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.red, width: 1.5),
                  )
                : InputBorder.none,
            suffixIcon: _isUpdatingLocation
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(LucideIcons.search),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
        ),
        if (_predictions.isNotEmpty)
          Container(
            height: 200,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: ListView.builder(
              itemCount: _predictions.length,
              itemBuilder: (context, index) => ListTile(
                title: Text(_predictions[index].fullText),
                onTap: () => _selectPlace(_predictions[index].placeId),
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
    final bool isHighlighted = _activeHighlights.contains(title);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () async {
            FocusManager.instance.primaryFocus?.unfocus();
            final results = await showDialog<List<String>>(
              context: context,
              builder: (ctx) => MultiSelectDialog(
                title: title,
                items: options,
                initialSelectedItems: selectedValues,
              ),
            );
            if (results != null) {
              onChanged(results);
              if (results.isNotEmpty && _activeHighlights.contains(title)) {
                setState(() => _activeHighlights.remove(title));
              }
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: AppTheme.innerDecoration(context).copyWith(
              border: isHighlighted ? Border.all(color: Colors.red) : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Select $title',
                  style: TextStyle(color: Colors.grey[700]),
                ),
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
              children: selectedValues
                  .map(
                    (t) => Chip(
                      label: Text(t),
                      onDeleted: () {
                        final newList = List<String>.from(selectedValues)
                          ..remove(t);
                        onChanged(newList);
                      },
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildLocationPrivacyToggle() {
    return SwitchListTile(
      title: const Text('Show my current city name'),
      subtitle: !_showCurrentLocationName
          ? Text(
              '1,000 DSP deducted for hiding',
              style: TextStyle(fontSize: 11, color: Colors.orange[400]),
            )
          : null,
      value: _showCurrentLocationName,
      onChanged: (v) {
        if (!v) {
          // User wants to hide — confirm DSP deduction
          _showHideCityConfirmation();
        } else {
          // User re-enables showing — no cost
          setState(() => _showCurrentLocationName = true);
        }
      },
      contentPadding: EdgeInsets.zero,
    );
  }

  Future<void> _showHideCityConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hide Current City?'),
        content: const Text(
          'Hiding your current city name will permanently deduct 1,000 DSP from your balance.\n\nThis action cannot be reversed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Deduct 1,000 DSP & Hide'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final user = ref.read(authRepositoryProvider).currentUser;
        if (user == null) return;

        await ref.read(pointsServiceProvider).deductPoints(
              userId: user.uid,
              amount: 1000,
              reason: 'hide_city_name',
            );

        if (mounted) {
          setState(() => _showCurrentLocationName = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('1,000 DSP deducted. Your city will be hidden.'),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to deduct DSP: $e')),
          );
        }
      }
    }
  }
}
