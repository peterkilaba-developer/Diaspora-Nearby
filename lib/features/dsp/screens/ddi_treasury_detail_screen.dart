import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';import 'package:diaspora_nearby/features/dsp/providers/dsp_valuation_provider.dart';

/// Detail screen for a treasury card — shows Diaspora Direct Investments
/// loan information for community treasuries, or system reserve information
/// for protocol treasuries, along with blockchain transaction activity.
class DdiTreasuryDetailScreen extends ConsumerWidget {
  final String title;
  final String subtitle;
  final String? walletAddress;
  final String balance;
  final bool isSystemReserve;

  const DdiTreasuryDetailScreen({
    super.key,
    required this.title,
    required this.subtitle,
    this.walletAddress,
    required this.balance,
    this.isSystemReserve = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          8 + MediaQuery.of(context).padding.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Treasury Balance Header ──
            _buildBalanceHeader(context, isDark),
            const SizedBox(height: 24),

            // ── Wallet Address ──
            if (walletAddress != null && walletAddress!.isNotEmpty)
              _buildWalletSection(context, isDark),

            // ── Investment Info or System Reserve Info ──
            if (!isSystemReserve) ...[
              _buildDdiInfoSection(context, isDark),
              const SizedBox(height: 16),
              // Learn More link replaces How It Works + Qualification sections
              Center(
                child: GestureDetector(
                  onTap: () => launchUrl(
                    Uri.parse('https://diasporanearby.com/#ddi'),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Text(
                    'Learn more about Diaspora Direct Investments →',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ] else ...[
              _buildSystemReserveInfo(context, isDark),
            ],

            const SizedBox(height: 24),

            // ── Transaction Activity ──
            _buildTransactionActivity(context, isDark),

            // ── Blockchain Explorer Links ──
            const SizedBox(height: 24),
            _buildExplorerLinks(context, isDark),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ── Balance Header ──────────────────────────────────────────────────────
  Widget _buildBalanceHeader(BuildContext context, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.accent.withValues(alpha: 0.15),
            Colors.orange.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Image.asset(
            'assets/icons/logo-orange-transparent-48.png',
            width: 44,
            height: 44,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 12),
          Consumer(
            builder: (context, ref, _) {
              final valuation = ref.watch(dspValuationProvider);
              final parsedInt = (double.tryParse(balance) ?? 0).toInt();
              final usdEst = valuation.formatBalance(parsedInt);
              return Column(
                children: [
                  Text(
                    '$balance \$DIASPORA',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 28,
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    usdEst,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF38BDF8),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
          if (balance == '0') ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Pre-TGE — Token Generation Event pending',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.orange,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Wallet Section ──────────────────────────────────────────────────────
  Widget _buildWalletSection(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? Colors.grey.withValues(alpha: 0.2)
                : Colors.grey.shade200,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  LucideIcons.wallet,
                  size: 12,
                  color: Colors.blueGrey,
                ),
                const SizedBox(width: 6),
                Text(
                  'WALLET ADDRESS',
                  style: TextStyle(
                    fontSize: 9,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              walletAddress!,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: Colors.orange,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Investment Info Section ──────────────────────────────────────────────
  Widget _buildDdiInfoSection(BuildContext context, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.grey.withValues(alpha: 0.15)
              : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  LucideIcons.landmark,
                  size: 20,
                  color: AppTheme.accent,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Diaspora Direct Investments',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Community Investment Loans',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Diaspora Direct Investments enable community members to access '
            'investment loans directly '
            'from their community treasury. Funds are used to support local '
            'businesses, projects, and initiatives that strengthen the diaspora '
            'economy.',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── System Reserve Info ─────────────────────────────────────────────────
  Widget _buildSystemReserveInfo(BuildContext context, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.grey.withValues(alpha: 0.15)
              : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  LucideIcons.lock,
                  size: 20,
                  color: Colors.blueGrey,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'System Reserve',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Protocol-managed treasury',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This treasury is managed by the protocol and operates under '
            'automated rules. Funds are allocated according to the tokenomics framework.',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // ── Transaction Activity ────────────────────────────────────────────────
  Widget _buildTransactionActivity(BuildContext context, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.grey.withValues(alpha: 0.15)
              : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                LucideIcons.activity,
                size: 16,
                color: AppTheme.accent,
              ),
              const SizedBox(width: 8),
              const Text(
                'TRANSACTION ACTIVITY',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: AppTheme.accent,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'COINBASE L2 BASE',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Direct users to blockchain explorers for full history
          if (walletAddress != null && walletAddress!.isNotEmpty) ...[
            Center(
              child: Column(
                children: [
                  Icon(
                    LucideIcons.link,
                    size: 36,
                    color: AppTheme.accent.withValues(alpha: 0.6),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'View on Blockchain Explorer',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'All $balance \$DIASPORA token transfers for this treasury\n'
                    'are recorded on the Coinbase L2 Base Blockchain and can be verified below.',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? Colors.grey.shade500
                          : Colors.grey.shade500,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ] else ...[
            Center(
              child: Column(
                children: [
                  Icon(
                    LucideIcons.inbox,
                    size: 36,
                    color: Colors.grey.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Wallet Not Yet Assigned',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'This treasury wallet will be created and linked\n'
                    'when this governance unit is activated.',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? Colors.grey.shade500
                          : Colors.grey.shade500,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Explorer Links ──────────────────────────────────────────────────────
  Widget _buildExplorerLinks(BuildContext context, bool isDark) {
    if (walletAddress == null || walletAddress!.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.15)),
        ),
        child: const Row(
          children: [
            Icon(LucideIcons.wallet, size: 18, color: Colors.orange),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Wallet address will be assigned at TGE. '
                'Blockchain explorer links will be available then.',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.orange,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'VIEW ON BLOCKCHAIN EXPLORER',
          style: TextStyle(
            fontSize: 9,
            color: Colors.grey.shade500,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        _buildExplorerTile(
          context,
          isDark,
          icon: LucideIcons.globe,
          label: 'Basescan',
          subtitle: 'basescan.org',
          url: 'https://basescan.org/address/$walletAddress#tokentxns',
        ),
        const SizedBox(height: 8),
        _buildExplorerTile(
          context,
          isDark,
          icon: LucideIcons.search,
          label: 'Blockscout',
          subtitle: 'base.blockscout.com',
          url:
              'https://base.blockscout.com/address/$walletAddress?tab=token_transfers',
        ),
      ],
    );
  }

  Widget _buildExplorerTile(
    BuildContext context,
    bool isDark, {
    required IconData icon,
    required String label,
    required String subtitle,
    required String url,
  }) {
    return InkWell(
      onTap: () =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? Colors.grey.withValues(alpha: 0.15)
                : Colors.grey.shade200,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppTheme.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const Icon(LucideIcons.externalLink, size: 14, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
