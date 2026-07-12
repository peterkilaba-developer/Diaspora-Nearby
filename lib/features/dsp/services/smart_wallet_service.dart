import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';

/// Provider for the SmartWalletService
final smartWalletServiceProvider = Provider<SmartWalletService>((ref) {
  return SmartWalletService();
});

/// Provider that fetches the user's on-chain $DIASPORA token balance
final tokenBalanceProvider = FutureProvider<String>((ref) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return '0';

  try {
    final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable(
          'getTokenBalance',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 8)),
        );
    final result = await callable.call<Map<String, dynamic>>({});
    final data = result.data;
    final formatted = data['formatted'] as String? ?? '0';
    // Remove trailing zeros for clean display (e.g. '50.0' -> '50')
    final num parsed = num.tryParse(formatted) ?? 0;
    if (parsed == parsed.toInt()) {
      return parsed.toInt().toString();
    }
    return parsed.toStringAsFixed(2);
  } catch (e) {
    debugPrint('[TokenBalance] Error fetching balance: $e');
    return '0';
  }
});

/// Provider that fetches on-chain $DIASPORA balance for a treasury wallet address.
/// Reads directly from the ERC-20 contract on Coinbase L2 Base Blockchain via getTokenBalance Cloud Function.
/// NOTE: For the treasury grid, use batchTokenBalancesProvider instead to avoid rate-limiting.
final treasuryTokenBalanceProvider = FutureProvider.family<String, String>((
  ref,
  walletAddress,
) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return '0';
  if (walletAddress.isEmpty) return '0';

  try {
    final callable = FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).httpsCallable('getTokenBalance');
    final result = await callable.call<Map<String, dynamic>>({
      'walletAddress': walletAddress,
    });
    final data = result.data;
    final formatted = data['formatted'] as String? ?? '0';
    final num parsed = num.tryParse(formatted) ?? 0;
    if (parsed == parsed.toInt()) {
      return parsed.toInt().toString();
    }
    return parsed.toStringAsFixed(2);
  } catch (e) {
    debugPrint(
      '[TreasuryBalance] Error fetching balance for $walletAddress: $e',
    );
    return '0';
  }
});

/// Model for batch token balances response.
class BatchTokenBalances {
  /// Map of governanceId → formatted balance string (e.g. "200")
  final Map<String, String> balances;

  /// Total $DIASPORA distributed across all treasury + user wallets
  final String totalDistributed;

  /// The authenticated user's personal wallet balance
  final String userBalance;

  const BatchTokenBalances({
    this.balances = const {},
    this.totalDistributed = '0',
    this.userBalance = '0',
  });
}

/// Provider that fetches ALL treasury token balances in one Cloud Function call.
/// This avoids Coinbase L2 Base Blockchain RPC rate-limiting that happens with 13+ individual calls.
final batchTokenBalancesProvider = FutureProvider<BatchTokenBalances>((
  ref,
) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return const BatchTokenBalances();

  try {
    final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable(
          'getBatchTokenBalances',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 10)),
        );
    final result = await callable.call<Map<String, dynamic>>({});
    final data = result.data;

    // Firebase returns nested maps as Map<Object?, Object?> — use Map.from() for safe conversion
    final rawBalancesObj = data['balances'];
    final Map<String, dynamic> rawBalances = rawBalancesObj is Map
        ? Map<String, dynamic>.from(rawBalancesObj)
        : {};

    final balances = <String, String>{};
    for (final entry in rawBalances.entries) {
      final val = entry.value;
      // Also handle nested maps that might be Map<Object?, Object?>
      final Map<String, dynamic> valMap = val is Map
          ? Map<String, dynamic>.from(val)
          : {};
      final formatted = valMap['formatted']?.toString() ?? '0';
      final num parsed = num.tryParse(formatted) ?? 0;
      balances[entry.key] = parsed == parsed.toInt()
          ? parsed.toInt().toString()
          : parsed.toStringAsFixed(2);
    }

    final totalRaw = data['totalDistributed']?.toString() ?? '0';
    final num totalParsed = num.tryParse(totalRaw) ?? 0;
    final totalFormatted = totalParsed == totalParsed.toInt()
        ? totalParsed.toInt().toString()
        : totalParsed.toStringAsFixed(2);

    final userBalRaw = data['userBalance']?.toString() ?? '0';
    final num userParsed = num.tryParse(userBalRaw) ?? 0;
    final userFormatted = userParsed == userParsed.toInt()
        ? userParsed.toInt().toString()
        : userParsed.toStringAsFixed(2);

    return BatchTokenBalances(
      balances: balances,
      totalDistributed: totalFormatted,
      userBalance: userFormatted,
    );
  } catch (e) {
    debugPrint('[BatchTokenBalances] Error: $e');
    return const BatchTokenBalances();
  }
});

