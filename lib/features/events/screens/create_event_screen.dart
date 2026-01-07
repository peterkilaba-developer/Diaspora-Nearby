import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/events/repository/event_repository.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/community/repository/community_repository.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/models/event_data.dart';
import 'package:diaspora_nearby/models/community_data.dart';
import 'package:diaspora_nearby/features/organization/repository/organization_repository.dart';
import 'package:diaspora_nearby/features/community/models/hierarchy_item.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_google_places_sdk/flutter_google_places_sdk.dart' as places;
import 'package:diaspora_nearby/config/env.dart';
import 'package:diaspora_nearby/features/chat/utils/community_chat_utils.dart';
import 'package:diaspora_nearby/features/shared/ui/glass_container.dart';
import 'package:diaspora_nearby/features/events/widgets/event_card.dart';
import 'package:diaspora_nearby/features/events/screens/organizer_events_screen.dart';
import 'package:diaspora_nearby/models/profile_data.dart';
import 'package:diaspora_nearby/models/chat.dart';

class CreateEventScreen extends ConsumerStatefulWidget {
  final Event? eventToEdit; 
  const CreateEventScreen({super.key, this.eventToEdit});

  @override
  ConsumerState<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends ConsumerState<CreateEventScreen> {
  @override
  Widget build(BuildContext context) {
    final isEditing = widget.eventToEdit != null;

    if (isEditing) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Event')),
        body: _CreateEventForm(eventToEdit: widget.eventToEdit),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Event Dashboard'),
          bottom: TabBar(
            indicatorColor: Theme.of(context).primaryColor,
            tabs: const [
              Tab(text: 'Create'),
              Tab(text: 'View'),
              Tab(text: 'Manage'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _CreateEventForm(),
            _JoinedEventsList(),
            OrganizerEventsList(padding: EdgeInsets.zero),
          ],
        ),
      ),
    );
  }
}

class _CreateEventForm extends ConsumerStatefulWidget {
  final Event? eventToEdit;
  const _CreateEventForm({this.eventToEdit});

  @override
  ConsumerState<_CreateEventForm> createState() => _CreateEventFormState();
}

class _CreateEventFormState extends ConsumerState<_CreateEventForm> {
  final _formKey = GlobalKey<FormState>();
  
  // Controllers
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _ticketPriceController = TextEditingController();
  final _maxAttendeesController = TextEditingController();

  // State Variables
  File? _imageFile;
  String? _existingImageUrl;
  DateTime _startDate = DateTime.now().add(const Duration(minutes: 30));
  TimeOfDay _startTime = TimeOfDay.now();
  DateTime _endDate = DateTime.now().add(const Duration(hours: 2));
  TimeOfDay _endTime = TimeOfDay.now();
  
  String _category = 'Social Gathering';
  bool _isPaid = false;
  
  // Audience
  String _attendingPermission = 'global_community';
  List<Community> _myCommunities = [];
  List<Chat> _myGroups = []; // [NEW] Groups
  List<ProfileData> _myContacts = [];
  List<String> _invitedUserIds = [];
  bool _isLoadingAudience = true;
  
  bool _isLoading = false;
  bool _isPublished = true; // [NEW] Default to published
  
  // Places
  late final places.FlutterGooglePlacesSdk _places;
  List<places.AutocompletePrediction> _placePredictions = [];
  bool _showPredictions = false;
  
  // Venue Components
  String? _venueName;
  String? _venueAddress;
  String? _venueCity;
  String? _venueState;
  String? _venueCountry;
  double? _latitude;
  double? _longitude;

  final List<String> _categories = [
    'Social Gathering', 'Cultural Event', 'Professional Networking', 'Educational Workshop',
    'Sports & Recreation', 'Food & Dining', 'Arts & Entertainment', 'Community Service',
    'Religious/Spiritual', 'Concert', 'Other'
  ];

