import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:diaspora_nearby/features/profile/models/relationship.dart';
import 'package:diaspora_nearby/features/profile/repository/relationship_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/shared/widgets/google_places_autocomplete_field.dart';
import 'package:diaspora_nearby/features/shared/models/google_places_models.dart';
import 'package:diaspora_nearby/features/shared/utils/app_snackbar.dart';
import 'package:lucide_icons/lucide_icons.dart';

class BereavementAnnouncementModal extends ConsumerStatefulWidget {
  final Relationship relationship;

  const BereavementAnnouncementModal({super.key, required this.relationship});

  @override
  ConsumerState<BereavementAnnouncementModal> createState() =>
      _BereavementAnnouncementModalState();
}

class _BereavementAnnouncementModalState
    extends ConsumerState<BereavementAnnouncementModal> {
  final _formKey = GlobalKey<FormState>();

  DateTime? _dateOfPassing;
  String? _placeOfPassingName;
  String? _placeOfPassingId;
  String? _locationOfBodyName;
  String? _locationOfBodyId;
  String? _funeralPlaceName;
  String? _funeralPlaceId;

  DateTime? _funeralDate;
  String _selectedFuneralPlan = 'Domestic';
  final bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final deceasedProfileAsync = ref.watch(
      userProfileByIdProvider(widget.relationship.id),
    );
    final deceasedProfile =
        deceasedProfileAsync.value ??
        ref
            .read(profileRepositoryProvider)
            .getCachedProfile(widget.relationship.id);

    // Auto-populate / Lock Place of Passing logic (with fallback when profile is still loading)
    final lastKnownLocation =
        deceasedProfile?.hostLocation.formattedAddress ?? 'Unknown';
    final lastKnownPlaceId = deceasedProfile?.hostLocation.placeId ?? '';

    if (_placeOfPassingName == null && deceasedProfile != null) {
      _placeOfPassingName = lastKnownLocation;
      _placeOfPassingId = lastKnownPlaceId;
    }

    final deceasedHostCountry =
        deceasedProfile?.hostCountry ?? 'Unknown Host Country';
    final deceasedHomeCountry =
        deceasedProfile?.homeCountry ?? 'Unknown Home Country';
    final isSameCountry = deceasedHostCountry == deceasedHomeCountry;

    final broadcastHostCity = deceasedProfile?.hostLocation.city ?? 'Local';
    final broadcastHomeCountry = deceasedHomeCountry;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.heartCrack, color: Colors.black),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Announce Passing',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Share the sad news about ${widget.relationship.name}. We will notify the community.',
                  style: const TextStyle(color: Colors.grey),
                ),
                const Divider(height: 32),

                // 1. Date of Passing
                _buildDateSelector(
                  context: context,
                  label: 'Date of Passing',
                  date: _dateOfPassing,
                  onTap: () => _selectDate(context, false),
                ),
                const SizedBox(height: 16),

                // 2. Place of Passing (LOCKED to Last Known Location)
                _buildSectionTitle('Place of Passing'),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _placeOfPassingName ?? lastKnownLocation,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Based on last known location',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 3. Location of Body (Autocomplete)
                GooglePlacesAutocompleteField(
                  label: 'Location of Body (Hospital, Mortuary)',
                  filter: PlaceTypeFilter.ESTABLISHMENT,
                  onSelected: (desc, id) {
                    setState(() {
                      _locationOfBodyName = desc;
                      _locationOfBodyId = id;
                    });
                  },
                ),
                const SizedBox(height: 24),

                // 4. Funeral Plan
                _buildSectionTitle('Funeral Plan'),
                RadioGroup<String>(
                  groupValue: _selectedFuneralPlan,
                  onChanged: (v) => setState(() => _selectedFuneralPlan = v!),
                  child: Column(
                    children: [
                      RadioListTile<String>(
                        title: Text(
                          'Domestic ($deceasedHostCountry)',
                          style: const TextStyle(fontSize: 14),
                        ),
                        value: 'Domestic',
                        contentPadding: EdgeInsets.zero,
                      ),
                      if (!isSameCountry)
                        RadioListTile<String>(
                          title: Text(
                            'International ($deceasedHomeCountry)',
                            style: const TextStyle(fontSize: 14),
                          ),
                          value: 'International',
                          contentPadding: EdgeInsets.zero,
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // 5. Date of Funeral
                _buildDateSelector(
                  context: context,
                  label: 'Date of Funeral',
                  date: _funeralDate,
                  onTap: () => _selectDate(context, true),
                  isOptional: true,
                ),
                const SizedBox(height: 16),

                // 6. Place of Funeral (Below Date)
                GooglePlacesAutocompleteField(
                  label: 'Place of Funeral / Service',
                  filter: PlaceTypeFilter.ESTABLISHMENT,
                  onSelected: (desc, id) {
                    setState(() {
                      _funeralPlaceName = desc;
                      _funeralPlaceId = id;
                    });
                  },
                ),

                const SizedBox(height: 24),

                // 7. Broadcast Info
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        LucideIcons.info,
                        size: 20,
                        color: Colors.amber,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Announcement will be broadcast to:\n• $broadcastHostCity Community\n• $broadcastHomeCountry Community',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black87,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Announce Passing'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateSelector({
    required BuildContext context,
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
    bool isOptional = false,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('$label${isOptional ? ' (Optional)' : ''}'),
        InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: theme.cardColor,
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.calendar,
                  size: 20,
                  color: theme.iconTheme.color,
                ),
                const SizedBox(width: 12),
                Text(
                  date == null
                      ? 'Select Date'
                      : DateFormat.yMMMd().format(date),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: date == null
                        ? Colors.grey
                        : theme.textTheme.bodyMedium?.color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
    );
  }

  Future<void> _selectDate(BuildContext context, bool isFuneral) async {
    final firstDate = isFuneral && _dateOfPassing != null
        ? _dateOfPassing!
        : DateTime(2000);
    final initialDate =
        isFuneral &&
            _dateOfPassing != null &&
            DateTime.now().isBefore(_dateOfPassing!)
        ? _dateOfPassing!
        : DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).brightness == Brightness.dark
                ? const ColorScheme.dark(
                    primary: Colors.white,
                    onPrimary: Colors.black,
                    surface: Colors.black,
                    onSurface: Colors.white,
                  )
                : const ColorScheme.light(
                    primary: Colors.black,
                    onPrimary: Colors.white,
                    surface: Colors.white,
                    onSurface: Colors.black,
                  ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isFuneral) {
          if (_dateOfPassing != null && picked.isBefore(_dateOfPassing!)) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Funeral date cannot be before date of passing'),
              ),
            );
            return;
          }
          _funeralDate = picked;
        } else {
          _dateOfPassing = picked;
          if (_funeralDate != null && _funeralDate!.isBefore(picked)) {
            _funeralDate = null;
          }
        }
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_dateOfPassing == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select Date of Passing')),
      );
      return;
    }

    if (_funeralDate != null && _funeralDate!.isBefore(_dateOfPassing!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Funeral date cannot be before date of passing'),
        ),
      );
      return;
    }

    final details = {
      'dateOfPassing': _dateOfPassing!.toIso8601String(),
      'placeOfPassing': {
        'name': _placeOfPassingName,
        'placeId': _placeOfPassingId,
      },
      'locationOfBody': {
        'name': _locationOfBodyName,
        'placeId': _locationOfBodyId,
      },
      'funeralPlan': _selectedFuneralPlan,
      'funeral': {
        'date': _funeralDate?.toIso8601String(),
        'place': _funeralPlaceName,
        'placeId': _funeralPlaceId,
      },
    };

    final repo = ref.read(relationshipRepositoryProvider);

    // [PERF] Close modal and show feedback on frame 0 (0ms)
    if (mounted) {
      Navigator.pop(context);
      AppSnackbar.success(
        context,
        'Bereavement announced and support group created.',
      );
    }

    unawaited(
      repo.announceBereavement(widget.relationship, details).catchError((
        Object e,
      ) {
        debugPrint('Error announcing bereavement: $e');
      }),
    );
  }
}
