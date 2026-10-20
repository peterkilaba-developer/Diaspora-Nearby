import 'package:universal_io/io.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/events/repository/event_repository.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/community/repository/community_repository.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/features/events/models/event_data.dart';
import 'package:diaspora_nearby/features/community/models/community_data.dart';
import 'package:diaspora_nearby/features/organization/repository/organization_repository.dart';
import 'package:uuid/uuid.dart';
import 'package:diaspora_nearby/features/shared/models/google_places_models.dart'
    as places;
import 'package:diaspora_nearby/features/chat/utils/community_chat_utils.dart';
import 'package:diaspora_nearby/features/shared/ui/glass_container.dart';
import 'package:diaspora_nearby/features/events/widgets/event_card.dart';
import 'package:diaspora_nearby/features/events/screens/organizer_events_screen.dart';
import 'package:diaspora_nearby/core/services/google_places_service.dart';
import 'package:diaspora_nearby/core/services/plus_code_service.dart';

import 'package:diaspora_nearby/features/chat/models/chat.dart';

class CreateEventScreen extends ConsumerStatefulWidget {
  final Event? eventToEdit;
  final String? eventIdToEdit;
  final String? communityId; // [NEW] Optional community context
  final String? groupId; // [NEW] Support creating event for a group

  const CreateEventScreen({
    super.key,
    this.eventToEdit,
    this.eventIdToEdit,
    this.communityId,
    this.groupId,
  });

