import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/marketplace/models/marketplace_listing.dart';
import 'package:diaspora_nearby/features/marketplace/repository/marketplace_repository.dart';
import 'package:diaspora_nearby/features/marketplace/screens/marketplace_screen.dart'
    show categoryIcon;
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:diaspora_nearby/features/marketplace/data/vehicle_data.dart';
import 'package:diaspora_nearby/features/marketplace/data/motorcycle_data.dart';
import 'package:diaspora_nearby/features/marketplace/services/vin_decoder_service.dart';
import 'package:diaspora_nearby/features/travel/widgets/vin_scanner_widget.dart';
import 'package:diaspora_nearby/features/marketplace/data/electronics_data.dart';
import 'package:diaspora_nearby/core/services/google_places_service.dart';
import 'package:diaspora_nearby/features/shared/models/google_places_models.dart';
import 'package:diaspora_nearby/core/utils/location_utils.dart';
import 'package:diaspora_nearby/features/marketplace/utils/currency_helper.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/features/marketplace/screens/listing_detail_screen.dart';
import 'package:diaspora_nearby/features/trust/services/trust_service.dart';

class CreateListingScreen extends ConsumerStatefulWidget {
  final MarketplaceListing? existingListing;
  final String? defaultListingType;

  const CreateListingScreen({
    super.key,
    this.existingListing,
    this.defaultListingType,
  });

  @override
  ConsumerState<CreateListingScreen> createState() =>
      _CreateListingScreenState();
}

class _CreateListingScreenState extends ConsumerState<CreateListingScreen> {
  final _formKey = GlobalKey<FormState>();
  int _currentStep = 0;
  bool _isSubmitting = false;
  bool get _isEditing => widget.existingListing != null;

  // Step 1 — Type & Category
  late String _listingType;
  String? _selectedCategory;
  String? _selectedSubcategory;
  String _scope = ListingScope.local;

  // Step 2 — Details
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  bool _priceNegotiable = false;
  String? _condition;

  // Contextual fields — Cars
  String? _vehicleMake;
  String? _vehicleModel;
  String? _vehicleYear;
  final _vehicleMileageController = TextEditingController();
  final _vehicleVinController = TextEditingController();
  String? _vehicleTransmission;
  String? _vehicleFuelType;
  String? _vehicleBodyType;
  String? _vehicleDriveType;
  String? _vehicleEngineSize; // e.g. "2.5L 4-cyl"
  String? _vehicleHP; // e.g. "203"
  String? _vehicleEngineLabel; // compact e.g. "1.5L I4"
  String? _vehicleDoors; // e.g. "4"
  String? _vehiclePlantCountry; // e.g. "JAPAN"
  String? _vehiclePlantCity;
  String? _vehicleTrim;
  String? _vehicleSeries;
  String? _vehicleAbs;
  String? _vehicleAirbagLocations;
  String? _vehicleGvwr;
  String? _vehicleType;
  String? _vehicleElectrificationType;
  String? _vehicleBatteryKWh;
  bool _vinLookupLoading = false;

  // Contextual fields — Motorcycles
  String? _motorcycleMake;
  String? _motorcycleModel;
  String? _motorcycleYear;
  final _motorcycleMileageController = TextEditingController();
  String? _motorcycleEngineSize;
  String? _motorcycleType;

  // Contextual fields — Car Parts
  final _partNumberController = TextEditingController();
  final _partVinController = TextEditingController();
  String? _partCarMake;
  String? _partCarModel;
  String? _partCarYear;
  List<String> _compatibleModels = [];

  // Contextual fields — Real Estate
  String? _realEstateBedrooms;
  String? _realEstateBathrooms;
  final _realEstateSqftController = TextEditingController();
  String? _realEstateType; // 'sale', 'rent'
  String? _realEstateLocationDisplay; // Display text for selected location
  String? _realEstateLocationPlaceId; // Google Place ID

  // Contextual fields — Electronics
  String? _electronicsBrand;
  String? _electronicsModel;
  String? _electronicsStorage;

  // Contextual fields — Services
  String? _serviceExperience;
  String? _serviceAvailability;
  String? _serviceAreaDisplay; // Display text for selected location
  String? _serviceAreaPlaceId; // Google Place ID

  // Contextual fields — Jobs
  final _jobCompanyController = TextEditingController();
  String? _jobEmploymentType;
  final _jobSalaryController = TextEditingController();
  String? _jobExperienceLevel;
  String? _jobWorkMode;
  DateTime? _jobDeadline;