/// Model for an on-chain ERC-20 token transfer event.
class OnChainTransfer {
  final String txHash;
  final int blockNumber;
  final DateTime timestamp;
  final String from;
  final String to;
  final double amount;
  final String direction; // 'in' or 'out'

  const OnChainTransfer({
    required this.txHash,
    required this.blockNumber,
    required this.timestamp,
    required this.from,
    required this.to,
    required this.amount,
    required this.direction,
  });

  bool get isIncoming => direction == 'in';

  /// Shortened address for display (0x1234...5678)
  String get shortFrom => from.length >= 10
      ? '${from.substring(0, 6)}...${from.substring(from.length - 4)}'
      : from;
  String get shortTo => to.length >= 10
      ? '${to.substring(0, 6)}...${to.substring(to.length - 4)}'
      : to;
}

/// Provider that fetches real on-chain $DIASPORA token transfer events
/// for the current user's wallet address from the Coinbase L2 Base Blockchain.
final onChainTransfersProvider = FutureProvider<List<OnChainTransfer>>((
  ref,
) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return [];

  try {
    final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable(
          'getTokenTransfers',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 10)),
        );
    final result = await callable.call<Map<String, dynamic>>({});
    final data = result.data;

    final rawTransfers = data['transfers'];
    if (rawTransfers == null || rawTransfers is! List) return [];

    final transfers = <OnChainTransfer>[];
    for (final raw in rawTransfers) {
      final Map<String, dynamic> tx = raw is Map
          ? Map<String, dynamic>.from(raw)
          : {};
      if (tx.isEmpty) continue;

      final amount = double.tryParse(tx['amount']?.toString() ?? '0') ?? 0;
      final timestampMs =
          tx['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;

      transfers.add(
        OnChainTransfer(
          txHash: tx['txHash']?.toString() ?? '',
          blockNumber: tx['blockNumber'] as int? ?? 0,
          timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs),
          from: tx['from']?.toString() ?? '',
          to: tx['to']?.toString() ?? '',
          amount: amount,
          direction: tx['direction']?.toString() ?? 'in',
        ),
      );
    }

    return transfers;
  } catch (e) {
    debugPrint('[OnChainTransfers] Error: $e');
    return [];
  }
});

/// Provider that streams the current user's smart wallet data
final userWalletProvider = StreamProvider<SmartWalletData?>((ref) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return Stream.value(null);
  final cachedAddress = ref.watch(userProfileProvider).value?.walletAddress;
  final cachedWallet = cachedAddress == null || cachedAddress.isEmpty
      ? null
      : SmartWalletData(address: cachedAddress);

  return FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .snapshots()
      .map((doc) {
        if (!doc.exists) return null;
        final data = doc.data()!;
        // Always force 'smart' type — legacy 'eoa' values in Firestore must not leak to UI
        return SmartWalletData(
          address: data['walletAddress'] as String?,
          walletType: 'smart',
          phoneHash: data['walletPhoneHash'] as String?,
          generatedAt: data['walletGeneratedAt'] != null
              ? (data['walletGeneratedAt'] as Timestamp).toDate()
              : null,
        );
      })
      .onErrorReturn(cachedWallet)
      .startWith(cachedWallet);
});

/// Represents the user's smart wallet details
class SmartWalletData {
  final String? address;
  final String walletType; // Always 'smart' (EOA wallets removed)
  final String? phoneHash;
  final DateTime? generatedAt;

  SmartWalletData({
    this.address,
    this.walletType = 'smart',
    this.phoneHash,
    this.generatedAt,
  });

  bool get isSmartWallet => walletType == 'smart';
  bool get hasWallet => address != null && address!.isNotEmpty;

