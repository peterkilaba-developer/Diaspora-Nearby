import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/core/data/countries.dart' as country_data;
import 'package:diaspora_nearby/features/shared/widgets/country_picker_sheet.dart';
import 'package:diaspora_nearby/features/travel/services/amadeus_service.dart';
import 'package:diaspora_nearby/features/travel/providers/travel_providers.dart';
import 'package:diaspora_nearby/features/travel/screens/booking_confirmation_screen.dart';
import 'package:diaspora_nearby/features/travel/widgets/smart_date_picker.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';

/// Multi-step flight booking screen:
/// Step 0 — Traveler count + details per traveler
/// Step 1 — Payment (credit card)
/// Step 2 — Review & confirm price & book
class FlightBookingScreen extends ConsumerStatefulWidget {
  final FlightOffer offer;

  const FlightBookingScreen({super.key, required this.offer});

  @override
  ConsumerState<FlightBookingScreen> createState() =>
      _FlightBookingScreenState();
}

class _TravelerData {
  final firstNameC = TextEditingController();
  final lastNameC = TextEditingController();
  final emailC = TextEditingController();
  final phoneC = TextEditingController();
  final dobC = TextEditingController();
  final passportC = TextEditingController();
  final passportExpiryC = TextEditingController();
  final nationalityC = TextEditingController(text: 'US');
  // Address fields (primary traveler only)
  final addressLineC = TextEditingController();
  final cityC = TextEditingController();
  final postalCodeC = TextEditingController();
  String gender = 'MALE';
  String dobApi = '';
  String passportExpiryApi = '';
  country_data.Country? selectedCountry;

  void dispose() {
    firstNameC.dispose();
    lastNameC.dispose();
    emailC.dispose();
    phoneC.dispose();
    dobC.dispose();
    passportC.dispose();
    passportExpiryC.dispose();
    nationalityC.dispose();
    addressLineC.dispose();
    cityC.dispose();
    postalCodeC.dispose();
  }
}

class _FlightBookingScreenState extends ConsumerState<FlightBookingScreen> {
  static const _radius = 15.0;
  final _travelerFormKey = GlobalKey<FormState>();
  final _paymentFormKey = GlobalKey<FormState>();
  int _currentStep = 0;
  bool _isProcessing = false;
  String? _errorMessage;

  // Travelers (at least 1)
  final List<_TravelerData> _travelers = [_TravelerData()];
  int _expandedTravelerIndex = 0;

  // Payment fields
  final _cardNumberController = TextEditingController();
  final _cardExpiryController = TextEditingController();
  final _cardCvvController = TextEditingController();
  final _cardHolderController = TextEditingController();

  // Confirmed pricing
  Map<String, dynamic>? _confirmedOfferJson;
  FlightOffer? _confirmedOffer;

  @override
  void initState() {
    super.initState();
    // Sticky form: auto-populate Traveler 1 from user profile
    _autoFillFromProfile();
  }

  void _autoFillFromProfile() {
    final profile = ref.read(userProfileProvider).value;
    if (profile == null) return;

    final t = _travelers.first;

    // Name
    if (profile.firstName.isNotEmpty) t.firstNameC.text = profile.firstName;
    if (profile.lastName.isNotEmpty) t.lastNameC.text = profile.lastName;

    // Phone
    if (profile.phone.isNotEmpty) t.phoneC.text = profile.phone;

    // Email from Firebase Auth (phone-based auth may not have email)
    final authUser = ref.read(authRepositoryProvider).currentUser;
    if (authUser?.email != null && authUser!.email!.isNotEmpty) {
      t.emailC.text = authUser.email!;
    }

    // Date of birth
    if (profile.dateOfBirth != null && profile.dateOfBirth!.isNotEmpty) {
      t.dobApi = profile.dateOfBirth!;
      try {
        final dob = DateTime.parse(profile.dateOfBirth!);
        t.dobC.text = '${dob.month}/${dob.day}/${dob.year}';
      } catch (_) {
        t.dobC.text = profile.dateOfBirth!;
      }
    }

    // Nationality from home country code (e.g. 'US', 'GH')
    if (profile.homeCountryCode != null &&
        profile.homeCountryCode!.isNotEmpty) {
      final code = profile.homeCountryCode!.toUpperCase();
      t.nationalityC.text = code;
      t.selectedCountry = country_data.getCountryByCode(code);
    }

    // Pre-fill card holder name
    if (profile.firstName.isNotEmpty && profile.lastName.isNotEmpty) {
      _cardHolderController.text = '${profile.firstName} ${profile.lastName}'
          .toUpperCase();
    }
  }