  // Organization State
  List<Map<String, dynamic>> _userOrgs = [];
  String? _selectedOrgId;

  final _layerLink = LayerLink();

  @override
  void initState() {
    super.initState();
    _places = places.FlutterGooglePlacesSdk(Env.googleMapsApiKey);
    
    // Set initial times
    final now = DateTime.now();
    final start = now.add(const Duration(minutes: 30));
    final end = start.add(const Duration(hours: 2));
    _startDate = start;
    _startTime = TimeOfDay.fromDateTime(start);
    _endDate = end;
    _endTime = TimeOfDay.fromDateTime(end);

    if (widget.eventToEdit != null) {
       _preFillForEdit();
    }
    
    WidgetsBinding.instance.addPostFrameCallback((_) async {
       _fetchAudienceData();
       final user = ref.read(authRepositoryProvider).currentUser;
       if (user != null) {
         debugPrint('Fetching organizations for user: ${user.uid}');
         final orgs = await ref.read(organizationRepositoryProvider).getUserOrganizations(user.uid);
         debugPrint('Fetched ${orgs.length} organizations: $orgs');
         if (mounted) {
            setState(() {
              _userOrgs = orgs;
              // If editing, try to match existing org
              if (widget.eventToEdit?.organizationId != null) {
                  _selectedOrgId = widget.eventToEdit!.organizationId;
              }
            });
         }
       }
    });
    
    // Listen to changes for validation
    _titleController.addListener(_onFormChanged);
    _locationController.addListener(_onFormChanged);
  }
  
  void _onFormChanged() {
    setState(() {});
  }
  
  bool get _isFormValid {
    if (_titleController.text.isEmpty) return false;
    if (_locationController.text.isEmpty) return false;
    if (_imageFile == null && _existingImageUrl == null) return false;
    return true;
  }

  void _preFillForEdit() {
     final e = widget.eventToEdit!;
     _titleController.text = e.title;
     _descriptionController.text = e.description;
     _locationController.text = e.location;
     _category = e.category;
     _isPaid = e.isPaid ?? false;
     if (e.ticketPrice != null) _ticketPriceController.text = e.ticketPrice.toString();
     if (e.maxAttendees != null) _maxAttendeesController.text = e.maxAttendees.toString();
     
     _existingImageUrl = e.imageUrl;
     
     try {
       _startDate = DateFormat('yyyy-MM-dd').parse(e.startDate);
       final timeParts = e.startTime.split(':');
       if (timeParts.length == 2) {
         _startTime = TimeOfDay(hour: int.parse(timeParts[0]), minute: int.parse(timeParts[1]));
       }
       
       if (e.endDate != null) {
         _endDate = DateFormat('yyyy-MM-dd').parse(e.endDate!);
       } else {
         _endDate = _startDate.add(const Duration(hours: 2));
       }

        if (e.endTime != null) {
           final endTimeParts = e.endTime!.split(':');
           if (endTimeParts.length == 2) {
             _endTime = TimeOfDay(hour: int.parse(endTimeParts[0]), minute: int.parse(endTimeParts[1]));
           }
        } else {
           _endTime = TimeOfDay.fromDateTime(DateTime.now().add(const Duration(hours: 2)));
        }
     } catch(err) {
       print('Error parsing date/time for edit: $err');
     }
     
     _attendingPermission = e.attendingPermission ?? 'global';
     if (e.invitedUserIds != null) {
       _invitedUserIds = List.from(e.invitedUserIds!);
     }

     // New Venue Fields
     _venueName = e.venueName;
     _venueAddress = e.venueAddress;
     _venueCity = e.venueCity;
     _venueState = e.venueState;
     _venueCountry = e.venueCountry;
     _latitude = e.latitude;
     _longitude = e.longitude;
     _isPublished = e.status == 'published'; // [NEW] Pre-fill status
  }

