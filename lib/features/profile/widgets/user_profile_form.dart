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
import 'package:diaspora_nearby/core/services/location_update_service.dart';
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
  String? _selectedProfession;
  String? _selectedIndustry;
  List<String> _selectedAvailability = [];
  List<String> _selectedServices = [];
  List<String> _selectedLookingFor = [];
  List<String> _selectedMeetingPreferences = [];
  List<String> _selectedLanguages = [];
  List<String> _selectedInterests = [];
  List<loc_model.PastLocation> _pastLocations = [];
  String _selectedYearsInHost = '';
  bool _showCurrentLocationName = true;
  bool _cityVisibilityForfeited = false;
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
    'Flexible schedule',
    'Open to collaborate',
    'Remote only',
    'Not available',
  ];
  static const List<String> _industryOptions = [
    'Accounting & Auditing',
    'Aerospace & Defense',
    'Agriculture & Farming',
    'Architecture & Planning',
    'Arts & Entertainment',
    'Automotive',
    'Banking & Financial Services',
    'Biotechnology',
    'Broadcasting & Media',
    'Construction & Building',
    'Consulting & Advisory',
    'E-Commerce',
    'Education & Training',
    'Energy & Utilities',
    'Engineering',
    'Environmental Services',
    'Fashion & Apparel',
    'Food & Beverage',
    'Government & Public Sector',
    'Healthcare & Medical',
    'Hospitality & Tourism',
    'Human Resources',
    'Import & Export',
    'Information Technology',
    'Insurance',
    'Legal Services',
    'Logistics & Supply Chain',
    'Manufacturing',
    'Marketing & Advertising',
    'Mining & Metals',
    'Non-Profit & NGO',
    'Pharmaceuticals',
    'Real Estate & Property',
    'Retail & Consumer Goods',
    'Sports & Recreation',
    'Telecommunications',
    'Transportation',
    'Other',
  ];
  static const List<String> _professionOptions = [
    'Accountant',
    'Architect',
    'Business Analyst',
    'Chef / Cook',
    'Civil Engineer',
    'Content Creator',
    'Data Scientist',
    'Dentist',
    'Designer (Graphic / UI / UX)',
    'Doctor / Physician',
    'Economist',
    'Electrician',
    'Entrepreneur / Business Owner',
    'Farmer / Agriculturist',
    'Financial Advisor',
    'Firefighter / EMT',
    'HR Professional',
    'Journalist / Writer',
    'Lawyer / Attorney',
    'Logistics Coordinator',
    'Marketing Specialist',
    'Mechanic',
    'Nurse',
    'Pharmacist',
    'Photographer / Videographer',
    'Pilot',
    'Plumber',
    'Product Manager',
    'Professor / Lecturer',
    'Project Manager',
    'Real Estate Agent',
    'Researcher / Scientist',
    'Sales Professional',
    'Social Worker',
    'Software Engineer / Developer',
    'Student',
    'Teacher / Educator',
    'Technician',
    'Translator / Interpreter',
    'Truck Driver',
    'Veterinarian',
    'Other',
  ];
  static const List<String> _languageOptions = [
    'Afrikaans',
    'Amharic',
    'Arabic',
    'Bengali',
    'Bulgarian',
    'Burmese',
    'Chinese (Cantonese)',
    'Chinese (Mandarin)',
    'Croatian',
    'Czech',
    'Danish',
    'Dutch',
    'English',
    'Farsi / Persian',
    'Filipino / Tagalog',
    'Finnish',
    'French',
    'German',
    'Greek',
    'Hausa',
    'Hebrew',
    'Hindi',
    'Hungarian',
    'Igbo',
    'Indonesian',
    'Italian',
    'Japanese',
    'Javanese',
    'Kannada',
    'Korean',
    'Malay',
    'Marathi',
    'Nepali',
    'Norwegian',
    'Oromo',
    'Pashto',
    'Polish',
    'Portuguese',
    'Punjabi',
    'Romanian',
    'Russian',
    'Serbian',
    'Shona',
    'Sinhala',
    'Somali',
    'Spanish',
    'Swahili',
    'Swedish',
    'Tamil',
    'Telugu',
    'Thai',
    'Tigrinya',
    'Turkish',
    'Ukrainian',
    'Urdu',
    'Vietnamese',
    'Wolof',
    'Yoruba',
    'Zulu',
    'Other',
  ];
  static const List<String> _servicesOptions = [
    'Airport Pickup',
    'Business Partnership',
    'Career Coaching',
    'Childcare Support',
    'Community Organizing',
    'Cultural Orientation',
    'Document Translation',
    'Driving Lessons',
    'Event Planning',
    'Financial Planning',
    'Freelancing',
    'Government Paperwork Help',
    'Health & Wellness Guidance',
    'Housing Help',
    'Immigration Guidance',
    'IT & Technical Support',
    'Language Tutoring',
    'Legal Assistance',
    'Mentorship',
    'Moving & Settling Help',
    'Networking Introductions',
    'Resume & Interview Prep',
    'Spiritual Guidance',
    'Tax Filing Assistance',
    'Other',
  ];
  static const List<String> _lookingForOptions = [
    'Business Partners',
    'Community Events',
    'Cultural Groups',
    'Friends & Social Circle',
    'Housing Leads',
    'Job Opportunities',
    'Language Exchange',
    'Local Advice & Tips',
    'Mentors & Coaches',
    'Networking',
    'Professional Development',
    'Relocation Support',
    'Roommates',
    'Study Groups',
    'Volunteer Opportunities',
    'Other',
  ];
  static const List<String> _interestsOptions = [
    'Artificial Intelligence',
    'Board Games',
    'Camping & Outdoors',
    'Cars & Motorsport',
    'Coding & Open Source',
    'Cooking & Recipes',
    'Crypto & Blockchain',
    'Dance',
    'DIY & Crafts',
    'Entrepreneurship',
    'Fashion & Style',
    'Film & Cinema',
    'Fitness & Gym',
    'Gaming',
    'Gardening',
    'History & Culture',
    'Investing & Stocks',
    'Languages',
    'Music',
    'Pets & Animals',
    'Photography',
    'Podcasts',
    'Politics & Current Events',
    'Reading & Books',
    'Real Estate',
    'Running & Marathon',
    'Science & Space',
    'Social Media',
    'Sports',
    'Technology & Gadgets',
    'Travel',
    'Volunteering',
    'Yoga & Meditation',
    'Other',
  ];
  static const List<String> _meetingTypeOptions = [
    'Virtual / Video Call',
    'Phone Call',
    'Coffee / In-Person',
    'Group Meetup',
    'Professional Setting',
    'Co-Working Space',
    'Casual Hangout',
    'Other',
  ];

  static const List<String> _degreeOptions = [
    'High School Diploma',
    'Associate\'s Degree',
    'Bachelor\'s Degree',
    'Master\'s Degree',
    'Doctoral Degree (PhD)',
    'Professional Degree (MD, JD, etc.)',
    'Vocational / Technical Certificate',
    'Trade Certification',
    'Diploma / Foundation',
    'Other',
  ];

  late List<String> _gradYearRange;
  // _noSchool removed — education is always required

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
    _eduInstController.addListener(() {
      if (mounted) setState(() {});
      remove('Education');
    });
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

    // Clear legacy "No School" value
    if (_eduInstController.text == 'No School') {
      _eduInstController.clear();
    }

    _selectedProfession = (p.profession != null && p.profession!.isNotEmpty)
        ? p.profession!.first
        : null;
    _selectedIndustry = (p.industry != null && p.industry!.isNotEmpty)
        ? p.industry!.first
        : null;
    _selectedAvailability = List.from(p.availability ?? []);
    _selectedLanguages = List.from(p.languages ?? []);
    _selectedInterests = List.from(p.interests ?? []);
    _selectedServices = List.from(p.servicesOffered ?? []);
    _selectedLookingFor = List.from(p.lookingFor ?? []);
    _selectedMeetingPreferences = List.from(p.meetingPreferences ?? []);
    _pastLocations = List.from(p.pastLocations ?? []);
    _selectedYearsInHost = p.yearsInHostCountry ?? '';
    _showCurrentLocationName = p.showCurrentLocationName ?? true;
    _cityVisibilityForfeited = p.cityVisibilityForfeited ?? false;

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

    // Validate text fields highlighted state
    if (_bioController.text.trim().isEmpty) {
      setState(() => _activeHighlights.add('Bio'));
      hasError = true;
    }
    if (_occupationController.text.trim().isEmpty) {
      setState(() => _activeHighlights.add('Occupation'));
      hasError = true;
    }

    // Validate Select/Chip Fields
    if (_selectedProfession == null || _selectedProfession!.isEmpty) {
      setState(() => _activeHighlights.add('Profession'));
      hasError = true;
    }
    if (_selectedIndustry == null || _selectedIndustry!.isEmpty) {
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
    // Education: school name is always required
    if (_eduInstController.text.trim().isEmpty) {
      setState(() => _activeHighlights.add('Education'));
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
        profession: _selectedProfession != null ? [_selectedProfession!] : [],
        industry: _selectedIndustry != null ? [_selectedIndustry!] : [],
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
        cityVisibilityForfeited: _cityVisibilityForfeited,
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
    await points.trackProfileCompletion(uid);
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
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
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
                  highlightKey: 'Bio',
                ),
              ),

              _buildSectionHeader('Professional Info'),
              _buildSectionContainer(
                child: Column(
                  children: [
                    _buildValueDropdown(
                      label: 'Profession',
                      value: _selectedProfession,
                      options: _professionOptions,
                      onChanged: (v) {
                        setState(() {
                          _selectedProfession = v;
                          _activeHighlights.remove('Profession');
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildValueDropdown(
                      label: 'Industry',
                      value: _selectedIndustry,
                      options: _industryOptions,
                      onChanged: (v) {
                        setState(() {
                          _selectedIndustry = v;
                          _activeHighlights.remove('Industry');
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      'Occupation',
                      _occupationController,
                      hintText: 'Current job title or role',
                      highlightKey: 'Occupation',
                    ),
                  ],
                ),
              ),

              _buildSectionHeader('Education'),
              _buildSectionContainer(
                child: Column(
                  children: [
                    GooglePlacesAutocompleteField(
                      label: 'School / College / University',
                      controller: _eduInstController,
                      isHighlighted: _activeHighlights.contains('Education'),
                      filter: PlaceTypeFilter.SCHOOLS,
                      onSelected: (desc, id) {
                        setState(() {
                          _eduInstController.text = desc;
                          _activeHighlights.remove('Education');
                        });
                      },
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
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
          color: Colors.black.withValues(alpha: 0.7),
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
                  ).primaryColor.withValues(alpha: 0.1),
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
          color: Theme.of(
            context,
          ).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
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
    String? highlightKey,
  }) {
    final bool isHighlighted =
        highlightKey != null && _activeHighlights.contains(highlightKey);

    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      textCapitalization: TextCapitalization.sentences,
      onChanged: (v) {
        if (highlightKey != null &&
            v.trim().isNotEmpty &&
            _activeHighlights.contains(highlightKey)) {
          setState(() => _activeHighlights.remove(highlightKey));
        }
      },
      validator:
          validator ??
          (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        border: InputBorder.none,
        enabledBorder: isHighlighted
            ? OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.red, width: 1.5),
              )
            : InputBorder.none,
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
        border: InputBorder.none,
        enabledBorder: isHighlighted
            ? OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.red, width: 1.5),
              )
            : InputBorder.none,
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

  Widget _buildResidencyEdit() {
    final bool isHighlighted = _activeHighlights.contains(
      'Years in Host Country',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Lived in ${widget.initialProfile.hostCountry ?? 'Host Country'} since',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: isHighlighted
              ? AppTheme.innerDecoration(
                  context,
                ).copyWith(border: Border.all(color: Colors.red, width: 1.5))
              : AppTheme.innerDecoration(context),
          child: DropdownButtonFormField<String>(
            initialValue: _selectedYearsInHost.isNotEmpty
                ? _selectedYearsInHost
                : null,
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
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.red, width: 1.5),
              ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: AppTheme.innerDecoration(context),
                child: Row(
                  children: [
                    const Icon(
                      LucideIcons.mapPin,
                      size: 16,
                      color: Colors.grey,
                    ),
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

  /// Immediately writes GPS-derived currentLocation to Firestore.
  void _updateLocationFromGPS() {
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid != null) {
      LocationUpdateService().updateCurrentLocation(uid);
    }
  }

  /// Immediately writes host location into currentLocation / geo in Firestore.
  /// Used when the user hides their city so proximity still resolves to host city.
  void _fallbackToHostLocation() {
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid != null) {
      LocationUpdateService().fallbackToHostLocation(
        uid,
        widget.initialProfile.hostLocation,
      );
    }
  }

  Widget _buildLocationPrivacyToggle() {
    final forfeited = _cityVisibilityForfeited;
    return SwitchListTile(
      title: const Text('Show my current city name'),
      subtitle: forfeited
          ? Text(
              'City Visibility P.o.C.T was forfeited and cannot be re-earned.',
              style: TextStyle(fontSize: 11, color: Colors.orange[400]),
            )
          : (_showCurrentLocationName
                ? Text(
                    '+10 P.o.C.T for transparency (forfeited permanently if hidden)',
                    style: TextStyle(fontSize: 11, color: Colors.green[400]),
                  )
                : null),
      value: _showCurrentLocationName,
      onChanged: (v) {
        if (v) {
          // Re-enabling — immediately refresh GPS so currentLocation reflects
          // real position again, replacing the host-location fallback.
          setState(() => _showCurrentLocationName = true);
          _updateLocationFromGPS();
        } else {
          // Hiding — permanent loss of the +10 if not already forfeited.
          if (forfeited) {
            setState(() => _showCurrentLocationName = false);
            _fallbackToHostLocation();
          } else {
            _confirmHideCity();
          }
        }
      },
      contentPadding: EdgeInsets.zero,
    );
  }

  Future<void> _confirmHideCity() async {
    bool acknowledged = false;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Expanded(child: Text('Hide City — Permanent Loss')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Hiding your current city will permanently forfeit your +10 City '
                'Visibility P.o.C.T.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              const Text(
                '• You will lose 10 P.o.C.T from your trust score immediately.\n'
                '• Turning visibility back on later will NOT restore the +10.\n'
                '• This is a one-way action — there is no second chance.\n'
                '• Lower P.o.C.T means lower DSP → \$DIASPORA conversion at TGE.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                value: acknowledged,
                onChanged: (val) => setSt(() => acknowledged = val ?? false),
                title: const Text(
                  'I understand this is permanent and cannot be undone.',
                  style: TextStyle(fontSize: 13),
                ),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep City Visible'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: acknowledged ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Hide & Forfeit +10 P.o.C.T'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      setState(() {
        _showCurrentLocationName = false;
        _cityVisibilityForfeited = true;
      });
      // Replace currentLocation with host location so proximity calculations
      // remain accurate while the city name stays hidden from other users.
      _fallbackToHostLocation();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('City hidden. +10 P.o.C.T permanently forfeited.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }
}