  @override
  ConsumerState<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends ConsumerState<CreateEventScreen> {
  bool _isDeleting = false;

  Future<void> _confirmAndDeleteEvent(Event event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Event?'),
        content: Text(
          'Are you sure you want to delete "${event.title}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);
    try {
      final user = ref.read(authRepositoryProvider).currentUser;
      await ref.read(eventRepositoryProvider).deleteEvent(event.id);
      ref.invalidate(eventDetailsProvider(event.id));
      ref.invalidate(allRawEventsStreamProvider);
      if (user != null) {
        ref.invalidate(userEventsProvider(user.uid));
        ref.invalidate(joinedEventsProvider(user.uid));
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Event deleted')),
        );
        context.go('/events');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDeleting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete event: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing =
        widget.eventToEdit != null || widget.eventIdToEdit != null;

    if (isEditing) {
      Event? resolvedEvent = widget.eventToEdit;
      if (resolvedEvent == null && widget.eventIdToEdit != null) {
        final asyncEvent = ref.watch(
          eventDetailsProvider(widget.eventIdToEdit!),
        );
        if (asyncEvent.isLoading) {
          return Scaffold(
            appBar: AppBar(title: const Text('Manage Event')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        resolvedEvent = asyncEvent.value;
        if (resolvedEvent == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Manage Event')),
            body: const Center(child: Text('Event not found')),
          );
        }
      }

      return Scaffold(
        appBar: AppBar(
          title: const Text('Manage Event'),
          actions: [
            if (resolvedEvent != null)
              IconButton(
                icon: const Icon(LucideIcons.users),
                tooltip: 'Attendees',
                onPressed: () => context.push(
                  '/events/${resolvedEvent!.id}/attendees',
                  extra: resolvedEvent,
                ),
              ),
            if (resolvedEvent != null)
              IconButton(
                icon: _isDeleting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.trash2, color: AppTheme.error),
                tooltip: 'Delete Event',
                onPressed: _isDeleting
                    ? null
                    : () => _confirmAndDeleteEvent(resolvedEvent!),
              ),
          ],
        ),
        body: _CreateEventForm(
          eventToEdit: resolvedEvent,
          communityId: widget.communityId, // [NEW]
          groupId: widget.groupId,
        ),
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
        body: TabBarView(
          children: [
            _CreateEventForm(
              communityId: widget.communityId,
              groupId: widget.groupId,
            ), // [NEW]
            const _JoinedEventsList(),
            const OrganizerEventsList(padding: EdgeInsets.zero),
          ],
        ),
      ),
    );
  }
}

class _CreateEventForm extends ConsumerStatefulWidget {
  final Event? eventToEdit;
  final String? communityId; // [NEW]
  final String? groupId;

  const _CreateEventForm({this.eventToEdit, this.communityId, this.groupId});

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
  XFile? _imageFile;
  String? _existingImageUrl;
  DateTime _startDate = DateTime.now().add(const Duration(minutes: 30));
  TimeOfDay _startTime = TimeOfDay.now();
  DateTime _endDate = DateTime.now().add(const Duration(hours: 2));
  TimeOfDay _endTime = TimeOfDay.now();

  String _category = 'Social Gathering';

  // Audience
  String _attendingPermission = 'global_community';
  List<Community> _myCommunities = [];
  List<Chat> _myGroups = []; // [NEW] Groups
  List<String> _invitedUserIds = [];
  bool _isLoadingAudience = true;

  bool _isPaid = false;
  bool _isLoading = false;
  bool _isPublished = true; // [NEW] Default to published

  // Places
  List<places.AutocompletePrediction> _placePredictions = [];
  bool _showPredictions = false;

  // Venue Components
  String? _venueName;
  String? _venueAddress;
  String? _venueCity;
  String? _venueState;
  String? _venueCountry;
  String? _plusCode;
  double? _latitude;
  double? _longitude;

  final List<String> _categories = [
    'Social Gathering',
    'Cultural Event',
    'Professional Networking',
    'Educational Workshop',
    'Sports & Recreation',
    'Food & Dining',
    'Arts & Entertainment',
    'Community Service',
    'Religious/Spiritual',
    'Concert',
    'Other',
  ];

  // Organization State
  List<Map<String, dynamic>> _userOrgs = [];
  String? _selectedOrgId;

  final _layerLink = LayerLink();

  @override
  void initState() {
    super.initState();

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
    } else if (widget.communityId != null) {
      // [NEW] Pre-select community if provided
      _attendingPermission = widget.communityId!;
    } else if (widget.groupId != null) {
      // [NEW] Pre-select group if provided
      _attendingPermission = widget.groupId!;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _fetchAudienceData();
      final user = ref.read(authRepositoryProvider).currentUser;
      if (user != null) {
        debugPrint('Fetching organizations for user: ${user.uid}');
        final orgs = await ref
            .read(organizationRepositoryProvider)
            .getUserOrganizations(user.uid);
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

    if (e.maxAttendees != null) {
      _maxAttendeesController.text = e.maxAttendees.toString();
    }

    _existingImageUrl = e.imageUrl;

    try {
      _startDate = DateFormat('yyyy-MM-dd').parse(e.startDate);
      final timeParts = e.startTime.split(':');
      if (timeParts.length == 2) {
        _startTime = TimeOfDay(
          hour: int.parse(timeParts[0]),
          minute: int.parse(timeParts[1]),
        );
      }

      if (e.endDate != null) {
        _endDate = DateFormat('yyyy-MM-dd').parse(e.endDate!);
      } else {
        _endDate = _startDate.add(const Duration(hours: 2));
      }

      if (e.endTime != null) {
        final endTimeParts = e.endTime!.split(':');
        if (endTimeParts.length == 2) {
          _endTime = TimeOfDay(
            hour: int.parse(endTimeParts[0]),
            minute: int.parse(endTimeParts[1]),
          );
        }
      } else {
        _endTime = TimeOfDay.fromDateTime(
          DateTime.now().add(const Duration(hours: 2)),
        );
      }
    } catch (err) {
      debugPrint('Error parsing date/time for edit: $err');
    }

    _attendingPermission = e.attendingPermission ?? 'global';
    if (e.invitedUserIds != null) {
      _invitedUserIds = List.from(e.invitedUserIds!);
    }

    // Paid Event Fields
    _isPaid = e.isPaid ?? false;
    if (e.ticketPrice != null) {
      _ticketPriceController.text = e.ticketPrice.toString();
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

      var communities = await communityRepo.getUserCommunities(user.uid);
      final chats = await chatRepo.getUserChats(); // [NEW] Fetch chats
      var groups = chats.where((c) => c.type == 'group').toList();

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
          // [NEW] Filter if communityId is restricted
          if (widget.communityId != null) {
            communities = communities
                .where((c) => c.id == widget.communityId)
                .toList();
            groups = []; // Clear groups as we are in strict community mode
          }

          // [NEW] Handle groupId restriction
          if (widget.groupId != null) {
            groups = groups.where((g) => g.id == widget.groupId).toList();
            communities =
                []; // Clear communities as we are in strict group mode
          }

          _myCommunities = communities;
          _myGroups = groups;

          // Only set default if NOT editing (preserve existing selection)
          if (widget.eventToEdit == null) {
            if (widget.communityId != null) {
              _attendingPermission = widget.communityId!;
            } else if (widget.groupId != null) {
              _attendingPermission = widget.groupId!;
            } else if (_myCommunities.isNotEmpty) {
              final defaultCommunity = _myCommunities.firstWhere(
                (c) => c.type == 'global',
                orElse: () => _myCommunities.firstWhere(
                  (c) => c.locationType == 'home' && c.type == 'country',
                  orElse: () => _myCommunities.firstWhere(
                    (c) => c.locationType == 'home',
                    orElse: () => _myCommunities.firstWhere(
                      (c) => c.type == 'country',
                      orElse: () => _myCommunities.first,
                    ),
                  ),
                ),
              );
              _attendingPermission = defaultCommunity.id;
            } else {
              _attendingPermission = 'global_community';
            }
          }

          _isLoadingAudience = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching audience data: $e');
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
    FocusScope.of(context).unfocus(); // [FIX]
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (pickedFile != null) {
      setState(() {
        _imageFile = pickedFile;
      });
    }
  }

  void _onLocationChanged(String value) {
    if (value.isEmpty) {
      setState(() {
        _placePredictions = [];
        _showPredictions = false;
      });
      return;
    }
    ref
        .read(googlePlacesServiceProvider)
        .autocomplete(value, filter: places.PlaceTypeFilter.VENUES)
        .then((predictions) {
          setState(() {
            _placePredictions = predictions;
            _showPredictions = true;
          });
        });
  }

  void _selectPlace(places.AutocompletePrediction prediction) async {
    _locationController.text = prediction.fullText;
    setState(() {
      _showPredictions = false;
      _placePredictions = [];
    });
    FocusScope.of(context).unfocus();

    try {
      final response = await ref
          .read(googlePlacesServiceProvider)
          .getPlaceDetails(prediction.placeId);

      final place = response?.place;
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
              if (comp.types.contains('administrative_area_level_1')) {
                _venueState = comp.name;
              }
              if (comp.types.contains('country')) _venueCountry = comp.name;
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching place details: $e');
    }
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    return DateFormat('HH:mm').format(dt);
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
                  padding: const EdgeInsets.all(
                    AppTheme.pageHorizontalPadding * 2,
                  ),
                  children: [
                    // Image Picker ... (same)
                    // Image Picker ... (same)
                    // Organization Selection
                    if (_userOrgs.isNotEmpty) ...[
                      DropdownButtonFormField<String?>(
                        initialValue: _selectedOrgId,
                        isExpanded: true, // Fix overflow
                        onTap: () => FocusScope.of(context).unfocus(), // [FIX]
                        decoration: InputDecoration(
                          labelText: 'Publish as',
                          prefixIcon: const Icon(LucideIcons.building2),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.3),
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
                                org['name'] ??
                                    org['businessName'] ??
                                    'Organization',
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
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          image: _imageFile != null
                              ? DecorationImage(
                                  image: kIsWeb
                                      ? NetworkImage(_imageFile!.path)
                                      : FileImage(File(_imageFile!.path))
                                            as ImageProvider,
                                  fit: BoxFit.cover,
                                )
                              : (_existingImageUrl != null
                                    ? DecorationImage(
                                        image: NetworkImage(_existingImageUrl!),
                                        fit: BoxFit.cover,
                                      )
                                    : null),
                        ),
                        child: Stack(
                          children: [
                            if (_imageFile == null && _existingImageUrl == null)
                              Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      LucideIcons.imagePlus,
                                      size: 50,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Upload Event Image',
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Select a beautiful cover photo',
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.outline,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            // Preview Badges
                            if (_imageFile != null ||
                                _existingImageUrl != null) ...[
                              Positioned(
                                top: 12,
                                left: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.surface
                                        .withValues(alpha: 0.8),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _category,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 12,
                                right: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _isPaid
                                        ? Theme.of(context).colorScheme.tertiary
                                        : Theme.of(context).colorScheme.primary,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _isPaid &&
                                            _ticketPriceController
                                                .text
                                                .isNotEmpty
                                        ? '\$${_ticketPriceController.text}'
                                        : 'Free',
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onPrimary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
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
                        fillColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide.none,
                        ),
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
                        fillColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      validator: (v) =>
                          v!.isEmpty ? 'Description is required' : null,
                    ),
                    const SizedBox(height: 16),

                    DropdownButtonFormField<String>(
                      initialValue: _category,
                      onTap: () => FocusScope.of(context).unfocus(), // [FIX]
                      decoration: InputDecoration(
                        labelText: 'Category *',
                        prefixIcon: const Icon(LucideIcons.tag),
                        filled: true,
                        fillColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      items: _categories
                          .map(
                            (c) => DropdownMenuItem(value: c, child: Text(c)),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _category = v!),
                    ),
                    const SizedBox(height: 16),

                    // Date Time Pickers
                    const Text(
                      'Start Date & Time',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              FocusScope.of(context).unfocus(); // [FIX]
                              final d = await showDatePicker(
                                context: context,
                                initialDate: _startDate,
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(
                                  const Duration(days: 30),
                                ),
                              );
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
                            label: Text(
                              DateFormat('MMM d, y').format(_startDate),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              FocusScope.of(context).unfocus(); // [FIX]
                              final t = await showTimePicker(
                                context: context,
                                initialTime: _startTime,
                              );
                              if (t != null) setState(() => _startTime = t);
                            },
                            icon: const Icon(LucideIcons.clock),
                            label: Text(_startTime.format(context)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'End Date & Time',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              FocusScope.of(context).unfocus(); // [FIX]
                              // [FIX] First date is StartDate
                              final d = await showDatePicker(
                                context: context,
                                initialDate: _endDate,
                                firstDate: _startDate,
                                lastDate: DateTime(2030),
                              );
                              if (d != null) setState(() => _endDate = d);
                            },
                            icon: const Icon(LucideIcons.calendar),
                            label: Text(
                              DateFormat('MMM d, y').format(_endDate),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              FocusScope.of(context).unfocus(); // [FIX]
                              final t = await showTimePicker(
                                context: context,
                                initialTime: _endTime,
                              );
                              if (t != null) {
                                // [FIX] Logical check for end time
                                final startDateTime = DateTime(
                                  _startDate.year,
                                  _startDate.month,
                                  _startDate.day,
                                  _startTime.hour,
                                  _startTime.minute,
                                );
                                final endDateTime = DateTime(
                                  _endDate.year,
                                  _endDate.month,
                                  _endDate.day,
                                  t.hour,
                                  t.minute,
                                );

                                if (endDateTime.isBefore(startDateTime)) {
                                  // If selected end time is before start time (e.g. same day), push it forward
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'End time cannot be before start time',
                                        ),
                                      ),
                                    );
                                  }
                                  // Optionally auto-correct
                                  final newEnd = startDateTime.add(
                                    const Duration(minutes: 30),
                                  );
                                  setState(
                                    () => _endTime = TimeOfDay.fromDateTime(
                                      newEnd,
                                    ),
                                  );
                                } else {
                                  setState(() => _endTime = t);
                                }
                              }
                            },
                            icon: const Icon(LucideIcons.clock),
                            label: Text(_endTime.format(context)),
                          ),
                        ),
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
                          labelText: 'Location / Venue (In-Person Only) *',
                          prefixIcon: const Icon(LucideIcons.mapPin),
                          filled: true,
                          fillColor: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: BorderSide.none,
                          ),
                          hintText: 'Search for address or place',
                          helperText:
                              'Enter a physical address. Online events are not supported.',
                        ),
                        onChanged: _onLocationChanged,
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return 'Location is required';
                          }
                          if (v.toLowerCase().contains('online') ||
                              v.toLowerCase().contains('zoom') ||
                              v.toLowerCase().contains('virtual')) {
                            return 'Online/Virtual events are not supported. Please enter a physical location.';
                          }
                          return null;
                        },
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
                        fillColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide.none,
                        ),
                        hintText: 'Leave empty for unlimited',
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
                              FocusScope.of(context).unfocus(); // [FIX]
                              // [FIX] Removed verification check
                              setState(() => _isPaid = !_isPaid);
                            },
                            trailing: Switch(
                              value: _isPaid,
                              onChanged: (v) {
                                // [FIX] Removed verification check
                                setState(() => _isPaid = v);
                              },
                              activeThumbColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                            ),
                          ),
                          if (_isPaid)
                            Padding(
                              padding: const EdgeInsets.all(
                                AppTheme.pageHorizontalPadding * 2,
                              ),
                              child: TextFormField(
                                controller: _ticketPriceController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: InputDecoration(
                                  labelText: 'Ticket Price (\$)',
                                  prefixIcon: const Icon(
                                    LucideIcons.dollarSign,
                                  ),
                                  filled: true,
                                  fillColor: Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(15),
                                    borderSide: BorderSide.none,
                                  ),
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
                        color: _isPublished
                            ? Theme.of(context).colorScheme.primaryContainer
                                  .withValues(alpha: 0.3)
                            : Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isPublished
                              ? Theme.of(context).colorScheme.primary
                              : Colors.transparent,
                        ),
                      ),
                      child: SwitchListTile(
                        title: Text(
                          _isPublished ? 'Published' : 'Hidden (Draft)',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          _isPublished
                              ? 'Visible to everyone'
                              : 'Hidden from everyone except you',
                        ),
                        value: _isPublished,
                        onChanged: (v) {
                          FocusScope.of(context).unfocus(); // [FIX]
                          setState(() => _isPublished = v);
                        },
                        secondary: Icon(
                          _isPublished ? LucideIcons.eye : LucideIcons.eyeOff,
                          color: _isPublished
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Audience
                    const Text(
                      'Audience Visibility',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (_isLoadingAudience)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(8.0),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else
                      GlassContainer(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ), // [FIX] 8px horizontal padding
                        child: Column(
                          children: [
                            // Communities
                            if (widget.communityId != null &&
                                _myCommunities.isNotEmpty)
                              // [NEW] Fixed/Locked Community Display
                              ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                title: Text(
                                  _myCommunities.first.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  'Event will be visible to this community \u2022 ${_myCommunities.first.memberCount} members',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                trailing: Icon(
                                  LucideIcons.checkCircle2,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                leading: CommunityChatUtils.getCommunityAvatar(
                                  context: context,
                                  chat: null,
                                  communityId: _myCommunities.first.id,
                                  type: _myCommunities.first.type,
                                  locationType:
                                      _myCommunities.first.locationType,
                                  profileImage:
                                      _myCommunities.first.profileImage,
                                  homeCountryCode:
                                      _myCommunities.first.homeCountryCode,
                                  hostCountryCode:
                                      _myCommunities.first.hostCountryCode,
                                  flag: _myCommunities.first.flag,
                                  size: 40,
                                ),
                              )
                            else if (widget.eventToEdit != null &&
                                _myCommunities.isNotEmpty)
                              // Locked community display when editing
                              Builder(
                                builder: (context) {
                                  final selected = _myCommunities.firstWhere(
                                    (c) => c.id == _attendingPermission,
                                    orElse: () => _myCommunities.first,
                                  );
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    title: Text(
                                      selected.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: const Text(
                                      'Community cannot be changed after creation',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    trailing: const Icon(
                                      LucideIcons.lock,
                                      color: Colors.grey,
                                      size: 20,
                                    ),
                                    leading:
                                        CommunityChatUtils.getCommunityAvatar(
                                          context: context,
                                          chat: null,
                                          communityId: selected.id,
                                          type: selected.type,
                                          locationType: selected.locationType,
                                          profileImage: selected.profileImage,
                                          homeCountryCode:
                                              selected.homeCountryCode,
                                          hostCountryCode:
                                              selected.hostCountryCode,
                                          flag: selected.flag,
                                          size: 40,
                                        ),
                                  );
                                },
                              )
                            else ...[
                              RadioGroup<String>(
                                groupValue: _attendingPermission,
                                onChanged: (v) {
                                  FocusScope.of(context).unfocus();
                                  setState(() => _attendingPermission = v!);
                                },
                                child: Column(
                                  children: _myCommunities.map((community) {
                                    final isGlobal = community.type == 'global';

                                    return RadioListTile<String>(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 8,
                                          ),
                                      title: Text(
                                        community.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      subtitle: Text(
                                        '${isGlobal ? 'Includes all app members \u2022 ' : ''}${community.memberCount} members',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      value: community.id,
                                      controlAffinity:
                                          ListTileControlAffinity.trailing,
                                      secondary:
                                          CommunityChatUtils.getCommunityAvatar(
                                            context: context,
                                            chat: null,
                                            communityId: community.id,
                                            type: community.type,
                                            locationType:
                                                community.locationType,
                                            profileImage:
                                                community.profileImage,
                                            homeCountryCode:
                                                community.homeCountryCode,
                                            hostCountryCode:
                                                community.hostCountryCode,
                                            flag: community.flag,
                                            size: 40,
                                          ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ],

                            // [NEW] Locked Group Display
                            if (widget.groupId != null && _myGroups.isNotEmpty)
                              ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                title: Text(
                                  _myGroups.first.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: const Text(
                                  'Private event for this group members only',
                                  style: TextStyle(fontSize: 12),
                                ),
                                trailing: Icon(
                                  LucideIcons.checkCircle2,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child:
                                      (_myGroups.first.photoUrl != null &&
                                          _myGroups.first.photoUrl!.isNotEmpty)
                                      ? Image.network(
                                          _myGroups.first.photoUrl!,
                                          width: 40,
                                          height: 40,
                                          fit: BoxFit.cover,
                                        )
                                      : Container(
                                          width: 40,
                                          height: 40,
                                          color: Colors.grey[300],
                                          child: const Icon(LucideIcons.users),
                                        ),
                                ),
                              ),
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
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.of(context).padding.bottom,
              ),
              decoration: BoxDecoration(
                color: AppTheme.cardDecoration(context).color,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _isLoading || !_isFormValid
                    ? null
                    : () {
                        if (widget.communityId != null &&
                            widget.eventToEdit == null) {
                          final communityName =
                              ref
                                  .read(communityProvider(widget.communityId!))
                                  .value
                                  ?.name ??
                              'this community';
                          _showExclusivityDialog(communityName);
                        } else {
                          _submitEvent();
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 0,
                ),
                child: _isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Theme.of(context).colorScheme.onPrimary,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        widget.eventToEdit != null
                            ? 'Update Event'
                            : 'Create Event',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: _placePredictions.length,
                  itemBuilder: (context, index) {
                    final p = _placePredictions[index];
                    return ListTile(
                      title: Text(p.primaryText),
                      subtitle: p.secondaryText.isNotEmpty
                          ? Text(p.secondaryText)
                          : null,
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

  Future<void> _showExclusivityDialog(String communityName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                LucideIcons.shield,
                color: theme.colorScheme.primary,
                size: 22,
              ),
              const SizedBox(width: 8),
              const Expanded(child: Text('Community Exclusive Event')),
            ],
          ),
          content: RichText(
            text: TextSpan(
              style: theme.textTheme.bodyMedium,
              children: [
                const TextSpan(
                  text: 'This event will be exclusively for members of ',
                ),
                TextSpan(
                  text: communityName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const TextSpan(
                  text:
                      '. Only current and future members of this community will be able to discover and attend this event.',
                ),
              ],
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          actions: [
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Create Event'),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      _submitEvent();
    }
  }

  Future<void> _submitEvent() async {
    if (!_formKey.currentState!.validate()) return;

    // Time Validation
    final start = DateTime(
      _startDate.year,
      _startDate.month,
      _startDate.day,
      _startTime.hour,
      _startTime.minute,
    );
    final end = DateTime(
      _endDate.year,
      _endDate.month,
      _endDate.day,
      _endTime.hour,
      _endTime.minute,
    );

    if (end.isBefore(start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('End time must be after start time'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_imageFile == null && _existingImageUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add an event image')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = ref.read(authStateProvider).value;
      final profile = ref.read(userProfileProvider).value;
      if (user == null || profile == null) {
        throw Exception('User not logged in');
      }

      final repo = ref.read(eventRepositoryProvider);

      String? orgName;
      if (_selectedOrgId != null) {
        final org = _userOrgs.firstWhere(
          (o) => o['id'] == _selectedOrgId,
          orElse: () => {'name': null}, // Use name: null or handle gracefully
        );
        orgName = org['name'] ?? org['businessName'];
      }

      final locationText = _locationController.text.trim();
      if (PlusCodeService.isValidPlusCode(locationText)) {
        final decoded = PlusCodeService.decode(locationText);
        if (decoded != null) {
          _latitude = decoded['latitude'];
          _longitude = decoded['longitude'];
          _plusCode = locationText;
        }
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
          location: locationText,
          category: _category,
          attendingPermission: _attendingPermission,
          venueName: _venueName,
          venueAddress: _venueAddress,
          venueCity: _venueCity,
          venueState: _venueState,
          venueCountry: _venueCountry,
          plusCode: _plusCode,
          latitude: _latitude,
          longitude: _longitude,
          status: _isPublished ? 'published' : 'hidden',
          organizationId: _selectedOrgId,
          organizationName: orgName,
        );

        // Directly set nullable fields that copyWith can't clear
        // (copyWith uses ?? which keeps old value when null is passed)
        updatedEvent.isPaid = _isPaid;
        updatedEvent.ticketPrice = _isPaid
            ? double.tryParse(_ticketPriceController.text) ?? 0
            : null;
        updatedEvent.invitedUserIds = _attendingPermission == 'private'
            ? _invitedUserIds
            : null;
        updatedEvent.maxAttendees = _maxAttendeesController.text.isNotEmpty
            ? int.tryParse(_maxAttendeesController.text)
            : null;

        await repo.updateEvent(updatedEvent, _imageFile);
        if (mounted) {
          // Invalidate providers so stale data is refreshed
          ref.invalidate(eventDetailsProvider(updatedEvent.id));
          ref.invalidate(allRawEventsStreamProvider);
          ref.invalidate(userEventsProvider(user.uid));

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Event Updated Successfully!')),
          );
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
          ticketPrice: _isPaid
              ? double.tryParse(_ticketPriceController.text) ?? 0
              : null,

          attendingPermission: _attendingPermission,
          invitedUserIds: _attendingPermission == 'private'
              ? _invitedUserIds
              : null,
          maxAttendees: _maxAttendeesController.text.isNotEmpty
              ? int.tryParse(_maxAttendeesController.text)
              : null,
          homeCountry: profile.homeCountry ?? profile.homeLocation.country,
          hostCountry: profile.hostCountry ?? profile.hostLocation.country,
          hostCity: profile.hostLocation.city,
          hostState: profile.hostLocation.state,
          homeCountryCode:
              profile.homeCountryCode ?? profile.homeLocation.countryCode,
          hostCountryCode:
              profile.hostCountryCode ?? profile.hostLocation.countryCode,
          venueName: _venueName,
          venueAddress: _venueAddress,
          venueCity: _venueCity,
          venueState: _venueState,
          venueCountry: _venueCountry,
          plusCode: _plusCode,
          latitude: _latitude,
          longitude: _longitude,
          status: _isPublished ? 'published' : 'hidden', // [NEW] Use toggle
          createdAt: DateTime.now().toIso8601String(),
          attendees: [user.uid],
          attendeeCount: 1,
          chatId: 'event_$eventId',
          organizationId: _selectedOrgId,
          organizationName: orgName,
        );

        await repo.createEvent(event, _imageFile);
        ref.invalidate(allRawEventsStreamProvider);
        ref.invalidate(userEventsProvider(user.uid));
        ref.invalidate(joinedEventsProvider(user.uid));

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Event Published Successfully!'),
              duration: Duration(seconds: 3),
            ),
          );

          // Navigate to the new event details page
          context.pushReplacement('/events/${event.id}', extra: event);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

// -----------------------------------------------------------------------------
// TAB 2: ATTENDING EVENTS (View)
// -----------------------------------------------------------------------------
class _JoinedEventsList extends ConsumerWidget {
  const _JoinedEventsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).value;
    if (user == null) return const Center(child: CircularProgressIndicator());

    final eventsStream = ref
        .watch(eventRepositoryProvider)
        .getJoinedEvents(user.uid);

    return StreamBuilder<List<Event>>(
      stream: eventsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final events = snapshot.data ?? [];
        if (events.isEmpty) {
          return const Center(
            child: Text('You have not joined any events yet.'),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.only(left: 8, right: 8, top: 8, bottom: 80),
          itemCount: events.length,
          separatorBuilder: (_, _) => const SizedBox(height: 16),
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
              isAttending: true, // Since it's 'Attending Events'
            );
          },
        );
      },
    );
  }
}
