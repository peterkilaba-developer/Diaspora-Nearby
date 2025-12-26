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
import 'package:diaspora_nearby/features/community/models/hierarchy_item.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_google_places_sdk/flutter_google_places_sdk.dart' as places;
import 'package:diaspora_nearby/config/env.dart';
import 'package:diaspora_nearby/features/chat/utils/community_chat_utils.dart';
import 'package:diaspora_nearby/features/shared/ui/glass_container.dart';
import 'package:diaspora_nearby/features/events/widgets/event_card.dart';
import 'package:diaspora_nearby/features/events/screens/organizer_events_screen.dart';
import 'package:diaspora_nearby/models/profile_data.dart';

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
  List<ProfileData> _myContacts = [];
  List<String> _invitedUserIds = [];
  bool _isLoadingAudience = true;
  
  bool _isLoading = false;
  
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
    
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchAudienceData());
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
  }

  Future<void> _fetchAudienceData() async {
    try {
      final user = ref.read(authStateProvider).value;
      if (user == null) return;
      
      final communityRepo = ref.read(communityRepositoryProvider);
      final chatRepo = ref.read(chatRepositoryProvider);
      
      final communities = await communityRepo.getUserCommunities(user.uid);
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
          Form(
            key: _formKey,
            child: ListView(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 150 + MediaQuery.of(context).viewInsets.bottom),
              children: [
                // Image Picker
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
                           if (d != null) setState(() => _startDate = d);
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
                           if (t != null) setState(() => _endTime = t);
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
                           final profile = ref.read(userProfileProvider).value;
                           final isVerified = profile?.businessProfile?.isBusinessVerified == true;
                           
                           if (!isVerified && !_isPaid) {
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Business Verification Required'),
                                  content: const Text('To host paid events and collect payments, you need to verify your business profile. This ensures trust and security for all attendees.'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Cancel'),
                                    ),
                                    FilledButton(
                                      onPressed: () {
                                        Navigator.pop(context);
                                        // TODO: Navigate to business registration
                                      },
                                      child: const Text('Verify Now'),
                                    ),
                                  ],
                                ),
                              );
                              return;
                           }
                           setState(() => _isPaid = !_isPaid);
                        },
                        trailing: Switch(
                          value: _isPaid,
                          onChanged: (v) {
                             final profile = ref.read(userProfileProvider).value;
                             final isVerified = profile?.businessProfile?.isBusinessVerified == true;
                             
                             if (v && !isVerified) {
                                // Trigger same dialog
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Business Verification Required'),
                                    content: const Text('To host paid events and collect payments, you need to verify your business profile.'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Back')),
                                    ],
                                  ),
                                );
                                return;
                             }
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
                const SizedBox(height: 24),
                
                // Audience
                const Text('Who can attend?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                if (_isLoadingAudience)
                   const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator()))
                else
                   GlassContainer(
                     padding: EdgeInsets.zero,
                     child: Column(
                       children: [
                            ..._myCommunities.map((community) {
                               final isHomeCountry = community.type == 'country' && community.locationType == 'home';
                               final isHostCity = community.type == 'city' && community.locationType == 'host';
                               
                               final typeLabel = _getCommunityTypeLabel(community.type ?? 'unknown');
                               final suffix = isHomeCountry ? ' (Your Home Country)' : (isHostCity ? ' (Your Host City)' : '');

                               return RadioListTile<String>(
                                 title: Text(community.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                 subtitle: Text('$typeLabel$suffix'),
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
                             const SizedBox(height: 8), // Replaced Divider with transparent spacing
                             RadioListTile<String>(
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
                 const SizedBox(height: 100), // Spacing for FAB
              ],
            ),
          ),
          
          // Floating Submit Button
          Positioned(
            left: 16, right: 16, 
            bottom: 20 + MediaQuery.of(context).padding.bottom,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _submitEvent,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                elevation: 4,
              ),
              child: _isLoading 
                ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Theme.of(context).colorScheme.onPrimary, strokeWidth: 2))
                : Text(widget.eventToEdit != null ? 'Update Event' : 'Create Event', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          
          // Google Places Autocomplete
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
                        subtitle: p.secondaryText != null ? Text(p.secondaryText!) : null,
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
           status: 'draft', // Default to draft as requested
           createdAt: DateTime.now().toIso8601String(),
           attendees: [user.uid],
           attendeeCount: 1,
         );

         await repo.createEvent(event, _imageFile);

         if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Event Saved as Draft! Publish it in the Manage tab.'),
              duration: Duration(seconds: 3),
            ));
            
            // Navigate to Manage Tab (index 2)
            if (widget.eventToEdit == null) {
              final tabController = DefaultTabController.of(context);
              tabController.animateTo(2);
              
              // Reset state to clear form
              setState(() {
                _titleController.clear();
                _descriptionController.clear();
                _locationController.clear();
                _maxAttendeesController.clear();
                _ticketPriceController.clear();
                _imageFile = null;
                _venueName = null;
                _venueAddress = null;
                _venueCity = null;
                _venueState = null;
                _venueCountry = null;
                _latitude = null;
                _longitude = null;
              });
            } else {
              context.pop();
            }
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

class _ReadOnlyEventCard extends StatelessWidget {
  final Event event;
  const _ReadOnlyEventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
        onTap: () => context.push('/events/${event.id}', extra: event),
        child: GlassContainer(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            Stack(
              children: [
                Container(
                  height: 120,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    image: event.imageUrl != null 
                      ? DecorationImage(image: NetworkImage(event.imageUrl!), fit: BoxFit.cover)
                      : null,
                    color: theme.colorScheme.surfaceContainerHighest,
                  ),
                  child: event.imageUrl == null ? Center(child: Icon(LucideIcons.image, color: theme.colorScheme.outline)) : null,
                ),
                Positioned(
                  top: 8, right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: theme.colorScheme.surface.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      '${event.attendeeCount} Attendees',
                      style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(LucideIcons.calendar, size: 14, color: theme.colorScheme.outline),
                      const SizedBox(width: 4),
                      Text(
                        '${DateFormat('MMM d').format(DateTime.parse(event.startDate))} • ${event.startTime}',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