  // Step 3 — Images & Contact
  final List<XFile> _selectedImages = [];
  final List<String> _deliveryOptions = ['pickup'];
  String _contactMethod = ContactMethod.chat;
  final _tagsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _listingType = widget.defaultListingType ?? ListingType.product;
    _vehicleVinController.addListener(() => setState(() {}));
    _prefillIfEditing();
  }

  void _prefillIfEditing() {
    final listing = widget.existingListing;
    if (listing == null) return;

    _listingType = listing.listingType;
    _selectedCategory = listing.category;
    _selectedSubcategory = listing.subcategory;
    _scope = listing.scope;
    _titleController.text = listing.title;
    _descriptionController.text = listing.description;
    _priceController.text = listing.priceAmount.toStringAsFixed(
      listing.priceAmount == listing.priceAmount.roundToDouble() ? 0 : 2,
    );
    _priceNegotiable = listing.priceNegotiable;
    _condition = listing.condition;
    _contactMethod = listing.contactMethod;

    // Vehicle details
    if (listing.vehicleDetails != null) {
      _vehicleMake = listing.vehicleDetails!['make'] as String?;
      _vehicleModel = listing.vehicleDetails!['model'] as String?;
      _vehicleYear = listing.vehicleDetails!['year'] as String?;
      _vehicleMileageController.text =
          listing.vehicleDetails!['mileage']?.toString() ?? '';
      _vehicleVinController.text =
          listing.vehicleDetails!['vin']?.toString() ?? '';
      _vehicleTransmission = listing.vehicleDetails!['transmission'] as String?;
      _vehicleFuelType = listing.vehicleDetails!['fuelType'] as String?;
      _vehicleBodyType = listing.vehicleDetails!['bodyType'] as String?;
      _vehicleDriveType = listing.vehicleDetails!['driveType'] as String?;
      _vehicleEngineSize = listing.vehicleDetails!['engineSize'] as String?;
      _vehicleHP = listing.vehicleDetails!['horsepower'] as String?;
      _vehicleEngineLabel = listing.vehicleDetails!['engineLabel'] as String?;
      _vehicleDoors = listing.vehicleDetails!['doors'] as String?;
      _vehiclePlantCountry = listing.vehicleDetails!['plantCountry'] as String?;
      _vehiclePlantCity = listing.vehicleDetails!['plantCity'] as String?;
      _vehicleTrim = listing.vehicleDetails!['trim'] as String?;
      _vehicleSeries = listing.vehicleDetails!['series'] as String?;
      _vehicleAbs = listing.vehicleDetails!['abs'] as String?;
      _vehicleAirbagLocations =
          listing.vehicleDetails!['airbagLocations'] as String?;
      _vehicleGvwr = listing.vehicleDetails!['gvwr'] as String?;
      _vehicleType = listing.vehicleDetails!['vehicleType'] as String?;
      _vehicleElectrificationType =
          listing.vehicleDetails!['electrificationType'] as String?;
      _vehicleBatteryKWh = listing.vehicleDetails!['batteryKWh'] as String?;
    }

    // Car parts details
    if (listing.carPartsDetails != null) {
      _partNumberController.text =
          listing.carPartsDetails!['partNumber']?.toString() ?? '';
      _partVinController.text =
          listing.carPartsDetails!['vin']?.toString() ?? '';
      _partCarMake = listing.carPartsDetails!['carMake'] as String?;
      _partCarModel = listing.carPartsDetails!['carModel'] as String?;
      _partCarYear = listing.carPartsDetails!['carYear'] as String?;
      final compat = listing.carPartsDetails!['compatibleModels'];
      if (compat is List) {
        _compatibleModels = compat.cast<String>().toList();
      }
    }

    // Real estate details
    if (listing.realEstateDetails != null) {
      _realEstateBedrooms = listing.realEstateDetails!['bedrooms'] as String?;
      _realEstateBathrooms = listing.realEstateDetails!['bathrooms'] as String?;
      _realEstateSqftController.text =
          listing.realEstateDetails!['sqft']?.toString() ?? '';
      _realEstateType = listing.realEstateDetails!['type'] as String?;
      _realEstateLocationDisplay =
          listing.realEstateDetails!['propertyAddress'] as String?;
      _realEstateLocationPlaceId =
          listing.realEstateDetails!['propertyPlaceId'] as String?;
    }

    // Electronics details
    if (listing.electronicsDetails != null) {
      _electronicsBrand = listing.electronicsDetails!['brand'] as String?;
      _electronicsModel = listing.electronicsDetails!['model'] as String?;
      _electronicsStorage = listing.electronicsDetails!['storage'] as String?;
    }

    // Service details
    if (listing.serviceDetails != null) {
      _serviceExperience = listing.serviceDetails!['experience'] as String?;
      _serviceAvailability = listing.serviceDetails!['availability'] as String?;
      _serviceAreaDisplay = listing.serviceDetails!['serviceArea'] as String?;
      _serviceAreaPlaceId =
          listing.serviceDetails!['serviceAreaPlaceId'] as String?;
    }

    // Job details
    if (listing.jobDetails != null) {
      _jobCompanyController.text =
          listing.jobDetails!['companyName']?.toString() ?? '';
      _jobEmploymentType = listing.jobDetails!['employmentType'] as String?;
      _jobSalaryController.text =
          listing.jobDetails!['salaryRange']?.toString() ?? '';
      _jobExperienceLevel = listing.jobDetails!['experienceLevel'] as String?;
      _jobWorkMode = listing.jobDetails!['workMode'] as String?;
      final deadlineStr = listing.jobDetails!['applicationDeadline'] as String?;
      if (deadlineStr != null && deadlineStr.isNotEmpty) {
        _jobDeadline = DateTime.tryParse(deadlineStr);
      }
    }

    // Tags
    if (listing.tags != null && listing.tags!.isNotEmpty) {
      _tagsController.text = listing.tags!.join(', ');
    }

    // Delivery options
    if (listing.deliveryOptions != null) {
      _deliveryOptions
        ..clear()
        ..addAll(listing.deliveryOptions!);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _vehicleMileageController.dispose();
    _vehicleVinController.dispose();
    _motorcycleMileageController.dispose();
    _partNumberController.dispose();
    _partVinController.dispose();

    _realEstateSqftController.dispose();
    _jobCompanyController.dispose();
    _jobSalaryController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // [COMMENTED] Gate: must be a verified business — re-add later
    // if (profile?.businessProfile?.isBusinessVerified != true) {
    //   return Scaffold(
    //     appBar: AppBar(
    //       title: const Text('Create Listing'),
    //       elevation: 0,
    //       backgroundColor: Colors.transparent,
    //     ),
    //     body: Center(
    //       child: Padding(
    //         padding: const EdgeInsets.all(32),
    //         child: Column(
    //           mainAxisAlignment: MainAxisAlignment.center,
    //           children: [
    //             Icon(LucideIcons.store, size: 48, color: theme.hintColor),
    //             const SizedBox(height: 16),
    //             Text('Business Account Required', ...),
    //             const SizedBox(height: 8),
    //             Text('Register and verify your business profile ...'),
    //             const SizedBox(height: 24),
    //             ElevatedButton.icon(
    //               onPressed: () => context.push('/profile'),
    //               icon: const Icon(LucideIcons.userPlus, size: 16),
    //               label: const Text('Go to Profile'),
    //             ),
    //           ],
    //         ),
    //       ),
    //     ),
    //   );
    // }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _stepTitle(),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                'Step ${_currentStep + 1} of 3',
                style: TextStyle(fontSize: 12, color: theme.hintColor),
              ),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            // Progress bar
            LinearProgressIndicator(
              value: (_currentStep + 1) / 3,
              backgroundColor: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.04),
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accent),
              minHeight: 3,
            ),

            // Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: _currentStep == 0
                    ? _buildStep1TypeCategory(theme, isDark)
                    : _currentStep == 1
                    ? _buildStep2Details(theme, isDark)
                    : _buildStep3ImagesContact(theme, isDark),
              ),
            ),

            // Bottom bar
            _buildBottomBar(theme, isDark),
          ],
        ),
      ),
    );
  }

  String _stepTitle() {
    switch (_currentStep) {
      case 0:
        return _listingType == ListingType.job
            ? 'Post a Job'
            : 'What are you listing?';
      case 1:
        return _listingType == ListingType.job
            ? 'Job Details'
            : _listingType == ListingType.service
            ? 'Service Details'
            : 'Listing Details';
      case 2:
        return _listingType == ListingType.job
            ? 'Images & Contact'
            : 'Photos & Contact';
      default:
        return _isEditing ? 'Edit Listing' : 'Create Listing';
    }
  }

  // ─── STEP 1: Type & Category ──────────────────────────────────────────
  Widget _buildStep1TypeCategory(ThemeData theme, bool isDark) {
    final categories = _listingType == ListingType.service
        ? MarketplaceCategory.serviceCategories
        : _listingType == ListingType.job
        ? MarketplaceCategory.jobCategories
        : MarketplaceCategory.productCategories;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Product vs Service toggle
        _buildSectionLabel('Type', theme),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildToggleOption(
                icon: LucideIcons.package,
                label: 'Product',
                isSelected: _listingType == ListingType.product,
                onTap: () => setState(() {
                  _listingType = ListingType.product;
                  _selectedCategory = null;
                  _selectedSubcategory = null;
                }),
                theme: theme,
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildToggleOption(
                icon: LucideIcons.wrench,
                label: 'Service',
                isSelected: _listingType == ListingType.service,
                onTap: () => setState(() {
                  _listingType = ListingType.service;
                  _selectedCategory = null;
                  _selectedSubcategory = null;
                  _condition = null;
                }),
                theme: theme,
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildToggleOption(
                icon: LucideIcons.briefcase,
                label: 'Job',
                isSelected: _listingType == ListingType.job,
                onTap: () => setState(() {
                  _listingType = ListingType.job;
                  _selectedCategory = null;
                  _selectedSubcategory = null;
                  _condition = null;
                }),
                theme: theme,
                isDark: isDark,
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // Category grid
        _buildSectionLabel('Category', theme),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 1.1,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final cat = categories[index];
            final isSelected = _selectedCategory == cat;
            return GestureDetector(
              onTap: () => setState(() {
                _selectedCategory = cat;
                _selectedSubcategory = null;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.accent.withValues(alpha: isDark ? 0.2 : 0.1)
                      : isDark
                      ? Colors.white.withValues(alpha: 0.03)
                      : Colors.black.withValues(alpha: 0.02),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      categoryIcon(cat),
                      size: 24,
                      color: isSelected
                          ? AppTheme.accent
                          : theme.colorScheme.onSurface.withValues(alpha: 0.35),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      MarketplaceCategory.displayName(cat),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: isSelected
                            ? AppTheme.accent
                            : theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            );
          },
        ),

        // Subcategory
        if (_selectedCategory != null) ...[
          const SizedBox(height: 20),
          _buildSectionLabel('Subcategory', theme),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: MarketplaceCategory.subcategories(_selectedCategory!).map(
              (sub) {
                final isSelected = _selectedSubcategory == sub;
                return GestureDetector(
                  onTap: () => setState(() => _selectedSubcategory = sub),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.accent.withValues(
                              alpha: isDark ? 0.25 : 0.12,
                            )
                          : isDark
                          ? Colors.white.withValues(alpha: 0.04)
                          : Colors.black.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      sub,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: isSelected
                            ? AppTheme.accent
                            : theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                      ),
                    ),
                  ),
                );
              },
            ).toList(),
          ),
        ],

        // Scope
        const SizedBox(height: 24),
        _buildSectionLabel(
          _listingType == ListingType.job
              ? 'Where is this job?'
              : _listingType == ListingType.service
              ? 'Where do you provide this service?'
              : 'Where are you selling?',
          theme,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildToggleOption(
                icon: LucideIcons.mapPin,
                label: 'Local',
                subtitle: 'In your host country',
                isSelected: _scope == ListingScope.local,
                onTap: () => setState(() => _scope = ListingScope.local),
                theme: theme,
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildToggleOption(
                icon: LucideIcons.globe,
                label: 'International',
                subtitle: 'Cross-border',
                isSelected: _scope == ListingScope.international,
                onTap: () =>
                    setState(() => _scope = ListingScope.international),
                theme: theme,
                isDark: isDark,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─── STEP 2: Details (Contextual) ─────────────────────────────────────
  Widget _buildStep2Details(ThemeData theme, bool isDark) {
    final profile = ref.watch(userProfileProvider).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── CONTEXTUAL FIELDS AT TOP (they generate the title) ────
        _buildContextualFields(theme, isDark),

        // Auto-generated title preview
        if (_generateTitle().isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: isDark ? 0.08 : 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Listing Title',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.accent,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _generateTitle(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 20),

        // Description
        _buildSectionLabel(
          _listingType == ListingType.job
              ? 'Job Description'
              : _listingType == ListingType.service
              ? 'Service Description'
              : 'Item Description',
          theme,
        ),
        const SizedBox(height: 8),
        _buildTextField(
          controller: _descriptionController,
          hint: _listingType == ListingType.job
              ? 'Describe the role, responsibilities, and requirements...'
              : _listingType == ListingType.service
              ? 'Describe your service, what you offer, and how it works...'
              : 'Describe your item in detail...',
          maxLines: 4,
          maxLength: 2000,
          theme: theme,
          isDark: isDark,
        ),

        const SizedBox(height: 20),

        // Price / Salary / Rate
        _buildSectionLabel(
          _listingType == ListingType.job
              ? 'Salary (${CurrencyHelper.currencyCode(profile?.hostCountryCode)})'
              : _listingType == ListingType.service
              ? 'Rate (${CurrencyHelper.currencyCode(profile?.hostCountryCode)})'
              : 'Price (${CurrencyHelper.currencyCode(profile?.hostCountryCode)})',
          theme,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                controller: _priceController,
                hint: '0',
                keyboardType: TextInputType.number,
                theme: theme,
                isDark: isDark,
                prefix: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    CurrencyHelper.currencySymbol(profile?.hostCountryCode),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: theme.hintColor,
                    ),
                  ),
                ),
                validator: (v) {
                  final label = _listingType == ListingType.job
                      ? 'Salary'
                      : _listingType == ListingType.service
                      ? 'Rate'
                      : 'Price';
                  if (v == null || v.isEmpty) return '$label is required';
                  if (double.tryParse(v) == null) return 'Invalid amount';
                  return null;
                },
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () => setState(() => _priceNegotiable = !_priceNegotiable),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: _priceNegotiable
                      ? AppTheme.accent.withValues(alpha: isDark ? 0.2 : 0.1)
                      : isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.tag,
                      size: 12,
                      color: _priceNegotiable
                          ? AppTheme.accent
                          : theme.hintColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Negotiable',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: _priceNegotiable
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: _priceNegotiable
                            ? AppTheme.accent
                            : theme.hintColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),

        // Condition (Products only)
        if (_listingType == ListingType.product) ...[
          const SizedBox(height: 20),
          _buildSectionLabel('Condition', theme),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                [
                  ItemCondition.brandNew,
                  ItemCondition.likeNew,
                  ItemCondition.usedGood,
                  ItemCondition.usedFair,
                ].map((c) {
                  final isSelected = _condition == c;
                  return GestureDetector(
                    onTap: () => setState(() => _condition = c),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.accent.withValues(
                                alpha: isDark ? 0.2 : 0.1,
                              )
                            : isDark
                            ? Colors.white.withValues(alpha: 0.04)
                            : Colors.black.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        ItemCondition.displayName(c),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: isSelected
                              ? AppTheme.accent
                              : theme.colorScheme.onSurface.withValues(
                                  alpha: 0.6,
                                ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
          ),
        ],
      ],
    );
  }

  /// Contextual fields based on category
  Widget _buildContextualFields(ThemeData theme, bool isDark) {
    switch (_selectedCategory) {
      case MarketplaceCategory.vehicles:
        return _buildVehicleFields(theme, isDark);
      case MarketplaceCategory.motorcycles:
        return _buildMotorcycleFields(theme, isDark);
      case MarketplaceCategory.carParts:
        return _buildCarPartsFields(theme, isDark);
      case MarketplaceCategory.realEstate:
        return _buildRealEstateFields(theme, isDark);
      case MarketplaceCategory.electronics:
        return _buildElectronicsFields(theme, isDark);
      default:
        if (_listingType == ListingType.service) {
          return _buildServiceFields(theme, isDark);
        }
        if (_listingType == ListingType.job) {
          return _buildJobFields(theme, isDark);
        }
        // For fashion, food, other — show manual title field
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionLabel('Listing Title', theme),
            const SizedBox(height: 8),
            _buildTextField(
              controller: _titleController,
              hint: 'Give your listing a title',
              maxLength: 120,
              theme: theme,
              isDark: isDark,
              validator: (v) =>
                  v == null || v.isEmpty ? 'Title is required' : null,
            ),
          ],
        );
    }
  }

  // ── Vehicle-specific fields ─────────────────────────────────────────
  Widget _buildVehicleFields(ThemeData theme, bool isDark) {
    // Build model list: static data + VIN-decoded model if not already present
    var models = _vehicleMake != null
        ? VehicleData.getModels(_vehicleMake!)
        : <String>[];
    if (_vehicleModel != null &&
        !models.any((m) => m.toLowerCase() == _vehicleModel!.toLowerCase())) {
      models = [_vehicleModel!, ...models];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('Car Details', theme),
        const SizedBox(height: 8),

        // ── VIN Lookup ──
        _buildVinLookupField(theme, isDark),
        const SizedBox(height: 12),

        // ── Make dropdown ──
        _buildSearchableDropdown(
          label: 'Make',
          value: _vehicleMake,
          items:
              _vehicleMake != null &&
                  !VehicleData.brands.any(
                    (b) => b.toLowerCase() == _vehicleMake!.toLowerCase(),
                  )
              ? [_vehicleMake!, ...VehicleData.brands]
              : VehicleData.brands,
          hint: 'Select brand',
          theme: theme,
          isDark: isDark,
          onChanged: (v) => setState(() {
            _vehicleMake = v;
            _vehicleModel = null; // reset model on brand change
          }),
        ),
        const SizedBox(height: 12),

        // ── Model dropdown (filtered by make) ──
        _buildSearchableDropdown(
          label: 'Model',
          value: _vehicleModel,
          items: models,
          hint: _vehicleMake == null ? 'Select make first' : 'Select model',
          theme: theme,
          isDark: isDark,
          enabled: _vehicleMake != null,
          onChanged: (v) => setState(() {
            _vehicleModel = v;
          }),
        ),
        const SizedBox(height: 12),

        // ── Year & Mileage row ──
        Row(
          children: [
            Expanded(
              child: _buildSearchableDropdown(
                label: 'Year',
                value: _vehicleYear,
                items: VehicleData.years,
                hint: 'Year',
                theme: theme,
                isDark: isDark,
                onChanged: (v) => setState(() {
                  _vehicleYear = v;
                }),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mileage',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: theme.hintColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _buildTextField(
                    controller: _vehicleMileageController,
                    hint: 'Mileage (km)',
                    keyboardType: TextInputType.number,
                    theme: theme,
                    isDark: isDark,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── Transmission (own row) ──
        Text(
          'Transmission',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: theme.hintColor,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: ['Automatic', 'Manual', 'CVT'].map((t) {
            final isSelected = _vehicleTransmission == t;
            return GestureDetector(
              onTap: () => setState(() => _vehicleTransmission = t),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.accent.withValues(alpha: isDark ? 0.25 : 0.12)
                      : isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  t,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: isSelected ? AppTheme.accent : theme.hintColor,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),

        // ── Fuel type (own row) ──
        Text(
          'Fuel Type',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: theme.hintColor,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: ['Petrol', 'Diesel', 'Electric', 'Hybrid', 'LPG'].map((f) {
            final isSelected = _vehicleFuelType == f;
            return GestureDetector(
              onTap: () => setState(() => _vehicleFuelType = f),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.accent.withValues(alpha: isDark ? 0.25 : 0.12)
                      : isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  f,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: isSelected ? AppTheme.accent : theme.hintColor,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),

        // ── Body Type (own row) ──
        Text(
          'Body Type',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: theme.hintColor,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children:
              [
                'Sedan',
                'SUV',
                'Hatchback',
                'Coupe',
                'Pickup',
                'Van',
                'Wagon',
                'Convertible',
                'Crossover',
              ].map((b) {
                final isSelected = _vehicleBodyType == b;
                return GestureDetector(
                  onTap: () => setState(() => _vehicleBodyType = b),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.accent.withValues(
                              alpha: isDark ? 0.25 : 0.12,
                            )
                          : isDark
                          ? Colors.white.withValues(alpha: 0.04)
                          : Colors.black.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      b,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: isSelected ? AppTheme.accent : theme.hintColor,
                      ),
                    ),
                  ),
                );
              }).toList(),
        ),
        const SizedBox(height: 16),

        // ── Drive Type (own row) ──
        Text(
          'Drive Type',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: theme.hintColor,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: ['FWD', 'RWD', 'AWD', '4WD'].map((d) {
            final isSelected = _vehicleDriveType == d;
            return GestureDetector(
              onTap: () => setState(() => _vehicleDriveType = d),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.accent.withValues(alpha: isDark ? 0.25 : 0.12)
                      : isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  d,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: isSelected ? AppTheme.accent : theme.hintColor,
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        // ── VIN-decoded extras (read-only info chips) ──
        if (_vehicleEngineSize != null ||
            _vehicleHP != null ||
            _vehicleDoors != null ||
            _vehiclePlantCountry != null) ...[
          const SizedBox(height: 16),
          Text(
            'Specs from VIN',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: theme.hintColor,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (_vehicleEngineSize != null)
                _buildInfoChip(LucideIcons.gauge, _vehicleEngineSize!, isDark),
              if (_vehicleHP != null)
                _buildInfoChip(LucideIcons.zap, '$_vehicleHP hp', isDark),
              if (_vehicleDoors != null)
                _buildInfoChip(
                  LucideIcons.doorOpen,
                  '$_vehicleDoors doors',
                  isDark,
                ),
              if (_vehiclePlantCountry != null)
                _buildInfoChip(
                  LucideIcons.factory,
                  _vehiclePlantCountry!,
                  isDark,
                ),
            ],
          ),
        ],

        // ── VIN-decoded extended info ──
        if (_vehicleTrim != null ||
            _vehicleSeries != null ||
            _vehicleAbs != null ||
            _vehicleAirbagLocations != null ||
            _vehicleGvwr != null ||
            _vehicleType != null ||
            _vehicleElectrificationType != null ||
            _vehicleBatteryKWh != null ||
            _vehiclePlantCity != null) ...[
          const SizedBox(height: 16),
          Text(
            'VIN Details',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: theme.hintColor,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (_vehicleTrim != null)
                _buildInfoChip(LucideIcons.star, 'Trim: $_vehicleTrim', isDark),
              if (_vehicleSeries != null)
                _buildInfoChip(
                  LucideIcons.layers,
                  'Series: $_vehicleSeries',
                  isDark,
                ),
              if (_vehicleType != null)
                _buildInfoChip(LucideIcons.car, '$_vehicleType', isDark),
              if (_vehicleAbs != null)
                _buildInfoChip(
                  LucideIcons.shieldCheck,
                  'ABS: $_vehicleAbs',
                  isDark,
                ),
              if (_vehicleAirbagLocations != null)
                _buildInfoChip(
                  LucideIcons.shieldAlert,
                  'Airbags: $_vehicleAirbagLocations',
                  isDark,
                ),
              if (_vehicleGvwr != null)
                _buildInfoChip(
                  LucideIcons.scale,
                  'GVWR: $_vehicleGvwr',
                  isDark,
                ),
              if (_vehicleElectrificationType != null)
                _buildInfoChip(
                  LucideIcons.batteryCharging,
                  '$_vehicleElectrificationType',
                  isDark,
                ),
              if (_vehicleBatteryKWh != null)
                _buildInfoChip(
                  LucideIcons.battery,
                  '$_vehicleBatteryKWh kWh',
                  isDark,
                ),
              if (_vehiclePlantCity != null && _vehiclePlantCountry != null)
                _buildInfoChip(
                  LucideIcons.mapPin,
                  'Made in $_vehiclePlantCity, $_vehiclePlantCountry',
                  isDark,
                )
              else if (_vehiclePlantCity != null)
                _buildInfoChip(
                  LucideIcons.mapPin,
                  'Made in $_vehiclePlantCity',
                  isDark,
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildInfoChip(IconData icon, String label, bool isDark) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.accent),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Motorcycle-specific fields ─────────────────────────────────────
  Widget _buildMotorcycleFields(ThemeData theme, bool isDark) {
    final models = _motorcycleMake != null
        ? MotorcycleData.getModels(_motorcycleMake!)
        : <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('Motorcycle Details', theme),
        const SizedBox(height: 8),

        // ── Make dropdown ──
        _buildSearchableDropdown(
          label: 'Make',
          value: _motorcycleMake,
          items: MotorcycleData.brands,
          hint: 'Select brand',
          theme: theme,
          isDark: isDark,
          onChanged: (v) => setState(() {
            _motorcycleMake = v;
            _motorcycleModel = null;
          }),
        ),
        const SizedBox(height: 12),

        // ── Model dropdown (filtered by make) ──
        _buildSearchableDropdown(
          label: 'Model',
          value: _motorcycleModel,
          items: models,
          hint: _motorcycleMake == null ? 'Select make first' : 'Select model',
          theme: theme,
          isDark: isDark,
          enabled: _motorcycleMake != null,
          onChanged: (v) => setState(() {
            _motorcycleModel = v;
          }),
        ),
        const SizedBox(height: 12),

        // ── Year & Mileage row ──
        Row(
          children: [
            Expanded(
              child: _buildSearchableDropdown(
                label: 'Year',
                value: _motorcycleYear,
                items: VehicleData.years,
                hint: 'Year',
                theme: theme,
                isDark: isDark,
                onChanged: (v) => setState(() {
                  _motorcycleYear = v;
                }),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mileage',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: theme.hintColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _buildTextField(
                    controller: _motorcycleMileageController,
                    hint: 'Mileage (km)',
                    keyboardType: TextInputType.number,
                    theme: theme,
                    isDark: isDark,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── Engine Size ──
        Text(
          'Engine Size',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: theme.hintColor,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: MotorcycleData.engineSizes.map((e) {
            final isSelected = _motorcycleEngineSize == e;
            return GestureDetector(
              onTap: () => setState(() => _motorcycleEngineSize = e),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.accent.withValues(alpha: isDark ? 0.25 : 0.12)
                      : isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  e,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: isSelected ? AppTheme.accent : theme.hintColor,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),

        // ── Motorcycle Type ──
        Text(
          'Motorcycle Type',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: theme.hintColor,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: MotorcycleData.motorcycleTypes.map((t) {
            final isSelected = _motorcycleType == t;
            return GestureDetector(
              onTap: () => setState(() => _motorcycleType = t),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.accent.withValues(alpha: isDark ? 0.25 : 0.12)
                      : isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  t,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: isSelected ? AppTheme.accent : theme.hintColor,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Car Parts–specific fields ──────────────────────────────────────
  Widget _buildCarPartsFields(ThemeData theme, bool isDark) {
    final models = _partCarMake != null
        ? VehicleData.getModels(_partCarMake!)
        : <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('Part Details', theme),
        const SizedBox(height: 8),

        // ── Part Number ──
        _buildTextField(
          controller: _partNumberController,
          hint: 'Part number (OEM or aftermarket)',
          theme: theme,
          isDark: isDark,
          prefix: Icon(LucideIcons.hash, size: 16, color: theme.hintColor),
        ),
        const SizedBox(height: 12),

        // ── Fits Car Make ──
        _buildSearchableDropdown(
          label: 'Fits Car Make',
          value: _partCarMake,
          items: VehicleData.brands,
          hint: 'Search car make…',
          theme: theme,
          isDark: isDark,
          onChanged: (v) {
            setState(() {
              _partCarMake = v;
              _partCarModel = null;
            });
          },
        ),
        const SizedBox(height: 12),

        // ── Fits Car Model ──
        _buildSearchableDropdown(
          label: 'Fits Car Model',
          value: _partCarModel,
          items: models,
          hint: _partCarMake == null ? 'Select make first' : 'Search model…',
          theme: theme,
          isDark: isDark,
          enabled: _partCarMake != null,
          onChanged: (v) {
            setState(() => _partCarModel = v);
          },
        ),
        const SizedBox(height: 12),

        // ── Year & VIN row ──
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: _buildSearchableDropdown(
                label: 'Fits Year',
                value: _partCarYear,
                items: VehicleData.years,
                hint: 'Year',
                theme: theme,
                isDark: isDark,
                onChanged: (v) {
                  setState(() => _partCarYear = v);
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'VIN',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: theme.hintColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _buildTextField(
                    controller: _partVinController,
                    hint: 'VIN (17 chars)',
                    theme: theme,
                    isDark: isDark,
                    prefix: Icon(
                      LucideIcons.fingerprint,
                      size: 16,
                      color: theme.hintColor,
                    ),
                    maxLength: 17,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Compatible Models (autocomplete chips) ──
        _buildCompatibleModelsChips(theme, isDark),
      ],
    );
  }

  /// VIN lookup field with scanner and auto-fill button for vehicle form
  Widget _buildVinLookupField(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── VIN Scanner button ──
        GestureDetector(
          onTap: _scanVin,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.accent.withValues(alpha: isDark ? 0.15 : 0.08),
                  AppTheme.accent.withValues(alpha: isDark ? 0.08 : 0.04),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppTheme.accent.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    LucideIcons.focus,
                    size: 20,
                    color: AppTheme.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Scan VIN Number',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.accent,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Scan barcode on door panel or photo of paperwork',
                        style: TextStyle(fontSize: 11, color: theme.hintColor),
                      ),
                    ],
                  ),
                ),
                Icon(
                  LucideIcons.chevronRight,
                  size: 18,
                  color: AppTheme.accent.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),

        // ── VIN text field + lookup button ──
        Text(
          'VIN Lookup',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: theme.hintColor,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildTextField(
                controller: _vehicleVinController,
                hint: 'Enter 17-character VIN',
                theme: theme,
                isDark: isDark,
                prefix: Icon(
                  LucideIcons.fingerprint,
                  size: 16,
                  color: theme.hintColor,
                ),
                maxLength: 17,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed:
                    _vinLookupLoading ||
                        _vehicleVinController.text.trim().length != 17
                    ? null
                    : () => _lookupVin(),
                icon: _vinLookupLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(LucideIcons.search, size: 16),
                label: Text(
                  _vinLookupLoading ? 'Looking up...' : 'Lookup',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Enter VIN to auto-fill vehicle details',
          style: TextStyle(
            fontSize: 11,
            color: theme.hintColor.withValues(alpha: 0.6),
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  /// Performs VIN lookup and auto-fills vehicle fields
  Future<void> _lookupVin() async {
    final vin = _vehicleVinController.text.trim().toUpperCase();
    if (vin.length != 17) return;

    setState(() => _vinLookupLoading = true);

    try {
      final result = await VinDecoderService.decode(vin);

      if (!mounted) return;

      if (!result.isValid) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.errorMessage ?? 'Could not decode VIN'),
            backgroundColor: AppTheme.error,
          ),
        );
        return;
      }

      // Auto-fill fields
      setState(() {
        if (result.make != null) {
          // Try to match the decoded make to our brand list
          final matchedBrand = VehicleData.brands.firstWhere(
            (b) => b.toLowerCase() == result.make!.toLowerCase(),
            orElse: () => '',
          );
          if (matchedBrand.isNotEmpty) {
            _vehicleMake = matchedBrand;

            // Try to match the model within that brand
            if (result.model != null) {
              final models = VehicleData.getModels(matchedBrand);
              final matchedModel = models.firstWhere(
                (m) => m.toLowerCase() == result.model!.toLowerCase(),
                orElse: () => '',
              );
              // Use matched model from static data, or fall back to API model
              _vehicleModel = matchedModel.isNotEmpty
                  ? matchedModel
                  : result.model;
            }
          } else {
            // Brand not in static data — use raw API values
            _vehicleMake = result.make;
            _vehicleModel = result.model;
          }
        }

        if (result.year != null) _vehicleYear = result.year;
        if (result.transmission != null) {
          _vehicleTransmission = result.transmission;
        }
        if (result.fuelType != null) _vehicleFuelType = result.fuelType;
        if (result.bodyClass != null) _vehicleBodyType = result.bodyClass;
        if (result.driveType != null) _vehicleDriveType = result.driveType;
        if (result.engineDescription != null) {
          _vehicleEngineSize = result.engineDescription;
        }
        if (result.compactEngineLabel != null) {
          _vehicleEngineLabel = result.compactEngineLabel;
        }
        if (result.engineHP != null) _vehicleHP = result.engineHP;
        if (result.doors != null) _vehicleDoors = result.doors;
        if (result.plantCountry != null) {
          _vehiclePlantCountry = result.plantCountry;
        }
        if (result.plantCity != null) {
          _vehiclePlantCity = result.plantCity;
        }
        if (result.trim != null) _vehicleTrim = result.trim;
        if (result.series != null) _vehicleSeries = result.series;
        if (result.abs != null) _vehicleAbs = result.abs;
        if (result.airbagLocations != null) {
          _vehicleAirbagLocations = result.airbagLocations;
        }
        if (result.gvwr != null) _vehicleGvwr = result.gvwr;
        if (result.vehicleType != null) _vehicleType = result.vehicleType;
        if (result.electrificationType != null) {
          _vehicleElectrificationType = result.electrificationType;
        }
        if (result.batteryKWh != null) {
          _vehicleBatteryKWh = result.batteryKWh;
        }
      });

      // Show success
      if (mounted) {
        final filled = <String>[];
        if (result.make != null) filled.add('Make');
        if (result.model != null) filled.add('Model');
        if (result.year != null) filled.add('Year');
        if (result.bodyClass != null) filled.add('Body');
        if (result.driveType != null) filled.add('Drive');
        if (result.engineDescription != null) filled.add('Engine');
        if (result.transmission != null) filled.add('Trans');
        if (result.fuelType != null) filled.add('Fuel');
        if (result.trim != null) filled.add('Trim');
        if (result.series != null) filled.add('Series');
        if (result.abs != null) filled.add('ABS');
        if (result.airbagLocations != null) filled.add('Airbags');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Auto-filled ${filled.length} fields: ${filled.join(', ')}',
            ),
            backgroundColor: AppTheme.accent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _vinLookupLoading = false);
      }
    }
  }

  /// Opens VIN barcode/OCR scanner and auto-fills on scan
  Future<void> _scanVin() async {
    final result = await showVinScanner(context);
    if (result == null || !mounted) return;

    _vehicleVinController.text = result.vin;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('VIN captured via ${result.source}: ${result.vin}'),
        backgroundColor: AppTheme.accent,
      ),
    );

    // Auto-trigger lookup
    _lookupVin();
  }

  /// Autocomplete chip builder for compatible car models
  Widget _buildCompatibleModelsChips(ThemeData theme, bool isDark) {
    // Build a flat list of "Brand Model" for searching
    final allModels = <String>[];
    for (final brand in VehicleData.brands) {
      for (final model in VehicleData.getModels(brand)) {
        allModels.add('$brand $model');
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Also Fits',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: theme.hintColor,
          ),
        ),
        const SizedBox(height: 4),

        // Chips
        if (_compatibleModels.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _compatibleModels.map((model) {
              return Container(
                padding: const EdgeInsets.only(
                  left: 10,
                  right: 4,
                  top: 4,
                  bottom: 4,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: isDark ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        model,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.accent,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 2),
                    GestureDetector(
                      onTap: () =>
                          setState(() => _compatibleModels.remove(model)),
                      child: Icon(
                        LucideIcons.x,
                        size: 14,
                        color: AppTheme.accent.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
        ],

        // Add button
        GestureDetector(
          onTap: () => _showModelSearchSheet(
            context: context,
            allModels: allModels,
            theme: theme,
            isDark: isDark,
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.plus, size: 16, color: AppTheme.accent),
                const SizedBox(width: 8),
                Text(
                  _compatibleModels.isEmpty
                      ? 'Add compatible models...'
                      : 'Add more models...',
                  style: TextStyle(fontSize: 14, color: theme.hintColor),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Shows a search bottom sheet to find and add compatible models
  void _showModelSearchSheet({
    required BuildContext context,
    required List<String> allModels,
    required ThemeData theme,
    required bool isDark,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ModelSearchSheet(
        allModels: allModels,
        selectedModels: _compatibleModels,
        onToggle: (model) {
          setState(() {
            if (_compatibleModels.contains(model)) {
              _compatibleModels.remove(model);
            } else {
              _compatibleModels.add(model);
            }
          });
        },
      ),
    );
  }

  /// Searchable dropdown builder
  Widget _buildSearchableDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required String hint,
    required ThemeData theme,
    required bool isDark,
    required ValueChanged<String?> onChanged,
    bool enabled = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: theme.hintColor,
          ),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: enabled
              ? () => _showSearchableBottomSheet(
                  context: context,
                  title: 'Select $label',
                  items: items,
                  onSelected: onChanged,
                  theme: theme,
                  isDark: isDark,
                )
              : null,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: enabled ? 0.06 : 0.02)
                  : Colors.black.withValues(alpha: enabled ? 0.03 : 0.01),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value ?? hint,
                    style: TextStyle(
                      fontSize: 14,
                      color: value != null
                          ? theme.colorScheme.onSurface
                          : theme.hintColor.withValues(
                              alpha: enabled ? 1.0 : 0.4,
                            ),
                    ),
                  ),
                ),
                Icon(
                  LucideIcons.chevronDown,
                  size: 16,
                  color: enabled
                      ? theme.hintColor
                      : theme.hintColor.withValues(alpha: 0.3),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Bottom sheet with search for dropdown items
  void _showSearchableBottomSheet({
    required BuildContext context,
    required String title,
    required List<String> items,
    required ValueChanged<String?> onSelected,
    required ThemeData theme,
    required bool isDark,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _SearchableListSheet(
        title: title,
        items: items,
        onSelected: (v) {
          onSelected(v);
          Navigator.of(ctx).pop();
        },
      ),
    );
  }

  // ── Real Estate specific fields ─────────────────────────────────────
  Widget _buildRealEstateFields(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('Property Details', theme),
        const SizedBox(height: 8),

        // Sale vs Rent
        Row(
          children: [
            Expanded(
              child: _buildToggleOption(
                icon: LucideIcons.home,
                label: 'For Sale',
                isSelected: _realEstateType == 'sale',
                onTap: () => setState(() => _realEstateType = 'sale'),
                theme: theme,
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildToggleOption(
                icon: LucideIcons.key,
                label: 'For Rent',
                isSelected: _realEstateType == 'rent',
                onTap: () => setState(() => _realEstateType = 'rent'),
                theme: theme,
                isDark: isDark,
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildSearchableDropdown(
                label: 'Bedrooms',
                value: _realEstateBedrooms,
                items: const [
                  'Studio',
                  '1',
                  '2',
                  '3',
                  '4',
                  '5',
                  '6',
                  '7',
                  '8',
                  '9',
                  '10+',
                ],
                hint: 'Bedrooms',
                theme: theme,
                isDark: isDark,
                onChanged: (v) => setState(() => _realEstateBedrooms = v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSearchableDropdown(
                label: 'Bathrooms',
                value: _realEstateBathrooms,
                items: const ['1', '2', '3', '4', '5', '6+'],
                hint: 'Bathrooms',
                theme: theme,
                isDark: isDark,
                onChanged: (v) => setState(() => _realEstateBathrooms = v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTextField(
                controller: _realEstateSqftController,
                hint: 'Area (sqft)',
                keyboardType: TextInputType.number,
                theme: theme,
                isDark: isDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildLocationPicker(
          label: 'Property Location',
          hint: 'Search for property location...',
          displayValue: _realEstateLocationDisplay,
          theme: theme,
          isDark: isDark,
          onSelected: (display, placeId) {
            setState(() {
              _realEstateLocationDisplay = display;
              _realEstateLocationPlaceId = placeId;
            });
          },
        ),
      ],
    );
  }

  // ── Electronics specific fields ─────────────────────────────────────
  Widget _buildElectronicsFields(ThemeData theme, bool isDark) {
    final models = _electronicsBrand != null
        ? ElectronicsData.getModels(_electronicsBrand!)
        : <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('Device Details', theme),
        const SizedBox(height: 8),

        // ── Brand dropdown ──
        _buildSearchableDropdown(
          label: 'Brand',
          value: _electronicsBrand,
          items: ElectronicsData.brands,
          hint: 'Select brand',
          theme: theme,
          isDark: isDark,
          onChanged: (v) => setState(() {
            _electronicsBrand = v;
            _electronicsModel = null; // reset model on brand change
          }),
        ),
        const SizedBox(height: 12),

        // ── Model dropdown (filtered by brand) ──
        _buildSearchableDropdown(
          label: 'Model',
          value: _electronicsModel,
          items: models,
          hint: _electronicsBrand == null
              ? 'Select brand first'
              : 'Select model',
          theme: theme,
          isDark: isDark,
          enabled: _electronicsBrand != null,
          onChanged: (v) => setState(() => _electronicsModel = v),
        ),
        const SizedBox(height: 16),

        // ── Storage chips ──
        Text(
          'Storage',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: theme.hintColor,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: ElectronicsData.storageOptions.map((s) {
            final isSelected = _electronicsStorage == s;
            return GestureDetector(
              onTap: () => setState(() => _electronicsStorage = s),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.accent.withValues(alpha: isDark ? 0.25 : 0.12)
                      : isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  s,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: isSelected ? AppTheme.accent : theme.hintColor,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Service specific fields ────────────────────────────────────────
  Widget _buildServiceFields(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('Service Name', theme),
        const SizedBox(height: 8),
        _buildTextField(
          controller: _titleController,
          hint: 'e.g. Professional Tax Filing Services',
          maxLength: 120,
          theme: theme,
          isDark: isDark,
          validator: (v) => v == null || v.isEmpty ? 'Title is required' : null,
        ),
        const SizedBox(height: 16),
        _buildSectionLabel('Service Details', theme),
        const SizedBox(height: 8),
        _buildSearchableDropdown(
          label: 'Experience',
          value: _serviceExperience,
          items: const [
            'Less than 1 year',
            '1 year',
            '2 years',
            '3 years',
            '4 years',
            '5 years',
            '6 years',
            '7 years',
            '8 years',
            '9 years',
            '10 years',
            '15 years',
            '20+ years',
          ],
          hint: 'Years of experience',
          theme: theme,
          isDark: isDark,
          onChanged: (v) => setState(() => _serviceExperience = v),
        ),
        const SizedBox(height: 12),
        _buildLocationPicker(
          label: 'Service Area',
          hint: 'Search for service area...',
          displayValue: _serviceAreaDisplay,
          theme: theme,
          isDark: isDark,
          onSelected: (display, placeId) {
            setState(() {
              _serviceAreaDisplay = display;
              _serviceAreaPlaceId = placeId;
            });
          },
        ),
        const SizedBox(height: 12),

        Text(
          'Availability',
          style: TextStyle(fontSize: 11, color: theme.hintColor),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children:
              [
                'Weekdays',
                'Weekends',
                'Evenings',
                'Flexible',
                'By Appointment',
              ].map((a) {
                final isSelected = _serviceAvailability == a;
                return GestureDetector(
                  onTap: () => setState(() => _serviceAvailability = a),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.accent.withValues(
                              alpha: isDark ? 0.2 : 0.1,
                            )
                          : isDark
                          ? Colors.white.withValues(alpha: 0.04)
                          : Colors.black.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      a,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: isSelected ? AppTheme.accent : theme.hintColor,
                      ),
                    ),
                  ),
                );
              }).toList(),
        ),
      ],
    );
  }

  Widget _buildJobFields(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('Job Title', theme),
        const SizedBox(height: 8),
        _buildTextField(
          controller: _titleController,
          hint: 'e.g. Senior Flutter Developer – Remote',
          maxLength: 120,
          theme: theme,
          isDark: isDark,
          validator: (v) => v == null || v.isEmpty ? 'Title is required' : null,
        ),
        const SizedBox(height: 16),
        _buildSectionLabel('Company Name', theme),
        const SizedBox(height: 8),
        _buildTextField(
          controller: _jobCompanyController,
          hint: 'e.g. DiasPay Inc.',
          theme: theme,
          isDark: isDark,
        ),
        const SizedBox(height: 16),
        Text(
          'Employment Type',
          style: TextStyle(fontSize: 11, color: theme.hintColor),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children:
              [
                'Full-time',
                'Part-time',
                'Contract',
                'Freelance',
                'Internship',
              ].map((t) {
                final isSelected = _jobEmploymentType == t;
                return GestureDetector(
                  onTap: () => setState(() => _jobEmploymentType = t),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.accent.withValues(
                              alpha: isDark ? 0.2 : 0.1,
                            )
                          : isDark
                          ? Colors.white.withValues(alpha: 0.04)
                          : Colors.black.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      t,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: isSelected ? AppTheme.accent : theme.hintColor,
                      ),
                    ),
                  ),
                );
              }).toList(),
        ),
        const SizedBox(height: 16),
        _buildSectionLabel('Salary Range', theme),
        const SizedBox(height: 8),
        _buildTextField(
          controller: _jobSalaryController,
          hint: 'e.g. \$80K – \$120K / year',
          theme: theme,
          isDark: isDark,
        ),
        const SizedBox(height: 16),
        Text(
          'Experience Required',
          style: TextStyle(fontSize: 11, color: theme.hintColor),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children:
              [
                'Entry Level',
                'Junior (1-2 yrs)',
                'Mid-Level (3-5 yrs)',
                'Senior (5-8 yrs)',
                'Lead (8+ yrs)',
                'Director / Executive',
              ].map((e) {
                final isSelected = _jobExperienceLevel == e;
                return GestureDetector(
                  onTap: () => setState(() => _jobExperienceLevel = e),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.accent.withValues(
                              alpha: isDark ? 0.2 : 0.1,
                            )
                          : isDark
                          ? Colors.white.withValues(alpha: 0.04)
                          : Colors.black.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      e,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: isSelected ? AppTheme.accent : theme.hintColor,
                      ),
                    ),
                  ),
                );
              }).toList(),
        ),
        const SizedBox(height: 16),
        Text(
          'Work Mode',
          style: TextStyle(fontSize: 11, color: theme.hintColor),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: ['Remote', 'On-site', 'Hybrid'].map((m) {
            final isSelected = _jobWorkMode == m;
            return GestureDetector(
              onTap: () => setState(() => _jobWorkMode = m),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.accent.withValues(alpha: isDark ? 0.2 : 0.1)
                      : isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  m,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: isSelected ? AppTheme.accent : theme.hintColor,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        Text(
          'Application Deadline',
          style: TextStyle(fontSize: 11, color: theme.hintColor),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: _jobDeadline ?? now.add(const Duration(days: 30)),
              firstDate: now,
              lastDate: now.add(const Duration(days: 365)),
              builder: (ctx, child) => Theme(
                data: theme.copyWith(
                  colorScheme: theme.colorScheme.copyWith(
                    primary: AppTheme.accent,
                  ),
                ),
                child: child!,
              ),
            );
            if (picked != null) setState(() => _jobDeadline = picked);
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.calendar, size: 16, color: theme.hintColor),
                const SizedBox(width: 10),
                Text(
                  _jobDeadline != null
                      ? '${_jobDeadline!.day}/${_jobDeadline!.month}/${_jobDeadline!.year}'
                      : 'Select deadline date',
                  style: TextStyle(
                    fontSize: 14,
                    color: _jobDeadline != null
                        ? theme.colorScheme.onSurface
                        : theme.hintColor,
                  ),
                ),
                const Spacer(),
                if (_jobDeadline != null)
                  GestureDetector(
                    onTap: () => setState(() => _jobDeadline = null),
                    child: Icon(
                      LucideIcons.x,
                      size: 14,
                      color: theme.hintColor,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Auto-generate listing title from category-specific fields
  String _generateTitle() {
    switch (_selectedCategory) {
      case MarketplaceCategory.vehicles:
        final parts = <String>[?_vehicleYear, ?_vehicleMake, ?_vehicleModel];
        return parts.join(' ');

      case MarketplaceCategory.motorcycles:
        final parts = <String>[
          ?_motorcycleYear,
          ?_motorcycleMake,
          ?_motorcycleModel,
          ?_motorcycleEngineSize,
        ];
        return parts.join(' ');

      case MarketplaceCategory.carParts:
        final parts = <String>[
          _partNumberController.text.trim().isNotEmpty
              ? _partNumberController.text.trim()
              : '',
          if (_partCarMake != null) 'for $_partCarMake',
          ?_partCarModel,
          if (_partCarYear != null) '(${_partCarYear!})',
        ];
        return parts.where((p) => p.isNotEmpty).join(' ');

      case MarketplaceCategory.realEstate:
        final beds = _realEstateBedrooms ?? '';
        final loc = _realEstateLocationDisplay ?? '';
        final type = _realEstateType == 'rent' ? 'For Rent' : 'For Sale';
        final parts = <String>[
          if (beds.isNotEmpty) '$beds Bedroom',
          'Property',
          type,
          if (loc.isNotEmpty) 'in $loc',
        ];
        return parts.join(' ');

      case MarketplaceCategory.electronics:
        final brand = _electronicsBrand ?? '';
        final model = _electronicsModel ?? '';
        final storage = _electronicsStorage ?? '';
        final parts = <String>[
          if (brand.isNotEmpty) brand,
          if (model.isNotEmpty) model,
          if (storage.isNotEmpty) storage,
        ];
        return parts.join(' ');

      default:
        // For fashion, services, and other categories
        // use the title controller as manual input
        return _titleController.text.trim();
    }
  }

  // ─── STEP 3: Images & Contact ─────────────────────────────────────────
  Widget _buildStep3ImagesContact(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Images
        _buildSectionLabel('Photos (up to 6)', theme),
        const SizedBox(height: 8),
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _selectedImages.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              if (index == 0) {
                return GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    width: 100,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.04)
                          : Colors.black.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.camera, color: theme.hintColor),
                        const SizedBox(height: 4),
                        Text(
                          'Add Photo',
                          style: TextStyle(
                            fontSize: 10,
                            color: theme.hintColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final img = _selectedImages[index - 1];
              return Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.file(
                      File(img.path),
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () =>
                          setState(() => _selectedImages.removeAt(index - 1)),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          LucideIcons.x,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),

        const SizedBox(height: 24),

        // Delivery options
        if (_listingType == ListingType.product) ...[
          _buildSectionLabel('Delivery Options', theme),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                [
                  {
                    'id': 'pickup',
                    'label': 'Pickup',
                    'icon': LucideIcons.mapPin,
                  },
                  {
                    'id': 'delivery',
                    'label': 'Delivery',
                    'icon': LucideIcons.truck,
                  },
                  {
                    'id': 'shipping',
                    'label': 'Shipping',
                    'icon': LucideIcons.package,
                  },
                  {
                    'id': 'digital',
                    'label': 'Digital',
                    'icon': LucideIcons.monitor,
                  },
                ].map((opt) {
                  final isSelected = _deliveryOptions.contains(
                    opt['id'] as String,
                  );
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _deliveryOptions.remove(opt['id'] as String);
                        } else {
                          _deliveryOptions.add(opt['id']! as String);
                        }
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.accent.withValues(
                                alpha: isDark ? 0.2 : 0.1,
                              )
                            : isDark
                            ? Colors.white.withValues(alpha: 0.04)
                            : Colors.black.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            opt['icon'] as IconData,
                            size: 13,
                            color: isSelected
                                ? AppTheme.accent
                                : theme.colorScheme.onSurface.withValues(
                                    alpha: 0.5,
                                  ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            opt['label']! as String,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
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
                  );
                }).toList(),
          ),
          const SizedBox(height: 24),
        ],

        // Contact method
        _buildSectionLabel(
          _listingType == ListingType.job
              ? 'How should applicants reach you?'
              : _listingType == ListingType.service
              ? 'How should clients contact you?'
              : 'How should buyers contact you?',
          theme,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children:
              [
                {
                  'id': ContactMethod.chat,
                  'label': 'In-App Chat',
                  'icon': LucideIcons.messageCircle,
                },
                {
                  'id': ContactMethod.phone,
                  'label': 'Phone',
                  'icon': LucideIcons.phone,
                },
                {
                  'id': ContactMethod.whatsapp,
                  'label': 'WhatsApp',
                  'icon': LucideIcons.smartphone,
                },
                {
                  'id': ContactMethod.email,
                  'label': 'Email',
                  'icon': LucideIcons.mail,
                },
              ].map((opt) {
                final isSelected = _contactMethod == opt['id'];
                return GestureDetector(
                  onTap: () =>
                      setState(() => _contactMethod = opt['id']! as String),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.accent.withValues(
                              alpha: isDark ? 0.2 : 0.1,
                            )
                          : isDark
                          ? Colors.white.withValues(alpha: 0.04)
                          : Colors.black.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          opt['icon'] as IconData,
                          size: 13,
                          color: isSelected
                              ? AppTheme.accent
                              : theme.colorScheme.onSurface.withValues(
                                  alpha: 0.5,
                                ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          opt['label']! as String,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
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
                );
              }).toList(),
        ),

        const SizedBox(height: 24),

        // Tags
        _buildSectionLabel('Tags (optional)', theme),
        const SizedBox(height: 8),
        _buildTextField(
          controller: _tagsController,
          hint: _listingType == ListingType.job
              ? 'e.g. remote, flutter, senior, startup (comma-separated)'
              : _listingType == ListingType.service
              ? 'e.g. plumbing, certified, 24hr, emergency (comma-separated)'
              : _selectedCategory == MarketplaceCategory.vehicles
              ? 'e.g. toyota, hilux, 4x4, diesel (comma-separated)'
              : _selectedCategory == MarketplaceCategory.carParts
              ? 'e.g. OEM, aftermarket, brake, engine, part-number (comma-separated)'
              : _selectedCategory == MarketplaceCategory.realEstate
              ? 'e.g. 3-bedroom, furnished, garden, garage (comma-separated)'
              : _selectedCategory == MarketplaceCategory.electronics
              ? 'e.g. iphone, 256gb, unlocked (comma-separated)'
              : _selectedCategory == MarketplaceCategory.fashion
              ? 'e.g. handmade, silk, large, designer (comma-separated)'
              : 'e.g. keyword1, keyword2 (comma-separated)',
          theme: theme,
          isDark: isDark,
        ),
      ],
    );
  }

  // ─── Bottom Navigation Bar ────────────────────────────────────────────
  Widget _buildBottomBar(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.02)
            : Colors.black.withValues(alpha: 0.01),
      ),
      child: SafeArea(
        child: Row(
          children: [
            if (_currentStep > 0)
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _currentStep--),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.onSurface,
                    side: BorderSide(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Back'),
                ),
              ),
            if (_currentStep > 0) const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _onNextOrSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _currentStep == 2 ? 'Publish Listing' : 'Next',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Actions ──────────────────────────────────────────────────────────
  void _onNextOrSubmit() {
    if (_currentStep == 0) {
      // Validate step 1
      if (_selectedCategory == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a category')),
        );
        return;
      }
      setState(() => _currentStep = 1);
    } else if (_currentStep == 1) {
      if (_formKey.currentState?.validate() != true) return;
      setState(() => _currentStep = 2);
    } else {
      // Validate at least 1 image for new listings
      if (!_isEditing && _selectedImages.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please add at least 1 photo')),
        );
        return;
      }
      _submitListing();
    }
  }

  Future<void> _submitListing() async {
    setState(() => _isSubmitting = true);

    try {
      final user = ref.read(authRepositoryProvider).currentUser;
      final profile = ref.read(userProfileProvider).value;
      if (user == null || profile == null) throw Exception('Not logged in');

      // Gate: Members offering services MUST have completed Proof of Humanity (PoH)
      if (_listingType == ListingType.service) {
        final trustData = await ref
            .read(trustServiceProvider)
            .getTrustData(user.uid);
        final isPoHComplete =
            (trustData?.uniqueFamilyCount ?? 0) >= 10 &&
            (trustData?.uniqueFriendCount ?? 0) >= 10 &&
            (trustData?.uniqueQrCount ?? 0) >= 10 &&
            (trustData?.uniqueVerificationCount ?? 0) >= 10 &&
            (profile.isComplete) &&
            (profile.showCurrentLocationName != false &&
                profile.currentLocation != null &&
                profile.cityVisibilityForfeited != true);
        if (!isPoHComplete) {
          throw Exception(
            'Providing services requires completing all 7 Proof of Humanity (PoH) milestones to protect community trust.',
          );
        }
      }

      // Upload images
      final imageUrls = <String>[];
      for (int i = 0; i < _selectedImages.length; i++) {
        final file = File(_selectedImages[i].path);
        final storageRef = FirebaseStorage.instance.ref().child(
          'marketplace/${user.uid}/${DateTime.now().millisecondsSinceEpoch}_$i.jpg',
        );
        await storageRef.putFile(file);
        final url = await storageRef.getDownloadURL();
        imageUrls.add(url);
      }

      // Parse tags
      final tags = _tagsController.text
          .split(',')
          .map((t) => t.trim().toLowerCase())
          .where((t) => t.isNotEmpty)
          .toList();

      // Build contextual details
      Map<String, dynamic>? vehicleDetails;
      Map<String, dynamic>? motorcycleDetails;
      Map<String, dynamic>? carPartsDetails;
      Map<String, dynamic>? realEstateDetails;
      Map<String, dynamic>? electronicsDetails;
      Map<String, dynamic>? serviceDetails;

      if (_selectedCategory == MarketplaceCategory.vehicles) {
        vehicleDetails = {
          'make': _vehicleMake ?? '',
          'model': _vehicleModel ?? '',
          'year': _vehicleYear ?? '',
          'mileage': _vehicleMileageController.text,
          'vin': _vehicleVinController.text.trim(),
          'transmission': _vehicleTransmission,
          'fuelType': _vehicleFuelType,
          'bodyType': _vehicleBodyType,
          'driveType': _vehicleDriveType,
          'engineSize': _vehicleEngineSize,
          'engineLabel': _vehicleEngineLabel,
          'horsepower': _vehicleHP,
          'doors': _vehicleDoors,
          'plantCountry': _vehiclePlantCountry,
          'plantCity': _vehiclePlantCity,
          'trim': _vehicleTrim,
          'series': _vehicleSeries,
          'abs': _vehicleAbs,
          'airbagLocations': _vehicleAirbagLocations,
          'gvwr': _vehicleGvwr,
          'vehicleType': _vehicleType,
          'electrificationType': _vehicleElectrificationType,
          'batteryKWh': _vehicleBatteryKWh,
        };
      } else if (_selectedCategory == MarketplaceCategory.motorcycles) {
        motorcycleDetails = {
          'make': _motorcycleMake ?? '',
          'model': _motorcycleModel ?? '',
          'year': _motorcycleYear ?? '',
          'mileage': _motorcycleMileageController.text,
          'engineSize': _motorcycleEngineSize ?? '',
          'type': _motorcycleType ?? '',
        };
      } else if (_selectedCategory == MarketplaceCategory.carParts) {
        final compatibleList = _compatibleModels;

        carPartsDetails = {
          'partNumber': _partNumberController.text.trim(),
          'carMake': _partCarMake ?? '',
          'carModel': _partCarModel ?? '',
          'carYear': _partCarYear ?? '',
          'vin': _partVinController.text.trim(),
          'compatibleModels': compatibleList,
        };
      } else if (_selectedCategory == MarketplaceCategory.realEstate) {
        realEstateDetails = {
          'type': _realEstateType,
          'bedrooms': _realEstateBedrooms ?? '',
          'bathrooms': _realEstateBathrooms ?? '',
          'sqft': _realEstateSqftController.text,
          'propertyAddress': _realEstateLocationDisplay ?? '',
          'propertyPlaceId': _realEstateLocationPlaceId ?? '',
        };
      } else if (_selectedCategory == MarketplaceCategory.electronics) {
        electronicsDetails = {
          'brand': _electronicsBrand ?? '',
          'model': _electronicsModel ?? '',
          'storage': _electronicsStorage ?? '',
        };
      }

      if (_listingType == ListingType.service) {
        serviceDetails = {
          'experience': _serviceExperience ?? '',
          'serviceArea': _serviceAreaDisplay ?? '',
          'serviceAreaPlaceId': _serviceAreaPlaceId ?? '',
          'availability': _serviceAvailability,
        };
      }

      Map<String, dynamic>? jobDetails;
      if (_listingType == ListingType.job) {
        jobDetails = {
          'companyName': _jobCompanyController.text,
          'employmentType': _jobEmploymentType,
          'salaryRange': _jobSalaryController.text,
          'experienceLevel': _jobExperienceLevel ?? '',
          'workMode': _jobWorkMode,
          'applicationDeadline': _jobDeadline?.toIso8601String() ?? '',
        };
      }

      final listing = MarketplaceListing(
        id: '',
        sellerId: user.uid,
        sellerName: profile.fullName,
        sellerPhoto: profile.profileImage.isNotEmpty
            ? profile.profileImage
            : null,
        sellerCountryCode: profile.hostCountryCode,
        sellerCity: profile.hostLocation.city,
        orgId: null,
        orgName: profile.businessProfile?.businessName,
        title: _generateTitle().isNotEmpty
            ? _generateTitle()
            : _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        category: _selectedCategory!,
        subcategory: _selectedSubcategory,
        listingType: _listingType,
        scope: _scope,
        priceAmount: double.parse(_priceController.text),
        priceNegotiable: _priceNegotiable,
        condition: _condition,
        vehicleDetails: vehicleDetails,
        motorcycleDetails: motorcycleDetails,
        carPartsDetails: carPartsDetails,
        realEstateDetails: realEstateDetails,
        electronicsDetails: electronicsDetails,
        serviceDetails: serviceDetails,
        jobDetails: jobDetails,
        images: imageUrls,
        tags: tags.isEmpty ? null : tags,
        location: ListingLocation(
          city: profile.hostLocation.city,
          country: profile.hostCountry,
          countryCode: profile.hostCountryCode,
        ),
        deliveryOptions: _deliveryOptions.isEmpty ? null : _deliveryOptions,
        contactMethod: _contactMethod,
        communityIds: profile.communityMemberships,
        expiresAt: DateTime.now().add(const Duration(days: 30)),
      );

      final repo = ref.read(marketplaceRepositoryProvider);

      if (_isEditing) {
        // Update existing listing
        await repo.updateListing(widget.existingListing!.id, listing.toMap());

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Listing updated successfully!'),
              backgroundColor: AppTheme.success,
            ),
          );
          context.pop();
        }
      } else {
        final listingId = await repo.createListing(listing);

        // Create the public group chat for this listing
        try {
          await ref
              .read(chatRepositoryProvider)
              .createListingChat(
                otherUserId: user.uid, // Seller is the creator/admin
                listingId: listingId,
                listingTitle: listing.title,
                listingType: listing.listingType,
                sellerRole: _getSellerRole(listing.category),
                listingImageUrl: imageUrls.isNotEmpty ? imageUrls.first : null,
              );
          debugPrint(
            '✅ [Marketplace] Listing group chat created for $listingId',
          );
        } catch (e) {
          debugPrint('⚠️ [Marketplace] Failed to create listing chat: $e');
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Listing published successfully!'),
              backgroundColor: AppTheme.success,
            ),
          );
          context.pop(); // Pop the create screen
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ListingDetailScreen(listingId: listingId),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Determine the seller role based on the listing category
  String _getSellerRole(String category) {
    if (MarketplaceCategory.jobCategories.contains(category)) {
      return 'Employer';
    } else if (MarketplaceCategory.serviceCategories.contains(category)) {
      return 'Provider';
    } else {
      return 'Seller';
    }
  }

  Future<void> _pickImage() async {
    if (_selectedImages.length >= 6) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Maximum 6 photos allowed')));
      return;
    }

    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 80,
    );

    if (image != null) {
      setState(() => _selectedImages.add(image));
    }
  }

  // ─── Shared Widgets ───────────────────────────────────────────────────
  Widget _buildSectionLabel(String label, ThemeData theme) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
      ),
    );
  }

  Widget _buildToggleOption({
    required IconData icon,
    required String label,
    String? subtitle,
    required bool isSelected,
    required VoidCallback onTap,
    required ThemeData theme,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.accent.withValues(alpha: isDark ? 0.2 : 0.1)
              : isDark
              ? Colors.white.withValues(alpha: 0.03)
              : Colors.black.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 22,
              color: isSelected ? AppTheme.accent : theme.hintColor,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected
                    ? AppTheme.accent
                    : theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: 10, color: theme.hintColor),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required ThemeData theme,
    required bool isDark,
    int maxLines = 1,
    int? maxLength,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    Widget? prefix,
    ValueChanged<String>? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      onChanged: onChanged,
      maxLines: maxLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
      validator: validator,
      textCapitalization: TextCapitalization.sentences,
      style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 13, color: theme.hintColor),
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        prefix: prefix,
        counterStyle: TextStyle(fontSize: 10, color: theme.hintColor),
      ),
    );
  }

  // ── Google Places location picker ───────────────────────────────────
  Widget _buildLocationPicker({
    required String label,
    required String hint,
    required String? displayValue,
    required ThemeData theme,
    required bool isDark,
    required void Function(String display, String placeId) onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: theme.hintColor,
          ),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () => _showLocationSearchSheet(
            context: context,
            title: label,
            theme: theme,
            isDark: isDark,
            onSelected: onSelected,
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.mapPin,
                  size: 16,
                  color: displayValue != null
                      ? AppTheme.accent
                      : theme.hintColor,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    displayValue ?? hint,
                    style: TextStyle(
                      fontSize: 14,
                      color: displayValue != null
                          ? theme.colorScheme.onSurface
                          : theme.hintColor,
                    ),
                  ),
                ),
                Icon(
                  LucideIcons.chevronRight,
                  size: 16,
                  color: theme.hintColor,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showLocationSearchSheet({
    required BuildContext context,
    required String title,
    required ThemeData theme,
    required bool isDark,
    required void Function(String display, String placeId) onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _LocationSearchSheet(
        title: title,
        placesService: ref.read(googlePlacesServiceProvider),
        onSelected: (display, placeId) {
          Navigator.pop(ctx);
          onSelected(display, placeId);
        },
      ),
    );
  }
}

/// A searchable list displayed in a bottom sheet for dropdown selections.
class _SearchableListSheet extends StatefulWidget {
  final String title;
  final List<String> items;
  final ValueChanged<String> onSelected;

  const _SearchableListSheet({
    required this.title,
    required this.items,
    required this.onSelected,
  });

  @override
  State<_SearchableListSheet> createState() => _SearchableListSheetState();
}

class _SearchableListSheetState extends State<_SearchableListSheet> {
  final _searchController = TextEditingController();
  List<String> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.items;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch(String query) {
    setState(() {
      if (query.isEmpty) {
        _filtered = widget.items;
      } else {
        final q = query.toLowerCase();
        _filtered = widget.items
            .where((i) => i.toLowerCase().contains(q))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final viewPad = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      maxChildSize: 0.9,
      minChildSize: 0.35,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle bar
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.hintColor.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                widget.title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Search field
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearch,
                autofocus: true,
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.onSurface,
                ),
                decoration: InputDecoration(
                  hintText: 'Search...',
                  hintStyle: TextStyle(fontSize: 14, color: theme.hintColor),
                  prefixIcon: Icon(
                    LucideIcons.search,
                    size: 18,
                    color: theme.hintColor,
                  ),
                  filled: true,
                  fillColor: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.04),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Results list
            Expanded(
              child: _filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No results',
                        style: TextStyle(fontSize: 14, color: theme.hintColor),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: EdgeInsets.only(
                        bottom:
                            viewPad +
                            MediaQuery.of(context).padding.bottom +
                            16,
                      ),
                      itemCount: _filtered.length,
                      itemBuilder: (ctx, i) {
                        final item = _filtered[i];
                        return ListTile(
                          dense: true,
                          title: Text(
                            item,
                            style: TextStyle(
                              fontSize: 14,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          onTap: () => widget.onSelected(item),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// A location search bottom sheet that uses Google Places autocomplete.
class _LocationSearchSheet extends StatefulWidget {
  final String title;
  final GooglePlacesService placesService;
  final void Function(String display, String placeId) onSelected;

  const _LocationSearchSheet({
    required this.title,
    required this.placesService,
    required this.onSelected,
  });

  @override
  State<_LocationSearchSheet> createState() => _LocationSearchSheetState();
}

class _LocationSearchSheetState extends State<_LocationSearchSheet> {
  final _searchController = TextEditingController();
  List<AutocompletePrediction> _predictions = [];
  bool _loading = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _onSearch(String query) async {
    if (query.trim().length < 2) {
      setState(() => _predictions = []);
      return;
    }
    setState(() => _loading = true);
    try {
      final results = await widget.placesService.autocomplete(
        query,
        filter: PlaceTypeFilter.GEOCODE,
      );
      if (mounted) setState(() => _predictions = results);
    } catch (_) {
      // Silently handle errors
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectPrediction(AutocompletePrediction prediction) async {
    try {
      final response = await widget.placesService.getPlaceDetails(
        prediction.placeId,
      );
      if (response == null) {
        widget.onSelected(prediction.fullText, prediction.placeId);
        return;
      }
      final place = response.place;

      // Build display using app's standard location convention
      String display = prediction.fullText;
      if (place.addressComponents != null &&
          place.addressComponents!.isNotEmpty) {
        final parsed = parseLocationComponents(
          place.address ?? prediction.fullText,
          place.addressComponents!,
        );
        if (parsed != null) {
          final parts = <String>[
            if (parsed.sublocality != null)
              formatLocationName(parsed.sublocality!),
            if (parsed.city != null) formatLocationName(parsed.city!),
            if (parsed.state != null) formatLocationName(parsed.state!),
            formatLocationName(parsed.country),
          ].where((s) => s.isNotEmpty).toList();
          if (parts.isNotEmpty) display = parts.join(', ');
        }
      }

      widget.onSelected(display, prediction.placeId);
    } catch (_) {
      // Fall back to using the prediction text
      widget.onSelected(prediction.fullText, prediction.placeId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final safePadBottom = MediaQuery.of(context).padding.bottom;
    final viewPad = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      maxChildSize: 0.9,
      minChildSize: 0.35,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle bar
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.hintColor.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                widget.title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Search field
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearch,
                autofocus: true,
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.onSurface,
                ),
                decoration: InputDecoration(
                  hintText: 'Search for a location...',
                  hintStyle: TextStyle(fontSize: 14, color: theme.hintColor),
                  prefixIcon: Icon(
                    LucideIcons.search,
                    size: 18,
                    color: theme.hintColor,
                  ),
                  suffixIcon: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                  filled: true,
                  fillColor: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.04),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Results list
            Expanded(
              child: _predictions.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              LucideIcons.mapPin,
                              size: 32,
                              color: theme.hintColor.withValues(alpha: 0.3),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _searchController.text.isEmpty
                                  ? 'Start typing to search'
                                  : 'No results found',
                              style: TextStyle(
                                fontSize: 14,
                                color: theme.hintColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: EdgeInsets.only(
                        bottom: viewPad + safePadBottom + 16,
                      ),
                      itemCount: _predictions.length,
                      itemBuilder: (ctx, i) {
                        final p = _predictions[i];
                        return ListTile(
                          leading: const Icon(
                            LucideIcons.mapPin,
                            size: 18,
                            color: AppTheme.accent,
                          ),
                          title: Text(
                            p.primaryText,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          subtitle: Text(
                            p.secondaryText,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.hintColor,
                            ),
                          ),
                          dense: true,
                          onTap: () => _selectPrediction(p),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// Bottom sheet for searching and selecting compatible car models.
class _ModelSearchSheet extends StatefulWidget {
  final List<String> allModels;
  final List<String> selectedModels;
  final ValueChanged<String> onToggle;

  const _ModelSearchSheet({
    required this.allModels,
    required this.selectedModels,
    required this.onToggle,
  });

  @override
  State<_ModelSearchSheet> createState() => _ModelSearchSheetState();
}

class _ModelSearchSheetState extends State<_ModelSearchSheet> {
  final _searchController = TextEditingController();
  List<String> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.allModels.take(50).toList(); // show first 50 by default
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    setState(() {
      if (query.isEmpty) {
        _filtered = widget.allModels.take(50).toList();
      } else {
        final lower = query.toLowerCase();
        _filtered = widget.allModels
            .where((m) => m.toLowerCase().contains(lower))
            .take(50)
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Add Compatible Models',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 12),

          // Search field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search brand or model...',
                  hintStyle: TextStyle(color: theme.hintColor),
                  prefixIcon: Icon(
                    LucideIcons.search,
                    size: 18,
                    color: theme.hintColor,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          Divider(
            height: 1,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
          ),

          // Results list
          Expanded(
            child: _filtered.isEmpty
                ? Center(
                    child: Text(
                      'No models found',
                      style: TextStyle(color: theme.hintColor),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _filtered.length,
                    itemBuilder: (ctx, i) {
                      final model = _filtered[i];
                      final isSelected = widget.selectedModels.contains(model);
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          isSelected
                              ? LucideIcons.checkCircle
                              : LucideIcons.circle,
                          size: 18,
                          color: isSelected
                              ? AppTheme.accent
                              : theme.hintColor.withValues(alpha: 0.4),
                        ),
                        title: Text(
                          model,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: isSelected
                                ? AppTheme.accent
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                        onTap: () {
                          widget.onToggle(model);
                          setState(() {}); // rebuild to show check
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