  @override
  void dispose() {
    for (final t in _travelers) {
      t.dispose();
    }
    _cardNumberController.dispose();
    _cardExpiryController.dispose();
    _cardCvvController.dispose();
    _cardHolderController.dispose();
    super.dispose();
  }

  String get _stepTitle {
    switch (_currentStep) {
      case 0:
        return 'Travelers (${_travelers.length})';
      case 1:
        return 'Payment';
      case 2:
        return 'Review & Book';
      default:
        return 'Book Flight';
    }
  }

  void _addTraveler() {
    if (_travelers.length >= 9) return;
    setState(() {
      _travelers.add(_TravelerData());
      _expandedTravelerIndex = _travelers.length - 1;
    });
  }

  void _removeTraveler(int index) {
    if (_travelers.length <= 1) return;
    setState(() {
      _travelers[index].dispose();
      _travelers.removeAt(index);
      if (_expandedTravelerIndex >= _travelers.length) {
        _expandedTravelerIndex = _travelers.length - 1;
      }
    });
  }

  // ── Step 0 → 1 ──
  void _goToPayment() {
    if (_travelerFormKey.currentState!.validate()) {
      if (_cardHolderController.text.isEmpty) {
        _cardHolderController.text =
            '${_travelers.first.firstNameC.text.trim()} ${_travelers.first.lastNameC.text.trim()}'
                .toUpperCase();
      }
      setState(() {
        _currentStep = 1;
        _errorMessage = null;
      });
    }
  }

