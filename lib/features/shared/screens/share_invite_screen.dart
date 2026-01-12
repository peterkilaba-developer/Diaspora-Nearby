import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';

class ShareInviteScreen extends ConsumerStatefulWidget {
  const ShareInviteScreen({super.key});

  @override
  ConsumerState<ShareInviteScreen> createState() => _ShareInviteScreenState();
}

class _ShareInviteScreenState extends ConsumerState<ShareInviteScreen> {
  @override
  Widget build(BuildContext context) {
    return const ShareInviteBody();
  }
  
  // Helper to re-fetch code if needed, but for now we trust FutureBuilder internal state or passed generic
  // Actually, we need the code available for the grid too.
  // Better approach: combine fetches or just pass code down if possible. 
  
  // Reworking build to fetch code once and use it.
}

class ShareInviteBody extends ConsumerStatefulWidget {
    const ShareInviteBody({super.key});

    @override
    ConsumerState<ShareInviteBody> createState() => _ShareInviteBodyState();
}

class _ShareInviteBodyState extends ConsumerState<ShareInviteBody> {
    bool _isGenerating = false;

    Future<void> _generateCode(String userId) async {
        setState(() => _isGenerating = true);
        try {
            // Fetch profile for name/country
            final profile = await ref.read(userProfileByIdProvider(userId).future);
            if (profile != null) {
                 final firstName = profile.firstName;
                 final countryCode = profile.homeLocation.countryCode ?? 'US';
                 
                 await ref.read(pointsRepositoryProvider).generateReferralCode(userId, firstName, countryCode);
                 // Refresh provider/UI will happen automatically if we used a stream, but here we might need to setState or refetch.
                 // Ideally PointsRepository should invalidate a provider, but let's just trigger a rebuild or refetch.
                 ref.invalidate(pointsRepositoryProvider); 
                 setState(() {});
            }
        } catch (e) {
            if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error generating code: $e")));
            }
        } finally {
            if (mounted) setState(() => _isGenerating = false);
        }
    }

    @override
    Widget build(BuildContext context) {
        final user = ref.watch(authRepositoryProvider).currentUser;
        if (user == null) return const SizedBox.shrink();

        final codeFuture = ref.watch(pointsRepositoryProvider).getReferralCode(user.uid);
        
        return FutureBuilder<String?>(
            future: codeFuture,
            builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !_isGenerating) {
                    return const Center(child: CircularProgressIndicator());
                }
                
                final code = snapshot.data;
                // final profileAsync = ref.watch(userProfileByIdProvider(user.uid)); // Unused currently in build

                return Scaffold(
                  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                  appBar: AppBar(
                    title: const Text("Share to your Community"),
                    centerTitle: true,
                    elevation: 0,
                    backgroundColor: Colors.transparent,
                    leading: IconButton(
                        icon: const Icon(LucideIcons.x),
                        onPressed: () => context.pop(),
                    ),
                  ),
                  body: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(AppTheme.pagePadding),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                             minHeight: constraints.maxHeight - MediaQuery.of(context).padding.top - kToolbarHeight - 32, // Adjust for appbar/padding
                          ),
                          child: IntrinsicHeight( // Helps center if needed, or just MainAxisAlignment.center
                            child: Column( // This column needs to be full height to justify center
                              // To truly center in a scroll view, we can verify height directly.
                              // Simplified approach: MainAxisAlignment.center works if constraints force minimum height.
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildHeader(context),
                                const SizedBox(height: 32),
                                // ...
                                
                                if (code != null)
                                    _buildCodeCard(context, code)
                                else
                                    _buildGenerateCard(context, user.uid),
                                    
                                const SizedBox(height: 32),
                                const Text(
                                  "Share via",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 24),
                                
                                if (code != null)
                                     _buildDirectShareButtons(context, code)
                                else
                                     const Center(child: Text("Generate a code to start sharing!", style: TextStyle(color: Colors.grey))),
                                     
                                SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
                              ],
                            ),
                          ),
                        ),
                      );
                    }
                  ),
                );
            }
        );
    }
    
    Widget _buildDirectShareButtons(BuildContext context, String code) {
        final message = "For my family and Friends at home and abroad. Join and connect with me in this platform.";
        // Link is added by the launch helper
        
        return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
                _buildPlatformButton(
                    context,
                    label: 'WhatsApp',
                    icon: LucideIcons.messageCircle,
                    color: Colors.green,
                    onTap: () => _launchWhatsApp(context, message, code),
                ),
                _buildPlatformButton(
                    context,
                    label: 'Facebook',
                    icon: LucideIcons.facebook,
                    color: Colors.blue,
                    onTap: () => _launchFacebook(context, code),
                ),
            ],
        );
    }

    Widget _buildGenerateCard(BuildContext context, String userId) {
        return Container(
            padding: const EdgeInsets.all(AppTheme.cardPadding),
            decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.accent.withOpacity(0.3)),
            ),
            child: Column(
                children: [
                    const Icon(LucideIcons.sparkles, size: 40, color: AppTheme.accent),
                    const SizedBox(height: 16),
                    const Text(
                        "No Invite Code Yet",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                        "Generate your unique code to start inviting friends and earning points.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                        onPressed: _isGenerating ? null : () => _generateCode(userId),
                        style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.accent,
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                        ),
                        child: _isGenerating 
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text("Generate Code"),
                    ),
                ],
            ),
        );
    }
    
    Widget _buildHeader(BuildContext context) {
        return Column(
            children: [
                Container(
                    width: 100, 
                    height: 100,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: AppTheme.accent.withOpacity(0.1),
                        shape: BoxShape.circle,
                    ),
                    child: Image.asset('assets/icons/logo-original.png'),
                ),
                const SizedBox(height: 24),
                const Text(
                    "Invite Family and Friends to Connect",
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                    "Earn 100 DSPs for Each Share",
                    style: TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                ),
            ],
        );
    }

    Widget _buildCodeCard(BuildContext context, String code) {
        return Container(
            padding: const EdgeInsets.all(AppTheme.cardPadding),
            decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.accent.withOpacity(0.3)),
                boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                    ),
                ],
            ),
            child: Column(
                children: [
                    const Text(
                        "YOUR REFERRAL CODE",
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                    code,
                                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 4),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            IconButton(
                                icon: const Icon(LucideIcons.copy, color: AppTheme.accent),
                                onPressed: () {
                                    Clipboard.setData(ClipboardData(text: code));
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Code copied!")));
                                },
                            ),
                        ],
                    ),
                ],
            ),
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

  Future<void> _launchWhatsApp(BuildContext context, String messageBase, String code) async {
    final String link = 'https://diasporanearby.com/invite?code=$code';
    final String fullMessage = '$messageBase\n\nSign up here: $link';
    
    final url = Uri.parse('whatsapp://send?text=${Uri.encodeComponent(fullMessage)}');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        final webUrl = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(fullMessage)}');
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

  Future<void> _launchFacebook(BuildContext context, String code) async {
    final String link = 'https://diasporanearby.com/invite?code=$code';
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
}
