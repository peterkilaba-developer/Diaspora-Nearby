import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/chat/utils/community_chat_utils.dart';
import 'package:diaspora_nearby/features/dsp/providers/dsp_valuation_provider.dart';

/// Detail screen for a treasury card — shows Diaspora Direct Investments
/// loan information for community treasuries, or system reserve information
/// for protocol treasuries, along with blockchain transaction activity.
class DdiTreasuryDetailScreen extends ConsumerWidget {
  final String title;
  final String subtitle;
  final String? walletAddress;
  final String balance;
  final bool isSystemReserve;
  final String? unitId;

  const DdiTreasuryDetailScreen({
    super.key,
    required this.title,
    required this.subtitle,
    this.walletAddress,
    required this.balance,
    this.isSystemReserve = false,
    this.unitId,
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
                      'Diaspora Direct Investments (DDI)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Community Lending & Sovereign Projects',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Diaspora Direct Investments (DDI) empower community members to access '
            'investment loans directly from community treasuries, '
            'funded through the 1:1 Ubuntu community match. Borrowing members '
            'post 10% collateral in \$DIASPORA and own 100% of the funded venture.',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      LucideIcons.arrowUpRight,
                      size: 14,
                      color: AppTheme.accent,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Upward Cascading Liquidity Protocol',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: AppTheme.accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'If the local Town DDI Treasury does not have enough funds to cover an approved loan, the protocol automatically cascades upward to draw the shortfall from the State Reserve Treasury, Country DDI Treasury, and Global Reserve.',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── System Reserve Info ─────────────────────────────────────────────────
  Widget _buildSystemReserveInfo(BuildContext context, bool isDark) {
    final String cardTitle = CommunityChatUtils.generateTreasuryCategoryTitle(
      unitId: unitId,
    );
    final String cardSubtitle;
    final IconData iconData;
    final String boxTitle;
    final String boxText;

    if (unitId == 'founders') {
      cardSubtitle = 'Core Maintenance Allocation (10%)';
      iconData = LucideIcons.users;
      boxTitle = 'Core Allocation & Vesting';
      boxText =
          'This treasury holds the 10% \$DIASPORA allocation dedicated to founders, core developers, and ongoing protocol maintenance. Funds are subject to vesting schedules to ensure long-term alignment with the community.';
    } else if (unitId == 'liquidity') {
      cardSubtitle = 'DEX Liquidity & Market Access';
      iconData = LucideIcons.droplets;
      boxTitle = 'Market Liquidity Provision';
      boxText =
          'This treasury provides initial and ongoing liquidity for decentralized exchanges (DEXs), enabling seamless trading, token swaps, and price stability across the ecosystem.';
    } else if (unitId == 'burn') {
      cardSubtitle = 'Protocol Deflationary Sink';
      iconData = LucideIcons.flame;
      boxTitle = 'Automated Deflationary Mechanism';
      boxText =
          'This wallet serves as an un-spendable deflationary sink (0x...dEaD). Tokens sent here or generated via protocol burn mechanisms are permanently removed from circulating supply to support token scarcity.';
    } else if (unitId == 'global_community') {
      cardSubtitle = 'Zero-Fee Activities & Community Operations';
      iconData = LucideIcons.globe;
      boxTitle = 'Global Reserve Operations';
      boxText =
          'The Global Reserve enables all free activities across the platform. It absorbs network transfer costs, subsidizes remittance fees paid to legacy money transfer companies (so users send value for free while legacy rails still get paid), funds community operations, supports Chambers of Commerce, and pays salaries for elected Community Council officers.';
    } else if (unitId?.contains('continent') == true) {
      cardSubtitle = 'Funding Sovereign Bond Engine';
      iconData = LucideIcons.landmark;
      boxTitle = 'Sovereign Bond Engine & Institutional Alignment';
      boxText =
          'Sovereign Bond Treasuries operate on a 100% Sovereign Bond Allocation: 100% of continental funds purchase sovereign government bonds and Treasury Bills (allocated pro-rata by member contributions, e.g., Tanzania’s contribution buys Bank of Tanzania bonds; host continent funds buy US Treasuries). 100% of coupon yields fund Diaspora Nearby platform operations (engineering, infrastructure, security), while transforming central banks into national integration partners.';
    } else {
      cardSubtitle = 'Liquidity & Upward Loan Cascading Backstop';
      iconData = LucideIcons.shield;
      boxTitle = 'Liquidity Backstop Function';
      boxText =
          'This reserve acts as a dynamic liquidity backstop for local community treasuries. Whenever local treasuries do not have enough funds to cover approved member loans, the requests cascade upward to this reserve to ensure member initiatives remain fully funded.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
        borderRadius: BorderRadius.circular(16),
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
                child: Icon(iconData, size: 20, color: Colors.blueGrey),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cardTitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      cardSubtitle,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
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
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blueGrey.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      LucideIcons.layers,
                      size: 14,
                      color: Colors.blueGrey,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      boxTitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.blueGrey,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  boxText,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                    height: 1.4,
                  ),
                ),
              ],
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
                  'ETHEREUM BASE',
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
                    'are recorded on the Ethereum Base Blockchain and can be verified below.',
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
