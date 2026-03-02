import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/travel/models/peer_listing.dart';
import 'package:diaspora_nearby/features/travel/services/peer_listing_repository.dart';
import 'package:diaspora_nearby/core/data/countries.dart' as country_data;
import 'package:diaspora_nearby/features/travel/screens/peer_listing_detail_screen.dart';

class CreateStayListingScreen extends ConsumerStatefulWidget {
  final PeerListing? existing; // If editing

  const CreateStayListingScreen({super.key, this.existing});

  @override
  ConsumerState<CreateStayListingScreen> createState() =>
      _CreateStayListingScreenState();
}

class _CreateStayListingScreenState
    extends ConsumerState<CreateStayListingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleC = TextEditingController();
  final _descC = TextEditingController();
  final _priceC = TextEditingController();
  final _addressC = TextEditingController();
  final _cityC = TextEditingController();
  final _subLocalityC = TextEditingController();
  final _stateC = TextEditingController();

  String _propertyType = 'Apartment';
  int _beds = 1;
  int _baths = 1;
  int _maxGuests = 2;
  final List<String> _selectedAmenities = [];
  bool _isSaving = false;

  static const _propertyTypes = [
    'Apartment',
    'House',
    'Room',
    'Villa',
    'Studio',
    'Condo',
  ];

  static const _allAmenities = [
    'Wi-Fi',
    'Kitchen',
    'Washer',
    'Dryer',
    'AC',
    'Heating',
    'TV',
    'Pool',
    'Parking',
    'Gym',
    'Workspace',
    'Iron',
    'Hair Dryer',
    'First Aid Kit',
    'Smoke Alarm',
    'Lockbox',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _prefillFromExisting(widget.existing!);
    } else {
      _prefillFromProfile();
    }
  }

  void _prefillFromExisting(PeerListing l) {
    _titleC.text = l.title;
    _descC.text = l.description;
    _priceC.text = l.pricePerUnit.toStringAsFixed(0);
    _addressC.text = l.address ?? '';
    _cityC.text = l.locality ?? l.city ?? '';
    _subLocalityC.text = l.subLocality ?? '';
    _stateC.text = l.state ?? '';
    _propertyType = l.propertyType ?? 'Apartment';
    _beds = l.beds ?? 1;
    _baths = l.baths ?? 1;
    _maxGuests = l.maxGuests ?? 2;
    if (l.amenities != null) _selectedAmenities.addAll(l.amenities!);
  }

  void _prefillFromProfile() {
    final profile = ref.read(userProfileProvider).valueOrNull;
    if (profile == null) return;
    _cityC.text = profile.hostLocation.city ?? '';
    _stateC.text = profile.hostLocation.state ?? '';
  }

  @override
  void dispose() {
    _titleC.dispose();
    _descC.dispose();
    _priceC.dispose();
    _addressC.dispose();
    _cityC.dispose();
    _subLocalityC.dispose();
    _stateC.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final profile = ref.read(userProfileProvider).valueOrNull;
      final user = ref.read(authRepositoryProvider).currentUser;
      if (user == null || profile == null) {
        throw Exception('Not logged in');
      }

      final repo = ref.read(peerListingRepositoryProvider);

      final listing = PeerListing(
        id: widget.existing?.id ?? '',
        type: 'stay',
        ownerId: user.uid,
        ownerName: profile.fullName,
        ownerPhoto: profile.profileImage,
        title: _titleC.text.trim(),
        description: _descC.text.trim(),
        pricePerUnit: double.tryParse(_priceC.text.trim()) ?? 0,
        city: _cityC.text.trim(),
        country: profile.hostCountry,
        countryCode: profile.hostCountryCode,
        address: _addressC.text.trim(),
        locality: _cityC.text.trim(),
        subLocality: _subLocalityC.text.trim(),
        state: _stateC.text.trim(),
        localityLower: _cityC.text.trim().toLowerCase(),
        stateLower: _stateC.text.trim().toLowerCase(),
        propertyType: _propertyType,
        beds: _beds,
        baths: _baths,
        maxGuests: _maxGuests,
        amenities: _selectedAmenities,
      );

      if (widget.existing != null) {
        await repo.updateListing(widget.existing!.id, listing.toJson());
        if (mounted) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Listing updated!'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        final newId = await repo.createListing(listing);
        final created = await repo.getListing(newId);
        if (mounted) {
          Navigator.pop(context, true);
          if (created != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PeerListingDetailScreen(listing: created),
              ),
            );
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Listing created!'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.existing != null;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(isEditing ? 'Edit Stay Listing' : 'List Your Stay'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.only(
            left: 8, right: 8, top: 8,
            bottom: MediaQuery.of(context).padding.bottom + 16,
          ),
          children: [
            // Property type
            _sectionLabel(theme, 'Property Type'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _propertyTypes.map((t) {
                final selected = _propertyType == t;
                return ChoiceChip(
                  label: Text(t),
                  selected: selected,
                  onSelected: (_) => setState(() => _propertyType = t),
                  selectedColor: AppTheme.accent.withOpacity(0.2),
                  backgroundColor: AppTheme.elevationColor(context, 2),
                  labelStyle: TextStyle(
                    color: selected
                        ? AppTheme.accent
                        : theme.colorScheme.onSurface.withOpacity(0.7),
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 13,
                  ),
                  side: BorderSide(
                    color: selected
                        ? AppTheme.accent.withOpacity(0.4)
                        : Colors.transparent,
                  ),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Title
            _buildTextField(
              controller: _titleC,
              label: 'Listing Title',
              hint: 'e.g. Cozy 2BR Apartment near Downtown',
              icon: LucideIcons.type,
              validator: (v) =>
                  v == null || v.isEmpty ? 'Title is required' : null,
            ),
            const SizedBox(height: 14),

            // Description
            _buildTextField(
              controller: _descC,
              label: 'Description',
              hint: 'Describe your space, neighborhood, and what makes it special...',
              icon: LucideIcons.alignLeft,
              maxLines: 4,
              validator: (v) =>
                  v == null || v.isEmpty ? 'Description is required' : null,
            ),
            const SizedBox(height: 14),

            // Price
            _buildTextField(
              controller: _priceC,
              label: 'Price per Night (USD)',
              hint: 'e.g. 85',
              icon: LucideIcons.dollarSign,
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.isEmpty) return 'Price is required';
                if (double.tryParse(v) == null) return 'Enter a valid number';
                return null;
              },
            ),
            const SizedBox(height: 14),

            // Location section
            _sectionLabel(theme, 'Location'),
            const SizedBox(height: 8),
            _buildTextField(
              controller: _cityC,
              label: 'City',
              hint: 'e.g. Houston',
              icon: LucideIcons.mapPin,
            ),
            const SizedBox(height: 12),
            Builder(
              builder: (context) {
                final profile = ref.read(userProfileProvider).valueOrNull;
                final cc = profile?.hostCountryCode ?? '';
                final hasState = country_data.hasStateLevelHierarchyFromData(cc);
                final stateTerm = country_data.getStateTerminology(cc);

                if (hasState) {
                  return Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          controller: _subLocalityC,
                          label: 'Neighborhood / Area',
                          hint: 'e.g. Midtown',
                          icon: LucideIcons.navigation,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          controller: _stateC,
                          label: stateTerm,
                          hint: 'e.g. Texas',
                          icon: LucideIcons.map,
                        ),
                      ),
                    ],
                  );
                } else {
                  return _buildTextField(
                    controller: _subLocalityC,
                    label: 'Neighborhood / Area',
                    hint: 'e.g. Midtown',
                    icon: LucideIcons.navigation,
                  );
                }
              },
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _addressC,
              label: 'Street Address (optional)',
              hint: 'Full street address',
              icon: LucideIcons.home,
            ),
            const SizedBox(height: 20),

            // Beds, Baths, Guests steppers
            _sectionLabel(theme, 'Capacity'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _stepper(theme, 'Beds', _beds, 1, 20, (v) => setState(() => _beds = v))),
                const SizedBox(width: 10),
                Expanded(child: _stepper(theme, 'Baths', _baths, 1, 10, (v) => setState(() => _baths = v))),
                const SizedBox(width: 10),
                Expanded(child: _stepper(theme, 'Guests', _maxGuests, 1, 30, (v) => setState(() => _maxGuests = v))),
              ],
            ),
            const SizedBox(height: 20),

            // Amenities
            _sectionLabel(theme, 'Amenities'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _allAmenities.map((a) {
                final selected = _selectedAmenities.contains(a);
                return FilterChip(
                  label: Text(a),
                  selected: selected,
                  onSelected: (val) {
                    setState(() {
                      if (val) {
                        _selectedAmenities.add(a);
                      } else {
                        _selectedAmenities.remove(a);
                      }
                    });
                  },
                  selectedColor: AppTheme.accent.withOpacity(0.15),
                  backgroundColor: AppTheme.elevationColor(context, 2),
                  checkmarkColor: AppTheme.accent,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    color: selected
                        ? AppTheme.accent
                        : theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  side: BorderSide(
                    color: selected
                        ? AppTheme.accent.withOpacity(0.3)
                        : Colors.transparent,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 32),

            // Save button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        isEditing ? 'Update Listing' : 'Publish Listing',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(ThemeData theme, String text) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppTheme.accent,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 18),
        filled: true,
        fillColor: AppTheme.elevationColor(context, 2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _stepper(
    ThemeData theme,
    String label,
    int value,
    int min,
    int max,
    ValueChanged<int> onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: AppTheme.elevationColor(context, 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _stepperButton(
                icon: LucideIcons.minus,
                onTap: value > min ? () => onChanged(value - 1) : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '$value',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              _stepperButton(
                icon: LucideIcons.plus,
                onTap: value < max ? () => onChanged(value + 1) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepperButton({required IconData icon, VoidCallback? onTap}) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: enabled
              ? AppTheme.accent.withOpacity(0.12)
              : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 14,
          color: enabled
              ? AppTheme.accent
              : Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
        ),
      ),
    );
  }
}
