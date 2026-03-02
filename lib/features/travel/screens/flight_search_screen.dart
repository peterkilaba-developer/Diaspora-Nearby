import 'package:flutter/material.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/travel/providers/travel_providers.dart';
import 'package:diaspora_nearby/features/travel/widgets/travel_search_interface.dart';
import 'package:diaspora_nearby/features/travel/widgets/travel_management_menu.dart';
import 'package:diaspora_nearby/features/travel/widgets/flight_result_card.dart';
import 'package:diaspora_nearby/features/travel/models/travel_search_result.dart';
import 'package:diaspora_nearby/features/travel/models/airport.dart';
import 'package:diaspora_nearby/features/travel/services/amadeus_service.dart';
import 'package:diaspora_nearby/features/travel/screens/flight_detail_screen.dart';
import 'package:diaspora_nearby/features/travel/widgets/smart_date_picker.dart';
import 'package:diaspora_nearby/features/travel/widgets/travel_skeleton_loader.dart';
import 'package:intl/intl.dart';

class FlightSearchScreen extends ConsumerStatefulWidget {
  const FlightSearchScreen({super.key});

  @override
  ConsumerState<FlightSearchScreen> createState() => _FlightSearchScreenState();
}

class _FlightSearchScreenState extends ConsumerState<FlightSearchScreen> {
  final _originController = TextEditingController();
  final _destController = TextEditingController();
  final _departDateController = TextEditingController();
  final _returnDateController = TextEditingController();
  
  bool _isSearching = false;
  List<FlightOffer> _flightOffers = [];
  bool _isRoundTrip = false; // Default to one-way for auto-search
  bool _showSearchForm = true;

  // Store raw IATA codes separately from display text
  String _originIata = '';
  String _destIata = '';

  // Store selected dates in API format (YYYY-MM-DD)
  String _departDateApi = '';
  String _returnDateApi = '';

  // Airport suggestions
  List<Airport> _originSuggestions = [];
  List<Airport> _destSuggestions = [];
  bool _showOriginSuggestions = false;
  bool _showDestSuggestions = false;

  String? _homeCountry;

  // ── Auto-search state ──
  bool _isAutoSearching = false;
  bool _autoSearchComplete = false;
  int _autoSearchDaysLoaded = 0;
  final int _autoSearchDaysTotal = 5;

  // Date-grouped results: date string → list of offers
  Map<String, List<FlightOffer>> _dateGroupedOffers = {};
  String? _cheapestDate; // Date with cheapest offer

  Airport? _resolvedOriginAirport;
  Airport? _resolvedDestAirport;

  @override
  void initState() {
    super.initState();
    _autoPopulateAndSearch();
  }

  void _setDefaultDates() {
    final today = DateTime.now();
    final tomorrow = today.add(const Duration(days: 1));

    final tomorrowApi = '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';

    _departDateApi = tomorrowApi;
    _departDateController.text = '${tomorrow.month}/${tomorrow.day}/${tomorrow.year}';
  }

  @override
  void dispose() {
    _originController.dispose();
    _destController.dispose();
    _departDateController.dispose();
    _returnDateController.dispose();
    super.dispose();
  }

  /// Auto-populate airports using international airport lookup, then auto-search
  Future<void> _autoPopulateAndSearch() async {
    final userId = ref.read(authRepositoryProvider).currentUser?.uid;
    if (userId == null) return;
    
    final profileData = await ref.read(profileRepositoryProvider).getUserProfile(userId);
    if (profileData == null) return;

    final airportService = ref.read(airportServiceProvider);

    // Resolve origin: closest international airport to current location
    if (profileData.currentLocation?.geometry.location != null) {
      final lat = profileData.currentLocation!.geometry.location.lat;
      final lng = profileData.currentLocation!.geometry.location.lng;
      final originAirport = await airportService.getClosestInternationalAirport(lat, lng);
      if (originAirport != null && mounted) {
        _resolvedOriginAirport = originAirport;
        setState(() {
          _originIata = originAirport.iataCode;
          _originController.text = '${originAirport.iataCode} - ${originAirport.name}';
        });
      }
    }

    // Resolve destination: closest international airport to home location
    if (profileData.homeLocation.geometry?.location != null) {
      final lat = profileData.homeLocation.geometry!.location.lat;
      final lng = profileData.homeLocation.geometry!.location.lng;
      final destAirport = await airportService.getClosestInternationalAirport(lat, lng);
      if (destAirport != null && mounted) {
        _resolvedDestAirport = destAirport;
        setState(() {
          _destIata = destAirport.iataCode;
          _destController.text = '${destAirport.iataCode} - ${destAirport.name}';
        });
      }
    }

    // Store home country for contextual empty state
    if (profileData.homeCountry != null && mounted) {
      setState(() {
        _homeCountry = profileData.homeCountry;
      });
    }

    // Set default dates
    _setDefaultDates();

    // Auto-trigger multi-day search if both airports resolved
    if (_originIata.isNotEmpty && _destIata.isNotEmpty && mounted) {
      _autoSearchMultiDay();
    }
  }

