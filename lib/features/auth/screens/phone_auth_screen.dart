import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/core/data/countries.dart' as country_data;
import 'package:diaspora_nearby/features/shared/widgets/country_picker_sheet.dart';
import 'package:sms_autofill/sms_autofill.dart';
import 'auth_controller.dart';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

class PhoneAuthScreen extends ConsumerStatefulWidget {
  const PhoneAuthScreen({super.key});

  @override
  ConsumerState<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends ConsumerState<PhoneAuthScreen> {
  final _phoneController = TextEditingController();
  final _searchController = TextEditingController();

  late country_data.Country _selectedCountry;

  @override
  void initState() {
    super.initState();
    // Synchronous country detection - device locale is instantly available
    _selectedCountry = _detectCountrySync();
    // Async phone number hint
    _tryGetPhoneNumber();
  }

  Future<void> _tryGetPhoneNumber() async {
    try {
      final mobileNumber = await SmsAutoFill().hint;
      if (mobileNumber != null && mobileNumber.isNotEmpty) {
        if (!mounted) return;

        // Mobile number usually comes with country code, e.g., +15551234567
        // We need to parse this to find the matching country
        final cleanNumber = mobileNumber.replaceAll(RegExp(r'[^\d+]'), '');

        country_data.Country? bestMatch;
        String? remainingNumber;

        // Try to find matching country by dial code
        // We sort by length descending to match longer codes first (e.g. +1 vs +1242)
        // Note: Ideally efficient implementation would be better, but list is small enough
        final sortedCountries = List<country_data.Country>.from(
          country_data.countries,
        )..sort((a, b) => b.dialCode.length.compareTo(a.dialCode.length));

        for (final country in sortedCountries) {
          if (cleanNumber.startsWith(country.dialCode)) {
            bestMatch = country;
            remainingNumber = cleanNumber.substring(country.dialCode.length);
            break;
          }
        }

        if (bestMatch != null && remainingNumber != null) {
          setState(() {
            _selectedCountry = bestMatch!;
            _phoneController.text = remainingNumber!;
          });
          debugPrint(
            '✅ Auto-filled phone: ${bestMatch.dialCode} $remainingNumber',
          );

          // Auto-submit for "One Tap" experience
          // Use a small delay to ensure state and UI are ready
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) _submit();
          });
        } else {
          // Fallback: Just set the text if we can't parse country
          // But usually 'hint' returns E.164 format
          debugPrint('⚠️ Could not parse country from: $mobileNumber');
        }
      }
    } catch (e) {
      debugPrint('â„¹ï¸ Phone number hint failed or cancelled: $e');
    }
  }

  /// Synchronously detect country from device locale (instant, no waiting)
  country_data.Country _detectCountrySync() {
    try {
      // Get device locale - this is instant
      final locale = ui.PlatformDispatcher.instance.locale;
      final countryCode = locale.countryCode?.toUpperCase();

      if (countryCode != null && countryCode.isNotEmpty) {
        final detected = country_data.getCountryByCode(countryCode);
        if (detected != null) {
          debugPrint('Ã¢ÂœÂ… Country auto-detected: ${detected.name}');
          return detected;
        }
      }
    } catch (e) {
      debugPrint('Ã¢ÂÂŒ Country detection failed: $e');
    }

    // Fallback to US
    debugPrint('Ã¢Â„Â¹Ã¯Â¸Â Fallback to US');
    return country_data.getCountryByCode('US') ?? country_data.countries.first;
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _showCountryPicker() {
    _searchController.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => CountryPickerSheet(
        selectedCountry: _selectedCountry,
        showDialCode: true,
        onCountrySelected: (country) {
          setState(() {
            _selectedCountry = country;
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  void _submit() {
    final phoneNumber =
        '${_selectedCountry.dialCode}${_phoneController.text.trim().replaceAll(RegExp(r'\D'), '')}';
    if (_phoneController.text.isNotEmpty) {
      ref
          .read(authControllerProvider.notifier)
          .signInWithPhone(context, phoneNumber);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authControllerProvider);
    final theme = Theme.of(context);

    return PopScope(
      canPop: !kIsWeb,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          // On web, if keyboard is open, unfocus to dismiss it cleanly
          final currentFocus = FocusManager.instance.primaryFocus;
          if (currentFocus != null) {
            currentFocus.unfocus();
          }
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: !kIsWeb,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight:
                  MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom -
                  48,
            ),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 40),

                  // Logo - Using the actual app logo with sage green tint
                  Center(
                    child: Image.asset(
                        'assets/icons/logo-transparent-128.png',
                        width: 120,
                        height: 120,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: const Center(
                            child: Text(
                              'DN',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 48,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Title
                  Text(
                    'Welcome to Diaspora Nearby',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),

                  // Subtitle
                  Text(
                    'Discover and Connect with people from your home country nearby or across the world',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // Phone input container
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.colorScheme.outline),
                      borderRadius: BorderRadius.circular(12),
                      color: theme.cardColor,
                    ),
                    child: Row(
                      children: [
                        // Country Code Picker
                        InkWell(
                          onTap: _showCountryPicker,
                          borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _selectedCountry.flag,
                                  style: const TextStyle(fontSize: 24),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _selectedCountry.dialCode,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Icon(Icons.arrow_drop_down),
                              ],
                            ),
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 24,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(width: 12),
                        // Phone Number Input
                        Expanded(
                          child: TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[\d\s\-\(\)]'),
                              ),
                              LengthLimitingTextInputFormatter(20),
                            ],
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              hintText: 'Phone number',
                              hintStyle: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.6),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 16,
                              ),
                            ),
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                    ),
                  ),

                  // Status message - show detected country
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        LucideIcons.mapPin,
                        size: 14,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Country: ${_selectedCountry.name}',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: _showCountryPicker,
                        child: Text(
                          'Change',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const Spacer(),

                  // D-C-B Circles
                  _buildDiscoverConnectBelong(),
                  const SizedBox(height: 24),

                  // Button
                  SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: isLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                        disabledBackgroundColor: theme.colorScheme.primary
                            .withValues(alpha: 0.5),
                      ),
                      child: isLoading
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Send Verification Code',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Terms of Service & Privacy Policy
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.7),
                        height: 1.5,
                      ),
                      children: [
                        const TextSpan(
                          text: 'By continuing, you agree to our ',
                        ),
                        WidgetSpan(
                          child: GestureDetector(
                            onTap: () => launchUrl(
                              Uri.parse(
                                  'https://diasporanearby.com/terms-of-service'),
                              mode: LaunchMode.externalApplication,
                            ),
                            child: Text(
                              'Terms of Service',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                                decorationColor: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                        const TextSpan(text: ' and '),
                        WidgetSpan(
                          child: GestureDetector(
                            onTap: () => launchUrl(
                              Uri.parse(
                                  'https://diasporanearby.com/privacy-policy'),
                              mode: LaunchMode.externalApplication,
                            ),
                            child: Text(
                              'Privacy Policy',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                                decorationColor: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildDiscoverConnectBelong() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildCircleItem(
          letter: 'D',
          label: 'Discover',
          gradientColors: [Colors.teal.shade500, Colors.blue.shade600],
        ),
        _buildConnectorLine([Colors.teal.shade500, Colors.blue.shade600]),
        _buildCircleItem(
          letter: 'C',
          label: 'Connect',
          gradientColors: [Colors.blue.shade600, Colors.purple.shade600],
        ),
        _buildConnectorLine([Colors.blue.shade600, Colors.purple.shade600]),
        _buildCircleItem(
          letter: 'B',
          label: 'Belong',
          gradientColors: [Colors.purple.shade600, Colors.pink.shade600],
        ),
      ],
    );
  }

  Widget _buildCircleItem({
    required String letter,
    required String label,
    required List<Color> gradientColors,
  }) {
    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Center(
            child: Text(
              letter,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildConnectorLine(List<Color> colors) {
    return Container(
      width: 24,
      height: 2,
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(1),
        gradient: LinearGradient(
          colors: colors.map((c) => c.withValues(alpha: 0.3)).toList(),
        ),
      ),
    );
  }
}