  Future<void> _fetchAudienceData() async {
    try {
      final user = ref.read(authStateProvider).value;
      if (user == null) return;
      
      final communityRepo = ref.read(communityRepositoryProvider);
      final chatRepo = ref.read(chatRepositoryProvider);
      
      final communities = await communityRepo.getUserCommunities(user.uid);
      final chats = await chatRepo.getUserChats(); // [NEW] Fetch chats
      final groups = chats.where((c) => c.type == 'group').toList();
      final contacts = await chatRepo.getChatContacts();
      
      // Sort priority: global -> continent -> country -> state -> city
      final typePriority = {
        'global': 0,
        'continent': 1,
        'country': 2,
        'state': 3,
        'city': 4,
      };

      communities.sort((a, b) {
        final pA = typePriority[a.type] ?? 99;
        final pB = typePriority[b.type] ?? 99;
        return pA.compareTo(pB);
      });

      if (mounted) {
        setState(() {
          _myCommunities = communities;
          _myGroups = groups;
          _myContacts = contacts;
          
          // Only set default if NOT editing (preserve existing selection)
          if (widget.eventToEdit == null) {
              if (_myCommunities.isNotEmpty) {
                 final defaultCommunity = _myCommunities.firstWhere(
                    // Priority 1: Home Country National Community
                    (c) => c.locationType == 'home' && c.type == 'country', 
                    orElse: () => _myCommunities.firstWhere(
                       // Priority 2: Any Home Community
                       (c) => c.locationType == 'home',
                       orElse: () => _myCommunities.firstWhere(
                          // Priority 3: National Community
                          (c) => c.type == 'country',
                          orElse: () => _myCommunities.firstWhere(
                             // Priority 4: Global
                             (c) => c.type == 'global',
                             orElse: () => _myCommunities.first
                          )
                       )
                    )
                 );
                 _attendingPermission = defaultCommunity.id;
              } else {
                 _attendingPermission = 'private'; 
              }
          }
          
          _isLoadingAudience = false;
        });
      }
    } catch (e) {
      print('Error fetching audience data: $e');
      if (mounted) setState(() => _isLoadingAudience = false);
    }
  }