  /// Fire parallel flight searches for the next N days
  Future<void> _autoSearchMultiDay() async {
    if (!mounted) return;

    setState(() {
      _isAutoSearching = true;
      _autoSearchComplete = false;
      _autoSearchDaysLoaded = 0;
      _dateGroupedOffers = {};
      _cheapestDate = null;
      _showSearchForm = false;
    });

    final amadeus = ref.read(amadeusServiceProvider);
    final today = DateTime.now();
    final dateFormat = DateFormat('yyyy-MM-dd');

    // Generate dates starting from tomorrow
    final dates = List.generate(_autoSearchDaysTotal, (i) {
      return dateFormat.format(today.add(Duration(days: i + 1)));
    });

    // Fire parallel requests
    final futures = dates.map((date) async {
      try {
        final offers = await amadeus.searchFlights(
          originIata: _originIata,
          destinationIata: _destIata,
          departureDate: date,
          adults: 1,
          maxResults: 5, // Top 5 per day to keep it manageable
        );
        return MapEntry(date, offers);
      } on AmadeusException {
        return MapEntry(date, <FlightOffer>[]);
      } catch (_) {
        return MapEntry(date, <FlightOffer>[]);
      }
    }).toList();

    // Process results as they come in
    for (final future in futures) {
      final entry = await future;
      if (!mounted) return;

      setState(() {
        _autoSearchDaysLoaded++;
        if (entry.value.isNotEmpty) {
          _dateGroupedOffers[entry.key] = entry.value;
        }

        // Track cheapest date
        _updateCheapestDate();
      });
    }

    if (!mounted) return;
    setState(() {
      _isAutoSearching = false;
      _autoSearchComplete = true;
      // Flatten all results for the standard results view fallback
      _flightOffers = _dateGroupedOffers.values.expand((e) => e).toList();
      _flightOffers.sort((a, b) => a.totalPrice.compareTo(b.totalPrice));
    });
  }

  void _updateCheapestDate() {
    double cheapest = double.infinity;
    String? cheapestDateKey;

    for (final entry in _dateGroupedOffers.entries) {
      for (final offer in entry.value) {
        if (offer.totalPrice < cheapest) {
          cheapest = offer.totalPrice;
          cheapestDateKey = entry.key;
        }
      }
    }

    _cheapestDate = cheapestDateKey;
  }

  Future<void> _searchAirports(String query, {required bool isOrigin}) async {
    if (query.length < 2) {
      setState(() {
        if (isOrigin) {
          _originSuggestions = [];
          _showOriginSuggestions = false;
        } else {
          _destSuggestions = [];
          _showDestSuggestions = false;
        }
      });
      return;
    }

    final airportService = ref.read(airportServiceProvider);
    final results = await airportService.searchAirports(query, limit: 6);

    if (!mounted) return;
    setState(() {
      if (isOrigin) {
        _originSuggestions = results;
        _showOriginSuggestions = results.isNotEmpty;
      } else {
        _destSuggestions = results;
        _showDestSuggestions = results.isNotEmpty;
      }
    });
  }

  void _selectAirport(Airport airport, {required bool isOrigin}) {
    setState(() {
      if (isOrigin) {
        _originIata = airport.iataCode;
        _originController.text = '${airport.iataCode} - ${airport.name}';
        _originSuggestions = [];
        _showOriginSuggestions = false;
      } else {
        _destIata = airport.iataCode;
        _destController.text = '${airport.iataCode} - ${airport.name}';
        _destSuggestions = [];
        _showDestSuggestions = false;
      }
    });
  }

  String _extractIata(String text) {
    if (text.contains(' - ')) return text.split(' - ').first.trim();
    return text.trim();
  }

  /// Standard manual search
  void _handleSearch() async {
    final origin = _originIata.isNotEmpty ? _originIata : _extractIata(_originController.text);
    final dest = _destIata.isNotEmpty ? _destIata : _extractIata(_destController.text);

    if (origin.isEmpty || dest.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select origin and destination airports')),
      );
      return;
    }

