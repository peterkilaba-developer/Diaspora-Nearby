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
import 'package:url_launcher/url_launcher.dart';

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
  bool _showApplicationForm = false;
  bool _isSubmitting = false;
  final Set<String> _pendingApplicationActions = {};

  // Form controllers
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _amountController = TextEditingController();
  final _purposeController = TextEditingController();
  final _businessNameController = TextEditingController();
  final _businessDescriptionController = TextEditingController();
  final _repaymentPlanController = TextEditingController();
  String _loanType = 'Business Investment';
  String _repaymentPeriod = '6 months';
  bool _confirmsHostBusiness = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill name from user profile
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final profile = ref.read(userProfileProvider).value;
      if (profile != null) {
        final name = '${profile.firstName} ${profile.lastName}'.trim();
        if (name.isNotEmpty) {
          _fullNameController.text = name;
        }
      }
    });
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

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Diaspora Direct Investments Loans',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        bottom: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Hero Header ──
              _buildHeroHeader(theme, isDark, communityName),
              const SizedBox(height: 20),

              // ── Quick Key Terms ──
              _buildKeyTermsSummary(theme),
              const SizedBox(height: 16),

              // ── Learn More Link ──
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
                      color: theme.colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ── Apply Button or Application Form ──
              if (!_showApplicationForm)
                _buildApplyButton(theme, isDark)
              else
                _buildApplicationForm(theme, isDark),

              const SizedBox(height: 28),
              _buildApplicationsSection(theme),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // ── Hero Header ──────────────────────────────────────────────────────────
  Widget _buildHeroHeader(ThemeData theme, bool isDark, String communityName) {
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
            'Diaspora Direct\nInvestments Loans',
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

  // ── Key Terms Summary ────────────────────────────────────────────────────
  Widget _buildKeyTermsSummary(ThemeData theme) {
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
            'Community-powered lending backed by \$DIASPORA tokens. '
            'Loans cascade from local → country → continental → global treasury.',
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
              _buildTermBadge(theme, '0%', 'Interest'),
              _buildTermBadge(theme, '\$DIASPORA', 'Collateral'),
              _buildTermBadge(theme, '3–24 mo', 'Repayment'),
              _buildTermBadge(theme, 'PoCT 91+', 'Required'),
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

  // ── Apply Button ─────────────────────────────────────────────────────────
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

  // ── Application Form ─────────────────────────────────────────────────────
  Widget _buildApplicationForm(ThemeData theme, bool isDark) {
    final communityName = widget.community?.name ?? 'this host community';
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

            // Full Name
            _buildLabel(theme, 'Full Legal Name'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _fullNameController,
              decoration: _inputDecoration(theme, 'Enter your full name'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: 16),

            // Loan Type
            _buildLabel(theme, 'Loan Type'),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _loanType,
              decoration: _inputDecoration(theme, ''),
              items: const [
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

            // Requested Amount
            _buildLabel(theme, 'Requested Amount (\$DIASPORA)'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _amountController,
              decoration: _inputDecoration(theme, 'e.g. 5000'),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Amount is required';
                final n = int.tryParse(v.trim());
                if (n == null || n <= 0) return 'Enter a valid amount';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Purpose
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

            // Business Name
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

            // Business Description
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

            // Repayment Period
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

            // Repayment Plan
            _buildLabel(theme, 'Repayment Plan'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _repaymentPlanController,
              decoration: _inputDecoration(
                theme,
                'How do you plan to repay the loan?',
              ),
              maxLines: 3,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Repayment plan is required'
                  : null,
            ),
            const SizedBox(height: 24),

            CheckboxListTile(
              value: _confirmsHostBusiness,
              onChanged: _isSubmitting
                  ? null
                  : (value) =>
                        setState(() => _confirmsHostBusiness = value ?? false),
              contentPadding: EdgeInsets.zero,
              activeColor: AppTheme.accent,
              title: Text(
                'This business is based in $communityName',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              subtitle: Text(
                'Host-community DDI loans require PoCT 91+ and are only '
                'for businesses operating in this community.',
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 12),

            // Submit Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submitApplication,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(LucideIcons.send, size: 16),
                label: Text(
                  _isSubmitting
                      ? 'Saving Application...'
                      : 'Submit Application',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
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
        borderSide: const BorderSide(color: AppTheme.error),
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
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = [...snapshot.data!.docs]
              ..sort((a, b) {
                final aTime = (a.data()['createdAt'] as num?)?.toInt() ?? 0;
                final bTime = (b.data()['createdAt'] as num?)?.toInt() ?? 0;
                return bTime.compareTo(aTime);
              });
            if (docs.isEmpty) {
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
              children: docs
                  .map((doc) => _buildApplicationCard(theme, doc))
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildApplicationCard(
    ThemeData theme,
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final voting = Map<String, dynamic>.from(
      data['voting'] as Map? ?? const {},
    );
    final status = data['status'] as String? ?? 'voting_open';
    final votingOpen = voting['status'] == 'open';
    final closesAt = (voting['closesAt'] as num?)?.toInt() ?? 0;
    final expired =
        votingOpen &&
        closesAt > 0 &&
        DateTime.now().millisecondsSinceEpoch > closesAt;
    final yay = (voting['yayCount'] as num?)?.toInt() ?? 0;
    final nay = (voting['nayCount'] as num?)?.toInt() ?? 0;
    final abstain = (voting['abstainCount'] as num?)?.toInt() ?? 0;
    final total = (voting['totalVotes'] as num?)?.toInt() ?? 0;
    final quorum = (voting['minimumQuorum'] as num?)?.toInt() ?? 10;
    final amount = (data['requestedAmount'] as num?)?.toInt() ?? 0;
    final busy = _pendingApplicationActions.contains(document.id);
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
                    document.id,
                    'yay',
                    'Yay',
                    AppTheme.accent,
                    busy,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildVoteButton(
                    document.id,
                    'nay',
                    'Nay',
                    theme.colorScheme.error,
                    busy,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildVoteButton(
                    document.id,
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
                onPressed: busy ? null : () => _resolveVote(document.id),
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
        side: BorderSide(color: color.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      ),
      child: Text(label),
    );
  }

  Future<void> _castVote(String applicationId, String verdict) async {
    setState(() => _pendingApplicationActions.add(applicationId));
    try {
      await FirebaseFunctions.instance.httpsCallable('castDdiLoanVote').call({
        'applicationId': applicationId,
        'verdict': verdict,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Your ${verdict.toUpperCase()} vote was recorded.'),
          ),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Could not record your vote.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _pendingApplicationActions.remove(applicationId));
      }
    }
  }

  Future<void> _resolveVote(String applicationId) async {
    setState(() => _pendingApplicationActions.add(applicationId));
    try {
      await FirebaseFunctions.instance
          .httpsCallable('resolveDdiLoanVoting')
          .call({'applicationId': applicationId});
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Could not finalize this vote.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _pendingApplicationActions.remove(applicationId));
      }
    }
  }

  Future<void> _submitApplication() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_confirmsHostBusiness) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Confirm that this business operates in your host community.',
          ),
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

    setState(() => _isSubmitting = true);
    String? discussionChatId;
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('submitDdiLoanApplication')
          .call({
            'communityId': widget.communityId ?? widget.community?.id,
            'fullLegalName': _fullNameController.text.trim(),
            'loanType': _loanType,
            'requestedAmount': int.parse(_amountController.text.trim()),
            'purpose': _purposeController.text.trim(),
            'businessName': _businessNameController.text.trim(),
            'businessDescription': _businessDescriptionController.text.trim(),
            'repaymentPeriod': _repaymentPeriod,
            'repaymentPlan': _repaymentPlanController.text.trim(),
            'confirmsHostBusiness': _confirmsHostBusiness,
          });
      final resultData = Map<String, dynamic>.from(result.data as Map);
      discussionChatId = resultData['discussionChatId'] as String?;
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Could not submit this application.'),
        ),
      );
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save application: $e')));
      return;
    }

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    // Funding remains pending TGE, but discussion and community voting begin.
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
          'Your PoCT and host-community eligibility gates passed. Your loan '
          'application has been saved, its public discussion group is live, '
          'and the 10-day community vote is open.\n\n'
          'Any community approval remains pending the Token Generation Event '
          '(TGE) and \$DIASPORA collateral capacity verification.',
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          if (discussionChatId != null)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                context.push('/chats/$discussionChatId');
              },
              child: const Text('Open Discussion'),
            ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _showApplicationForm = false);
              // Clear form
              _fullNameController.clear();
              _amountController.clear();
              _purposeController.clear();
              _businessNameController.clear();
              _businessDescriptionController.clear();
              _repaymentPlanController.clear();
              _confirmsHostBusiness = false;
            },
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
    );
  }
}
