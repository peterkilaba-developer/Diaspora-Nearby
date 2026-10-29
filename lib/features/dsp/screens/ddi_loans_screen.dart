import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/community/models/community_data.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/trust/services/trust_service.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import 'package:diaspora_nearby/features/dsp/services/smart_wallet_service.dart';

/// Diaspora Direct Investments Loans screen — shows loan information
/// and an application form for local community members.
class DdiLoansScreen extends ConsumerStatefulWidget {
  final String? communityId;
  final Community? community;

  const DdiLoansScreen({super.key, this.communityId, this.community});

  @override
  ConsumerState<DdiLoansScreen> createState() => _DdiLoansScreenState();
}

class _DdiLoansScreenState extends ConsumerState<DdiLoansScreen> {
  static final Map<String, List<Map<String, dynamic>>> _cachedAppsByCommunity =
      {};
  bool _showApplicationForm = false;
  final Set<String> _pendingApplicationActions = {};
  final Map<String, String> _optimisticVoteVerdicts = {};
  final Map<String, String> _optimisticStatusOverrides = {};
  final List<Map<String, dynamic>> _optimisticApplications = [];

  // Form controllers
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _amountController = TextEditingController();
  final _purposeController = TextEditingController();
  final _businessNameController = TextEditingController();
  final _businessDescriptionController = TextEditingController();
  final _repaymentPlanController = TextEditingController();
  String _loanType = 'Investments';
  String _repaymentPeriod = '6 months';
  bool _confirmsLocalInvestment = false;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(userProfileProvider).value;
    if (profile != null) {
      final name = '${profile.firstName} ${profile.lastName}'.trim();
      if (name.isNotEmpty) {
        _fullNameController.text = name;
      }
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _amountController.dispose();
    _purposeController.dispose();
    _businessNameController.dispose();
    _businessDescriptionController.dispose();
    _repaymentPlanController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final communityName = widget.community?.name ?? 'Your Community';
    final isHome =
        widget.community?.locationType == 'home' ||
        (widget.communityId?.contains('_home_') ?? false) ||
        (widget.community?.id.contains('_home_') ?? false);
    final isHost =
        widget.community?.locationType == 'host' ||
        (widget.communityId?.contains('_host_') ?? false) ||
        (widget.community?.id.contains('_host_') ?? false);
    final isCountry =
        widget.community?.type == 'country' ||
        (widget.communityId?.contains('_country_') ?? false) ||
        (widget.community?.id.contains('_country_') ?? false);
    final isTown =
        widget.community?.type == 'town' ||
        widget.community?.type == 'city' ||
        (widget.communityId?.contains('_town_') ?? false) ||
        (widget.communityId?.contains('_city_') ?? false) ||
        (widget.community?.id.contains('_town_') ?? false) ||
        (widget.community?.id.contains('_city_') ?? false);

    final isEligible = (isTown || isCountry) && (isHome || isHost);

    if (!isEligible) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text(
            'DDI Loans',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  LucideIcons.landmark,
                  size: 48,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  'DDI Loans Unavailable',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Diaspora Direct Investment loans are only available for Host Town, Home Town, Host Country, and Home Country communities.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final String title;
    if (isCountry) {
      title = isHome ? 'Home Country DDI Loans' : 'Host Country DDI Loans';
    } else {
      title = isHome ? 'Home Town DDI Loans' : 'Host Town DDI Loans';
    }

    final uid = ref.watch(authRepositoryProvider).currentUser?.uid ?? '';
    final userPoints =
        ref.watch(userPointsProvider(uid)).value ??
        ref.read(pointsRepositoryProvider).getCachedUserPoints(uid);
    final trustScore = userPoints?.trustScore ?? 0;

    final tokenBalanceAsync = ref.watch(tokenBalanceProvider);
    final userTokenBalance =
        double.tryParse(tokenBalanceAsync.value ?? '0') ?? 0.0;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Hero Header ──
              _buildHeroHeader(theme, isDark, communityName, isHome, isCountry),
              const SizedBox(height: 20),

              // ── Key Terms Summary ──
              _buildKeyTermsSummary(theme, isCountry),
              const SizedBox(height: 20),

              // ── Apply Button or Application Form ──
              if (!_showApplicationForm)
                _buildApplyButton(theme, isDark)
              else
                _buildApplicationForm(
                  theme,
                  isDark,
                  isHome,
                  isCountry,
                  trustScore,
                  userTokenBalance,
                ),

              const SizedBox(height: 28),
              _buildApplicationsSection(theme),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroHeader(
    ThemeData theme,
    bool isDark,
    String communityName,
    bool isHome,
    bool isCountry,
  ) {
    final heroTitle = isCountry
        ? (isHome ? 'Home Country\nDDI Loans' : 'Host Country\nDDI Loans')
        : (isHome ? 'Home Town\nDDI Loans' : 'Host Town\nDDI Loans');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: AppTheme.cardDecoration(context),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Image.asset(
              'assets/icons/logo-orange-transparent-32.png',
              width: 32,
              height: 32,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            heroTitle,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 22,
              color: theme.colorScheme.onSurface,
              height: 1.2,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            communityName,
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Funding available after Token Generation Event (TGE)',
              style: TextStyle(
                fontSize: 11,
                color: Colors.orange,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyTermsSummary(ThemeData theme, bool isCountry) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'KEY TERMS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: AppTheme.accent,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            isCountry
                ? 'Country-level DDI treasuries fund large-scale member loans exceeding \$1,000,000+ (for commercial real estate, corporate acquisitions, franchises, agriculture, infrastructure). '
                      'Borrowing members who put up 10% collateral in \$DIASPORA own the venture, its assets, and the loan obligation. '
                      'Borrowers repay by buying \$DIASPORA on the open market (DEX) and depositing tokens back to the Treasury.'
                : 'Community-powered, interest-free lending directly to members backed by \$DIASPORA tokens. '
                      'Members can apply individually or pool collateral to access up to \$1,000,000 for Town DDI. '
                      'Borrowers own the enterprise 100% and repay by buying \$DIASPORA on the open market (DEX).',
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildTermBadge(
                theme,
                isCountry ? 'Exceeds \$1M+' : 'Up to \$1M',
                'Loan Capacity',
              ),
              _buildTermBadge(theme, '10% Token', 'Collateral (Pooled)'),
              _buildTermBadge(theme, '0%', 'Interest'),
              _buildTermBadge(theme, 'DEX Buyback', 'Repayment'),
              _buildTermBadge(theme, 'PCT 91+', 'Required'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTermBadge(ThemeData theme, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: AppTheme.innerDecoration(context),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApplyButton(ThemeData theme, bool isDark) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => setState(() => _showApplicationForm = true),
            icon: const Icon(LucideIcons.fileText, size: 18),
            label: const Text(
              'Apply for an Investment Loan',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Qualified applications open public discussion and a 10-day vote. '
          'Funding remains pending TGE.',
          style: TextStyle(
            fontSize: 11,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildApplicationForm(
    ThemeData theme,
    bool isDark,
    bool isHome,
    bool isCountry,
    int trustScore,
    double userBalance,
  ) {
    final communityName = widget.community?.name ?? 'this community';
    final currentUser = ref.watch(authRepositoryProvider).currentUser;
    final trustData = ref
        .watch(userTrustProvider(currentUser?.uid ?? ''))
        .value;
    final profile = ref.watch(userProfileProvider).value;
    final daysActive = profile?.createdAt != null
        ? DateTime.now().difference(profile!.createdAt!).inDays
        : 0;

    final has7Genesis =
        (trustData?.uniqueFamilyCount ?? 0) >= 10 &&
        (trustData?.uniqueFriendCount ?? 0) >= 10 &&
        (trustData?.uniqueQrCount ?? 0) >= 10 &&
        (trustData?.uniqueVerificationCount ?? 0) >= 10 &&
        (trustData?.uniqueVouchCount ?? 0) >= 10 &&
        (trustData?.awardedQualificationMilestones.contains(
                  'profile_complete',
                ) ==
                true ||
            trustData?.awardedQualificationMilestones.contains(
                  'profileComplete',
                ) ==
                true);

    final is100DaysActive = daysActive >= 100;
    final isPctQualified = trustScore >= 91;
    final isQualified =
        trustData?.isDdiEligible ??
        (isPctQualified && has7Genesis && is100DaysActive);

    final requestedVal = int.tryParse(_amountController.text.trim()) ?? 0;
    final requiredCollateral = requestedVal * 0.10;
    final hasSufficientCollateral = userBalance >= requiredCollateral;
    final balanceFormatted = userBalance.toStringAsFixed(
      userBalance.truncateToDouble() == userBalance ? 0 : 2,
    );
    final requiredFormatted = requiredCollateral > 0
        ? (requiredCollateral.truncateToDouble() == requiredCollateral
              ? requiredCollateral.toInt().toString()
              : requiredCollateral.toStringAsFixed(2))
        : '0';

    return Form(
      key: _formKey,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: AppTheme.cardDecoration(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  LucideIcons.fileText,
                  size: 16,
                  color: AppTheme.accent,
                ),
                const SizedBox(width: 8),
                const Text(
                  'LOAN APPLICATION',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: AppTheme.accent,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() => _showApplicationForm = false),
                  child: Icon(
                    LucideIcons.x,
                    size: 18,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            _buildLabel(theme, 'Full Legal Name'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _fullNameController,
              decoration: _inputDecoration(theme, 'Enter your full name'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: 16),

            _buildLabel(theme, 'Loan Type'),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _loanType,
              decoration: _inputDecoration(theme, ''),
              items: const [
                DropdownMenuItem(
                  value: 'Investments',
                  child: Text('Investments'),
                ),
                DropdownMenuItem(
                  value: 'Education and Training',
                  child: Text('Education and Training'),
                ),
                DropdownMenuItem(
                  value: 'Business Investment',
                  child: Text('Business Investment'),
                ),
                DropdownMenuItem(
                  value: 'Real Estate Business',
                  child: Text('Real Estate Business'),
                ),
                DropdownMenuItem(
                  value: 'Education & Skills Business',
                  child: Text('Education & Skills Business'),
                ),
                DropdownMenuItem(
                  value: 'Agriculture & Farming Business',
                  child: Text('Agriculture & Farming Business'),
                ),
                DropdownMenuItem(
                  value: 'Healthcare Business',
                  child: Text('Healthcare Business'),
                ),
                DropdownMenuItem(
                  value: 'Other Local Business',
                  child: Text('Other Local Business'),
                ),
              ],
              onChanged: (v) => setState(() => _loanType = v ?? _loanType),
            ),
            const SizedBox(height: 16),

            _buildLabel(theme, 'Requested Amount (\$DIASPORA)'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _amountController,
              decoration: _inputDecoration(
                theme,
                isCountry
                    ? 'e.g. 1000000+ (Exceeding \$1,000,000)'
                    : 'e.g. 500000 (Up to \$1,000,000)',
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Amount is required';
                final n = int.tryParse(v.trim());
                if (n == null || n <= 0) return 'Enter a valid amount';
                final reqCol = n * 0.10;
                if (userBalance < reqCol) {
                  final reqFormatted = reqCol.truncateToDouble() == reqCol
                      ? reqCol.toInt().toString()
                      : reqCol.toStringAsFixed(2);
                  return 'Needs $reqFormatted \$DIASPORA collateral (Your balance: $balanceFormatted \$DIASPORA)';
                }
                return null;
              },
            ),
            const SizedBox(height: 8),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: (requestedVal > 0 && !hasSufficientCollateral)
                    ? Colors.red.withValues(alpha: 0.1)
                    : AppTheme.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    (requestedVal > 0 && !hasSufficientCollateral)
                        ? LucideIcons.alertCircle
                        : LucideIcons.shieldCheck,
                    size: 14,
                    color: (requestedVal > 0 && !hasSufficientCollateral)
                        ? Colors.red
                        : AppTheme.accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '10% Collateral Required: $requiredFormatted \$DIASPORA | Your Balance: $balanceFormatted \$DIASPORA',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: (requestedVal > 0 && !hasSufficientCollateral)
                            ? Colors.red
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            _buildLabel(theme, 'Investment Purpose'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _purposeController,
              decoration: _inputDecoration(
                theme,
                'Describe how you plan to use the funds',
              ),
              maxLines: 3,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Purpose is required'
                  : null,
            ),
            const SizedBox(height: 16),

            _buildLabel(theme, 'Business Name'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _businessNameController,
              decoration: _inputDecoration(theme, 'Name of your business'),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Business name is required'
                  : null,
            ),
            const SizedBox(height: 16),

            _buildLabel(theme, 'Business Description'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _businessDescriptionController,
              decoration: _inputDecoration(
                theme,
                'Brief description of your business',
              ),
              maxLines: 3,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Description is required'
                  : null,
            ),
            const SizedBox(height: 16),

            _buildLabel(theme, 'Preferred Repayment Period'),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _repaymentPeriod,
              decoration: _inputDecoration(theme, ''),
              items: const [
                DropdownMenuItem(value: '3 months', child: Text('3 months')),
                DropdownMenuItem(value: '6 months', child: Text('6 months')),
                DropdownMenuItem(value: '12 months', child: Text('12 months')),
                DropdownMenuItem(value: '18 months', child: Text('18 months')),
                DropdownMenuItem(value: '24 months', child: Text('24 months')),
              ],
              onChanged: (v) =>
                  setState(() => _repaymentPeriod = v ?? _repaymentPeriod),
            ),
            const SizedBox(height: 16),

            _buildLabel(theme, 'Repayment Plan (Option A — DEX Buyback)'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _repaymentPlanController,
              decoration: _inputDecoration(
                theme,
                'Describe your revenue & repayment schedule. Repayments buy \$DIASPORA on open market (DEX) and deposit to Treasury.',
              ),
              maxLines: 3,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Repayment plan is required'
                  : null,
            ),
            const SizedBox(height: 24),

            CheckboxListTile(
              value: _confirmsLocalInvestment,
              onChanged: (value) =>
                  setState(() => _confirmsLocalInvestment = value ?? false),
              contentPadding: EdgeInsets.zero,
              activeColor: AppTheme.accent,
              title: Text(
                'I confirm this loan will be used locally in $communityName and that I currently live in this community',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              subtitle: Text(
                isCountry
                    ? 'DDI loans require 91+ PCT, completion of all 7 Genesis Milestones, 100+ days active membership, and a 67% community vote for member loans exceeding \$1,000,000+.'
                    : 'DDI loans require 91+ PCT, completion of all 7 Genesis Milestones, 100+ days active membership, local investment, and local residence. Members may pool collateral to access up to \$1,000,000.',
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: !isQualified ? null : _submitApplication,
                icon: const Icon(LucideIcons.send, size: 16),
                label: Text(
                  !isQualified
                      ? 'Not Qualified (Requires 91+ PCT, 7 Genesis Milestones & 100+ Days Active)'
                      : 'Submit Application',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'A qualifying submission opens public discussion and a 10-day '
              'community vote. Token funding capacity is evaluated after TGE.',
              style: TextStyle(
                fontSize: 10,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(ThemeData theme, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.onSurface,
      ),
    );
  }

  InputDecoration _inputDecoration(ThemeData theme, String hint) {
    final isDark = theme.brightness == Brightness.dark;
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        fontSize: 13,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
      ),
      filled: true,
      fillColor: isDark ? AppTheme.elevationDark2 : AppTheme.elevationLight2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget _buildApplicationsSection(ThemeData theme) {
    final communityId = widget.communityId ?? widget.community?.id;
    if (communityId == null || communityId.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'COMMUNITY APPLICATIONS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: AppTheme.accent,
          ),
        ),
        const SizedBox(height: 12),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('ddi_loan_applications')
              .where('communityId', isEqualTo: communityId)
              .limit(100)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text(
                'Applications are available to host-community members.',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              );
            }

            List<Map<String, dynamic>> liveEntries;
            if (snapshot.hasData) {
              final docs = [...snapshot.data!.docs]
                ..sort((a, b) {
                  final aTime = (a.data()['createdAt'] as num?)?.toInt() ?? 0;
                  final bTime = (b.data()['createdAt'] as num?)?.toInt() ?? 0;
                  return bTime.compareTo(aTime);
                });
              liveEntries = docs
                  .map((d) => {'id': d.id, ...d.data()})
                  .toList();
              _cachedAppsByCommunity[communityId] = liveEntries;
            } else {
              liveEntries = _cachedAppsByCommunity[communityId] ?? [];
            }

            final liveBizNames = liveEntries
                .map((e) => e['businessName'])
                .toSet();
            final pendingOptimistic = _optimisticApplications
                .where((e) => !liveBizNames.contains(e['businessName']))
                .toList();
            final allApps = [...pendingOptimistic, ...liveEntries];

            if (allApps.isEmpty && !snapshot.hasData) {
              return const SizedBox.shrink();
            }

            if (allApps.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: AppTheme.innerDecoration(context),
                child: const Text(
                  'No DDI loan applications have been submitted here yet.',
                  style: TextStyle(fontSize: 12),
                ),
              );
            }
            return Column(
              children: allApps
                  .map((app) => _buildApplicationCard(theme, app))
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildApplicationCard(
    ThemeData theme,
    Map<String, dynamic> data,
  ) {
    final docId = data['id'] as String? ?? '';
    final voting = Map<String, dynamic>.from(
      data['voting'] as Map? ?? const {},
    );
    final optimisticVerdict = _optimisticVoteVerdicts[docId];
    final status =
        _optimisticStatusOverrides[docId] ??
        (data['status'] as String? ?? 'voting_open');
    final votingOpen =
        _optimisticStatusOverrides[docId] == null && voting['status'] == 'open';
    final closesAt = (voting['closesAt'] as num?)?.toInt() ?? 0;
    final expired =
        votingOpen &&
        closesAt > 0 &&
        DateTime.now().millisecondsSinceEpoch > closesAt;
    final yay =
        ((voting['yayCount'] as num?)?.toInt() ?? 0) +
        (optimisticVerdict == 'yay' ? 1 : 0);
    final nay =
        ((voting['nayCount'] as num?)?.toInt() ?? 0) +
        (optimisticVerdict == 'nay' ? 1 : 0);
    final abstain =
        ((voting['abstainCount'] as num?)?.toInt() ?? 0) +
        (optimisticVerdict == 'abstain' ? 1 : 0);
    final total =
        ((voting['totalVotes'] as num?)?.toInt() ?? 0) +
        (optimisticVerdict != null ? 1 : 0);
    final quorum = (voting['minimumQuorum'] as num?)?.toInt() ?? 10;
    final amount = (data['requestedAmount'] as num?)?.toInt() ?? 0;
    final busy = _pendingApplicationActions.contains(docId);
    final discussionChatId = data['discussionChatId'] as String?;
    final closesDate = closesAt == 0
        ? ''
        : DateTime.fromMillisecondsSinceEpoch(
            closesAt,
          ).toLocal().toString().split(' ').first;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  data['businessName'] as String? ?? 'Business application',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _buildStatusPill(status),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${data['loanType'] ?? 'Business Investment'} - '
            '$amount \$DIASPORA requested',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            data['purpose'] as String? ?? '',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            votingOpen
                ? 'Vote closes $closesDate - $total of $quorum quorum votes cast'
                : 'Final vote: Yay $yay / Nay $nay / Abstain $abstain',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (votingOpen) ...[
            const SizedBox(height: 6),
            Text(
              'Yay $yay   Nay $nay   Abstain $abstain',
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (discussionChatId != null)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.push('/chats/$discussionChatId'),
                icon: const Icon(LucideIcons.messagesSquare, size: 16),
                label: const Text('Open Public Discussion'),
              ),
            ),
          if (votingOpen && !expired) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildVoteButton(
                    docId,
                    'yay',
                    'Yay',
                    AppTheme.accent,
                    busy,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildVoteButton(
                    docId,
                    'nay',
                    'Nay',
                    theme.colorScheme.error,
                    busy,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildVoteButton(
                    docId,
                    'abstain',
                    'Abstain',
                    theme.colorScheme.onSurfaceVariant,
                    busy,
                  ),
                ),
              ],
            ),
          ],
          if (expired) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: busy
                    ? null
                    : () => _resolveVote(docId, yay, nay, total, quorum),
                child: const Text('Finalize Vote Result'),
              ),
            ),
          ],
          if (status == 'approved_pending_tge_collateral')
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Community approved. Funding remains pending TGE and token '
                'collateral capacity verification.',
                style: TextStyle(fontSize: 11, color: AppTheme.accent),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusPill(String status) {
    final (label, color) = switch (status) {
      'approved_pending_tge_collateral' => ('Approved', AppTheme.accent),
      'rejected_by_community_vote' => ('Rejected', AppTheme.error),
      _ => ('Voting Open', Colors.orange),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildVoteButton(
    String applicationId,
    String verdict,
    String label,
    Color color,
    bool busy,
  ) {
    return OutlinedButton(
      onPressed: busy ? null : () => _castVote(applicationId, verdict),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      ),
      child: Text(label),
    );
  }

  Future<void> _castVote(String applicationId, String verdict) async {
    final prevVerdict = _optimisticVoteVerdicts[applicationId];
    setState(() {
      _optimisticVoteVerdicts[applicationId] = verdict;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Your ${verdict.toUpperCase()} vote was recorded.'),
      ),
    );

    try {
      await FirebaseFunctions.instance.httpsCallable('castDdiLoanVote').call({
        'applicationId': applicationId,
        'verdict': verdict,
      });
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        setState(() {
          if (prevVerdict == null) {
            _optimisticVoteVerdicts.remove(applicationId);
          } else {
            _optimisticVoteVerdicts[applicationId] = prevVerdict;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Could not record your vote.')),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          if (prevVerdict == null) {
            _optimisticVoteVerdicts.remove(applicationId);
          } else {
            _optimisticVoteVerdicts[applicationId] = prevVerdict;
          }
        });
      }
    }
  }

  Future<void> _resolveVote(
    String applicationId,
    int yay,
    int nay,
    int total,
    int quorum,
  ) async {
    final decided = yay + nay;
    final approved =
        total >= quorum && decided > 0 && (yay / decided) >= 0.67;
    setState(() {
      _optimisticStatusOverrides[applicationId] = approved
          ? 'approved_pending_tge_collateral'
          : 'rejected_by_community_vote';
    });

    try {
      await FirebaseFunctions.instance
          .httpsCallable('resolveDdiLoanVoting')
          .call({'applicationId': applicationId});
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        setState(() {
          _optimisticStatusOverrides.remove(applicationId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Could not finalize this vote.')),
        );
      }
    }
  }

  Future<void> _submitApplication() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_confirmsLocalInvestment) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please confirm that the loan will be used locally.'),
        ),
      );
      return;
    }

    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in to submit an application.'),
        ),
      );
      return;
    }

    final communityId = widget.communityId ?? widget.community?.id;
    final fullLegalName = _fullNameController.text.trim();
    final loanType = _loanType;
    final requestedAmount = int.parse(_amountController.text.trim());
    final purpose = _purposeController.text.trim();
    final businessName = _businessNameController.text.trim();
    final businessDescription = _businessDescriptionController.text.trim();
    final repaymentPeriod = _repaymentPeriod;
    final repaymentPlan = _repaymentPlanController.text.trim();
    final confirmsLocalInvestment = _confirmsLocalInvestment;

    final optimisticEntry = <String, dynamic>{
      'id': 'optimistic_${DateTime.now().millisecondsSinceEpoch}',
      'communityId': communityId,
      'fullLegalName': fullLegalName,
      'loanType': loanType,
      'requestedAmount': requestedAmount,
      'purpose': purpose,
      'businessName': businessName,
      'businessDescription': businessDescription,
      'repaymentPeriod': repaymentPeriod,
      'repaymentPlan': repaymentPlan,
      'status': 'voting_open',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'voting': {
        'status': 'open',
        'closesAt': DateTime.now()
            .add(const Duration(days: 10))
            .millisecondsSinceEpoch,
        'yayCount': 0,
        'nayCount': 0,
        'abstainCount': 0,
        'totalVotes': 0,
        'minimumQuorum': 10,
      },
    };

    // 0-Latency optimistic insert, form collapse, and immediate confirmation modal
    setState(() {
      _optimisticApplications.insert(0, optimisticEntry);
      _showApplicationForm = false;
      _amountController.clear();
      _purposeController.clear();
      _businessNameController.clear();
      _businessDescriptionController.clear();
      _repaymentPlanController.clear();
      _confirmsLocalInvestment = false;
    });

    showDialog(
      context: context,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(LucideIcons.checkCircle, color: AppTheme.accent, size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Application Received',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: const Text(
            'Your PCT and host-community eligibility gates passed. Your loan '
            'application has been saved, its public discussion group is live, '
            'and the 10-day community vote is open.\n\n'
            'Any community approval remains pending the Token Generation Event '
            '(TGE) and \$DIASPORA collateral capacity verification.',
            style: TextStyle(fontSize: 13, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Done',
                style: TextStyle(
                  color: AppTheme.accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    unawaited(
      FirebaseFunctions.instance
          .httpsCallable('submitDdiLoanApplication')
          .call({
            'communityId': communityId,
            'fullLegalName': fullLegalName,
            'loanType': loanType,
            'requestedAmount': requestedAmount,
            'purpose': purpose,
            'businessName': businessName,
            'businessDescription': businessDescription,
            'repaymentPeriod': repaymentPeriod,
            'repaymentPlan': repaymentPlan,
            'confirmsLocalInvestment': confirmsLocalInvestment,
          })
          .then<void>((_) {})
          .catchError((Object e) {
            if (!mounted) return;
            setState(() {
              _optimisticApplications.remove(optimisticEntry);
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not save application: $e')),
            );
          }),
    );
  }
}