  @override
  void dispose() {
    _titleController.removeListener(_onFormChanged);
    _locationController.removeListener(_onFormChanged);
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _ticketPriceController.dispose();
    _maxAttendeesController.dispose();
    super.dispose();
  }

   Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
      });
    }
  }

  void _onLocationChanged(String value) {
    if (value.isEmpty) {
      setState(() { _placePredictions = []; _showPredictions = false; });
      return;
    }
    _places.findAutocompletePredictions(value).then((response) {
      setState(() { _placePredictions = response.predictions; _showPredictions = true; });
    });
  }

  void _selectPlace(places.AutocompletePrediction prediction) async {
    _locationController.text = prediction.fullText;
    setState(() { _showPredictions = false; _placePredictions = []; });
    FocusScope.of(context).unfocus();

    try {
      final response = await _places.fetchPlace(
        prediction.placeId,
        fields: [
          places.PlaceField.Name,
          places.PlaceField.Address,
          places.PlaceField.AddressComponents,
          places.PlaceField.Location,
        ],
      );
      
      final place = response.place;
      if (place != null) {
        setState(() {
          _venueName = place.name;
          _venueAddress = place.address;
          _latitude = place.latLng?.lat;
          _longitude = place.latLng?.lng;
          
          // Parse Address Components
          if (place.addressComponents != null) {
            for (var comp in place.addressComponents!) {
              if (comp.types.contains('locality')) _venueCity = comp.name;
              if (comp.types.contains('administrative_area_level_1')) _venueState = comp.name;
              if (comp.types.contains('country')) _venueCountry = comp.name;
            }
          }
        });
      }
    } catch (e) {
      print('Error fetching place details: $e');
    }
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    return DateFormat('HH:mm').format(dt);
  }
  
  String _getCommunityTypeLabel(String? type) {
    switch(type) {
      case 'global': return 'Global Community';
      case 'country': return 'National Community';
      case 'state': return 'State Community';
      case 'city': return 'City Community';
      default: return 'Community';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Image Picker ... (same)
                      // Image Picker ... (same)
                      // Organization Selection
                      if (_userOrgs.isNotEmpty) ...[
                        DropdownButtonFormField<String?>(
                          value: _selectedOrgId,
                          isExpanded: true, // Fix overflow
                          decoration: InputDecoration(
                            labelText: 'Publish as',
                            prefixIcon: const Icon(LucideIcons.building2),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Personal Event (Me)'),
                            ),
                            ..._userOrgs.map((org) {
                              return DropdownMenuItem<String?>(
                                value: org['id'],
                                child: Text(
                                  org['name'] ?? org['businessName'] ?? 'Organization',
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              );
                            }),
                          ],
                          onChanged: (val) {
                            setState(() {
                              _selectedOrgId = val;
                            });
                          },
                        ),
                        const SizedBox(height: 20),
                      ],

                       GestureDetector(
                        onTap: _pickImage,
                        child: Container(
                          height: 200,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                            image: _imageFile != null 
                              ? DecorationImage(image: FileImage(_imageFile!), fit: BoxFit.cover)
                              : (_existingImageUrl != null 
                                   ? DecorationImage(image: NetworkImage(_existingImageUrl!), fit: BoxFit.cover)
                                   : null),
                          ),
                          child: Stack(
                            children: [
                              if (_imageFile == null && _existingImageUrl == null)
                                Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(LucideIcons.imagePlus, size: 50, color: Theme.of(context).colorScheme.primary),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Upload Event Image', 
                                        style: TextStyle(
                                          color: Theme.of(context).colorScheme.primary,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold
                                        )
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Select a beautiful cover photo', 
                                        style: TextStyle(
                                          color: Theme.of(context).colorScheme.outline,
                                          fontSize: 12
                                        )
                                      ),
                                    ],
                                  ),
                                ),
                                
                              // Preview Badges
                              if (_imageFile != null || _existingImageUrl != null) ...[
                                 Positioned(
                                     top: 12, left: 12,
                                     child: Container(
                                       padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                       decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(8)),
                                       child: Text(_category, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 12, fontWeight: FontWeight.bold)),
                                     ),
                                 ),
                                 Positioned(
                                     top: 12, right: 12,
                                     child: Container(
                                       padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                       decoration: BoxDecoration(
                                         color: _isPaid ? Theme.of(context).colorScheme.tertiary : Theme.of(context).colorScheme.primary,
                                         borderRadius: BorderRadius.circular(8),
                                       ),
                                       child: Text(
                                         _isPaid && _ticketPriceController.text.isNotEmpty ? '\$${_ticketPriceController.text}' : 'Free',
                                         style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                                       ),
                                     ),
                                 ),
                              ]
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
      
                      // Form Fields
                      TextFormField(
                        controller: _titleController,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: 'Event Title *',
                          prefixIcon: const Icon(LucideIcons.type),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                        ),
                        validator: (v) => v!.isEmpty ? 'Title is required' : null,
                      ),
                      const SizedBox(height: 16),
                      
                      TextFormField(
                        controller: _descriptionController,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: 'Description',
                          alignLabelWithHint: true,
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                        ),
                        validator: (v) => v!.isEmpty ? 'Description is required' : null,
                      ),
                      const SizedBox(height: 16),
      
                      DropdownButtonFormField<String>(
                        value: _category,
                        decoration: InputDecoration(
                          labelText: 'Category *',
                          prefixIcon: const Icon(LucideIcons.tag),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                        ),
                        items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                        onChanged: (v) => setState(() => _category = v!),
                      ),
                      const SizedBox(height: 16),
      
                      // Date Time Pickers
                      const Text('Start Date & Time', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                           Expanded(child: OutlinedButton.icon(
                               onPressed: () async {
                                 final d = await showDatePicker(context: context, initialDate: _startDate, firstDate: DateTime.now(), lastDate: DateTime(2030));
                                 if (d != null) {
                                    setState(() {
                                       _startDate = d;
                                       // Auto-adjust end date if needed
                                       if (_endDate.isBefore(_startDate)) {
                                          _endDate = _startDate;
                                       }
                                    });
                                 }
                               },
                               icon: const Icon(LucideIcons.calendar),
                               label: Text(DateFormat('MMM d, y').format(_startDate)),
                           )),
                           const SizedBox(width: 12),
                           Expanded(child: OutlinedButton.icon(
                               onPressed: () async {
                                 final t = await showTimePicker(context: context, initialTime: _startTime);
                                 if (t != null) setState(() => _startTime = t);
                               },
                               icon: const Icon(LucideIcons.clock),
                               label: Text(_startTime.format(context)),
                           )),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text('End Date & Time', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 8),
                       Row(
                        children: [
                           Expanded(child: OutlinedButton.icon(
                               onPressed: () async {
                                 // [FIX] First date is StartDate
                                 final d = await showDatePicker(context: context, initialDate: _endDate, firstDate: _startDate, lastDate: DateTime(2030));
                                 if (d != null) setState(() => _endDate = d);
                               },
                               icon: const Icon(LucideIcons.calendar),
                               label: Text(DateFormat('MMM d, y').format(_endDate)),
                           )),
                           const SizedBox(width: 12),
                           Expanded(child: OutlinedButton.icon(
                               onPressed: () async {
                                 final t = await showTimePicker(context: context, initialTime: _endTime);
                                 if (t != null) {
                                    // [FIX] Logical check for end time
                                    final startDateTime = DateTime(_startDate.year, _startDate.month, _startDate.day, _startTime.hour, _startTime.minute);
                                    final endDateTime = DateTime(_endDate.year, _endDate.month, _endDate.day, t.hour, t.minute);
                                    
                                    if (endDateTime.isBefore(startDateTime)) {
                                       // If selected end time is before start time (e.g. same day), push it forward
                                       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('End time cannot be before start time')));
                                       // Optionally auto-correct
                                       final newEnd = startDateTime.add(const Duration(minutes: 30));
                                       setState(() => _endTime = TimeOfDay.fromDateTime(newEnd));
                                    } else {
                                       setState(() => _endTime = t);
                                    }
                                 }
                               },
                               icon: const Icon(LucideIcons.clock),
                               label: Text(_endTime.format(context)),
                           )),
                        ],
                      ),
                      const SizedBox(height: 24),
      
                      // Location Composite
                      CompositedTransformTarget(
                        link: _layerLink,
                        child: TextFormField(
                          controller: _locationController,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            labelText: 'Location / Venue *', 
                            prefixIcon: const Icon(LucideIcons.mapPin), 
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                            hintText: 'Search for address or place'
                          ),
                          onChanged: _onLocationChanged,
                          validator: (v) => v!.isEmpty ? 'Location is required' : null,
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                       // Max Attendees
                      TextFormField(
                        controller: _maxAttendeesController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Maximum Attendees (Optional)', 
                          prefixIcon: const Icon(LucideIcons.users),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                          hintText: 'Leave empty for unlimited'
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Paid Checkbox
                      Card(
                        child: Column(
                          children: [
                            ListTile(
                              title: const Text('Is this a paid event?'),
                              onTap: () {
                                 // [FIX] Removed verification check
                                 setState(() => _isPaid = !_isPaid);
                              },
                              trailing: Switch(
                                value: _isPaid,
                                onChanged: (v) {
                                   // [FIX] Removed verification check
                                   setState(() => _isPaid = v);
                                },
                                activeColor: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            if (_isPaid)
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: TextFormField(
                                  controller: _ticketPriceController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: InputDecoration(
                                    labelText: 'Ticket Price (\$)',
                                    prefixIcon: const Icon(LucideIcons.dollarSign),
                                    filled: true,
                                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Publish / Hide Toggle
                      Container(
                        decoration: BoxDecoration(
                          color: _isPublished ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3) : Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _isPublished ? Theme.of(context).colorScheme.primary : Colors.transparent),
                        ),
                        child: SwitchListTile(
                          title: Text(_isPublished ? 'Published' : 'Hidden (Draft)', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(_isPublished ? 'Visible to everyone' : 'Hidden from everyone except you'),
                          value: _isPublished,
                          onChanged: (v) => setState(() => _isPublished = v),
                          secondary: Icon(_isPublished ? LucideIcons.eye : LucideIcons.eyeOff, color: _isPublished ? Theme.of(context).colorScheme.primary : Colors.grey),
                        ),
                      ),
                      const SizedBox(height: 24),
                      
                      // Audience
                      const Text('Who can attend?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      if (_isLoadingAudience)
                         const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator()))
                      else
                         GlassContainer(
                           padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8), // [FIX] 8px horizontal padding
                           child: Column(
                             children: [
                                  // Communities
                                  ..._myCommunities.map((community) {
                                     // [FIX] No subtitles, just name. Exception maybe Global?
                                     // User said "remove sub titles for communities". 
                                     // "global community is unfiltered and includes all app members" -> Add note to Global
                                     
                                     final isGlobal = community.type == 'global';
                                     
                                      return RadioListTile<String>(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                        title: Text(community.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                        subtitle: Text(
                                          '${isGlobal ? 'Includes all app members • ' : ''}${community.memberCount} members', 
                                          style: const TextStyle(fontSize: 12)
                                        ),
                                        value: community.id,
                                        groupValue: _attendingPermission,
                                        onChanged: (v) => setState(() => _attendingPermission = v!),
                                        controlAffinity: ListTileControlAffinity.trailing,
                                        secondary: CommunityChatUtils.getCommunityAvatar(
                                            context: context, chat: null, communityId: community.id,
                                            type: community.type, locationType: community.locationType,
                                            profileImage: community.profileImage, homeCountryCode: community.homeCountryCode,
                                            hostCountryCode: community.hostCountryCode, flag: community.flag, size: 40,
                                        ),
                                      );
                                   }),
                                   
                                   // [NEW] Groups
                                   if (_myGroups.isNotEmpty) ...[
                                      const Padding(
                                        padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 16),
                                        child: Align(alignment: Alignment.centerLeft, child: Text('My Groups', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey))),
                                      ),
                                      ..._myGroups.map((group) {
                                         // Groups don't have subtitles requested
                                          return RadioListTile<String>(
                                             contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                             title: Text(group.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                             subtitle: Text('${group.memberCount ?? group.participants.length} members', style: const TextStyle(fontSize: 12)),
                                             value: group.id,
                                             groupValue: _attendingPermission,
                                             onChanged: (v) => setState(() => _attendingPermission = v!),
                                             controlAffinity: ListTileControlAffinity.trailing,
                                             secondary: ClipRRect(
                                                borderRadius: BorderRadius.circular(20),
                                                child: (group.photoUrl != null && group.photoUrl!.isNotEmpty)
                                                  ? Image.network(
                                                      group.photoUrl!, 
                                                      width: 40, height: 40, 
                                                      fit: BoxFit.cover, 
                                                      errorBuilder: (_,__,___) => Container(width: 40, height: 40, color: Colors.grey[300], child: const Icon(LucideIcons.users)),
                                                    )
                                                  : Container(width: 40, height: 40, color: Colors.grey[300], child: const Icon(LucideIcons.users)),
                                             )
                                          );
                                      })
                                   ],
      
                                   const SizedBox(height: 8), 
                                    RadioListTile<String>(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                      title: const Text('Private (Invitation Only)', style: TextStyle(fontWeight: FontWeight.bold)),
                                      value: 'private',
                                      groupValue: _attendingPermission,
                                      onChanged: (v) => setState(() => _attendingPermission = v!),
                                      controlAffinity: ListTileControlAffinity.trailing,
                                      secondary: const CircleAvatar(child: Icon(LucideIcons.lock)),
                                    ),
                                   if (_attendingPermission == 'private') ...[
                                     const Padding(padding: EdgeInsets.all(16), child: Text('Invitee Selection TBD')) 
                                   ]
                             ],
                           ),
                         ),
                       const SizedBox(height: 20), // Spacing for scrolling
                    ],
                  ),
                ),
              ),
              
              // Sticky Bottom Button
              Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  boxShadow: [
                     BoxShadow(
                       color: Colors.black.withValues(alpha: 0.05),
                       blurRadius: 10,
                       offset: const Offset(0, -5),
                     )
                  ]
                ),
                child: ElevatedButton(
                  onPressed: _isLoading || !_isFormValid ? null : _submitEvent,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    elevation: 0,
                  ),
                  child: _isLoading 
                    ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Theme.of(context).colorScheme.onPrimary, strokeWidth: 2))
                    : Text(widget.eventToEdit != null ? 'Update Event' : 'Create Event', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          
          // Google Places Autocomplete (Sticky Overlay)
          if (_showPredictions)
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: const Offset(0, 60),
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(12)),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: _placePredictions.length,
                    itemBuilder: (context, index) {
                      final p = _placePredictions[index];
                      return ListTile(
                        title: Text(p.primaryText),
                        subtitle: p.secondaryText.isNotEmpty ? Text(p.secondaryText) : null,
                        onTap: () => _selectPlace(p),
                      );
                    },
                  ),
                ),
              ),
            ),
        ],
    );
  }

  Future<void> _submitEvent() async {
    if (!_formKey.currentState!.validate()) return;
    
    // Time Validation
    final start = DateTime(_startDate.year, _startDate.month, _startDate.day, _startTime.hour, _startTime.minute);
    final end = DateTime(_endDate.year, _endDate.month, _endDate.day, _endTime.hour, _endTime.minute);
    
    if (end.isBefore(start)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('End time must be after start time'),
        backgroundColor: Colors.red,
      ));
      return;
    }

    if (_imageFile == null && _existingImageUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please add an event image')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = ref.read(authStateProvider).value;
      final profile = ref.read(userProfileProvider).value;
      if (user == null || profile == null) throw Exception('User not logged in');

      final repo = ref.read(eventRepositoryProvider);

      String? orgName;
      if (_selectedOrgId != null) {
         final org = _userOrgs.firstWhere(
           (o) => o['id'] == _selectedOrgId, 
           orElse: () => {'name': null} // Use name: null or handle gracefully
         );
         orgName = org['name'] ?? org['businessName'];
      }
      
      if (widget.eventToEdit != null) {
         // UPDATE
         final updatedEvent = widget.eventToEdit!.copyWith(
            title: _titleController.text.trim(),
            description: _descriptionController.text.trim(),
            startDate: DateFormat('yyyy-MM-dd').format(_startDate),
            startTime: _formatTimeOfDay(_startTime),
            endDate: DateFormat('yyyy-MM-dd').format(_endDate),
            endTime: _formatTimeOfDay(_endTime),
            location: _locationController.text.trim(),
            category: _category,
            isPaid: _isPaid,
            ticketPrice: _isPaid ? double.tryParse(_ticketPriceController.text) : null,
            attendingPermission: _attendingPermission,
            invitedUserIds: _attendingPermission == 'private' ? _invitedUserIds : null,
            maxAttendees: _maxAttendeesController.text.isNotEmpty ? int.tryParse(_maxAttendeesController.text) : null,
            venueName: _venueName,
            venueAddress: _venueAddress,
            venueCity: _venueCity,
            venueState: _venueState,
            venueCountry: _venueCountry,
            latitude: _latitude,
            longitude: _longitude,
            status: _isPublished ? 'published' : 'hidden', // [NEW] Use toggle
            organizationId: _selectedOrgId,
            organizationName: orgName,
         );
         
         await repo.updateEvent(updatedEvent, _imageFile);
         if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Event Updated Successfully!')));
           context.pop(); 
         }
      } else {
         // CREATE
         final eventId = const Uuid().v4();
         final event = Event(
           id: eventId,
           title: _titleController.text.trim(),
           description: _descriptionController.text.trim(),
           startDate: DateFormat('yyyy-MM-dd').format(_startDate),
           startTime: _formatTimeOfDay(_startTime),
           endDate: DateFormat('yyyy-MM-dd').format(_endDate),
           endTime: _formatTimeOfDay(_endTime),
           location: _locationController.text.trim(),
           category: _category,
           creatorId: user.uid,
           isPaid: _isPaid,
           ticketPrice: _isPaid ? double.tryParse(_ticketPriceController.text) : null,
           attendingPermission: _attendingPermission,
           invitedUserIds: _attendingPermission == 'private' ? _invitedUserIds : null,
           maxAttendees: _maxAttendeesController.text.isNotEmpty ? int.tryParse(_maxAttendeesController.text) : null,
           homeCountry: profile.homeCountry,
           hostCountry: profile.hostLocation.country,
           hostCity: profile.hostLocation.city,
           hostState: profile.hostLocation.state,
           homeCountryCode: profile.homeCountryCode,
           hostCountryCode: profile.hostCountryCode,
           venueName: _venueName,
           venueAddress: _venueAddress,
           venueCity: _venueCity,
           venueState: _venueState,
           venueCountry: _venueCountry,
           latitude: _latitude,
           longitude: _longitude,
           status: _isPublished ? 'published' : 'hidden', // [NEW] Use toggle
           createdAt: DateTime.now().toIso8601String(),
           attendees: [user.uid],
           attendeeCount: 1,
           organizationId: _selectedOrgId,
           organizationName: orgName,
         );

         await repo.createEvent(event, _imageFile);

         if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Event Published Successfully!'),
              duration: Duration(seconds: 3),
            ));
            
            // Navigate to the new event details page
            context.pushReplacement('/events/${event.id}', extra: event);
         }
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
       if (mounted) setState(() => _isLoading = false);
    }
  }
}

