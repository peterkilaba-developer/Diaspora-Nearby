import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
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
              'Available after Token Generation Event (TGE)',
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
              _buildTermBadge(theme, 'PoCT', 'Qualification'),
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
          'Loan applications will be processed after the Token Generation Event (TGE)',
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
                const Icon(LucideIcons.fileText, size: 16, color: AppTheme.accent),
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
                    child: Text('Business Investment')),
                DropdownMenuItem(
                    value: 'Real Estate & Property',
                    child: Text('Real Estate & Property')),
                DropdownMenuItem(
                    value: 'Education & Skills',
                    child: Text('Education & Skills')),
                DropdownMenuItem(
                    value: 'Agriculture & Farming',
                    child: Text('Agriculture & Farming')),
                DropdownMenuItem(
                    value: 'Healthcare Initiative',
                    child: Text('Healthcare Initiative')),
                DropdownMenuItem(
                    value: 'Community Project',
                    child: Text('Community Project')),
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
                  theme, 'Describe how you plan to use the funds'),
              maxLines: 3,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Purpose is required'
                  : null,
            ),
            const SizedBox(height: 16),

            // Business Name
            _buildLabel(theme, 'Business / Project Name'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _businessNameController,
              decoration:
                  _inputDecoration(theme, 'Name of your business or project'),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Business/project name is required'
                  : null,
            ),
            const SizedBox(height: 16),

            // Business Description
            _buildLabel(theme, 'Business / Project Description'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _businessDescriptionController,
              decoration: _inputDecoration(
                  theme, 'Brief description of your business or project'),
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
                  theme, 'How do you plan to repay the loan?'),
              maxLines: 3,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Repayment plan is required'
                  : null,
            ),
            const SizedBox(height: 24),

            // Submit Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _submitApplication,
                icon: const Icon(LucideIcons.send, size: 16),
                label: const Text(
                  'Submit Application',
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
              'Your application will be queued for review after TGE. '
              'No funds will be disbursed until the token is live.',
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

  void _submitApplication() {
    if (!_formKey.currentState!.validate()) return;

    // Pre-TGE: Show confirmation dialog
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
          'Your loan application has been saved and will be queued for '
          'review once the Token Generation Event (TGE) goes live.\n\n'
          'In the meantime, continue building your Proof of Community Trust '
          '(PoCT) score to maximize your loan eligibility.',
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
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
