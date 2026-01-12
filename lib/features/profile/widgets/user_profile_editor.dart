import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:diaspora_nearby/models/google_places_models.dart';

import 'package:diaspora_nearby/models/profile_data.dart';
import 'package:diaspora_nearby/models/location.dart' as loc_model;
import 'package:diaspora_nearby/services/google_places_service.dart';
import 'package:diaspora_nearby/data/countries.dart' as country_data;
import 'package:diaspora_nearby/utils/location_utils.dart' as loc_utils;
import '../../shared/widgets/multi_select_dialog.dart';
import '../widgets/add_past_location_dialog.dart';
import 'package:universal_io/io.dart';
import 'package:image_picker/image_picker.dart';
import 'package:diaspora_nearby/features/shared/widgets/user_card.dart';

class UserProfileEditor extends ConsumerStatefulWidget {
  final ProfileData initialProfile;
  final Future<void> Function(ProfileData, XFile?) onSave;

  const UserProfileEditor({
    super.key,
    required this.initialProfile,
    required this.onSave,
  });



  @override
  ConsumerState<UserProfileEditor> createState() => _UserProfileEditorState();
}

class _UserProfileEditorState extends ConsumerState<UserProfileEditor> {
  late List<String> _yearRange;
  bool _isSaving = false;

  // Controllers
  final TextEditingController _bioController = TextEditingController();
  final TextEditingController _occupationController = TextEditingController();
  final TextEditingController _searchController = TextEditingController(); // For Host Location

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

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1024, maxHeight: 1024, imageQuality: 85);
    if (pickedFile != null) {
      setState(() {
        _newProfileImage = pickedFile;
      });
    }
  }

  // Host Location Update State
  List<AutocompletePrediction> _predictions = [];
  loc_model.UserLocation? _tempSelectedLocation;
  bool _isUpdatingLocation = false;
  bool _isLocationVerified = false;

  static const List<String> _availabilityOptions = [
    'Full-time', 'Part-time', 'Weekends only', 'Evenings only', 'Open to collaborate', 'Remote only', 'Not available',
  ];
  static const List<String> _industryOptions = [
    'Technology', 'Healthcare', 'Finance', 'Education', 'Construction', 'Retail', 'Art & Design', 'Hospitality', 'Legal', 'Government', 'Non-Profit', 'Other',
  ];
  static const List<String> _professionOptions = [
    'Software Engineer', 'Doctor', 'Teacher', 'Lawyer', 'Accountant', 'Nurse', 'Designer', 'Project Manager', 'Marketing Specialist', 'Sales Professional', 'Analyst', 'Entrepreneur', 'Student', 'Researcher', 'Other',
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
    _initializeData();
  }

  void _initializeData() {
    final currentYear = DateTime.now().year;
    _yearRange = List.generate(
      currentYear - 1960 + 1,
      (index) => (currentYear - index).toString(),
    );
    _yearRange.insert(0, 'Since birth');

    final p = widget.initialProfile;
    _bioController.text = p.bio ?? '';
    _occupationController.text = p.occupation ?? '';
    
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
  }

  @override
  void dispose() {
    _bioController.dispose();
    _occupationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    
    try {
      final updatedProfile = widget.initialProfile.copyWith(
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
        // Include host location update if verified
        hostLocation: _tempSelectedLocation ?? widget.initialProfile.hostLocation,
        hostCountry: _tempSelectedLocation?.country ?? widget.initialProfile.hostCountry,
        hostCountryCode: _tempSelectedLocation?.countryCode ?? widget.initialProfile.hostCountryCode,
        showCurrentLocationName: _showCurrentLocationName,
      );
      
      await widget.onSave(updatedProfile, _newProfileImage);
      
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
         setState(() => _isSaving = false);
         // Error is typically displayed by parent/provider, but we can show snackbar here if needed
         // For now, assume parent might show something or we just stay open
      }
    }
  }

  // --- Location Logic ---

  // --- Location Logic ---
  
  void _onSearchChanged(String input) async {
    if (input.isEmpty) {
      if (mounted) setState(() => _predictions = []);
      return;
    }
    final places = ref.read(googlePlacesServiceProvider);
    final results = await places.autocomplete(input);
    if (mounted) setState(() => _predictions = results);
  }

  // _selectPlace Logic is below under _buildLocationUpdateSection region



  // --- UI Building ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        leading: IconButton(
          icon: const Icon(LucideIcons.x),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _submit,
            child: _isSaving 
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) 
              : const Text('Save'),
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // User Card with Change Photo Action
            Stack(
              children: [
                UserCardView(
                  key: const ValueKey('editor_UserCard'),
                  user: widget.initialProfile,
                  localImage: _newProfileImage,
                  isStatic: true,
                  onImageTap: _pickImage, // [NEW] Tap avatar to change photo
                ),
                Positioned(
                  left: 24, // Align with avatar
                  top: 80,  // Near bottom of avatar
                  child: GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(LucideIcons.camera, color: Colors.white, size: 12),
                          SizedBox(width: 4),
                          Text('Change', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            _buildSectionContainer(
               title: 'Residency & Locations',
               icon: LucideIcons.mapPin,
               child: Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                    _buildResidencyEdit(),
                    const SizedBox(height: 12),
                    _buildPastLocationsEdit(),
                    const SizedBox(height: 12),
                    _buildLocationPrivacyToggle(),
                    _buildLocationUpdateSection(),
                 ],
               )
            ),

            _buildSectionContainer(
              title: 'About Me',
              icon: LucideIcons.user,
              child: TextField(
                controller: _bioController,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Write something about yourself...'),
              )
            ),

            _buildSectionContainer(
              title: 'Professional Info',
              icon: LucideIcons.briefcase,
              child: Column(children: [
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
              ]),
            ),

            _buildSectionContainer(
               title: 'Languages',
               icon: LucideIcons.languages,
               child: _buildMultiSelectDropdown(
                 title: 'Languages',
                 options: _languageOptions,
                 selectedValues: _selectedLanguages,
                 onChanged: (v) => setState(() => _selectedLanguages = v),
               )
            ),

            _buildSectionContainer(
              title: 'Interests',
              icon: LucideIcons.heart,
              child: _buildMultiSelectDropdown(
                title: 'Interests',
                options: _interestsOptions,
                selectedValues: _selectedInterests,
                onChanged: (v) => setState(() => _selectedInterests = v),
              )
            ),
            
            _buildSectionContainer(
               title: 'Community Support',
               icon: LucideIcons.users,
               child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                     const Text('Services I Can Offer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                     const SizedBox(height: 8),
                     _buildMultiSelectDropdown(
                       title: 'Services',
                       options: _servicesOptions,
                       selectedValues: _selectedServices,
                       onChanged: (v) => setState(() => _selectedServices = v),
                     ),
                     const SizedBox(height: 16),
                     const Text("What I'm Looking For", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                     const SizedBox(height: 8),
                     _buildMultiSelectDropdown(
                       title: "Looking For",
                       options: _lookingForOptions,
                       selectedValues: _selectedLookingFor,
                       onChanged: (v) => setState(() => _selectedLookingFor = v),
                     )
                  ],
               )
            ),

            _buildSectionContainer(
               title: 'Availability',
               icon: LucideIcons.clock,
               child: _buildMultiSelectDropdown(
                 title: 'Availability',
                 options: _availabilityOptions,
                 selectedValues: _selectedAvailability,
                 onChanged: (v) => setState(() => _selectedAvailability = v),
               )
            ),
            
            _buildSectionContainer(
               title: 'Meeting Preferences',
               icon: LucideIcons.coffee,
               child: _buildMultiSelectDropdown(
                  title: 'Meeting Preferences',
                  options: _meetingTypeOptions,
                  selectedValues: _selectedMeetingPreferences,
                  onChanged: (v) => setState(() => _selectedMeetingPreferences = v),
               )
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionContainer({required String title, IconData? icon, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
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
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildResidencyEdit() {
     return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
           Text('Lived in ${widget.initialProfile.hostCountry ?? 'Host Country'} since', style: const TextStyle(fontWeight: FontWeight.bold)),
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

  Widget _buildPastLocationsEdit() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Also lived in', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), // Added Title
        const SizedBox(height: 8),
        if (_pastLocations.isNotEmpty) ...[
          // Removed duplicate title from here
          ..._pastLocations.map((p) {
             // Robust Flag Logic matching UserProfileView
             String? flag;
             if (p.location.countryCode != null) {
               flag = country_data.getCountryByCode(p.location.countryCode!)?.flag;
             }
             
             // Fallback: search by country name if code is missing
             if (flag == null && p.location.country != null) {
                final countries = country_data.countries.where((c) => c.name.toLowerCase() == p.location.country!.toLowerCase() || c.code.toLowerCase() == p.location.country!.toLowerCase()).toList();
                if (countries.isNotEmpty) flag = countries.first.flag;
             }

             return ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                     const Icon(LucideIcons.mapPin, size: 16),
                     if (flag != null) ...[
                        const SizedBox(width: 8),
                        Text(flag, style: const TextStyle(fontSize: 18)),
                     ],
                  ],
                ),
                title: Text(p.location.formattedAddress),
                subtitle: Text('Until ${() {
                      try {
                        final dt = DateTime.parse(p.until);
                        return dt.year.toString();
                      } catch (_) {
                         return p.until;
                      }
                  }()}'),
                trailing: IconButton(icon: const Icon(LucideIcons.trash2, color: Colors.red, size: 16), onPressed: () => setState(() => _pastLocations.remove(p))),
             );
          }),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton.icon(
            onPressed: () {
               showDialog(
                 context: context,
                 builder: (ctx) => AddPastLocationDialog(
                    yearRange: _yearRange,
                    onAdd: (loc) => setState(() => _pastLocations.add(loc)),
                    placesService: ref.read(googlePlacesServiceProvider),
                    homeCountryCode: widget.initialProfile.homeCountryCode,
                 )
               );
            },
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
          const SizedBox(height: 16),
          // 1. Search Bar (Restored)
          TextField(
            controller: _searchController, 
            onChanged: _onSearchChanged, 
            textCapitalization: TextCapitalization.sentences, 
            decoration: InputDecoration(
               hintText: 'Search Host City (GPS Verified)', 
               suffixIcon: _isUpdatingLocation 
                  ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2)) 
                  : _searchController.text.isNotEmpty
                      ? IconButton(
                           icon: const Icon(LucideIcons.x, size: 18),
                           onPressed: () {
                             _searchController.clear();
                             _onSearchChanged('');
                             setState(() => _tempSelectedLocation = null);
                           },
                        )
                      : const Icon(LucideIcons.search),
               border: const OutlineInputBorder(),
               helperText: 'You must be physically located in the city you select.',
            )
          ),
          
          // 2. Suggestions
          if (_predictions.isNotEmpty) 
            Material(
              elevation: 4,
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                 height: 200, 
                 decoration: BoxDecoration(
                   borderRadius: BorderRadius.circular(8),
                   border: Border.all(color: Theme.of(context).dividerColor),
                 ),
                 child: ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: _predictions.length,
                    separatorBuilder: (ctx, i) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                       final p = _predictions[i];
                       return ListTile(
                         title: Text(p.primaryText),
                         subtitle: Text(p.fullText, style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor), maxLines: 1, overflow: TextOverflow.ellipsis),
                         onTap: () => _selectPlace(p.placeId),
                         dense: true,
                       );
                    }
                 )
              ),
            ),
       ],
     );
  }

  // --- Hybrid Verification Logic ---

  Future<void> _selectPlace(String placeId) async {
    setState(() => _isUpdatingLocation = true);
    try {
      final places = ref.read(googlePlacesServiceProvider);
      // 1. Get Place Details (Target)
      final response = await places.getPlaceDetails(placeId);
      final place = response?.place;
      
      if (place == null) throw Exception('Could not fetch place details');

      final targetLat = place.latLng?.lat;
      final targetLng = place.latLng?.lng;
      if (targetLat == null || targetLng == null) throw Exception('Selected place has no coordinates');

      List<AddressComponent> components = place.addressComponents ?? [];
      final parsedLoc = loc_utils.parseLocationComponents(place.address ?? '', components);
      if (parsedLoc == null) throw Exception('Could not parse location components');

      // 2. GPS Check
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) throw Exception('Location permission denied');
      }
      if (permission == LocationPermission.deniedForever) throw Exception('Location permission permanently denied');

      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
      
      // 3. Distance Calculation
      final distanceKm = loc_utils.calculateDistance(
         position.latitude, position.longitude, targetLat, targetLng
      );
      
      const double MAX_DISTANCE_KM = 50.0;
      
      if (distanceKm > MAX_DISTANCE_KM) {
         _showVerificationErrorDialog(parsedLoc.city ?? 'Selected City', distanceKm);
         // Clear predictions but don't set location
         setState(() {
            _predictions = [];
            _searchController.clear();
         });
         return; 
      }

      // 4. Success - Set Location
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
             lng: targetLng
          )
        ),
      );

      if (mounted) {
         setState(() {
           _tempSelectedLocation = newLocation;
           _predictions = [];
           _searchController.text = newLocation.formattedAddress;
           _isLocationVerified = true;
         });
         FocusScope.of(context).unfocus(); 
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() {
          _tempSelectedLocation = null;
          _isLocationVerified = false;
        });
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
        content: Text('You are ${distanceKm.round()}km away from $targetCity.\n\nTo ensure community integrity, you must be physically located in/near your host city to update it.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Understand'))],
      ),
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
                return MultiSelectDialog(
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

  Widget _buildLocationPrivacyToggle() {
    return SwitchListTile(
      title: const Text('Show my current city name'),
      subtitle: const Text('If off, others only see your country and distance away.'),
      value: _showCurrentLocationName,
      onChanged: (v) => setState(() => _showCurrentLocationName = v),
      secondary: const Icon(LucideIcons.eye, size: 20),
      contentPadding: EdgeInsets.zero,
    );
  }
}
