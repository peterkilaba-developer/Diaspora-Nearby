import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:diaspora_nearby/config/env.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/real_estate/models/real_estate_listing.dart';
import 'package:diaspora_nearby/features/real_estate/services/real_estate_repository.dart';
import 'package:diaspora_nearby/features/real_estate/screens/land_survey_screen.dart';
import 'package:diaspora_nearby/features/real_estate/screens/real_estate_detail_screen.dart';

/// Shared listing form for all real estate categories: Plot, Farm, House.
/// Opens with the category pre-selected based on which card was tapped.
class CreateRealEstateListingScreen extends ConsumerStatefulWidget {
  final String defaultCategory; // 'plot', 'farm', 'house'
  final RealEstateListing? existing; // for editing

  const CreateRealEstateListingScreen({
    super.key,
    required this.defaultCategory,
    this.existing,
  });

  @override
  ConsumerState<CreateRealEstateListingScreen> createState() =>
      _CreateRealEstateListingScreenState();
}

class _CreateRealEstateListingScreenState
    extends ConsumerState<CreateRealEstateListingScreen> {
  final _formKey = GlobalKey<FormState>();

  // Common fields
  late String _category;
  final _titleC = TextEditingController();
  final _descC = TextEditingController();
  final _priceC = TextEditingController();
  final _addressC = TextEditingController();
  final _cityC = TextEditingController();
  final _subLocalityC = TextEditingController();
  final _stateC = TextEditingController();
  final _sizeC = TextEditingController();
  String _sizeUnit = 'm\u00B2';
  String _listingType = 'sale';
  bool _hasTitle = false;
  String? _zoning;

  // Plot-specific
  bool _isFenced = false;
  bool _hasWater = false;
  bool _hasElectricity = false;
  bool _hasRoad = false;
  String? _terrainType;

  // Farm-specific
  final _farmableAreaC = TextEditingController();
  String? _soilType;
  final List<String> _selectedCrops = [];
  bool _hasIrrigation = false;
  bool _hasStorage = false;
  final _workersC = TextEditingController();

  // House-specific
  int _bedrooms = 1;
  int _bathrooms = 1;
  int _floors = 1;
  String? _propertyCondition;
  final _yearBuiltC = TextEditingController();
  final _livingAreaC = TextEditingController();
  String _livingAreaUnit = 'm\u00B2';
  final List<String> _selectedAmenities = [];
  bool _hasGarage = false;
  bool _hasGarden = false;

  // GPS Survey
  LandSurveyResult? _surveyResult;
  String? _surveyCountry;
  String? _surveyCountryCode;
  int _aerialViewMode =
      0; // 0 = Property aerial, 1 = Location map, 2 = Neighborhood aerial

  // Photos
  final List<XFile> _selectedImages = [];
  final List<String> _existingPhotoUrls = []; // for editing
  bool _isUploading = false;
  int _uploadedCount = 0;

  bool _isSaving = false;

  static const _zoningTypes = [
    'Residential',
    'Commercial',
    'Agricultural',
    'Industrial',
    'Mixed',
  ];
  static const _terrainTypes = [
    'Flat',
    'Hilly',
    'Sloped',
    'Waterfront',
    'Forested',
  ];
  static const _soilTypes = [
    'Loam',
    'Clay',
    'Sandy',
    'Silt',
    'Peat',
    'Volcanic',
  ];
  static const _cropTypes = [
    'Maize',
    'Wheat',
    'Rice',
    'Coffee',
    'Tea',
    'Sugarcane',
    'Vegetables',
    'Fruits',
    'Flowers',
    'Livestock',
    'Poultry',
    'Fish',
  ];
  static const _houseConditions = [
    'New Build',
    'Renovated',
    'Good Condition',
    'Needs Work',
    'Shell',
  ];
  static const _houseAmenities = [
    'Wi-Fi',
    'Water Tank',
    'Solar',
    'Borehole',
    'Security',
    'CCTV',
    'Swimming Pool',
    'Gym',
    'Parking',
    'Servant Quarters',
    'Garden',
    'Balcony',
    'Rooftop',
    'Backup Generator',
  ];

  @override
  void initState() {
    super.initState();
    _category = widget.defaultCategory;
    if (widget.existing != null) {
      _prefillFromExisting(widget.existing!);
    } else {
      _prefillFromProfile();
    }
    // Listen to fields that affect auto-generated title
    _sizeC.addListener(_onTitleFieldChanged);
    _cityC.addListener(_onTitleFieldChanged);
    _stateC.addListener(_onTitleFieldChanged);
  }

  void _onTitleFieldChanged() {
    if (_titleC.text.trim().isEmpty) {
      setState(() {}); // Rebuild to update auto-generated title preview
    }
  }

  void _prefillFromExisting(RealEstateListing l) {
    _category = l.category;
    _titleC.text = l.title;
    _descC.text = l.description;
    _priceC.text = l.price.toStringAsFixed(0);
    _addressC.text = l.address ?? '';
    _cityC.text = l.locality ?? l.city ?? '';
    _subLocalityC.text = l.subLocality ?? '';
    _stateC.text = l.state ?? '';
    _sizeC.text = l.size?.toStringAsFixed(0) ?? '';
    _sizeUnit = l.sizeUnit ?? 'acres';
    _listingType = l.listingType ?? 'sale';
    _hasTitle = l.hasTitle ?? false;
    _zoning = l.zoning;
    // Plot
    _isFenced = l.isFenced ?? false;
    _hasWater = l.hasWater ?? false;
    _hasElectricity = l.hasElectricity ?? false;
    _hasRoad = l.hasRoad ?? false;
    _terrainType = l.terrainType;
    // Farm
    _farmableAreaC.text = l.farmableArea?.toStringAsFixed(0) ?? '';
    _soilType = l.soilType;
    if (l.crops != null) _selectedCrops.addAll(l.crops!);
    _hasIrrigation = l.hasIrrigation ?? false;
    _hasStorage = l.hasStorage ?? false;
    _workersC.text = l.workers?.toString() ?? '';
    // House
    _bedrooms = l.bedrooms ?? 1;
    _bathrooms = l.bathrooms ?? 1;
    _floors = l.floors ?? 1;
    _propertyCondition = l.propertyCondition;
    _yearBuiltC.text = l.yearBuilt?.toString() ?? '';
    _livingAreaC.text = l.livingArea?.toStringAsFixed(0) ?? '';
    _livingAreaUnit = l.livingAreaUnit ?? 'sqm';
    if (l.amenities != null) _selectedAmenities.addAll(l.amenities!);
    _hasGarage = l.hasGarage ?? false;
    _hasGarden = l.hasGarden ?? false;
    // Photos
    if (l.photos.isNotEmpty) _existingPhotoUrls.addAll(l.photos);
  }

  void _prefillFromProfile() {
    final profile = ref.read(userProfileProvider).value;
    if (profile == null) return;
    _cityC.text = profile.homeLocation.city ?? '';
    _stateC.text = profile.homeLocation.state ?? '';
  }

  @override
  void dispose() {
    _sizeC.removeListener(_onTitleFieldChanged);
    _cityC.removeListener(_onTitleFieldChanged);
    _stateC.removeListener(_onTitleFieldChanged);
    _titleC.dispose();
    _descC.dispose();
    _priceC.dispose();
    _addressC.dispose();
    _cityC.dispose();
    _subLocalityC.dispose();
    _stateC.dispose();
    _sizeC.dispose();
    _farmableAreaC.dispose();
    _workersC.dispose();
    _yearBuiltC.dispose();
    _livingAreaC.dispose();
    super.dispose();
  }

  /// Auto-generate the listing title based on category and filled fields.
  String _generateTitle() {
    final city = _cityC.text.trim();
    final state = _stateC.text.trim();
    final locationParts = <String>[];
    if (city.isNotEmpty) locationParts.add(city);
    if (state.isNotEmpty) locationParts.add(state);
    final location = locationParts.isNotEmpty ? locationParts.join(', ') : '';

    final typeLabel = _listingType == 'sale'
        ? 'for Sale'
        : _listingType == 'rent'
        ? 'for Rent'
        : 'for Lease';

    switch (_category) {
      case 'house':
        final beds = '$_bedrooms Bed';
        final baths = '$_bathrooms Bath';
        final suffix = location.isNotEmpty ? ' in $location' : '';
        return '$beds, $baths House $typeLabel$suffix';
      case 'farm':
        final sizeText = _sizeC.text.trim();
        final prefix = sizeText.isNotEmpty ? '$sizeText m\u00B2 ' : '';
        final suffix = location.isNotEmpty ? ' in $location' : '';
        return '${prefix}Farm $typeLabel$suffix';
      case 'plot':
      default:
        final sizeText = _sizeC.text.trim();
        final prefix = sizeText.isNotEmpty ? '$sizeText m\u00B2 ' : '';
        final suffix = location.isNotEmpty ? ' in $location' : '';
        return '${prefix}Plot $typeLabel$suffix';
    }
  }

  /// Apply survey results: auto-populate location and size.
  /// All categories use meters (m) with feet (ft) as secondary.
  void _applySurveyResult(LandSurveyResult result) {
    setState(() {
      _surveyResult = result;
      // Auto-populate location fields (read-only)
      _addressC.text = result.address ?? '';
      _cityC.text = result.city ?? '';
      _stateC.text = result.state ?? '';
      _subLocalityC.text = result.subLocality ?? '';
      _surveyCountry = result.country;
      _surveyCountryCode = result.countryCode;
      // Auto-populate size in meters (primary unit)
      _sizeC.text = result.areaSqm.toStringAsFixed(0);
      _sizeUnit = 'm\u00B2';
    });
  }

  // ─── Photo Picking ──────────────────────────────────────────────────

  Future<void> _pickImages() async {
    final maxPhotos = _category == 'house' ? 20 : 10;
    final remaining =
        maxPhotos - _selectedImages.length - _existingPhotoUrls.length;
    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Maximum $maxPhotos photos allowed'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final picker = ImagePicker();
    final images = await picker.pickMultiImage(
      maxWidth: 1280,
      imageQuality: 80,
    );

    if (images.isNotEmpty) {
      setState(() {
        final toAdd = images.take(remaining).toList();
        _selectedImages.addAll(toAdd);
      });
    }
  }

  void _removeNewImage(int index) {
    setState(() => _selectedImages.removeAt(index));
  }

  void _removeExistingImage(int index) {
    setState(() => _existingPhotoUrls.removeAt(index));
  }

  // ─── Save ───────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_surveyResult == null && widget.existing == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('GPS land survey is required before listing'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Validate minimum photos for houses
    if (_category == 'house') {
      final totalPhotos = _existingPhotoUrls.length + _selectedImages.length;
      if (totalPhotos < 10) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please add at least 10 photos ($totalPhotos/10)'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade700,
          ),
        );
        return;
      }
    }

    setState(() {
      _isSaving = true;
      _isUploading = _selectedImages.isNotEmpty;
      _uploadedCount = 0;
    });

    try {
      final profile = ref.read(userProfileProvider).value;
      final user = ref.read(authRepositoryProvider).currentUser;
      if (user == null || profile == null) throw Exception('Not logged in');

      // Upload new images to Firebase Storage
      final newImageUrls = <String>[];
      for (int i = 0; i < _selectedImages.length; i++) {
        final file = File(_selectedImages[i].path);
        final storageRef = FirebaseStorage.instance.ref().child(
          'real_estate/${user.uid}/${DateTime.now().millisecondsSinceEpoch}_$i.jpg',
        );
        await storageRef.putFile(file);
        final url = await storageRef.getDownloadURL();
        newImageUrls.add(url);
        if (mounted) setState(() => _uploadedCount = i + 1);
      }

      setState(() => _isUploading = false);

      // Combine existing + newly uploaded photos
      final allPhotos = [..._existingPhotoUrls, ...newImageUrls];

      final repo = ref.read(realEstateRepositoryProvider);

      final listing = RealEstateListing(
        id: widget.existing?.id ?? '',
        category: _category,
        ownerId: user.uid,
        ownerName: profile.fullName,
        ownerPhoto: profile.profileImage,
        title: _generateTitle(),
        description: _descC.text.trim(),
        photos: allPhotos,
        price: double.tryParse(_priceC.text.trim()) ?? 0,
        city: _cityC.text.trim(),
        country:
            _surveyCountry ?? widget.existing?.country ?? profile.homeCountry,
        countryCode:
            _surveyCountryCode ??
            widget.existing?.countryCode ??
            profile.homeCountryCode,
        address: _addressC.text.trim(),
        locality: _cityC.text.trim(),
        subLocality: _subLocalityC.text.trim(),
        state: _stateC.text.trim(),
        localityLower: _cityC.text.trim().toLowerCase(),
        stateLower: _stateC.text.trim().toLowerCase(),
        lat: _surveyResult?.centerLat ?? widget.existing?.lat,
        lng: _surveyResult?.centerLng ?? widget.existing?.lng,
        // GPS Survey data
        boundaryPoints:
            _surveyResult?.boundaryPoints ?? widget.existing?.boundaryPoints,
        centerLat: _surveyResult?.centerLat ?? widget.existing?.centerLat,
        centerLng: _surveyResult?.centerLng ?? widget.existing?.centerLng,
        calculatedAreaSqm:
            _surveyResult?.areaSqm ?? widget.existing?.calculatedAreaSqm,
        locationVerified:
            _surveyResult != null ||
            (widget.existing?.locationVerified ?? false),
        // Common
        size: double.tryParse(_sizeC.text.trim()),
        sizeUnit: _sizeUnit,
        listingType: _listingType,
        hasTitle: _hasTitle,
        zoning: _zoning,
        // Plot
        isFenced: _category == 'plot' ? _isFenced : null,
        hasWater: _category == 'plot' ? _hasWater : null,
        hasElectricity: _category == 'plot' ? _hasElectricity : null,
        hasRoad: _category == 'plot' ? _hasRoad : null,
        terrainType: _category == 'plot' ? _terrainType : null,
        // Farm
        farmableArea: _category == 'farm'
            ? double.tryParse(_farmableAreaC.text.trim())
            : null,
        soilType: _category == 'farm' ? _soilType : null,
        crops: _category == 'farm' && _selectedCrops.isNotEmpty
            ? _selectedCrops
            : null,
        hasIrrigation: _category == 'farm' ? _hasIrrigation : null,
        hasStorage: _category == 'farm' ? _hasStorage : null,
        workers: _category == 'farm'
            ? int.tryParse(_workersC.text.trim())
            : null,
        // House
        bedrooms: _category == 'house' ? _bedrooms : null,
        bathrooms: _category == 'house' ? _bathrooms : null,
        floors: _category == 'house' ? _floors : null,
        propertyCondition: _category == 'house' ? _propertyCondition : null,
        yearBuilt: _category == 'house'
            ? int.tryParse(_yearBuiltC.text.trim())
            : null,
        livingArea: _category == 'house'
            ? double.tryParse(_livingAreaC.text.trim())
            : null,
        livingAreaUnit: _category == 'house' ? _livingAreaUnit : null,
        amenities: _category == 'house' && _selectedAmenities.isNotEmpty
            ? _selectedAmenities
            : null,
        hasGarage: _category == 'house' ? _hasGarage : null,
        hasGarden: _category == 'house' ? _hasGarden : null,
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
        // Fetch the newly created listing to navigate to its detail page
        final created = await repo.getListing(newId);
        if (mounted) {
          Navigator.pop(context, true); // Pop the create screen
          if (created != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RealEstateDetailScreen(listing: created),
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
          SnackBar(
            content: Text('Error: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isEditing = widget.existing != null;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: Text(
          isEditing ? 'Edit Listing' : 'List Real Estate',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.accent,
                    ),
                  )
                : Text(
                    isEditing ? 'Save' : 'Publish',
                    style: const TextStyle(
                      color: AppTheme.accent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: AppTheme.pageHorizontalPadding,
                right: AppTheme.pageHorizontalPadding,
                top: 8,
                bottom: MediaQuery.of(context).padding.bottom + 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Category selector ──
                  _sectionLabel(theme, 'Category'),
                  const SizedBox(height: 8),
                  _buildCategorySelector(theme, isDark),

                  const SizedBox(height: 20),

                  // ── GPS Land Survey (first, before anything else) ──
                  _sectionLabel(theme, 'Location (GPS Survey)'),
                  const SizedBox(height: 8),
                  if (widget.existing == null) ...[
                    if (_surveyResult == null)
                      _buildSurveyButton(theme, isDark)
                    else
                      _buildSurveyResultCard(theme, isDark),
                  ] else ...[
                    // Edit mode: show new survey result if redone,
                    // otherwise show existing location with redo option
                    if (_surveyResult != null)
                      _buildSurveyResultCard(theme, isDark)
                    else ...[
                      _buildReadOnlyLocationCard(theme, isDark),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final result =
                                await Navigator.push<LandSurveyResult>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const LandSurveyScreen(),
                                  ),
                                );
                            if (result != null) {
                              _applySurveyResult(result);
                            }
                          },
                          icon: const Icon(LucideIcons.rotateCcw, size: 16),
                          label: const Text('Redo GPS Survey'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.accent,
                            side: BorderSide.none,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],

                  const SizedBox(height: 20),

                  // ── Basic info ──
                  _sectionLabel(theme, 'Basic Information'),
                  const SizedBox(height: 8),

                  // Auto-generated title (read-only, no customize)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.elevationColor(context, 1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              LucideIcons.type,
                              size: 14,
                              color: theme.hintColor,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Title (auto-generated)',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.hintColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const Spacer(),
                            Icon(
                              LucideIcons.lock,
                              size: 12,
                              color: theme.hintColor.withValues(alpha: 0.4),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _generateTitle(),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _descC,
                    label: 'Description',
                    hint: 'Describe the property...',
                    icon: LucideIcons.alignLeft,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: _buildTextField(
                          controller: _priceC,
                          label: 'Price',
                          hint: '0',
                          icon: LucideIcons.dollarSign,
                          keyboardType: TextInputType.number,
                          validator: (v) =>
                              v == null || v.trim().isEmpty ? 'Required' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildDropdown(
                          theme: theme,
                          isDark: isDark,
                          label: 'Type',
                          value: _listingType,
                          items: const ['sale', 'rent', 'lease'],
                          labels: const ['Sale', 'Rent', 'Lease'],
                          onChanged: (v) => setState(() => _listingType = v!),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ── Property details ──
                  _sectionLabel(theme, 'Property Details'),
                  const SizedBox(height: 8),

                  // Size row (read-only, auto-populated from GPS survey)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.elevationColor(context, 1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          LucideIcons.maximize2,
                          size: 16,
                          color: theme.hintColor,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Land Size',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.hintColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _sizeC.text.trim().isNotEmpty
                                    ? '${_sizeC.text.trim()} $_sizeUnit'
                                    : 'Auto-calculated from GPS survey',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: _sizeC.text.trim().isNotEmpty
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: _sizeC.text.trim().isNotEmpty
                                      ? theme.colorScheme.onSurface
                                      : theme.hintColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          LucideIcons.lock,
                          size: 14,
                          color: theme.hintColor.withValues(alpha: 0.4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Zoning
                  _buildChipSelector(
                    theme: theme,
                    isDark: isDark,
                    label: 'Zoning',
                    options: _zoningTypes,
                    selected: _zoning,
                    onSelected: (v) =>
                        setState(() => _zoning = _zoning == v ? null : v),
                  ),
                  const SizedBox(height: 12),

                  // Title deed toggle
                  _buildSwitch(
                    theme: theme,
                    label: 'Has Title Deed',
                    icon: LucideIcons.fileCheck,
                    value: _hasTitle,
                    onChanged: (v) => setState(() => _hasTitle = v),
                  ),

                  const SizedBox(height: 20),

                  // ── Category-specific fields ──
                  if (_category == 'plot') _buildPlotFields(theme, isDark),
                  if (_category == 'farm') _buildFarmFields(theme, isDark),
                  if (_category == 'house') _buildHouseFields(theme, isDark),

                  const SizedBox(height: 20),

                  // ── Photos Section ──
                  _buildPhotosSection(theme, isDark),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          // Upload progress overlay
          if (_isUploading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.5),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: AppTheme.elevationColor(context, 3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(
                          color: AppTheme.accent,
                          strokeWidth: 3,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Uploading photos...',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$_uploadedCount / ${_selectedImages.length}',
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Category Selector ────────────────────────────────────────────────
  Widget _buildCategorySelector(ThemeData theme, bool isDark) {
    const categories = [
      ('plot', LucideIcons.map, 'Plot'),
      ('farm', LucideIcons.sprout, 'Farm'),
      ('house', LucideIcons.home, 'House'),
    ];

    return Row(
      children: categories.map((cat) {
        final isSelected = _category == cat.$1;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: cat.$1 != 'house' ? 8 : 0),
            child: GestureDetector(
              onTap: () => setState(() => _category = cat.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.accent.withValues(alpha: isDark ? 0.2 : 0.1)
                      : AppTheme.elevationColor(context, 1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(
                      cat.$2,
                      size: 22,
                      color: isSelected
                          ? AppTheme.accent
                          : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      cat.$3,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: isSelected
                            ? AppTheme.accent
                            : theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ─── Plot Fields ──────────────────────────────────────────────────────
  Widget _buildPlotFields(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(theme, 'Plot Details'),
        const SizedBox(height: 8),
        _buildChipSelector(
          theme: theme,
          isDark: isDark,
          label: 'Terrain',
          options: _terrainTypes,
          selected: _terrainType,
          onSelected: (v) =>
              setState(() => _terrainType = _terrainType == v ? null : v),
        ),
        const SizedBox(height: 12),
        _buildSwitch(
          theme: theme,
          label: 'Fenced',
          icon: LucideIcons.lock,
          value: _isFenced,
          onChanged: (v) => setState(() => _isFenced = v),
        ),
        _buildSwitch(
          theme: theme,
          label: 'Water Access',
          icon: LucideIcons.droplets,
          value: _hasWater,
          onChanged: (v) => setState(() => _hasWater = v),
        ),
        _buildSwitch(
          theme: theme,
          label: 'Electricity',
          icon: LucideIcons.zap,
          value: _hasElectricity,
          onChanged: (v) => setState(() => _hasElectricity = v),
        ),
        _buildSwitch(
          theme: theme,
          label: 'Road Access',
          icon: LucideIcons.navigation,
          value: _hasRoad,
          onChanged: (v) => setState(() => _hasRoad = v),
        ),
      ],
    );
  }

  // ─── Farm Fields ──────────────────────────────────────────────────────
  Widget _buildFarmFields(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(theme, 'Farm Details'),
        const SizedBox(height: 8),
        _buildTextField(
          controller: _farmableAreaC,
          label: 'Farmable Area (m\u00B2)',
          hint: 'Usable farm area in m\u00B2',
          icon: LucideIcons.sprout,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),
        _buildChipSelector(
          theme: theme,
          isDark: isDark,
          label: 'Soil Type',
          options: _soilTypes,
          selected: _soilType,
          onSelected: (v) =>
              setState(() => _soilType = _soilType == v ? null : v),
        ),
        const SizedBox(height: 12),
        _buildMultiChipSelector(
          theme: theme,
          isDark: isDark,
          label: 'Crops / Livestock',
          options: _cropTypes,
          selected: _selectedCrops,
          onToggle: (v) {
            setState(() {
              if (_selectedCrops.contains(v)) {
                _selectedCrops.remove(v);
              } else {
                _selectedCrops.add(v);
              }
            });
          },
        ),
        const SizedBox(height: 12),
        _buildSwitch(
          theme: theme,
          label: 'Irrigation System',
          icon: LucideIcons.droplets,
          value: _hasIrrigation,
          onChanged: (v) => setState(() => _hasIrrigation = v),
        ),
        _buildSwitch(
          theme: theme,
          label: 'Storage Facility',
          icon: LucideIcons.warehouse,
          value: _hasStorage,
          onChanged: (v) => setState(() => _hasStorage = v),
        ),
        const SizedBox(height: 12),
        _buildTextField(
          controller: _workersC,
          label: 'Workers',
          hint: 'Number of workers (optional)',
          icon: LucideIcons.users,
          keyboardType: TextInputType.number,
        ),
      ],
    );
  }

  // ─── House Fields ─────────────────────────────────────────────────────
  Widget _buildHouseFields(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(theme, 'House Details'),
        const SizedBox(height: 8),

        // Bedrooms, bathrooms, floors steppers
        _stepper(
          theme,
          'Bedrooms',
          _bedrooms,
          1,
          20,
          (v) => setState(() => _bedrooms = v),
        ),
        const SizedBox(height: 8),
        _stepper(
          theme,
          'Bathrooms',
          _bathrooms,
          1,
          10,
          (v) => setState(() => _bathrooms = v),
        ),
        const SizedBox(height: 8),
        _stepper(
          theme,
          'Floors',
          _floors,
          1,
          10,
          (v) => setState(() => _floors = v),
        ),
        const SizedBox(height: 12),

        // Living area
        Row(
          children: [
            Expanded(
              flex: 2,
              child: _buildTextField(
                controller: _livingAreaC,
                label: 'Living Area',
                hint: '0',
                icon: LucideIcons.square,
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildDropdown(
                theme: theme,
                isDark: isDark,
                label: 'Unit',
                value: _livingAreaUnit,
                items: const ['m\u00B2', 'ft\u00B2'],
                labels: const ['m\u00B2', 'ft\u00B2'],
                onChanged: (v) => setState(() => _livingAreaUnit = v!),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Year built
        _buildTextField(
          controller: _yearBuiltC,
          label: 'Year Built',
          hint: 'e.g. 2020',
          icon: LucideIcons.calendar,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),

        // Condition
        _buildChipSelector(
          theme: theme,
          isDark: isDark,
          label: 'Condition',
          options: _houseConditions,
          selected: _propertyCondition,
          onSelected: (v) => setState(
            () => _propertyCondition = _propertyCondition == v ? null : v,
          ),
        ),
        const SizedBox(height: 12),

        // Amenities
        _buildMultiChipSelector(
          theme: theme,
          isDark: isDark,
          label: 'Amenities',
          options: _houseAmenities,
          selected: _selectedAmenities,
          onToggle: (v) {
            setState(() {
              if (_selectedAmenities.contains(v)) {
                _selectedAmenities.remove(v);
              } else {
                _selectedAmenities.add(v);
              }
            });
          },
        ),
        const SizedBox(height: 12),

        _buildSwitch(
          theme: theme,
          label: 'Garage',
          icon: LucideIcons.car,
          value: _hasGarage,
          onChanged: (v) => setState(() => _hasGarage = v),
        ),
        _buildSwitch(
          theme: theme,
          label: 'Garden',
          icon: LucideIcons.flower2,
          value: _hasGarden,
          onChanged: (v) => setState(() => _hasGarden = v),
        ),
      ],
    );
  }

  // ─── Photos Section ──────────────────────────────────────────────────

  Widget _buildPhotosSection(ThemeData theme, bool isDark) {
    final maxPhotos = _category == 'house' ? 20 : 10;
    final totalPhotos = _existingPhotoUrls.length + _selectedImages.length;
    final isHouse = _category == 'house';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _sectionLabel(
              theme,
              isHouse ? 'Photos (min 10, max 20)' : 'Photos (optional, max 10)',
            ),
            const Spacer(),
            Text(
              '$totalPhotos / $maxPhotos',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isHouse && totalPhotos < 10
                    ? Colors.red.shade400
                    : AppTheme.accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (totalPhotos > 0) ...[
          SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: totalPhotos + (totalPhotos < maxPhotos ? 1 : 0),
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                // Add button at the end
                if (i == totalPhotos) {
                  return _addPhotoCard(isDark);
                }

                // Existing photo (URL)
                if (i < _existingPhotoUrls.length) {
                  return _photoThumbnail(
                    child: Image.network(
                      _existingPhotoUrls[i],
                      fit: BoxFit.cover,
                      width: 110,
                      height: 110,
                    ),
                    onRemove: () => _removeExistingImage(i),
                  );
                }

                // New photo (local file)
                final fileIndex = i - _existingPhotoUrls.length;
                return _photoThumbnail(
                  child: Image.file(
                    File(_selectedImages[fileIndex].path),
                    fit: BoxFit.cover,
                    width: 110,
                    height: 110,
                  ),
                  onRemove: () => _removeNewImage(fileIndex),
                );
              },
            ),
          ),
        ] else
          _addPhotosBanner(theme, isDark),
      ],
    );
  }

  Widget _addPhotoCard(bool isDark) {
    return GestureDetector(
      onTap: _pickImages,
      child: Container(
        width: 110,
        height: 110,
        decoration: BoxDecoration(
          color: AppTheme.elevationColor(context, 1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.plus, size: 24, color: AppTheme.accent),
            SizedBox(height: 4),
            Text(
              'Add',
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoThumbnail({
    required Widget child,
    required VoidCallback onRemove,
  }) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(width: 110, height: 110, child: child),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.x, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _addPhotosBanner(ThemeData theme, bool isDark) {
    return GestureDetector(
      onTap: _pickImages,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28),
        decoration: BoxDecoration(
          color: AppTheme.elevationColor(context, 1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(
              LucideIcons.camera,
              size: 32,
              color: AppTheme.accent.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 8),
            Text(
              _category == 'house'
                  ? 'Add at least 10 photos'
                  : 'Add photos (optional)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tap to select from gallery',
              style: TextStyle(fontSize: 11, color: theme.hintColor),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Shared Helpers ───────────────────────────────────────────────────

  Widget _sectionLabel(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
        ),
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
      textCapitalization: keyboardType == TextInputType.number
          ? TextCapitalization.none
          : TextCapitalization.sentences,
      validator: validator,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: AppTheme.elevationColor(context, 1),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        isDense: true,
      ),
    );
  }

  Widget _buildDropdown({
    required ThemeData theme,
    required bool isDark,
    required String label,
    required String value,
    required List<String> items,
    required List<String> labels,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.elevationColor(context, 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
          DropdownButton<String>(
            value: value,
            isExpanded: true,
            underline: const SizedBox(),
            style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface),
            dropdownColor: AppTheme.elevationColor(context, 3),
            items: List.generate(
              items.length,
              (i) => DropdownMenuItem(value: items[i], child: Text(labels[i])),
            ),
            onChanged: onChanged,
            isDense: true,
          ),
        ],
      ),
    );
  }

  Widget _buildChipSelector({
    required ThemeData theme,
    required bool isDark,
    required String label,
    required List<String> options,
    required String? selected,
    required ValueChanged<String> onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: options.map((t) {
            final sel = selected == t;
            return GestureDetector(
              onTap: () => onSelected(t),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: sel
                      ? AppTheme.accent.withValues(alpha: isDark ? 0.2 : 0.1)
                      : AppTheme.elevationColor(context, 1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  t,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                    color: sel
                        ? AppTheme.accent
                        : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildMultiChipSelector({
    required ThemeData theme,
    required bool isDark,
    required String label,
    required List<String> options,
    required List<String> selected,
    required ValueChanged<String> onToggle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: options.map((a) {
            final sel = selected.contains(a);
            return GestureDetector(
              onTap: () => onToggle(a),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: sel
                      ? AppTheme.accent.withValues(alpha: isDark ? 0.2 : 0.1)
                      : AppTheme.elevationColor(context, 1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  a,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                    color: sel
                        ? AppTheme.accent
                        : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSwitch({
    required ThemeData theme,
    required String label,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
          Transform.scale(
            scale: 0.8,
            child: Switch.adaptive(
              value: value,
              activeTrackColor: AppTheme.accent,
              thumbColor: WidgetStateProperty.resolveWith(
                (states) =>
                    states.contains(WidgetState.selected) ? Colors.white : null,
              ),
              onChanged: onChanged,
            ),
          ),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.elevationColor(context, 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const Spacer(),
          _stepperButton(
            icon: LucideIcons.minus,
            onTap: value > min ? () => onChanged(value - 1) : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              '$value',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppTheme.elevationColor(context, 2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 14,
          color: onTap != null
              ? AppTheme.accent
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2),
        ),
      ),
    );
  }

  // ─── GPS Survey Widgets ───────────────────────────────────────────

  Widget _buildSurveyButton(ThemeData theme, bool isDark) {
    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push<LandSurveyResult>(
          context,
          MaterialPageRoute(builder: (_) => const LandSurveyScreen()),
        );
        if (result != null && mounted) {
          _applySurveyResult(result);
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.accent.withValues(alpha: 0.1),
              AppTheme.accent.withValues(alpha: 0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                LucideIcons.mapPin,
                color: AppTheme.accent,
                size: 22,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Start GPS Land Survey',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppTheme.accent,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Walk to each corner to mark boundaries and capture location',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: theme.colorScheme.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    LucideIcons.shieldAlert,
                    size: 12,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Required for fraud prevention',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSurveyResultCard(ThemeData theme, bool isDark) {
    final r = _surveyResult!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.elevationColor(context, 1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.checkCircle,
                size: 16,
                color: Colors.green.shade500,
              ),
              const SizedBox(width: 8),
              Text(
                'GPS-Verified Location',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.green.shade500,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () async {
                  final result = await Navigator.push<LandSurveyResult>(
                    context,
                    MaterialPageRoute(builder: (_) => const LandSurveyScreen()),
                  );
                  if (result != null && mounted) {
                    _applySurveyResult(result);
                  }
                },
                child: const Text(
                  'Redo Survey',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _surveyRow(theme, 'Address', _addressC.text),
          if (_subLocalityC.text.isNotEmpty)
            _surveyRow(theme, 'Area', _subLocalityC.text),
          _surveyRow(theme, 'City', _cityC.text),
          _surveyRow(theme, 'State', _stateC.text),
          if (r.country != null) _surveyRow(theme, 'Country', r.country!),

          // Aerial view toggle + satellite map
          const SizedBox(height: 12),
          // View mode toggle
          Row(
            children: [
              _aerialChip(theme, 0, 'Aerial', LucideIcons.satellite),
              const SizedBox(width: 8),
              _aerialChip(theme, 1, 'Map', LucideIcons.map),
              const SizedBox(width: 8),
              _aerialChip(theme, 2, 'Area', LucideIcons.maximize),
            ],
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              final z = _aerialViewMode == 2 ? 15 : 18;
              final url =
                  'https://www.google.com/maps/@${r.centerLat.toStringAsFixed(6)},${r.centerLng.toStringAsFixed(6)},${z}z/data=!3m1!1e1';
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 200,
                width: double.infinity,
                child: Stack(
                  children: [
                    // Zoomable satellite / map image
                    InteractiveViewer(
                      minScale: 1.0,
                      maxScale: 4.0,
                      child: Image.network(
                        _aerialViewMode == 0
                            ? _buildSatelliteUrl(r)
                            : _aerialViewMode == 1
                            ? _buildMapUrl(r)
                            : _buildNeighborhoodUrl(r),
                        width: double.infinity,
                        height: 200,
                        fit: BoxFit.cover,
                        loadingBuilder: (_, child, progress) {
                          if (progress == null) return child;
                          return Container(
                            color: isDark
                                ? Colors.grey.shade900
                                : Colors.grey.shade200,
                            child: const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.accent,
                              ),
                            ),
                          );
                        },
                        errorBuilder: (_, _, _) => Container(
                          color: isDark
                              ? Colors.grey.shade900
                              : Colors.grey.shade200,
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                LucideIcons.satellite,
                                size: 24,
                                color: theme.hintColor,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Satellite image unavailable',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.hintColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Open in Maps hint
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              LucideIcons.satellite,
                              size: 10,
                              color: Colors.white70,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Tap to open in Maps',
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Zoom hint
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              LucideIcons.zoomIn,
                              size: 10,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'Pinch to zoom',
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.white.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const Divider(height: 16),
          // Dual unit area display (m and ft)
          Builder(
            builder: (_) {
              final sqm = r.areaSqm;
              final sqft = (sqm * 10.7639).toStringAsFixed(0);
              final sqmStr = sqm.toStringAsFixed(0);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        LucideIcons.ruler,
                        size: 14,
                        color: Colors.green.shade600,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Area: $sqmStr m\u00B2  ·  $sqft ft\u00B2',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.green.shade600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        LucideIcons.navigation,
                        size: 14,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.4,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${r.boundaryPoints.length} corners',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                LucideIcons.lock,
                size: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
              ),
              const SizedBox(width: 6),
              Text(
                'Location is locked from GPS coordinates',
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _surveyRow(ThemeData theme, String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadOnlyLocationCard(ThemeData theme, bool isDark) {
    final l = widget.existing!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.elevationColor(context, 1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                l.locationVerified == true
                    ? LucideIcons.checkCircle
                    : LucideIcons.mapPin,
                size: 16,
                color: l.locationVerified == true
                    ? Colors.green.shade500
                    : theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 8),
              Text(
                l.locationVerified == true
                    ? 'GPS-Verified Location'
                    : 'Location',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: l.locationVerified == true
                      ? Colors.green.shade500
                      : theme.colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              Icon(
                LucideIcons.lock,
                size: 14,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (l.address != null && l.address!.isNotEmpty)
            _surveyRow(theme, 'Address', l.address!),
          if (l.subLocality != null && l.subLocality!.isNotEmpty)
            _surveyRow(theme, 'Area', l.subLocality!),
          if (l.locality != null && l.locality!.isNotEmpty)
            _surveyRow(theme, 'City', l.locality!),
          if (l.state != null && l.state!.isNotEmpty)
            _surveyRow(theme, 'State', l.state!),
          if (l.country != null && l.country!.isNotEmpty)
            _surveyRow(theme, 'Country', l.country!),
        ],
      ),
    );
  }

  /// Chip for switching between Property / Neighborhood aerial views.
  Widget _aerialChip(ThemeData theme, int mode, String label, IconData icon) {
    final selected = _aerialViewMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _aerialViewMode = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.accent.withValues(alpha: 0.15)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: selected
                  ? AppTheme.accent
                  : theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected
                    ? AppTheme.accent
                    : theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build Google Maps Static API URL for satellite imagery of the property.
  String _buildSatelliteUrl(LandSurveyResult r, {int zoom = 18}) {
    // Create polygon path string
    final pathPoints = r.boundaryPoints
        .map(
          (p) =>
              '${p['lat']!.toStringAsFixed(6)},${p['lng']!.toStringAsFixed(6)}',
        )
        .join('|');
    // Close the polygon by repeating the first point
    final firstPt = r.boundaryPoints.first;
    final closedPath =
        '$pathPoints|${firstPt['lat']!.toStringAsFixed(6)},${firstPt['lng']!.toStringAsFixed(6)}';

    final center =
        '${r.centerLat.toStringAsFixed(6)},${r.centerLng.toStringAsFixed(6)}';

    // Use Google Maps Static API — polygon is drawn server-side
    return 'https://maps.googleapis.com/maps/api/staticmap'
        '?center=$center'
        '&zoom=$zoom'
        '&size=600x400'
        '&scale=2'
        '&maptype=satellite'
        '&path=color:0xFFFF6B35|weight:3|fillcolor:0x40FF6B35|$closedPath'
        '&markers=size:small|color:red|$center'
        '&key=${Env.googleMapsApiKey}';
  }

  /// Build a wider aerial view to show the neighborhood / surroundings.
  String _buildNeighborhoodUrl(LandSurveyResult r) {
    final center =
        '${r.centerLat.toStringAsFixed(6)},${r.centerLng.toStringAsFixed(6)}';
    return 'https://maps.googleapis.com/maps/api/staticmap'
        '?center=$center'
        '&zoom=15'
        '&size=600x400'
        '&scale=2'
        '&maptype=satellite'
        '&markers=color:red|label:P|$center'
        '&key=${Env.googleMapsApiKey}';
  }

  /// Build a road-map style static map URL with boundary polygon overlay.
  String _buildMapUrl(LandSurveyResult r, {int zoom = 16}) {
    final pathPoints = r.boundaryPoints
        .map(
          (p) =>
              '${p['lat']!.toStringAsFixed(6)},${p['lng']!.toStringAsFixed(6)}',
        )
        .join('|');
    final firstPt = r.boundaryPoints.first;
    final closedPath =
        '$pathPoints|${firstPt['lat']!.toStringAsFixed(6)},${firstPt['lng']!.toStringAsFixed(6)}';
    final center =
        '${r.centerLat.toStringAsFixed(6)},${r.centerLng.toStringAsFixed(6)}';

    return 'https://maps.googleapis.com/maps/api/staticmap'
        '?center=$center'
        '&zoom=$zoom'
        '&size=600x400'
        '&scale=2'
        '&maptype=roadmap'
        '&path=color:0xFFFF6B35|weight:3|fillcolor:0x30FF6B35|$closedPath'
        '&markers=size:small|color:red|$center'
        '&key=${Env.googleMapsApiKey}';
  }
}
