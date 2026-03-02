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

class CreateCarListingScreen extends ConsumerStatefulWidget {
  final PeerListing? existing;

  const CreateCarListingScreen({super.key, this.existing});

  @override
  ConsumerState<CreateCarListingScreen> createState() =>
      _CreateCarListingScreenState();
}

class _CreateCarListingScreenState
    extends ConsumerState<CreateCarListingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleC = TextEditingController();
  final _descC = TextEditingController();
  final _priceC = TextEditingController();
  final _makeC = TextEditingController();
  final _modelC = TextEditingController();
  final _yearC = TextEditingController();
  final _cityC = TextEditingController();
  final _subLocalityC = TextEditingController();
  final _stateC = TextEditingController();
  final _addressC = TextEditingController();

  String _transmission = 'Automatic';
  String _fuelType = 'Petrol';
  String _drivetrain = 'FWD';
  int _seats = 5;
  final List<String> _selectedFeatures = [];
  bool _isSaving = false;

  static const _transmissions = ['Automatic', 'Manual'];
  static const _fuelTypes = ['Petrol', 'Diesel', 'Electric', 'Hybrid'];
  static const _drivetrains = ['FWD', 'RWD', 'AWD', '4WD'];
  static const _allFeatures = [
    'AC',
    'GPS',
    'Bluetooth',
    'USB Charging',
    'Backup Camera',
    'Dashcam',
    'Roof Rack',
    'Child Seat',
    'Spare Tire',
    'First Aid Kit',
    'Toll Pass',
    'Ski Rack',
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
    _makeC.text = l.make ?? '';
    _modelC.text = l.model ?? '';
    _yearC.text = l.year?.toString() ?? '';
    _cityC.text = l.locality ?? l.city ?? '';
    _subLocalityC.text = l.subLocality ?? '';
    _stateC.text = l.state ?? '';
    _addressC.text = l.address ?? '';
    _transmission = l.transmission ?? 'Automatic';
    _fuelType = l.fuelType ?? 'Petrol';
    _drivetrain = l.drivetrain ?? 'FWD';
    _seats = l.seats ?? 5;
    if (l.features != null) _selectedFeatures.addAll(l.features!);
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
    _makeC.dispose();
    _modelC.dispose();
    _yearC.dispose();
    _cityC.dispose();
    _subLocalityC.dispose();
    _stateC.dispose();
    _addressC.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final profile = ref.read(userProfileProvider).valueOrNull;
      final user = ref.read(authRepositoryProvider).currentUser;
      if (user == null || profile == null) throw Exception('Not logged in');

      final repo = ref.read(peerListingRepositoryProvider);

      final listing = PeerListing(
        id: widget.existing?.id ?? '',
        type: 'car',
        ownerId: user.uid,
        ownerName: profile.fullName,
        ownerPhoto: profile.profileImage,
        title: _titleC.text.trim().isNotEmpty
            ? _titleC.text.trim()
            : '${_makeC.text.trim()} ${_modelC.text.trim()}'.trim(),
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
        make: _makeC.text.trim(),
        model: _modelC.text.trim(),
        year: int.tryParse(_yearC.text.trim()),
        transmission: _transmission,
        seats: _seats,
        fuelType: _fuelType,
        drivetrain: _drivetrain,
        features: _selectedFeatures,
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
              content: Text('Car listed!'),
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
        title: Text(isEditing ? 'Edit Car Listing' : 'List Your Car'),
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
            // Make & Model
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _makeC,
                    label: 'Make',
                    hint: 'e.g. Toyota',
                    icon: LucideIcons.car,
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTextField(
                    controller: _modelC,
                    label: 'Model',
                    hint: 'e.g. Corolla',
                    icon: LucideIcons.tag,
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Required' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Year & Price
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _yearC,
                    label: 'Year',
                    hint: 'e.g. 2022',
                    icon: LucideIcons.calendar,
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTextField(
                    controller: _priceC,
                    label: 'Price/Day (USD)',
                    hint: 'e.g. 45',
                    icon: LucideIcons.dollarSign,
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      if (double.tryParse(v) == null) return 'Invalid';
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Title (auto-generated if empty)
            _buildTextField(
              controller: _titleC,
              label: 'Listing Title (optional)',
              hint: 'Auto-generated from Make & Model if empty',
              icon: LucideIcons.type,
            ),
            const SizedBox(height: 14),

            // Description
            _buildTextField(
              controller: _descC,
              label: 'Description',
              hint: 'Describe the car condition, mileage, special features...',
              icon: LucideIcons.alignLeft,
              maxLines: 3,
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
              label: 'Pick-up Address (optional)',
              hint: 'Full street address',
              icon: LucideIcons.home,
            ),
            const SizedBox(height: 20),

            // Transmission
            _sectionLabel(theme, 'Transmission'),
            const SizedBox(height: 8),
            Row(
              children: _transmissions.map((t) {
                final selected = _transmission == t;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(t),
                    selected: selected,
                    onSelected: (_) => setState(() => _transmission = t),
                    selectedColor: AppTheme.accent.withOpacity(0.2),
                    backgroundColor: AppTheme.elevationColor(context, 2),
                    labelStyle: TextStyle(
                      color: selected
                          ? AppTheme.accent
                          : theme.colorScheme.onSurface.withOpacity(0.7),
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13,
                    ),
                    side: BorderSide(
                      color: selected
                          ? AppTheme.accent.withOpacity(0.4)
                          : Colors.transparent,
                    ),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Fuel type
            _sectionLabel(theme, 'Fuel Type'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _fuelTypes.map((f) {
                final selected = _fuelType == f;
                return ChoiceChip(
                  label: Text(f),
                  selected: selected,
                  onSelected: (_) => setState(() => _fuelType = f),
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
            const SizedBox(height: 16),

            // Drivetrain
            _sectionLabel(theme, 'Drivetrain'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _drivetrains.map((d) {
                final selected = _drivetrain == d;
                return ChoiceChip(
                  label: Text(d),
                  selected: selected,
                  onSelected: (_) => setState(() => _drivetrain = d),
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
            const SizedBox(height: 16),

            // Seats stepper
            _sectionLabel(theme, 'Seats'),
            const SizedBox(height: 8),
            _stepper(theme, _seats, 1, 15,
                (v) => setState(() => _seats = v)),
            const SizedBox(height: 20),

            // Features
            _sectionLabel(theme, 'Features'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _allFeatures.map((f) {
                final selected = _selectedFeatures.contains(f);
                return FilterChip(
                  label: Text(f),
                  selected: selected,
                  onSelected: (val) {
                    setState(() {
                      if (val) {
                        _selectedFeatures.add(f);
                      } else {
                        _selectedFeatures.remove(f);
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
                        isEditing ? 'Update Listing' : 'Publish Car Listing',
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
    int value,
    int min,
    int max,
    ValueChanged<int> onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.elevationColor(context, 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _stepperButton(
            icon: LucideIcons.minus,
            onTap: value > min ? () => onChanged(value - 1) : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              '$value',
              style: TextStyle(
                fontSize: 20,
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
    );
  }

  Widget _stepperButton({required IconData icon, VoidCallback? onTap}) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: enabled
              ? AppTheme.accent.withOpacity(0.12)
              : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 16,
          color: enabled
              ? AppTheme.accent
              : Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
        ),
      ),
    );
  }
}
