import 'dart:async';
import 'dart:ui';
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
import 'package:diaspora_nearby/features/marketplace/data/vehicle_data.dart';
import 'package:diaspora_nearby/features/marketplace/services/vin_decoder_service.dart';
import 'package:diaspora_nearby/features/travel/widgets/vin_scanner_widget.dart';
import 'package:diaspora_nearby/core/services/google_places_service.dart';
import 'package:diaspora_nearby/core/utils/location_utils.dart';
import 'package:diaspora_nearby/features/shared/models/google_places_models.dart';

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
  final _descC = TextEditingController();
  final _priceC = TextEditingController();
  final _cityC = TextEditingController();
  final _subLocalityC = TextEditingController();
  final _stateC = TextEditingController();
  final _addressC = TextEditingController();
  final _locationSearchC = TextEditingController();
  Timer? _searchDebounce;
  int _searchSeq = 0;
  List<AutocompletePrediction> _predictions = [];
  bool _isSearchingLocation = false;
  double? _lat;
  double? _lng;
  String? _country;
  String? _countryCode;
  final _vehicleVinController = TextEditingController();
  final _vehicleMileageController = TextEditingController();

  // Vehicle details (populated by dropdowns or VIN lookup)
  String? _vehicleMake;
  String? _vehicleModel;
  String? _vehicleYear;
  String _transmission = 'Automatic';
  String _fuelType = 'Petrol';
  String? _vehicleBodyType;
  String _drivetrain = 'FWD';
  int _seats = 5;
  final List<String> _selectedFeatures = [];
  bool _isSaving = false;

  // VIN lookup
  bool _vinLookupLoading = false;
  String? _vehicleEngineSize;
  String? _vehicleHP;
  String? _vehicleEngineLabel;
  String? _vehicleDoors;
  String? _vehiclePlantCountry;
  String? _vehiclePlantCity;
  String? _vehicleTrim;
  String? _vehicleSeries;
  String? _vehicleAbs;
  String? _vehicleAirbagLocations;
  String? _vehicleGvwr;
  String? _vehicleType;
  String? _vehicleElectrificationType;
  String? _vehicleBatteryKWh;

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
    _vehicleVinController.addListener(() => setState(() {}));
    if (widget.existing != null) {
      _prefillFromExisting(widget.existing!);
    } else {
      _prefillFromProfile();
    }
  }

  void _prefillFromExisting(PeerListing l) {
    _descC.text = l.description;
    _priceC.text = l.pricePerUnit.toStringAsFixed(0);
    final city = l.locality ?? l.city ?? '';
    _cityC.text = city;
    _subLocalityC.text = l.subLocality ?? '';
    _stateC.text =
        sanitizeStateForCountry(
          state: l.state,
          city: city,
          countryCode: l.countryCode,
          countryName: l.country,
        ) ??
        '';
    _country = l.country;
    _countryCode = l.countryCode;
    _lat = l.lat;
    _lng = l.lng;
    _addressC.text = l.address ?? '';
    _transmission = l.transmission ?? 'Automatic';
    _fuelType = l.fuelType ?? 'Petrol';
    _drivetrain = l.drivetrain ?? 'FWD';
    _seats = l.seats ?? 5;
    if (l.features != null) _selectedFeatures.addAll(l.features!);

    // Match make/model to dropdowns
    if (l.make != null) {
      final matched = VehicleData.brands.firstWhere(
        (b) => b.toLowerCase() == l.make!.toLowerCase(),
        orElse: () => '',
      );
      if (matched.isNotEmpty) {
        _vehicleMake = matched;
        if (l.model != null) {
          final models = VehicleData.getModels(matched);
          final matchedModel = models.firstWhere(
            (m) => m.toLowerCase() == l.model!.toLowerCase(),
            orElse: () => '',
          );
          _vehicleModel = matchedModel.isNotEmpty ? matchedModel : l.model;
        }
      } else {
        // Brand not in static data — use stored values directly
        _vehicleMake = l.make;
        _vehicleModel = l.model;
      }
    }
    if (l.year != null) _vehicleYear = l.year.toString();
    _vehicleVinController.text = l.vin ?? '';
    _vehicleMileageController.text = l.mileage?.toString() ?? '';
    _vehicleBodyType = l.bodyType;
    _vehicleTrim = l.trim;
    _vehicleSeries = l.series;
    _vehicleDoors = l.doors?.toString();
    _vehicleEngineSize = l.engineSize;
    _vehicleHP = l.engineHP;
    _vehicleEngineLabel = l.engineLabel;
    _vehiclePlantCountry = l.plantCountry;
    _vehiclePlantCity = l.plantCity;
    _vehicleAbs = l.abs;
    _vehicleAirbagLocations = l.airbagLocations;
    _vehicleGvwr = l.gvwr;
    _vehicleType = l.vehicleType;
    _vehicleElectrificationType = l.electrificationType;
    _vehicleBatteryKWh = l.batteryKWh;
  }

  void _prefillFromProfile() {
    final profile = ref.read(userProfileProvider).value;
    if (profile == null) return;
    final city = profile.hostLocation.city ?? '';
    _cityC.text = city;
    _stateC.text =
        sanitizeStateForCountry(
          state: profile.hostLocation.state,
          city: city,
          countryCode: profile.hostCountryCode,
          countryName: profile.hostCountry,
        ) ??
        '';
    _country = profile.hostCountry;
    _countryCode = profile.hostCountryCode;
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _descC.dispose();
    _priceC.dispose();
    _cityC.dispose();
    _subLocalityC.dispose();
    _stateC.dispose();
    _addressC.dispose();
    _locationSearchC.dispose();
    _vehicleVinController.dispose();
    _vehicleMileageController.dispose();
    super.dispose();
  }

  void _onLocationSearchChanged(String query) {
    _searchDebounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.length < 2) {
      setState(() {
        _predictions = [];
        _isSearchingLocation = false;
      });
      return;
    }
    setState(() => _isSearchingLocation = true);
    final seq = ++_searchSeq;
    _searchDebounce = Timer(const Duration(milliseconds: 280), () async {
      try {
        final service = ref.read(googlePlacesServiceProvider);
        final results = await service.autocomplete(
          trimmed,
          filter: PlaceTypeFilter.ALL,
        );
        if (!mounted || seq != _searchSeq) return;
        setState(() {
          _predictions = results;
          _isSearchingLocation = false;
        });
      } catch (_) {
        if (mounted && seq == _searchSeq) {
          setState(() => _isSearchingLocation = false);
        }
      }
    });
  }

  Future<void> _onPlaceSelected(AutocompletePrediction prediction) async {
    _searchDebounce?.cancel();
    FocusScope.of(context).unfocus();
    setState(() {
      _predictions = [];
      _isSearchingLocation = false;
      _locationSearchC.text = prediction.fullText;
    });

    try {
      final service = ref.read(googlePlacesServiceProvider);
      final response = await service.getPlaceDetails(prediction.placeId);
      if (!mounted || response == null) return;
      final place = response.place;
      final rawFull =
          place.fullAddress ?? place.address ?? prediction.fullText;
      if (place.latLng != null) {
        _lat = place.latLng!.lat;
        _lng = place.latLng!.lng;
      }
      if (place.addressComponents != null) {
        final parsed = parseLocationComponents(
          rawFull,
          place.addressComponents!,
        );
        if (parsed != null) {
          setState(() {
            _cityC.text = parsed.city ?? '';
            _subLocalityC.text = parsed.sublocality ?? '';
            _stateC.text = parsed.state ?? '';
            _country = parsed.country;
            _countryCode = parsed.countryCode;
            _addressC.text =
                (parsed.streetAddress != null &&
                    parsed.streetAddress!.isNotEmpty)
                ? parsed.streetAddress!
                : rawFull;
          });
        }
      }
    } catch (_) {}
  }

  // ─── Generate auto title ──────────────────────────────────────────
  String _generateTitle() {
    final parts = <String>[];
    if (_vehicleYear != null) parts.add(_vehicleYear!);
    if (_vehicleMake != null) parts.add(_vehicleMake!);
    if (_vehicleModel != null) parts.add(_vehicleModel!);
    return parts.join(' ');
  }

  // ─── Save ─────────────────────────────────────────────────────────
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_vehicleMake == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a vehicle make'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final profile = ref.read(userProfileProvider).value;
      final user = ref.read(authRepositoryProvider).currentUser;
      if (user == null || profile == null) throw Exception('Not logged in');

      final repo = ref.read(peerListingRepositoryProvider);
      final title = _generateTitle();
      final isEditing = widget.existing != null;
      final listingId = isEditing
          ? widget.existing!.id
          : repo.generateListingId();

      final effectiveCountry =
          _country ?? widget.existing?.country ?? profile.hostCountry;
      final effectiveCountryCode =
          _countryCode ??
          widget.existing?.countryCode ??
          profile.hostCountryCode;
      final cleanCity = _cityC.text.trim();
      final cleanState = sanitizeStateForCountry(
        state: _stateC.text.trim(),
        city: cleanCity,
        countryCode: effectiveCountryCode,
        countryName: effectiveCountry,
      );

      final listing = PeerListing(
        id: listingId,
        type: 'car',
        ownerId: widget.existing?.ownerId ?? user.uid,
        ownerName: profile.fullName,
        ownerPhoto: profile.profileImage,
        title: title.isNotEmpty ? title : 'Car Rental',
        description: _descC.text.trim(),
        photos: widget.existing?.photos ?? const [],
        pricePerUnit: double.tryParse(_priceC.text.trim()) ?? 0,
        currency: widget.existing?.currency ?? 'USD',
        city: cleanCity,
        country: effectiveCountry,
        countryCode: effectiveCountryCode,
        address: _addressC.text.trim(),
        locality: cleanCity,
        subLocality: _subLocalityC.text.trim(),
        state: cleanState,
        localityLower: cleanCity.toLowerCase(),
        stateLower: cleanState?.toLowerCase(),
        lat: _lat ?? widget.existing?.lat,
        lng: _lng ?? widget.existing?.lng,
        status: widget.existing?.status ?? 'active',
        viewCount: widget.existing?.viewCount ?? 0,
        savedCount: widget.existing?.savedCount ?? 0,
        createdAt: widget.existing?.createdAt,
        make: _vehicleMake,
        model: _vehicleModel,
        year: _vehicleYear != null ? int.tryParse(_vehicleYear!) : null,
        vin: _vehicleVinController.text.trim().isNotEmpty
            ? _vehicleVinController.text.trim().toUpperCase()
            : null,
        transmission: _transmission,
        seats: _seats,
        fuelType: _fuelType,
        drivetrain: _drivetrain,
        bodyType: _vehicleBodyType,
        trim: _vehicleTrim,
        series: _vehicleSeries,
        doors: _vehicleDoors != null ? int.tryParse(_vehicleDoors!) : null,
        engineSize: _vehicleEngineSize,
        engineHP: _vehicleHP,
        engineLabel: _vehicleEngineLabel,
        mileage: _vehicleMileageController.text.trim().isNotEmpty
            ? int.tryParse(_vehicleMileageController.text.trim())
            : null,
        vehicleType: _vehicleType,
        abs: _vehicleAbs,
        airbagLocations: _vehicleAirbagLocations,
        gvwr: _vehicleGvwr,
        electrificationType: _vehicleElectrificationType,
        batteryKWh: _vehicleBatteryKWh,
        plantCountry: _vehiclePlantCountry,
        plantCity: _vehiclePlantCity,
        features: List<String>.from(_selectedFeatures),
      );

      repo.cacheListing(listing);

      if (mounted) {
        final navigator = Navigator.of(context);
        final messenger = ScaffoldMessenger.of(context);
        navigator.pop(true);
        if (!isEditing) {
          navigator.push(
            MaterialPageRoute(
              builder: (_) => PeerListingDetailScreen(listing: listing),
            ),
          );
        }
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              isEditing ? 'Car updated!' : 'Car listed for rental!',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      unawaited(() async {
        try {
          if (isEditing) {
            await repo.updateListing(listingId, listing.toJson());
          } else {
            await repo.createListing(listing);
          }
        } catch (e) {
          debugPrint('CreateCarListingScreen save error: $e');
        }
      }());
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

  // ─── VIN Lookup ───────────────────────────────────────────────────
  Future<void> _lookupVin() async {
    final vin = _vehicleVinController.text.trim().toUpperCase();
    if (vin.length != 17) return;

    final cachedVin = VinDecoderService.getCached(vin);
    if (cachedVin == null) {
      setState(() => _vinLookupLoading = true);
    }

    try {
      final result = cachedVin ?? await VinDecoderService.decode(vin);
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

      setState(() {
        if (result.make != null) {
          final matchedBrand = VehicleData.brands.firstWhere(
            (b) => b.toLowerCase() == result.make!.toLowerCase(),
            orElse: () => '',
          );
          if (matchedBrand.isNotEmpty) {
            _vehicleMake = matchedBrand;
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
        if (result.transmission != null) _transmission = result.transmission!;
        if (result.fuelType != null) _fuelType = result.fuelType!;
        if (result.bodyClass != null) _vehicleBodyType = result.bodyClass;
        if (result.driveType != null) _drivetrain = result.driveType!;
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
      if (mounted) setState(() => _vinLookupLoading = false);
    }
  }

  // ─── VIN Scanner ──────────────────────────────────────────────────
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

  // ─── Build ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isEditing = widget.existing != null;
    // Build model list: static data + VIN-decoded model if not already present
    var models = _vehicleMake != null
        ? VehicleData.getModels(_vehicleMake!)
        : <String>[];
    if (_vehicleModel != null &&
        !models.any((m) => m.toLowerCase() == _vehicleModel!.toLowerCase())) {
      models = [_vehicleModel!, ...models];
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(
          isEditing ? 'Edit Car' : 'Post Car',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.only(
                  left: 8,
                  right: 8,
                  top: 8,
                  bottom: MediaQuery.of(context).padding.bottom + 100,
                ),
                children: [
                  // ── VIN Scanner + Lookup section ──
                  _buildSectionLabel('VIN Number', theme),
                  const SizedBox(height: 8),
                  _buildVinScannerAndLookup(theme, isDark),
                  const SizedBox(height: 20),

                  // ── Car Details ──
                  _buildSectionLabel('Car Details', theme),
                  const SizedBox(height: 8),

                  // Make dropdown
                  _buildSearchableDropdown(
                    label: 'Make',
                    value: _vehicleMake,
                    items:
                        _vehicleMake != null &&
                            !VehicleData.brands.any(
                              (b) =>
                                  b.toLowerCase() ==
                                  _vehicleMake!.toLowerCase(),
                            )
                        ? [_vehicleMake!, ...VehicleData.brands]
                        : VehicleData.brands,
                    hint: 'Select brand',
                    theme: theme,
                    isDark: isDark,
                    onChanged: (v) => setState(() {
                      _vehicleMake = v;
                      _vehicleModel = null;
                    }),
                  ),
                  const SizedBox(height: 12),

                  // Model dropdown
                  _buildSearchableDropdown(
                    label: 'Model',
                    value: _vehicleModel,
                    items: models,
                    hint: _vehicleMake == null
                        ? 'Select make first'
                        : 'Select model',
                    theme: theme,
                    isDark: isDark,
                    enabled: _vehicleMake != null,
                    onChanged: (v) => setState(() => _vehicleModel = v),
                  ),
                  const SizedBox(height: 12),

                  // Year & Mileage row
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
                          onChanged: (v) => setState(() => _vehicleYear = v),
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

                  // Auto-generated title preview
                  if (_generateTitle().isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withValues(
                          alpha: isDark ? 0.08 : 0.05,
                        ),
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
                    const SizedBox(height: 16),
                  ],

                  // Transmission
                  _buildChipRow(
                    'Transmission',
                    theme,
                    ['Automatic', 'Manual', 'CVT'],
                    _transmission,
                    isDark,
                    (v) => setState(() => _transmission = v),
                  ),
                  const SizedBox(height: 16),

                  // Fuel type
                  _buildChipRow(
                    'Fuel Type',
                    theme,
                    ['Petrol', 'Diesel', 'Electric', 'Hybrid', 'LPG'],
                    _fuelType,
                    isDark,
                    (v) => setState(() => _fuelType = v),
                  ),
                  const SizedBox(height: 16),

                  // Body type
                  if (_vehicleBodyType != null) ...[
                    _buildChipRow(
                      'Body Type',
                      theme,
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
                      ],
                      _vehicleBodyType,
                      isDark,
                      (v) => setState(() => _vehicleBodyType = v),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Drivetrain
                  _buildChipRow(
                    'Drivetrain',
                    theme,
                    ['FWD', 'RWD', 'AWD', '4WD'],
                    _drivetrain,
                    isDark,
                    (v) => setState(() => _drivetrain = v),
                  ),
                  const SizedBox(height: 16),

                  // VIN-decoded specs chips
                  if (_vehicleEngineSize != null ||
                      _vehicleHP != null ||
                      _vehicleDoors != null ||
                      _vehiclePlantCountry != null) ...[
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
                          _infoChip(
                            LucideIcons.gauge,
                            _vehicleEngineSize!,
                            isDark,
                          ),
                        if (_vehicleHP != null)
                          _infoChip(LucideIcons.zap, '$_vehicleHP hp', isDark),
                        if (_vehicleDoors != null)
                          _infoChip(
                            LucideIcons.doorOpen,
                            '$_vehicleDoors doors',
                            isDark,
                          ),
                        if (_vehiclePlantCountry != null)
                          _infoChip(
                            LucideIcons.factory,
                            _vehiclePlantCountry!,
                            isDark,
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
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
                          _infoChip(
                            LucideIcons.star,
                            'Trim: $_vehicleTrim',
                            isDark,
                          ),
                        if (_vehicleSeries != null)
                          _infoChip(
                            LucideIcons.layers,
                            'Series: $_vehicleSeries',
                            isDark,
                          ),
                        if (_vehicleType != null)
                          _infoChip(LucideIcons.car, '$_vehicleType', isDark),
                        if (_vehicleAbs != null)
                          _infoChip(
                            LucideIcons.shieldCheck,
                            'ABS: $_vehicleAbs',
                            isDark,
                          ),
                        if (_vehicleAirbagLocations != null)
                          _infoChip(
                            LucideIcons.shieldAlert,
                            'Airbags: $_vehicleAirbagLocations',
                            isDark,
                          ),
                        if (_vehicleGvwr != null)
                          _infoChip(
                            LucideIcons.scale,
                            'GVWR: $_vehicleGvwr',
                            isDark,
                          ),
                        if (_vehicleElectrificationType != null)
                          _infoChip(
                            LucideIcons.batteryCharging,
                            '$_vehicleElectrificationType',
                            isDark,
                          ),
                        if (_vehicleBatteryKWh != null)
                          _infoChip(
                            LucideIcons.battery,
                            '$_vehicleBatteryKWh kWh',
                            isDark,
                          ),
                        if (_vehiclePlantCity != null &&
                            _vehiclePlantCountry != null)
                          _infoChip(
                            LucideIcons.mapPin,
                            'Made in $_vehiclePlantCity, $_vehiclePlantCountry',
                            isDark,
                          )
                        else if (_vehiclePlantCity != null)
                          _infoChip(
                            LucideIcons.mapPin,
                            'Made in $_vehiclePlantCity',
                            isDark,
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Seats stepper
                  _buildSectionLabel('Seats', theme),
                  const SizedBox(height: 8),
                  _buildStepper(
                    theme,
                    _seats,
                    1,
                    15,
                    (v) => setState(() => _seats = v),
                  ),
                  const SizedBox(height: 20),

                  // ── Rental Details ──
                  _buildSectionLabel('Rental Details', theme),
                  const SizedBox(height: 8),

                  // Price per day
                  _buildTextField(
                    controller: _priceC,
                    hint: 'Price per day',
                    keyboardType: TextInputType.number,
                    theme: theme,
                    isDark: isDark,
                    prefix: Icon(
                      LucideIcons.dollarSign,
                      size: 16,
                      color: theme.hintColor,
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Price required';
                      if (double.tryParse(v) == null) return 'Invalid';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // Description
                  _buildTextField(
                    controller: _descC,
                    hint:
                        'Describe your car — condition, any rules, '
                        'delivery options...',
                    maxLines: 3,
                    theme: theme,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 20),

                  // ── Pick-up Location ──
                  _buildSectionLabel('Pick-up Location', theme),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _locationSearchC,
                    onChanged: _onLocationSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Search pick-up address or city on Google Maps...',
                      prefixIcon: const Icon(
                        LucideIcons.search,
                        size: 16,
                        color: AppTheme.accent,
                      ),
                      suffixIcon: _isSearchingLocation
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.accent,
                                ),
                              ),
                            )
                          : _locationSearchC.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(LucideIcons.x, size: 14),
                              onPressed: () {
                                _locationSearchC.clear();
                                setState(() => _predictions = []);
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: AppTheme.elevationColor(context, 2),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  if (_predictions.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      constraints: const BoxConstraints(maxHeight: 200),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _predictions.length,
                        itemBuilder: (context, idx) {
                          final p = _predictions[idx];
                          return ListTile(
                            dense: true,
                            leading: const Icon(
                              LucideIcons.mapPin,
                              size: 16,
                              color: AppTheme.accent,
                            ),
                            title: Text(
                              p.primaryText,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: p.secondaryText.isNotEmpty
                                ? Text(
                                    p.secondaryText,
                                    style: const TextStyle(fontSize: 11),
                                  )
                                : null,
                            onTap: () => _onPlaceSelected(p),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _cityC,
                    hint: 'City',
                    theme: theme,
                    isDark: isDark,
                    prefix: Icon(
                      LucideIcons.mapPin,
                      size: 16,
                      color: theme.hintColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Builder(
                    builder: (context) {
                      final profile = ref.read(userProfileProvider).value;
                      final cc = _countryCode ?? profile?.hostCountryCode ?? '';
                      final hasState = country_data.hasStateLevelForCountry(
                        countryCode: cc,
                        countryName: _country ?? profile?.hostCountry,
                      );
                      final stateTerm = country_data.getStateTerminology(cc);
                      if (hasState) {
                        return Row(
                          children: [
                            Expanded(
                              child: _buildTextField(
                                controller: _subLocalityC,
                                hint: 'Neighborhood / Area',
                                theme: theme,
                                isDark: isDark,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildTextField(
                                controller: _stateC,
                                hint: stateTerm,
                                theme: theme,
                                isDark: isDark,
                              ),
                            ),
                          ],
                        );
                      }
                      return _buildTextField(
                        controller: _subLocalityC,
                        hint: 'Neighborhood / Area',
                        theme: theme,
                        isDark: isDark,
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _addressC,
                    hint: 'Pick-up address (optional)',
                    theme: theme,
                    isDark: isDark,
                    prefix: Icon(
                      LucideIcons.home,
                      size: 16,
                      color: theme.hintColor,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Features ──
                  _buildSectionLabel('Features', theme),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _allFeatures.map((f) {
                      final sel = _selectedFeatures.contains(f);
                      return FilterChip(
                        label: Text(f),
                        selected: sel,
                        onSelected: (val) => setState(() {
                          if (val) {
                            _selectedFeatures.add(f);
                          } else {
                            _selectedFeatures.remove(f);
                          }
                        }),
                        selectedColor: AppTheme.accent.withValues(alpha: 0.15),
                        backgroundColor: AppTheme.elevationColor(context, 2),
                        checkmarkColor: AppTheme.accent,
                        labelStyle: TextStyle(
                          fontSize: 12,
                          color: sel
                              ? AppTheme.accent
                              : theme.colorScheme.onSurface.withValues(
                                  alpha: 0.6,
                                ),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        side: BorderSide.none,
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

            // ── Bottom save button ──
            _buildBottomBar(theme, isDark),
          ],
        ),
      ),
    );
  }

  // ─── VIN Scanner + Lookup Field ───────────────────────────────────
  Widget _buildVinScannerAndLookup(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Scanner button
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

        // VIN text field + lookup button
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

  // ─── Bottom bar ───────────────────────────────────────────────────
  Widget _buildBottomBar(ThemeData theme, bool isDark) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(color: AppTheme.elevationColor(context, 1)),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _isSaving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
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
                  widget.existing != null
                      ? 'Update Car'
                      : 'Publish Car for Rental',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    );
  }

  // ─── Reusable widgets ─────────────────────────────────────────────

  Widget _buildSectionLabel(String text, ThemeData theme) {
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
    required String hint,
    required ThemeData theme,
    required bool isDark,
    int maxLines = 1,
    int? maxLength,
    TextInputType keyboardType = TextInputType.text,
    Widget? prefix,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
      validator: validator,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: prefix != null
            ? Padding(
                padding: const EdgeInsets.only(left: 12, right: 8),
                child: prefix,
              )
            : null,
        prefixIconConstraints: prefix != null
            ? const BoxConstraints(minWidth: 0, minHeight: 0)
            : null,
        counterText: '',
        filled: true,
        fillColor: AppTheme.elevationColor(context, 2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }

  Widget _buildSearchableDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required String hint,
    required ThemeData theme,
    required bool isDark,
    bool enabled = true,
    required ValueChanged<String?> onChanged,
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
              ? () => _showSearchSheet(
                  items: items,
                  title: label,
                  current: value,
                  onSelected: onChanged,
                )
              : null,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.elevationColor(context, 2),
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
                          : theme.hintColor.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                Icon(
                  LucideIcons.chevronDown,
                  size: 16,
                  color: enabled ? theme.hintColor : theme.disabledColor,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showSearchSheet({
    required List<String> items,
    required String title,
    required String? current,
    required ValueChanged<String?> onSelected,
  }) {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: StatefulBuilder(
            builder: (ctx, setSheetState) {
              final query = controller.text.toLowerCase();
              final filtered = items
                  .where((i) => i.toLowerCase().contains(query))
                  .toList();
              return Container(
                decoration: BoxDecoration(
                  color: AppTheme.elevationColor(context, 3),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: DraggableScrollableSheet(
                  initialChildSize: 0.6,
                  maxChildSize: 0.85,
                  minChildSize: 0.3,
                  expand: false,
                  builder: (_, scrollCtrl) => Column(
                    children: [
                      const SizedBox(height: 8),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Theme.of(ctx).hintColor.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: TextField(
                          controller: controller,
                          autofocus: true,
                          decoration: InputDecoration(
                            hintText: 'Search $title...',
                            prefixIcon: const Icon(
                              LucideIcons.search,
                              size: 18,
                            ),
                            filled: true,
                            fillColor: AppTheme.elevationColor(ctx, 1),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onChanged: (_) => setSheetState(() {}),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          controller: scrollCtrl,
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final item = filtered[i];
                            final sel = item == current;
                            return ListTile(
                              dense: true,
                              title: Text(
                                item,
                                style: TextStyle(
                                  fontWeight: sel
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: sel ? AppTheme.accent : null,
                                ),
                              ),
                              trailing: sel
                                  ? const Icon(
                                      LucideIcons.check,
                                      size: 16,
                                      color: AppTheme.accent,
                                    )
                                  : null,
                              onTap: () {
                                onSelected(item);
                                Navigator.pop(ctx);
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildChipRow(
    String label,
    ThemeData theme,
    List<String> options,
    String? selected,
    bool isDark,
    ValueChanged<String> onTap,
  ) {
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
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: options.map((o) {
            final sel = selected == o;
            return GestureDetector(
              onTap: () => onTap(o),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: sel
                      ? AppTheme.accent.withValues(alpha: isDark ? 0.25 : 0.12)
                      : isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  o,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                    color: sel ? AppTheme.accent : theme.hintColor,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _infoChip(IconData icon, String label, bool isDark) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
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

  Widget _buildStepper(
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
          _stepperBtn(
            LucideIcons.minus,
            value > min ? () => onChanged(value - 1) : null,
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
          _stepperBtn(
            LucideIcons.plus,
            value < max ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }

  Widget _stepperBtn(IconData icon, VoidCallback? onTap) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: enabled
              ? AppTheme.accent.withValues(alpha: 0.12)
              : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 16,
          color: enabled
              ? AppTheme.accent
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2),
        ),
      ),
    );
  }
}
