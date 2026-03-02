import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

/// Detail screen for a treasury card — shows DDI (Diaspora Direct Investment)
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Treasury Balance Header ──
            _buildBalanceHeader(context, isDark),
            const SizedBox(height: 24),

            // ── Wallet Address ──
            if (walletAddress != null && walletAddress!.isNotEmpty)
              _buildWalletSection(context, isDark),

            // ── DDI Info or System Reserve Info ──
            if (!isSystemReserve) ...[
              _buildDdiInfoSection(context, isDark),
              const SizedBox(height: 24),
              _buildHowItWorksSection(context, isDark),
              const SizedBox(height: 24),
              _buildQualificationSection(context, isDark),
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
        border: Border.all(
          color: AppTheme.accent.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          Image.asset(
            'assets/icons/logo-original.png',
            width: 44,
            height: 44,
            fit: BoxFit.contain,
            color: Colors.orange,
          ),
          const SizedBox(height: 12),
          Text(
            '$balance \$DIASPORA',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 28,
              color: Colors.orange,
            ),
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
                const Icon(LucideIcons.wallet, size: 12, color: Colors.blueGrey),
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

  // ── DDI Info Section ────────────────────────────────────────────────────
  Widget _buildDdiInfoSection(BuildContext context, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.white,
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
            'DDI enables community members to access investment loans directly '
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

  // ── How It Works ────────────────────────────────────────────────────────
  Widget _buildHowItWorksSection(BuildContext context, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.white,
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
          const Text(
            'HOW DDI LOANS WORK',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: AppTheme.accent,
            ),
          ),
          const SizedBox(height: 16),
          _buildStep(
            isDark,
            number: '1',
            title: 'Apply from Your Community',
            description:
                'Submit a loan application through your local community treasury. '
                'Describe your investment purpose and requested amount.',
            icon: LucideIcons.fileText,
          ),
          const SizedBox(height: 14),
          _buildStep(
            isDark,
            number: '2',
            title: 'Qualification Check',
            description:
                'Your eligibility is determined by your Proof of Community Trust '
                '(PoCT) score and your \$DIASPORA token balance — the higher your '
                'trust and stake, the more you can access.',
            icon: LucideIcons.shieldCheck,
          ),
          const SizedBox(height: 14),
          _buildStep(
            isDark,
            number: '3',
            title: 'Cascading Fund Access',
            description:
                'If your local treasury lacks sufficient funds, the request '
                'automatically cascades upward — city → country → continent → '
                'global treasury — until a treasury with capacity is found.',
            icon: LucideIcons.arrowUpCircle,
          ),
          const SizedBox(height: 14),
          _buildStep(
            isDark,
            number: '4',
            title: 'Fund & Invest',
            description:
                'Once approved and funded, the \$DIASPORA tokens are disbursed '
                'to your wallet. Repayment terms are set by community governance.',
            icon: LucideIcons.coins,
          ),
        ],
      ),
    );
  }

  Widget _buildStep(
    bool isDark, {
    required String number,
    required String title,
    required String description,
    required IconData icon,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppTheme.accent.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
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
              Row(
                children: [
                  Icon(icon, size: 14, color: AppTheme.accent),
                  const SizedBox(width: 6),
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Qualification Section ───────────────────────────────────────────────
  Widget _buildQualificationSection(BuildContext context, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.white,
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
          const Text(
            'QUALIFICATION CRITERIA',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: AppTheme.accent,
            ),
          ),
          const SizedBox(height: 16),
          _buildQualRow(
            isDark,
            icon: LucideIcons.shieldCheck,
            label: 'Proof of Community Trust (PoCT)',
            value: 'Higher PoCT = larger loan access',
            color: AppTheme.accent,
          ),
          const SizedBox(height: 12),
          _buildQualRow(
            isDark,
            icon: LucideIcons.coins,
            label: '\$DIASPORA Token Balance',
            value: 'Your stake determines collateral',
            color: Colors.orange,
          ),
          const SizedBox(height: 12),
          _buildQualRow(
            isDark,
            icon: LucideIcons.history,
            label: 'Repayment History',
            value: 'Available after TGE launch',
            color: Colors.blueGrey,
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Icon(LucideIcons.info, size: 14, color: Colors.orange),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'DDI loans will be available after the Token Generation Event (TGE). '
                    'Build your PoCT score now to maximize future loan access.',
                    style: TextStyle(fontSize: 11, color: Colors.orange, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQualRow(
    bool isDark, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── System Reserve Info ─────────────────────────────────────────────────
  Widget _buildSystemReserveInfo(BuildContext context, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.white,
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
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.white,
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
              const Icon(LucideIcons.activity, size: 16, color: AppTheme.accent),
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
                  'BASE CHAIN',
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

          // Pre-TGE empty state
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
                  'No Transactions Yet',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Blockchain transactions will appear here after the\n'
                  'Token Generation Event (TGE) and wallet deployment.',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
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
          border: Border.all(
            color: Colors.orange.withValues(alpha: 0.15),
          ),
        ),
        child: const Row(
          children: [
            Icon(LucideIcons.wallet, size: 18, color: Colors.orange),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Wallet address will be assigned at TGE. '
                'Blockchain explorer links will be available then.',
                style: TextStyle(fontSize: 11, color: Colors.orange, height: 1.4),
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
          url: 'https://basescan.org/address/$walletAddress',
        ),
        const SizedBox(height: 8),
        _buildExplorerTile(
          context,
          isDark,
          icon: LucideIcons.search,
          label: 'Blockscout',
          subtitle: 'base.blockscout.com',
          url: 'https://base.blockscout.com/address/$walletAddress',
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
      onTap: () => launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      ),
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
            const Icon(
              LucideIcons.externalLink,
              size: 14,
              color: Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}