// -----------------------------------------------------------------------------
// TAB 2: JOINED EVENTS (View)
// -----------------------------------------------------------------------------
class _JoinedEventsList extends ConsumerWidget {
  const _JoinedEventsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
     final user = ref.watch(authStateProvider).value;
    if (user == null) return const Center(child: CircularProgressIndicator());

    final eventsStream = ref.watch(eventRepositoryProvider).getJoinedEvents(user.uid);

    return StreamBuilder<List<Event>>(
      stream: eventsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        
        final events = snapshot.data ?? [];
        if (events.isEmpty) {
           return const Center(child: Text('You have not joined any events yet.'));
        }
        
        return ListView.separated(
            padding: const EdgeInsets.only(left: 8, right: 8, top: 8, bottom: 80),
            itemCount: events.length,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final event = events[index];
              // Reusing OrganizerEventCard for display, but filtering actions might be needed?
              // OrganizerEventCard has Delete/Edit which regular joined users shouldn't see.
              // We need a read-only card or check permissions inside card.
              // For now, let's assume OrganizerEventCard is for ORGANIZERS.
              // We should create a regular EventCard or reuse the one from EventsScreen?
              // Using unified EventCard for consistency
              return EventCard(
                event: event,
                isAttending: true, // Since it's 'Joined Events'
              );
            },
        );
      },
    );
  }
}