  /// Get a shortened display address (0x1234...5678)
  String get shortAddress {
    if (address == null || address!.length < 10) return address ?? '';
    return '${address!.substring(0, 6)}...${address!.substring(address!.length - 4)}';
  }
}

/// Service for managing Smart Wallet operations.
///
/// This service calls Cloud Functions to create and manage
/// smart wallets using account abstraction (CREATE2).
/// No private keys are stored on the client — the backend signer
/// controls all smart wallets.
class SmartWalletService {
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'us-central1',
  );
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get or create a smart wallet for the current authenticated user.
  ///
  /// This is called after phone authentication to ensure the user
  /// has a deterministic smart wallet tied to their phone number.
  ///
  /// Returns [SmartWalletData] with the wallet address and type.
  Future<SmartWalletData> getOrCreateWallet() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User must be authenticated to create a wallet');
    }

    debugPrint('[SmartWallet] Getting/creating wallet for ${user.uid}');

    try {
      final callable = _functions.httpsCallable(
        'getOrCreateSmartWallet',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 12)),
      );
      final result = await callable.call<Map<String, dynamic>>({});

      final data = result.data;
      debugPrint(
        '[SmartWallet] Result: address=${data['address']}, '
        'type=${data['walletType']}, existed=${data['alreadyExisted']}',
      );

      return SmartWalletData(
        address: data['address'] as String?,
        walletType: 'smart',
      );
    } catch (e) {
      debugPrint('[SmartWallet] Error creating wallet: $e');
      rethrow;
    }
  }

  /// Check if the current user has a wallet already.
  Future<SmartWalletData?> getCurrentWallet() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) return null;

      final data = doc.data()!;
      final address = data['walletAddress'] as String?;

      if (address == null || address.isEmpty) return null;

      return SmartWalletData(
        address: address,
        walletType: 'smart',
        phoneHash: data['walletPhoneHash'] as String?,
        generatedAt: data['walletGeneratedAt'] != null
            ? (data['walletGeneratedAt'] as Timestamp).toDate()
            : null,
      );
    } catch (e) {
      debugPrint('[SmartWallet] Error fetching wallet: $e');
      return null;
    }
  }

  /// Get the wallet address for the crypto screen display.
  /// Returns the saved address or null.
  Future<String?> getWalletAddress() async {
    final wallet = await getCurrentWallet();
    return wallet?.address;
  }

  /// Ensure wallet exists (called during sign-in flow).
  /// All wallets are now smart wallets — this creates one if missing.
  /// This is a fire-and-forget operation — the wallet creation
  /// happens asynchronously on the backend.
  Future<void> ensureWalletOnSignIn() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) {
        // No user doc yet — trigger wallet creation
        debugPrint(
          '[SmartWallet] No user doc, triggering wallet creation for ${user.uid}',
        );
        await getOrCreateWallet();
        return;
      }

      final data = doc.data()!;
      final currentType = data['walletType'] as String?;
      final hasAddress =
          data['walletAddress'] != null &&
          (data['walletAddress'] as String).isNotEmpty;

      if (currentType == 'smart') {
        debugPrint('[SmartWallet] User already has smart wallet, skipping');
        return;
      }

      // Migrate legacy 'eoa' type to 'smart' in Firestore
      if (currentType != null && currentType != 'smart' && hasAddress) {
        debugPrint(
          '[SmartWallet] Migrating legacy walletType "$currentType" to "smart" for ${user.uid}',
        );
        await _firestore.collection('users').doc(user.uid).update({
          'walletType': 'smart',
        });
        return;
      }

      // Trigger wallet creation/migration via Cloud Function
      debugPrint(
        '[SmartWallet] Triggering wallet creation/migration for ${user.uid}',
      );
      await getOrCreateWallet();
    } catch (e) {
      // Don't block the sign-in flow if wallet creation fails
      debugPrint('[SmartWallet] Wallet creation failed (non-blocking): $e');
    }
  }

  /// Ensure the user has a smart wallet. Called from the crypto screen
  /// to create a wallet if the user doesn't have one yet.
  Future<SmartWalletData?> ensureSmartWallet() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    try {
      return await getOrCreateWallet();
    } catch (e) {
      debugPrint('[SmartWallet] Migration failed: $e');
      return null;
    }
  }
}