    if (_departDateApi.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a departure date')),
      );
      return;
    }

    setState(() {
      _isSearching = true;
      _showOriginSuggestions = false;
      _showDestSuggestions = false;
      _autoSearchComplete = false;
      _dateGroupedOffers = {};
    });

    try {
      final amadeus = ref.read(amadeusServiceProvider);
      final offers = await amadeus.searchFlights(
        originIata: origin,
        destinationIata: dest,
        departureDate: _departDateApi,
        returnDate: _isRoundTrip && _returnDateApi.isNotEmpty ? _returnDateApi : null,
        adults: 1,
        maxResults: 15,
      );

      if (!mounted) return;

      setState(() {
        _isSearching = false;
        _showSearchForm = false;
        _flightOffers = offers;
      });

      if (_flightOffers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No flights found for this route and date')),
        );
        setState(() { _showSearchForm = true; });
      }
    } on AmadeusException catch (e) {
      if (!mounted) return;
      setState(() { _isSearching = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Search error: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() { _isSearching = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connection error: $e')),
      );
    }
  }

  void _handleClear() {
    setState(() {
      _originController.clear();
      _destController.clear();
      _departDateController.clear();
      _returnDateController.clear();
      _departDateApi = '';
      _returnDateApi = '';
      _originIata = '';
      _destIata = '';
      _originSuggestions = [];
      _destSuggestions = [];
      _showOriginSuggestions = false;
      _showDestSuggestions = false;
      _flightOffers.clear();
      _showSearchForm = true;
      _autoSearchComplete = false;
      _dateGroupedOffers = {};
      _cheapestDate = null;
      _autoPopulateAndSearch();
    });
  }

  Future<void> _pickDate(TextEditingController controller, {required bool isDeparture}) async {
    final now = DateTime.now();
    
    DateTime firstDate = now;
    DateTime initialDate = now.add(const Duration(days: 1));
    
    if (isDeparture) {
      if (_departDateApi.isNotEmpty) {
        try {
          initialDate = DateTime.parse(_departDateApi);
        } catch (_) {}
      }
    } else {
      if (_departDateApi.isNotEmpty) {
        try {
          final departDate = DateTime.parse(_departDateApi);
          firstDate = departDate;
          initialDate = departDate;
          if (_returnDateApi.isNotEmpty) {
            final existingReturn = DateTime.parse(_returnDateApi);
            if (existingReturn.isAfter(departDate) || existingReturn.isAtSameMomentAs(departDate)) {
              initialDate = existingReturn;
            }
          }
        } catch (_) {}
      }
    }

    if (initialDate.isBefore(firstDate)) initialDate = firstDate;
    final lastDate = now.add(const Duration(days: 365));
    if (initialDate.isAfter(lastDate)) initialDate = lastDate;

    final date = await SmartDatePicker.show(
      context: context,
      title: isDeparture ? 'Departure Date' : 'Return Date',
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (date != null && mounted) {
      final apiFormat = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final displayFormat = '${date.month}/${date.day}/${date.year}';
      setState(() {
        controller.text = displayFormat;
        if (isDeparture) {
          _departDateApi = apiFormat;
          if (_returnDateApi.isNotEmpty) {
            try {
              final returnDate = DateTime.parse(_returnDateApi);
              if (returnDate.isBefore(date)) {
                _returnDateController.clear();
                _returnDateApi = '';
              }
            } catch (_) {}
          }
        } else {
          _returnDateApi = apiFormat;
        }
      });
    }
  }

  Widget _buildAirportField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required bool isOrigin,
    required List<Airport> suggestions,
    required bool showSuggestions,
  }) {
    final theme = Theme.of(context);
    final inputDecoration = InputDecoration(
      filled: true,
      fillColor: AppTheme.elevationColor(context, 2),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintText: hint,
      prefixIcon: Icon(icon, color: theme.colorScheme.onSurface.withOpacity(0.5)),
      suffixIcon: controller.text.isNotEmpty
          ? IconButton(
              icon: Icon(LucideIcons.x, size: 18, color: theme.colorScheme.onSurface.withOpacity(0.5)),
              onPressed: () => setState(() {
                controller.clear();
                if (isOrigin) {
                  _originIata = '';
                  _originSuggestions = [];
                  _showOriginSuggestions = false;
                } else {
                  _destIata = '';
                  _destSuggestions = [];
                  _showDestSuggestions = false;
                }
              }),
            )
          : null,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: controller,
          decoration: inputDecoration,
          onChanged: (value) => _searchAirports(value, isOrigin: isOrigin),
          onTap: () {
            if (controller.text.length >= 2) {
              _searchAirports(controller.text, isOrigin: isOrigin);
            }
          },
        ),
        if (showSuggestions && suggestions.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: AppTheme.elevationColor(context, 3),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: suggestions.length,
              itemBuilder: (context, index) {
                final airport = suggestions[index];
                return ListTile(
                  dense: true,
                  leading: Icon(LucideIcons.plane, size: 16, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                  title: Text(
                    '${airport.iataCode} - ${airport.name}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${airport.municipality}, ${airport.isoCountry}',
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                  ),
                  onTap: () => _selectAirport(airport, isOrigin: isOrigin),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildSearchForm() {
    final theme = Theme.of(context);
    final inputDecoration = InputDecoration(
      filled: true,
      fillColor: AppTheme.elevationColor(context, 2),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Round Trip / One Way toggle
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _isRoundTrip = true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _isRoundTrip ? theme.colorScheme.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _isRoundTrip ? theme.colorScheme.primary : theme.dividerColor,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Round Trip',
                      style: TextStyle(
                        color: _isRoundTrip ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() {
                    _isRoundTrip = false;
                    _returnDateController.clear();
                    _returnDateApi = '';
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: !_isRoundTrip ? theme.colorScheme.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: !_isRoundTrip ? theme.colorScheme.primary : theme.dividerColor,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'One Way',
                      style: TextStyle(
                        color: !_isRoundTrip ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Origin with autocomplete
        _buildAirportField(
          controller: _originController,
          hint: 'Where from? (city or airport)',
          icon: LucideIcons.planeTakeoff,
          isOrigin: true,
          suggestions: _originSuggestions,
          showSuggestions: _showOriginSuggestions,
        ),
        const SizedBox(height: 10),

        // Destination with autocomplete
        _buildAirportField(
          controller: _destController,
          hint: 'Where to? (city or airport)',
          icon: LucideIcons.planeLanding,
          isOrigin: false,
          suggestions: _destSuggestions,
          showSuggestions: _showDestSuggestions,
        ),
        const SizedBox(height: 10),

        // Dates in a single row
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _departDateController,
                readOnly: true,
                onTap: () => _pickDate(_departDateController, isDeparture: true),
                decoration: inputDecoration.copyWith(
                  hintText: 'Depart',
                  prefixIcon: Icon(LucideIcons.calendarDays, size: 18, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            if (_isRoundTrip) ...[
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _returnDateController,
                  readOnly: true,
                  onTap: () => _pickDate(_returnDateController, isDeparture: false),
                  decoration: inputDecoration.copyWith(
                    hintText: 'Return',
                    prefixIcon: Icon(LucideIcons.calendarCheck, size: 18, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  // ── Auto-search results UI ──

  Widget _buildAutoSearchResults() {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('yyyy-MM-dd');
    final displayDateFormat = DateFormat('EEE, MMM d');

    // Sort dates chronologically
    final sortedDates = _dateGroupedOffers.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Route header
        Container(
          margin: const EdgeInsets.symmetric(
            horizontal: AppTheme.pageHorizontalPadding,
            vertical: 8,
          ),
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.cardDecoration(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(LucideIcons.plane, size: 20, color: AppTheme.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$_originIata → $_destIata',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  // Refresh button
                  IconButton(
                    icon: Icon(
                      LucideIcons.refreshCw,
                      size: 18,
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                    onPressed: _autoSearchMultiDay,
                    tooltip: 'Refresh flights',
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    LucideIcons.mapPin,
                    size: 14,
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _resolvedOriginAirport != null && _resolvedDestAirport != null
                          ? '${_resolvedOriginAirport!.municipality} → ${_resolvedDestAirport!.municipality}'
                          : 'One-way flights',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ),
                ],
              ),
              if (_isAutoSearching) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: _autoSearchDaysLoaded / _autoSearchDaysTotal,
                        color: AppTheme.accent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Checking $_autoSearchDaysLoaded of $_autoSearchDaysTotal days...',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 8),
                Text(
                  _dateGroupedOffers.isEmpty
                      ? 'No flights found for the next $_autoSearchDaysTotal days'
                      : 'Showing best flights for next $_autoSearchDaysTotal days • One way',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
              ],
            ],
          ),
        ),

        // Date-grouped flights
        ...sortedDates.map((dateStr) {
          final offers = _dateGroupedOffers[dateStr]!;
          final date = dateFormat.parse(dateStr);
          final isCheapest = dateStr == _cheapestDate;
          final cheapestPrice = offers
              .map((o) => o.totalPrice)
              .reduce((a, b) => a < b ? a : b);

          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.pageHorizontalPadding,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date header
                Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.calendar,
                        size: 16,
                        color: isCheapest
                            ? Colors.green
                            : theme.colorScheme.onSurface.withOpacity(0.5),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        displayDateFormat.format(date),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: isCheapest
                              ? Colors.green
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                      if (isCheapest) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Cheapest',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.green,
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      Text(
                        'from \$${cheapestPrice.toStringAsFixed(0)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isCheapest
                              ? Colors.green
                              : AppTheme.accent,
                        ),
                      ),
                    ],
                  ),
                ),
                // Flight cards for this date
                ...offers.map((offer) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FlightResultCard(
                    offer: offer,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => FlightDetailScreen(offer: offer),
                        ),
                      );
                    },
                  ),
                )),
              ],
            ),
          );
        }),

        // Bottom padding
        SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool hasAutoResults = _autoSearchComplete && _dateGroupedOffers.isNotEmpty;
    final bool showAppBarSearch = (!_showSearchForm && _flightOffers.isNotEmpty) || hasAutoResults;

    // If auto-search produced results, show the date-grouped view
    if (hasAutoResults && !_showSearchForm && !_isSearching) {
      return GestureDetector(
        onTap: () {
          setState(() {
            _showOriginSuggestions = false;
            _showDestSuggestions = false;
          });
          FocusScope.of(context).unfocus();
        },
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          appBar: AppBar(
            titleSpacing: 0,
            title: const Text('Flight Search'),
            elevation: 0,
            backgroundColor: Colors.transparent,
            actions: [
              IconButton(
                icon: const Icon(LucideIcons.search),
                tooltip: 'Custom Search',
                onPressed: () {
                  setState(() {
                    _showSearchForm = true;
                  });
                },
              ),
              const TravelManagementMenu(category: 'Flight'),
            ],
          ),
          body: SingleChildScrollView(
            child: _buildAutoSearchResults(),
          ),
        ),
      );
    }

    // Auto-search in progress (no results yet)
    if (_isAutoSearching && _dateGroupedOffers.isEmpty) {
      return Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          titleSpacing: 0,
          title: const Text('Flight Search'),
          elevation: 0,
          backgroundColor: Colors.transparent,
          actions: [
            IconButton(
              icon: const Icon(LucideIcons.search),
              tooltip: 'Custom Search',
              onPressed: () {
                setState(() {
                  _showSearchForm = true;
                  _isAutoSearching = false;
                });
              },
            ),
            const TravelManagementMenu(category: 'Flight'),
          ],
        ),
        body: const TravelApiSkeletonLoader(
          label: 'Finding flights...',
        ),
      );
    }

    // Fallback: standard search interface (manual search or auto-search showing partial results)
    final dummyResults = _flightOffers.map((o) => TravelSearchResult(
      id: o.id, title: '', subtitle: '', price: '',
    )).toList();

    return GestureDetector(
      onTap: () {
        setState(() {
          _showOriginSuggestions = false;
          _showDestSuggestions = false;
        });
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          titleSpacing: 0,
          title: const Text('Flight Search'),
          elevation: 0,
          backgroundColor: Colors.transparent,
          actions: [
            if (showAppBarSearch)
              IconButton(
                icon: const Icon(LucideIcons.search),
                tooltip: 'Modify Search',
                onPressed: () {
                  setState(() {
                    _showSearchForm = true;
                  });
                },
              ),
            const TravelManagementMenu(category: 'Flight'),
          ],
        ),
        body: TravelSearchInterface(
          title: 'Book a Flight',
          icon: LucideIcons.plane,
          searchForm: _buildSearchForm(),
          isSearching: _isSearching,
          results: dummyResults,
          onClear: _handleClear,
          onSearch: _handleSearch,
          showSearchForm: _showSearchForm,
          emptyStateMessage: _homeCountry != null
              ? 'Search flights to $_homeCountry or your next adventure'
              : 'Search flights to your next adventure',
          customResultCount: _flightOffers.length,
          customResultBuilder: (context, index) {
            final offer = _flightOffers[index];
            return FlightResultCard(
              offer: offer,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FlightDetailScreen(offer: offer),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