  // ── Step 1 → 2 ──
  Future<void> _goToReview() async {
    if (!_paymentFormKey.currentState!.validate()) return;

    if (widget.offer.rawJson == null) {
      setState(() => _errorMessage = 'Flight data unavailable for pricing.');
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final amadeus = ref.read(amadeusServiceProvider);
      final confirmedJson = await amadeus.confirmFlightPrice(
        widget.offer.rawJson!,
      );
      final confirmedOffer = FlightOffer.fromJson(confirmedJson);

      if (mounted) {
        setState(() {
          _confirmedOfferJson = confirmedJson;
          _confirmedOffer = confirmedOffer;
          _isProcessing = false;
          _currentStep = 2;
        });
      }
    } on AmadeusException catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _errorMessage = 'Price confirmation failed: ${e.message}';
        });
      }
    } catch (e, s) {
      debugPrint('✈️ [FlightBooking] confirmPrice error: $e\n$s');
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _errorMessage = 'Price error: $e';
        });
      }
    }
  }

  // ── Step 2: Book ──
  Future<void> _createBooking() async {
    if (_confirmedOfferJson == null) return;

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final amadeus = ref.read(amadeusServiceProvider);

      final travelersList = _travelers.asMap().entries.map((entry) {
        final i = entry.key;
        final t = entry.value;
        final natCode = t.nationalityC.text.trim().toUpperCase();
        final dialCode = t.selectedCountry?.dialCode.replaceAll('+', '') ?? '1';
        return {
          'id': '${i + 1}',
          'dateOfBirth': t.dobApi,
          'name': {
            'firstName': t.firstNameC.text.trim().toUpperCase(),
            'lastName': t.lastNameC.text.trim().toUpperCase(),
          },
          'gender': t.gender,
          'contact': {
            'emailAddress': t.emailC.text.trim(),
            'phones': [
              {
                'deviceType': 'MOBILE',
                'countryCallingCode': dialCode,
                'number': t.phoneC.text.trim().replaceAll(RegExp(r'[^\d]'), ''),
              },
            ],
          },
          'documents': [
            {
              'documentType': 'PASSPORT',
              'number': t.passportC.text.trim().toUpperCase(),
              'expiryDate': t.passportExpiryApi.isNotEmpty
                  ? t.passportExpiryApi
                  : '2030-12-31',
              'issuanceCountry': natCode,
              'validityCountry': natCode,
              'nationality': natCode,
              'holder': i == 0,
            },
          ],
        };
      }).toList();

      final primary = _travelers.first;
      final primaryDialCode =
          primary.selectedCountry?.dialCode.replaceAll('+', '') ?? '1';
      final primaryNat = primary.nationalityC.text.trim().toUpperCase();
      final contact = {
        'addresseeName': {
          'firstName': primary.firstNameC.text.trim().toUpperCase(),
          'lastName': primary.lastNameC.text.trim().toUpperCase(),
        },
        'purpose': 'STANDARD',
        'phones': [
          {
            'deviceType': 'MOBILE',
            'countryCallingCode': primaryDialCode,
            'number': primary.phoneC.text.trim().replaceAll(
              RegExp(r'[^\d]'),
              '',
            ),
          },
        ],
        'emailAddress': primary.emailC.text.trim(),
        'address': {
          'lines': [
            primary.addressLineC.text.trim().isNotEmpty
                ? primary.addressLineC.text.trim()
                : '123 Main Street',
          ],
          'postalCode': primary.postalCodeC.text.trim().isNotEmpty
              ? primary.postalCodeC.text.trim()
              : '10001',
          'cityName': primary.cityC.text.trim().isNotEmpty
              ? primary.cityC.text.trim().toUpperCase()
              : 'NEW YORK',
          'countryCode': primaryNat,
        },
      };

      final payment = {
        'cardNumber': _cardNumberController.text.trim().replaceAll(' ', ''),
        'expiry': _cardExpiryController.text.trim(),
        'holder': _cardHolderController.text.trim(),
      };

      final order = await amadeus.createFlightOrder(
        confirmedOfferJson: _confirmedOfferJson!,
        travelers: travelersList,
        contact: contact,
        payment: payment,
      );

      if (context.mounted) {
        // ── Save booking to Firestore ──
        final uid = ref.read(authRepositoryProvider).currentUser?.uid;
        final departureDate =
            widget.offer.itineraries.isNotEmpty &&
                widget.offer.itineraries.first.segments.isNotEmpty
            ? widget.offer.itineraries.first.segments.first.departureAt
            : '';
        final totalPrice = (_confirmedOffer ?? widget.offer).totalPrice;
        final currency = (_confirmedOffer ?? widget.offer).currency;
        final passengerName =
            '${primary.firstNameC.text} ${primary.lastNameC.text}${_travelers.length > 1 ? ' +${_travelers.length - 1}' : ''}';

        if (uid != null) {
          try {
            await FirebaseFirestore.instance
                .collection('flight_bookings')
                .doc(order.id)
                .set({
                  'userId': uid,
                  'orderId': order.id,
                  'pnrReference': order.pnrReference ?? 'N/A',
                  'passengerName': passengerName,
                  'passengerNames': _travelers
                      .map(
                        (t) =>
                            '${t.firstNameC.text.trim()} ${t.lastNameC.text.trim()}',
                      )
                      .toList(),
                  'route': widget.offer.routeSummary,
                  'departureDate': departureDate,
                  'totalPrice': totalPrice,
                  'currency': currency,
                  'status': 'confirmed',
                  'bookingType': 'flight',
                  'travelerCount': _travelers.length,
                  'createdAt': FieldValue.serverTimestamp(),
                });
          } catch (e) {
            debugPrint('⚠️ Failed to save booking to Firestore: $e');
          }
        }

        if (context.mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => BookingConfirmationScreen(
                bookingType: 'Flight',
                bookingId: order.id,
                pnrReference: order.pnrReference ?? 'N/A',
                passengerName: passengerName,
                route: widget.offer.routeSummary,
                date: departureDate,
                price: '\$${totalPrice.toStringAsFixed(2)}',
                currency: currency,
              ),
            ),
          );
        }
      }
    } on AmadeusException catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _errorMessage = 'Booking failed: ${e.message}';
        });
      }
    } catch (e, s) {
      debugPrint('✈️ [FlightBooking] createBooking error: $e\n$s');
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _errorMessage = 'Booking error: $e';
        });
      }
    }
  }

  Future<void> _pickDateOfBirth(int travelerIndex) async {
    final now = DateTime.now();
    final date = await SmartDatePicker.show(
      context: context,
      title: 'Date of Birth',
      initialDate: DateTime(1990, 1, 1),
      firstDate: DateTime(1920),
      lastDate: now,
      shortcuts: [],
    );
    if (date != null && mounted) {
      final t = _travelers[travelerIndex];
      setState(() {
        t.dobApi =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        t.dobC.text = '${date.month}/${date.day}/${date.year}';
      });
    }
  }

  Future<void> _pickPassportExpiry(int travelerIndex) async {
    final now = DateTime.now();
    final date = await SmartDatePicker.show(
      context: context,
      title: 'Passport Expiry Date',
      initialDate: now.add(const Duration(days: 365)),
      firstDate: now,
      lastDate: DateTime(now.year + 15),
      shortcuts: [],
    );
    if (date != null && mounted) {
      final t = _travelers[travelerIndex];
      setState(() {
        t.passportExpiryApi =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        t.passportExpiryC.text = '${date.month}/${date.day}/${date.year}';
      });
    }
  }

  void _pickNationality(int travelerIndex) {
    final t = _travelers[travelerIndex];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: CountryPickerSheet(
          selectedCountry: t.selectedCountry,
          showDialCode: false,
          onCountrySelected: (country) {
            Navigator.pop(context);
            setState(() {
              t.selectedCountry = country;
              t.nationalityC.text = country.code.toUpperCase();
            });
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final offer = _confirmedOffer ?? widget.offer;

    return Scaffold(
      backgroundColor: AppTheme.elevationColor(context, 0),
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(_stepTitle),
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () {
            if (_currentStep > 0) {
              setState(() {
                _currentStep--;
                _errorMessage = null;
              });
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Column(
          children: [
            _buildStepIndicator(theme),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  32 + MediaQuery.of(context).padding.bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFlightSummary(theme, offer),
                    const SizedBox(height: 20),

                    if (_errorMessage != null) ...[
                      _buildErrorBanner(),
                      const SizedBox(height: 16),
                    ],

                    if (_currentStep == 0)
                      _buildTravelerStep(theme)
                    else if (_currentStep == 1)
                      _buildPaymentForm(theme)
                    else
                      _buildReviewStep(theme, offer),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  STEP INDICATOR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStepIndicator(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          _stepDot(theme, 0, 'Travelers'),
          _stepLine(theme, 0),
          _stepDot(theme, 1, 'Payment'),
          _stepLine(theme, 1),
          _stepDot(theme, 2, 'Review'),
        ],
      ),
    );
  }

  Widget _stepDot(ThemeData theme, int step, String label) {
    final isActive = _currentStep >= step;
    final isCurrent = _currentStep == step;
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive
                  ? AppTheme.accent
                  : AppTheme.elevationColor(context, 2),
              border: isCurrent
                  ? Border.all(color: AppTheme.accent, width: 2)
                  : null,
            ),
            child: Center(
              child: isActive && !isCurrent
                  ? const Icon(LucideIcons.check, size: 14, color: Colors.white)
                  : Text(
                      '${step + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isActive
                            ? Colors.white
                            : theme.colorScheme.onSurface.withValues(
                                alpha: 0.4,
                              ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
              color: isActive
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepLine(ThemeData theme, int beforeStep) {
    final isActive = _currentStep > beforeStep;
    return Container(
      height: 2,
      width: 24,
      margin: const EdgeInsets.only(bottom: 14),
      color: isActive
          ? AppTheme.accent
          : theme.colorScheme.onSurface.withValues(alpha: 0.1),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  FLIGHT SUMMARY HEADER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildFlightSummary(ThemeData theme, FlightOffer offer) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.elevationColor(context, 1),
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              LucideIcons.plane,
              color: AppTheme.accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  offer.routeSummary,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${offer.stopsDescription} · ${offer.durationFormatted}',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${offer.totalPrice.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.accent,
                ),
              ),
              Text(
                offer.currency,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  ERROR BANNER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.alertTriangle, size: 16, color: Colors.red[400]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(fontSize: 12, color: Colors.red[400]),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  STEP 0 — TRAVELERS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTravelerStep(ThemeData theme) {
    return Form(
      key: _travelerFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Traveler count stepper ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.elevationColor(context, 1),
              borderRadius: BorderRadius.circular(_radius),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.users,
                  size: 20,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Travelers',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        '${_travelers.length} passenger${_travelers.length > 1 ? 's' : ''}',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Minus button
                _stepperButton(
                  theme,
                  icon: LucideIcons.minus,
                  enabled: _travelers.length > 1,
                  onTap: () => _removeTraveler(_travelers.length - 1),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                    '${_travelers.length}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                // Plus button
                _stepperButton(
                  theme,
                  icon: LucideIcons.plus,
                  enabled: _travelers.length < 9,
                  onTap: _addTraveler,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Traveler forms (accordion) ──
          ...List.generate(_travelers.length, (i) {
            return _buildTravelerCard(theme, i);
          }),

          const SizedBox(height: 24),

          _buildContinueButton(
            onPressed: _goToPayment,
            label: 'Continue to Payment',
            icon: LucideIcons.arrowRight,
          ),
        ],
      ),
    );
  }

  Widget _stepperButton(
    ThemeData theme, {
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: enabled
              ? AppTheme.accent.withValues(alpha: 0.1)
              : theme.colorScheme.onSurface.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: enabled
                ? AppTheme.accent.withValues(alpha: 0.3)
                : theme.colorScheme.onSurface.withValues(alpha: 0.08),
          ),
        ),
        child: Icon(
          icon,
          size: 16,
          color: enabled
              ? AppTheme.accent
              : theme.colorScheme.onSurface.withValues(alpha: 0.2),
        ),
      ),
    );
  }

  Widget _buildTravelerCard(ThemeData theme, int index) {
    final t = _travelers[index];
    final isExpanded = _expandedTravelerIndex == index;
    final isPrimary = index == 0;

    final inputDecoration = InputDecoration(
      filled: true,
      fillColor: AppTheme.elevationColor(context, 2),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.elevationColor(context, 1),
        borderRadius: BorderRadius.circular(_radius),
        border: isExpanded
            ? Border.all(color: AppTheme.accent.withValues(alpha: 0.3))
            : null,
      ),
      child: Column(
        children: [
          // Header (tap to expand/collapse)
          InkWell(
            onTap: () => setState(() => _expandedTravelerIndex = index),
            borderRadius: BorderRadius.circular(_radius),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.accent.withValues(
                        alpha: isExpanded ? 0.15 : 0.08,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.firstNameC.text.isNotEmpty
                              ? '${t.firstNameC.text} ${t.lastNameC.text}'
                              : isPrimary
                              ? 'Primary Traveler'
                              : 'Traveler ${index + 1}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        if (isPrimary)
                          const Text(
                            'Main contact',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppTheme.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!isPrimary)
                    GestureDetector(
                      onTap: () => _removeTraveler(index),
                      child: Icon(
                        LucideIcons.trash2,
                        size: 16,
                        color: Colors.red.withValues(alpha: 0.6),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Icon(
                    isExpanded
                        ? LucideIcons.chevronUp
                        : LucideIcons.chevronDown,
                    size: 18,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ],
              ),
            ),
          ),

          // Expanded form
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 12),

                  // Name row
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: t.firstNameC,
                          textCapitalization: TextCapitalization.words,
                          decoration: inputDecoration.copyWith(
                            hintText: 'First Name *',
                            prefixIcon: Icon(
                              LucideIcons.user,
                              size: 18,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                          style: const TextStyle(fontSize: 13),
                          validator: (v) =>
                              (v?.trim().isEmpty ?? true) ? 'Required' : null,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: t.lastNameC,
                          textCapitalization: TextCapitalization.words,
                          decoration: inputDecoration.copyWith(
                            hintText: 'Last Name *',
                          ),
                          style: const TextStyle(fontSize: 13),
                          validator: (v) =>
                              (v?.trim().isEmpty ?? true) ? 'Required' : null,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Gender
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.elevationColor(context, 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          LucideIcons.userCircle,
                          size: 18,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Gender',
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                        const Spacer(),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'MALE',
                              label: Text(
                                'Male',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            ButtonSegment(
                              value: 'FEMALE',
                              label: Text(
                                'Female',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                          selected: {t.gender},
                          onSelectionChanged: (v) =>
                              setState(() => t.gender = v.first),
                          style: ButtonStyle(
                            backgroundColor: WidgetStateProperty.resolveWith((
                              states,
                            ) {
                              if (states.contains(WidgetState.selected)) {
                                return AppTheme.accent.withValues(alpha: 0.15);
                              }
                              return Colors.transparent;
                            }),
                            foregroundColor: WidgetStateProperty.resolveWith((
                              states,
                            ) {
                              if (states.contains(WidgetState.selected)) {
                                return AppTheme.accent;
                              }
                              return theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              );
                            }),
                            side: WidgetStateProperty.all(
                              BorderSide(
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.1,
                                ),
                              ),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // DOB
                  TextFormField(
                    controller: t.dobC,
                    readOnly: true,
                    onTap: () => _pickDateOfBirth(index),
                    decoration: inputDecoration.copyWith(
                      hintText: 'Date of Birth *',
                      prefixIcon: Icon(
                        LucideIcons.cake,
                        size: 18,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                    style: const TextStyle(fontSize: 13),
                    validator: (v) =>
                        (v?.trim().isEmpty ?? true) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),

                  // Contact — only for primary traveler
                  if (isPrimary) ...[
                    _sectionHeader(theme, 'CONTACT'),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: t.emailC,
                      keyboardType: TextInputType.emailAddress,
                      decoration: inputDecoration.copyWith(
                        hintText: 'Email Address *',
                        prefixIcon: Icon(
                          LucideIcons.mail,
                          size: 18,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
                      style: const TextStyle(fontSize: 13),
                      validator: (v) {
                        if (v?.trim().isEmpty ?? true) return 'Required';
                        if (!v!.contains('@')) return 'Invalid email';
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),

                    TextFormField(
                      controller: t.phoneC,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[\d\s\-\+\(\)]'),
                        ),
                      ],
                      decoration: inputDecoration.copyWith(
                        hintText: 'Phone Number *',
                        prefixIcon: Icon(
                          LucideIcons.phone,
                          size: 18,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
                      style: const TextStyle(fontSize: 13),
                      validator: (v) =>
                          (v?.trim().isEmpty ?? true) ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Travel document
                  _sectionHeader(theme, 'TRAVEL DOCUMENT'),
                  const SizedBox(height: 12),

                  // Nationality — country picker
                  GestureDetector(
                    onTap: () => _pickNationality(index),
                    child: AbsorbPointer(
                      child: TextFormField(
                        controller: t.nationalityC,
                        decoration: inputDecoration.copyWith(
                          hintText: 'Nationality *',
                          prefixIcon: Padding(
                            padding: const EdgeInsets.only(left: 12, right: 4),
                            child: Text(
                              t.selectedCountry?.flag ?? '🏳️',
                              style: const TextStyle(fontSize: 20),
                            ),
                          ),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 0,
                          ),
                          suffixIcon: Icon(
                            LucideIcons.chevronDown,
                            size: 16,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.4,
                            ),
                          ),
                        ),
                        style: const TextStyle(fontSize: 13),
                        validator: (v) => (v?.trim().length != 2)
                            ? 'Select nationality'
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  TextFormField(
                    controller: t.passportC,
                    textCapitalization: TextCapitalization.characters,
                    decoration: inputDecoration.copyWith(
                      hintText: 'Passport Number *',
                      prefixIcon: Icon(
                        LucideIcons.bookOpen,
                        size: 18,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                    style: const TextStyle(fontSize: 13),
                    validator: (v) =>
                        (v?.trim().isEmpty ?? true) ? 'Required' : null,
                  ),
                  const SizedBox(height: 10),

                  // Passport expiry date
                  TextFormField(
                    controller: t.passportExpiryC,
                    readOnly: true,
                    onTap: () => _pickPassportExpiry(index),
                    decoration: inputDecoration.copyWith(
                      hintText: 'Passport Expiry Date *',
                      prefixIcon: Icon(
                        LucideIcons.calendarCheck,
                        size: 18,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                    style: const TextStyle(fontSize: 13),
                    validator: (v) =>
                        (v?.trim().isEmpty ?? true) ? 'Required' : null,
                  ),

                  // Address fields — only for primary traveler
                  if (isPrimary) ...[
                    const SizedBox(height: 16),
                    _sectionHeader(theme, 'ADDRESS'),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: t.addressLineC,
                      textCapitalization: TextCapitalization.words,
                      decoration: inputDecoration.copyWith(
                        hintText: 'Street Address *',
                        prefixIcon: Icon(
                          LucideIcons.mapPin,
                          size: 18,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
                      style: const TextStyle(fontSize: 13),
                      validator: (v) =>
                          (v?.trim().isEmpty ?? true) ? 'Required' : null,
                    ),
                    const SizedBox(height: 10),

                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: t.cityC,
                            textCapitalization: TextCapitalization.words,
                            decoration: inputDecoration.copyWith(
                              hintText: 'City *',
                            ),
                            style: const TextStyle(fontSize: 13),
                            validator: (v) =>
                                (v?.trim().isEmpty ?? true) ? 'Required' : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 120,
                          child: TextFormField(
                            controller: t.postalCodeC,
                            textCapitalization: TextCapitalization.characters,
                            decoration: inputDecoration.copyWith(
                              hintText: 'Postal Code',
                            ),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  STEP 1 — PAYMENT
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPaymentForm(ThemeData theme) {
    final inputDecoration = InputDecoration(
      filled: true,
      fillColor: AppTheme.elevationColor(context, 2),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );

    return Form(
      key: _paymentFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Security notice
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.elevationColor(context, 1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  LucideIcons.shieldCheck,
                  size: 16,
                  color: Color(0xFF4CAF50),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your payment details are secure and encrypted.',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          _sectionHeader(theme, 'CARD DETAILS'),
          const SizedBox(height: 12),

          // Card number
          TextFormField(
            controller: _cardNumberController,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              _CardNumberFormatter(),
            ],
            decoration: inputDecoration.copyWith(
              hintText: 'Card Number *',
              prefixIcon: Icon(
                LucideIcons.creditCard,
                size: 18,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              suffixIcon: _buildCardBrandIcon(),
            ),
            style: const TextStyle(fontSize: 14, letterSpacing: 1.5),
            validator: (v) {
              final digits = v?.replaceAll(' ', '') ?? '';
              if (digits.length < 13) return 'Invalid card number';
              return null;
            },
          ),
          const SizedBox(height: 10),

          // Card holder
          TextFormField(
            controller: _cardHolderController,
            textCapitalization: TextCapitalization.characters,
            decoration: inputDecoration.copyWith(
              hintText: 'Cardholder Name *',
              prefixIcon: Icon(
                LucideIcons.user,
                size: 18,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            style: const TextStyle(fontSize: 13),
            validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null,
          ),
          const SizedBox(height: 10),

          // Expiry + CVV
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _cardExpiryController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    _ExpiryDateFormatter(),
                  ],
                  decoration: inputDecoration.copyWith(
                    hintText: 'MM/YY *',
                    prefixIcon: Icon(
                      LucideIcons.calendar,
                      size: 18,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  style: const TextStyle(fontSize: 14, letterSpacing: 1.5),
                  validator: (v) {
                    if (v == null || v.length < 5) return 'MM/YY';
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _cardCvvController,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 4,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: inputDecoration.copyWith(
                    hintText: 'CVV *',
                    counterText: '',
                    prefixIcon: Icon(
                      LucideIcons.lock,
                      size: 18,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  style: const TextStyle(fontSize: 14, letterSpacing: 2),
                  validator: (v) {
                    if (v == null || v.length < 3) return 'Invalid';
                    return null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          _buildContinueButton(
            onPressed: _isProcessing ? null : _goToReview,
            label: _isProcessing ? 'Confirming Price...' : 'Continue to Review',
            icon: _isProcessing ? null : LucideIcons.arrowRight,
            isLoading: _isProcessing,
          ),
        ],
      ),
    );
  }

  Widget? _buildCardBrandIcon() {
    final digits = _cardNumberController.text.replaceAll(' ', '');
    if (digits.isEmpty) return null;

    String brand = '💳';
    if (digits.startsWith('4')) {
      brand = 'VISA';
    } else if (digits.startsWith('5') || digits.startsWith('2')) {
      brand = 'MC';
    } else if (digits.startsWith('3')) {
      brand = 'AMEX';
    } else if (digits.startsWith('6')) {
      brand = 'DISC';
    }

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Text(
        brand,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: AppTheme.accent,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  STEP 2 — REVIEW & BOOK
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildReviewStep(ThemeData theme, FlightOffer offer) {
    final maskedCard = _maskedCardNumber();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Travelers summary
        _sectionHeader(theme, 'TRAVELERS (${_travelers.length})'),
        const SizedBox(height: 8),
        ...List.generate(_travelers.length, (i) {
          final t = _travelers[i];
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.elevationColor(context, 1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _reviewRow(
                  theme,
                  LucideIcons.user,
                  '${t.firstNameC.text} ${t.lastNameC.text}${i == 0 ? ' (Primary)' : ''}',
                ),
                _reviewRow(
                  theme,
                  LucideIcons.flag,
                  '${t.selectedCountry?.flag ?? ''} ${t.selectedCountry?.name ?? t.nationalityC.text}',
                ),
                _reviewRow(
                  theme,
                  LucideIcons.bookOpen,
                  'Passport: ${t.passportC.text}',
                ),
                if (t.passportExpiryC.text.isNotEmpty)
                  _reviewRow(
                    theme,
                    LucideIcons.calendarCheck,
                    'Expires: ${t.passportExpiryC.text}',
                  ),
                _reviewRow(theme, LucideIcons.cake, t.dobC.text, isLast: true),
              ],
            ),
          );
        }),
        const SizedBox(height: 12),

        // Payment summary
        _sectionHeader(theme, 'PAYMENT'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.elevationColor(context, 1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _reviewRow(theme, LucideIcons.creditCard, maskedCard),
              _reviewRow(theme, LucideIcons.user, _cardHolderController.text),
              _reviewRow(
                theme,
                LucideIcons.calendar,
                'Exp: ${_cardExpiryController.text}',
                isLast: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Confirmed pricing
        _sectionHeader(theme, 'CONFIRMED PRICING'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.elevationColor(context, 1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              ...offer.travelerPricings.map(
                (tp) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Traveler ${tp.travelerId} (${tp.travelerType})',
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                      Text(
                        '${tp.currency} ${tp.totalPrice}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Divider(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    '\$${offer.totalPrice.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.accent,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Price change notice
        if (_confirmedOffer != null &&
            _confirmedOffer!.totalPrice != widget.offer.totalPrice)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.alertTriangle,
                  size: 16,
                  color: Colors.amber[700],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Price updated from \$${widget.offer.totalPrice.toStringAsFixed(2)} '
                    'to \$${_confirmedOffer!.totalPrice.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 12, color: Colors.amber[700]),
                  ),
                ),
              ],
            ),
          ),

        // Terms
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.elevationColor(context, 1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                LucideIcons.info,
                size: 14,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'By proceeding you agree to the airline\'s terms and conditions.',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Book button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isProcessing ? null : _createBooking,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(_radius),
              ),
              elevation: 0,
            ),
            icon: _isProcessing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(LucideIcons.checkCircle, size: 18),
            label: Text(
              _isProcessing
                  ? 'Booking...'
                  : 'Confirm & Pay \$${(_confirmedOffer ?? widget.offer).totalPrice.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  String _maskedCardNumber() {
    final raw = _cardNumberController.text.replaceAll(' ', '');
    if (raw.length < 4) return '•••• •••• •••• ••••';
    return '•••• •••• •••• ${raw.substring(raw.length - 4)}';
  }

  // ── Shared helpers ──

  Widget _sectionHeader(ThemeData theme, String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildContinueButton({
    VoidCallback? onPressed,
    required String label,
    IconData? icon,
    bool isLoading = false,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radius),
          ),
          elevation: 0,
        ),
        icon: isLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(icon ?? LucideIcons.arrowRight, size: 18),
        label: Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _reviewRow(
    ThemeData theme,
    IconData icon,
    String text, {
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        children: [
          Icon(
            icon,
            size: 14,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  INPUT FORMATTERS
// ═══════════════════════════════════════════════════════════════════════════

/// Formats card number as: 4111 1111 1111 1111
class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(' ', '');
    if (digits.length > 16) return oldValue;

    final buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Formats expiry as: MM/YY
class _ExpiryDateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll('/', '');
    if (digits.length > 4) return oldValue;

    final buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i == 2) buffer.write('/');
      buffer.write(digits[i]);
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
