import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'blocked_users_screen.dart';
import 'legal_content_screen.dart'; // [NEW]

class PrivacySettingsScreen extends StatelessWidget {
  const PrivacySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy & Safety'),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 16,
        ),
        children: [
          _buildSettingsItem(
            context,
            icon: LucideIcons.ban,
            title: 'Blocked Accounts',
            subtitle: 'Manage blocked users',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BlockedUsersScreen()),
              );
            },
          ),
          // Placeholders for future settings
          /*
          _buildSettingsItem(
            context,
            icon: LucideIcons.eye,
            title: 'Last Seen & Online',
            subtitle: 'Everyone',
            onTap: () {},
          ),
          _buildSettingsItem(
            context,
            icon: LucideIcons.lock,
            title: 'Profile Photo',
            subtitle: 'Everyone',
            onTap: () {},
          ),
          */
          const SizedBox(height: 24),
          _buildSectionHeader(context, 'LEGAL'),
          _buildSettingsItem(
            context,
            icon: LucideIcons.fileText,
            title: 'Privacy Policy',
            subtitle: 'Read our privacy policy',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const LegalContentScreen(
                    title: 'Privacy Policy',
                    content: _privacyPolicyContent,
                  ),
                ),
              );
            },
          ),
          _buildSettingsItem(
            context,
            icon: LucideIcons.fileSignature,
            title: 'Terms of Service (EULA)',
            subtitle: 'Read our terms of service',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const LegalContentScreen(
                    title: 'Terms of Service (EULA)',
                    content: _tosContent,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildSettingsItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      title: Text(title),
      subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      trailing: const Icon(LucideIcons.chevronRight, size: 16),
      onTap: onTap,
    );
  }
}

// --- Content Constants ---

const String _privacyPolicyContent = '''
Last Updated: 2026-02-13

1. Introduction
Welcome to Diaspora Nearby ("we," "our," or "us"). We are committed to protecting your privacy. This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our mobile application (the "App").

By using the App, you consent to the data practices described in this policy. If you do not agree with the terms of this Privacy Policy, please do not access the App.

2. Information We Collect
We utilize Google Firebase and other third-party services to provide our services. We may collect the following types of information:

A. Personal Data
When you register or use the App, we collect personal information such as name, username, profile picture, email address, and phone number.

B. Location Data
Crucial for App Functionality: "Diaspora Nearby" is a location-based social network. We collect your precise and coarse location data to connect you with community members, events, and organizations near you. This data is used to display your distance from others and to filter content based on proximity. You can control location access through your device settings at any time.

C. Device & Technical Data
Device model, operating system version, unique device identifiers, IP address, and app usage data via Firebase Analytics.

D. User Generated Content
Media (photos/videos), Audio (voice notes), and Messages (text) sent between users.

3. How We Use Your Information
We use the collected information to:
- Provide Core Services: find and display users, groups, and events near you.
- Account Management: To create, authenticate, and manage your account.
- Communication: To send you updates, security alerts, and support messages.
- Improvement: To analyze usage trends and improve App functionality.
- Safety: To monitor and prevent fraudulent or abusive activity.

4. Permissions We Request
The App may request access to Location, Camera, Microphone, and Storage/Photos to provide its features.

5. Data Sharing and Disclosure
We do not sell your personal data. We share information only with service providers (Google Firebase, Google Maps) to support app functionality, or when required by law.

6. Data Retention and Deletion
We retain your data as long as your account is active. You have the right to delete your account and associated data through app settings.

7. Children's Privacy
The App is not intended for children under 13. We do not knowingly collect personal information from children under 13.

8. Contact Us
If you have questions, contact us at support@diasporanearby.com.
''';

const String _tosContent = '''
Last Updated: 2026-02-13

1. Acceptance of Terms
By accessing and using the Diaspora Nearby mobile application (the "App"), you accept and agree to be bound by the terms and provision of this agreement.

2. User Accounts
To access certain features, you must create an account. You agree to provide accurate information and maintain the security of your account.

3. User Conduct
You agree not to use the App to violate laws, harass others, upload offensive content, or disrupt the network.

4. User Content
You retain ownership of content you post. You grant Diaspora Nearby a license to use and display such content to provide app services.

5. EULA / License Grant
Diaspora Nearby grants you a personal, non-exclusive, non-transferable license to use the App on your mobile device for personal use only.

6. Restrictions
You may not:
- Reverse engineer or attempt to extract source code.
- Use the App for commercial purposes without authorization.
- Circumvent any security measures.

7. Termination
We reserve the right to terminate or suspend your account access immediately for violations of these Terms.

8. Disclaimer of Warranties
The App is provided "AS IS" without warranties of any kind.

9. Limitation of Liability
Diaspora Nearby is not liable for indirect, incidental, or consequential damages arising from app use.

10. Contact Us
For questions, contact us at support@diasporanearby.com.
''';
