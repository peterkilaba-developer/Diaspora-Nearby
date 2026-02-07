import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/core/data/countries.dart' as country_data;
import 'package:diaspora_nearby/features/shared/widgets/country_picker_sheet.dart';
import 'package:sms_autofill/sms_autofill.dart';
import 'auth_controller.dart';
import 'package:diaspora_nearby/features/community/services/community_service.dart';
import 'dart:ui' as ui;

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
            'âœ… Auto-filled phone: ${bestMatch.dialCode} $remainingNumber',
          );
        } else {
          // Fallback: Just set the text if we can't parse country
          // But usually 'hint' returns E.164 format
          debugPrint('âš ï¸ Could not parse country from: $mobileNumber');
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

    return Scaffold(
      resizeToAvoidBottomInset: true,
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
                    child: ColorFiltered(
                      colorFilter: ColorFilter.mode(
                        theme.colorScheme.primary, // Sage green
                        BlendMode.srcIn,
                      ),
                      child: Image.asset(
                        'assets/icons/logo-original.png',
                        width: 120,
                        height: 120,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Container(
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
                                    .withOpacity(0.6),
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
                            .withOpacity(0.5),
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

                  // DEBUG: Reset Database Button
                  // Only visible in debug mode or for testing convenience
                  if (kDebugMode) ...[
                    const SizedBox(height: 24),
                    Center(
                      child: TextButton.icon(
                        onPressed: () async {
                          // Default selections
                          final Map<String, bool> targets = {
                            'Users': true,
                            'Communities': true,
                            'Organizations': true,
                            'Events': true,
                            'Radio Health': true,
                            'Chats (RTDB)': true,
                            'Storage (Photos)': true,
                            'Points & Referrals': true,
                            'Feedback History': true,
                            'Proximity Cooldown': true,
                            'Empty Communities':
                                false, // Default false to avoid accidental deletion of legit empty ones if any (though rule says none)
                          };

                          final selected = await showDialog<List<String>>(
                            context: context,
                            builder: (context) => StatefulBuilder(
                              builder: (context, setState) {
                                return AlertDialog(
                                  title: const Text('Reset Database Options'),
                                  content: SizedBox(
                                    width: double.maxFinite,
                                    child: SingleChildScrollView(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: targets.keys.map((key) {
                                          return CheckboxListTile(
                                            title: Text(key),
                                            value: targets[key],
                                            onChanged: (val) {
                                              setState(
                                                () =>
                                                    targets[key] = val ?? false,
                                              );
                                            },
                                            activeColor: Colors.red,
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context), // Refund null
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        // Map display keys to internal keys
                                        final List<String> result = [];
                                        if (targets['Users']!) {
                                          result.add('users');
                                        }
                                        if (targets['Communities']!) {
                                          result.add('communities');
                                        }
                                        if (targets['Organizations']!) {
                                          result.add('organizations');
                                        }
                                        if (targets['Events']!) {
                                          result.add('events');
                                        }
                                        if (targets['Radio Health']!) {
                                          result.add('radio');
                                        }
                                        if (targets['Chats (RTDB)']!) {
                                          result.add('chats');
                                        }
                                        if (targets['Storage (Photos)']!) {
                                          result.add('storage');
                                        }
                                        if (targets['Points & Referrals']!) {
                                          result.add('points');
                                        }
                                        if (targets['Feedback History']!) {
                                          result.add('feedback');
                                        }
                                        if (targets['Proximity Cooldown']!) {
                                          result.add('proximity');
                                        }
                                        if (targets['Empty Communities']!) {
                                          result.add('empty_communities');
                                        }

                                        Navigator.pop(context, result);
                                      },
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.red,
                                      ),
                                      child: const Text('DELETE SELECTED'),
                                    ),
                                  ],
                                );
                              },
                            ),
                          );

                          if (selected != null && selected.isNotEmpty) {
                            try {
                              // Show loading dialog
                              if (!context.mounted) return;
                              showDialog(
                                context: context,
                                barrierDismissible: false,
                                builder: (context) => const Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );

                              // Prune Empty Communities if selected
                              if (selected.contains('empty_communities')) {
                                await CommunityService()
                                    .pruneEmptyCommunities();
                                selected.remove('empty_communities');
                              }

                              if (selected.isNotEmpty) {
                                final result = await CommunityService()
                                    .hardResetDatabase(resetTargets: selected);

                                if (context.mounted) {
                                  Navigator.pop(context); // Pop loading

                                  final succeeded = result['success'] ?? [];
                                  final failed = result['failed'] ?? [];

                                  if (failed.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Reset Complete: ${succeeded.join(", ")}',
                                        ),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  } else {
                                    // Partial Success
                                    final sb = StringBuffer();
                                    if (succeeded.isNotEmpty) {
                                      sb.writeln(
                                        'Deleted: ${succeeded.join(", ")}',
                                      );
                                    }
                                    sb.write('Failed: ${failed.join(", ")}');

                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(sb.toString()),
                                        backgroundColor: Colors.orange,
                                      ),
                                    );
                                  }
                                }
                              } else {
                                if (context.mounted) {
                                  Navigator.pop(
                                    context,
                                  ); // Pop loading if nothing selected
                                }
                              }
                            } catch (e) {
                              if (context.mounted) {
                                Navigator.pop(context); // Pop loading

                                // Check for partial success message from service if thrown (though we switched to map, failsafe)
                                String message = 'Error: $e';
                                Color color = Colors.red;

                                if (e.toString().contains('Partial success')) {
                                  message =
                                      'Reset Complete (Local Data cleared).\nRemote Data skipped (Not logged in).';
                                  color = Colors.orange;
                                }

                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(message),
                                    backgroundColor: color,
                                  ),
                                );
                              }
                            }
                          }
                        },
                        icon: const Icon(
                          Icons.delete_forever,
                          color: Colors.red,
                          size: 20,
                        ),
                        label: const Text(
                          'Reset App Data (Debug)',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),
                ],
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
          colors: colors.map((c) => c.withOpacity(0.3)).toList(),
        ),
      ),
    );
  }
}
