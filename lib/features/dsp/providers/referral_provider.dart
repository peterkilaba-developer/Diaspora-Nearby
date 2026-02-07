import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Stores a referral code captured from a deep link or search parameter
/// before the user has completed their profile.
final pendingReferralCodeProvider = StateProvider<String?>((ref) => null);
