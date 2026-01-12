import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

class ShareOptionsSheet extends StatelessWidget {
  final String referralCode;
  final String homeCountry;

  const ShareOptionsSheet({
    super.key,
    required this.referralCode,
    required this.homeCountry,
  });

  void _showPlatformSelector(BuildContext context, String messageSubject, String messageBody) {
    // Construct the link
    final String link = 'https://diasporanearby.com/invite?code=$referralCode';
    final String whatsappMessage = '$messageBody\n\nSign up here: $link';
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Share via',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildPlatformButton(
                    context,
                    label: 'WhatsApp',
                    icon: LucideIcons.messageCircle, // Using generic icon as Lucide doesn't have brand icons
                    color: Colors.green,
                    onTap: () => _launchWhatsApp(context, whatsappMessage),
                  ),
                  _buildPlatformButton(
                    context,
                    label: 'Facebook',
                    icon: LucideIcons.facebook, 
                    color: Colors.blue,
                    onTap: () => _launchFacebook(context, link),
                  ),
                ],
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPlatformButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 32),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Future<void> _launchWhatsApp(BuildContext context, String message) async {
    Navigator.pop(context); // Close selector
    // Use externalApplication mode to force open the app
    final url = Uri.parse('whatsapp://send?text=${Uri.encodeComponent(message)}');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        // Fallback to web whatsapp if app not installed or fails
        final webUrl = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(message)}');
        if (await canLaunchUrl(webUrl)) {
             await launchUrl(webUrl, mode: LaunchMode.externalApplication);
        } else {
           if (context.mounted) {
             ScaffoldMessenger.of(context).showSnackBar(
               const SnackBar(content: Text('Could not launch WhatsApp')),
             );
           }
        }
      }
    } catch (e) {
      debugPrint('Error launching WhatsApp: $e');
    }
  }

  Future<void> _launchFacebook(BuildContext context, String link) async {
    Navigator.pop(context); // Close selector
    // Facebook sharing usually only takes the URL.
    final url = Uri.parse('https://www.facebook.com/sharer/sharer.php?u=${Uri.encodeComponent(link)}');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Could not launch Facebook')),
           );
         }
      }
    } catch (e) {
      debugPrint('Error launching Facebook: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      // ... existing build method ...
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Share Invitation',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                onPressed: () => context.pop(),
                icon: const Icon(LucideIcons.x),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Choose how you want to connect:',
            style: TextStyle(
              color: Theme.of(context).hintColor,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 20),
          
          // Grid of 4 options
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.1, // Slightly wider than tall
            children: [
              _buildOptionCard(
                context,
                icon: LucideIcons.home,
                title: 'Share with Family',
                subtitle: 'Connect with Family in $homeCountry',
                onTap: () => _showPlatformSelector(
                  context,
                  'Share with Family (Home)',
                  'Hi! I\'m using the Diaspora Nearby app to connect with our family and community in $homeCountry. It\'s a great way to handle remittances, investments, and stay in touch.',
                ),
              ),
              _buildOptionCard(
                context,
                icon: LucideIcons.plane,
                title: 'Share with Family',
                subtitle: 'Connect with Family Abroad',
                onTap: () => _showPlatformSelector(
                  context,
                  'Share with Family (Abroad)',
                  'Hi! I found this app Diaspora Nearby to help us stay connected with family abroad. We can track events, investments, and support each other easily.',
                ),
              ),
              _buildOptionCard(
                context,
                icon: LucideIcons.users,
                title: 'Share with Friends',
                subtitle: 'Connect with Friends in $homeCountry',
                onTap: () => _showPlatformSelector(
                  context,
                  'Share with Friends (Home)',
                  'Hey! Check out the Diaspora Nearby app. It\'s the best way to connect with our friends back in $homeCountry and explore opportunities together.',
                ),
              ),
              _buildOptionCard(
                context,
                icon: LucideIcons.globe,
                title: 'Share with Friends',
                subtitle: 'Connect with Friends Abroad',
                onTap: () => _showPlatformSelector(
                  context,
                  'Share with Friends (Abroad)',
                  'Hey! I\'m using the Diaspora Nearby app to find and connect with friends abroad. It\'s awesome for finding community events and opportunities near us.',
                ),
              ),
            ],
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 10),
        ],
      ),
    );
  }

  Widget _buildOptionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTheme.accent.withOpacity(0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.accent.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.accent.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: AppTheme.accent,
                size: 24,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).hintColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
