import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/shared/ui/glass_container.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/more/widgets/business_registration_modal.dart';
import 'package:diaspora_nearby/features/shared/screens/placeholder_screen.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/providers/theme_provider.dart';
import 'dart:ui';
import 'package:diaspora_nearby/services/push_notification_service.dart';
import 'package:diaspora_nearby/models/profile_data.dart';
import 'package:diaspora_nearby/models/profile_data.dart';
import 'package:diaspora_nearby/services/sharing_service.dart';
import 'package:diaspora_nearby/features/organization/screens/organization_management_screen.dart'; // [NEW]
import 'package:diaspora_nearby/features/settings/screens/privacy_settings_screen.dart'; // [NEW]
import 'package:diaspora_nearby/features/more/screens/feedback_screen.dart';

class MoreScreen extends ConsumerStatefulWidget {
  const MoreScreen({super.key});

  @override
  ConsumerState<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends ConsumerState<MoreScreen> {
  bool _showLogoutConfirm = false;
  int _deletableChatsCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchDeletableChatsCount();
  }

  Future<void> _fetchDeletableChatsCount() async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
       if (!mounted) return;
       final count = await ref.read(chatRepositoryProvider).getDeletableChatsCount();
       if (mounted) {
         setState(() => _deletableChatsCount = count);
       }
    });
  }

  @override
  Widget build(BuildContext context) {

    final userProfile = ref.watch(userProfileProvider).value;
    final theme = Theme.of(context);
    
    // Pixel Parity: Header Height Logic
    final topPadding = MediaQuery.of(context).padding.top;
    const headerHeight = 56.0;

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Background - assuming global background, but ensuring it's here
          // If we had a global background image/gradient, it would be behind everything.
          // For now, using scaffold background.

          // Content
          CustomScrollView(
            slivers: [
               SliverPadding(
                padding: EdgeInsets.only(top: topPadding + headerHeight + 16, bottom: 80, left: 8, right: 8),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    
                    // PWA Install Button (Stub/Adapted)
                    // React has PWA install card. In pure Flutter mobile, we don't need this usually.
                    // But for parity, if targeting Web, we might. 
                    // Proceeding to omit PWA install unless user asks, focusing on menu sections.
                    
                    // --- Quick Actions ---
                    _buildSectionHeader('QUICK ACTIONS'),

                     GlassContainer(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                           // Moved "Invite" to top and renamed
                           _buildMenuItem(
                            icon: LucideIcons.share2, 
                            iconColor: const Color(0xFF25D366), 
                            title: 'Invite family and friends',
                            subtitle: 'Share the app with others',
                            onTap: () {
                               SharingService.instance.shareApp();
                            }
                           ),

                           if (userProfile?.isAdmin == true)
                             _buildMenuItem(
                               icon: LucideIcons.layoutDashboard,
                               iconColor: Colors.deepPurple,
                               title: 'Admin Dashboard',
                               subtitle: 'Manage app, users, and content',
                               onTap: () {
                                 context.push('/admin');
                               },
                             ),

                           _buildMenuItem(
                            icon: LucideIcons.bell,
                            iconColor: Colors.blue,
                            title: 'Notifications',
                            subtitle: 'View all your notifications',
                            onTap: () {
                               context.push('/notifications');
                            }
                           ),

                           _buildMenuItem(
                            icon: LucideIcons.plus,
                            iconColor: theme.colorScheme.primary,
                            title: 'Events', // Renamed
                            subtitle: 'Organize or manage community events',
                            onTap: () async {
                               context.push('/events/create');
                            }
                           ),

                           _buildMenuItem(
                            icon: LucideIcons.building2,
                            iconColor: Colors.blue.shade600,
                            title: 'Organizations',
                            subtitle: 'Register, browse or manage organizations',
                            onTap: () {
                               _showOrganizationsMenu(context, theme);
                            }
                           ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // --- Your Account ---
                    _buildSectionHeader('YOUR ACCOUNT'),
                    GlassContainer(
                       padding: EdgeInsets.zero,
                       child: Column(
                         children: [
                             _buildMenuItem(
                               icon: LucideIcons.user,
                               iconColor: Colors.green,
                               title: 'My Profile',
                               subtitle: 'Update your personal information',
                               onTap: () {
                                 final uid = userProfile?.uid ?? ref.read(authRepositoryProvider).currentUser?.uid;
                                 if (uid != null) {
                                    context.push('/profile/$uid'); 
                                 } else {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile not found')));
                                 }
                               }
                             ),
                             
                             // Moved Push Notifications here
                             _buildMenuItem(
                               icon: LucideIcons.bell,
                               iconColor: Colors.purple,
                               title: 'Push Notifications',
                               subtitle: 'Manage notification preferences',
                               onTap: () {
                                  if (userProfile != null && userProfile.uid != null) {
                                     _showNotificationDialog(userProfile);
                                  }
                               }
                             ),

                             // Removed redundant "Manage Organizations"

                           _buildMenuItem(
                             icon: LucideIcons.shield,
                             iconColor: Colors.blue.shade600,
                             title: 'Privacy & Safety',
                             subtitle: 'Control your privacy settings',
                             onTap: () {
                                Navigator.of(context).push(MaterialPageRoute(
                                 builder: (_) => const PlaceholderScreen(
                                   title: 'Privacy & Safety', 
                                   icon: LucideIcons.shield,
                                   message: 'Manage your privacy settings and blocked users here.\n\n(Coming Soon)',
                                 )
                               ));
                             }
                           ),

                           _buildMenuItem(
                             icon: LucideIcons.settings,
                             iconColor: Colors.grey,
                             title: 'Settings',
                             subtitle: 'App preferences and notifications',
                             onTap: () {
                                Navigator.of(context).push(MaterialPageRoute(
                                 builder: (_) => const PlaceholderScreen(
                                   title: 'Settings', 
                                   icon: LucideIcons.settings,
                                   message: 'General application settings.\n\n(Coming Soon)',
                                 )
                               ));
                             }
                           ),
                         ],
                       ),
                    ),
                    const SizedBox(height: 16),

                    // --- Support & Feedback ---
                    _buildSectionHeader('SUPPORT & FEEDBACK'),
                    GlassContainer(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          _buildMenuItem(
                            icon: LucideIcons.helpCircle,
                            iconColor: Colors.cyan,
                            title: 'Help Center',
                            subtitle: 'Get help and find answers',
                             onTap: () {
                                Navigator.of(context).push(MaterialPageRoute(
                                 builder: (_) => const PlaceholderScreen(
                                   title: 'Help Center', 
                                   icon: LucideIcons.helpCircle,
                                   message: 'Find answers to common questions or contact support.\n\n(Coming Soon)',
                                 )
                               ));
                             }
                           ),

                           _buildMenuItem(
                            icon: LucideIcons.messageSquare,
                            iconColor: Colors.indigo,
                            title: 'Send Feedback',
                            subtitle: 'Help us improve the app',
                             onTap: () {
                                Navigator.of(context).push(MaterialPageRoute(
                                 builder: (_) => const FeedbackScreen(), // Linked FeedbackScreen
                               ));
                             }
                           ),

                           _buildMenuItem(
                            icon: LucideIcons.star,
                            iconColor: Colors.orange, 
                            title: 'Rate App',
                            subtitle: 'Share your experience',
                             onTap: () {
                                Navigator.of(context).push(MaterialPageRoute(
                                 builder: (_) => const PlaceholderScreen(
                                   title: 'Rate App', 
                                   icon: LucideIcons.star,
                                   message: 'Enjoying the app? Please rate us on the app store!\n\n(Coming Soon)',
                                 )
                               ));
                             }
                           ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // --- Chat Management ---
                    _buildSectionHeader('CHAT MANAGEMENT'),
                     GlassContainer(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          _buildMenuItem(
                            icon: LucideIcons.trash2,
                            iconColor: const Color(0xFFEF4444), // Red-500
                            title: 'Delete all chats',
                             subtitle: _deletableChatsCount > 0 
                                ? '$_deletableChatsCount chats can be deleted' 
                                : 'No chats to delete',
                             subtitleColor: _deletableChatsCount > 0 
                                ? theme.colorScheme.error 
                                : theme.disabledColor,
                             onTap: () async {
                                 if (_deletableChatsCount == 0) return;

                                 final confirm = await showDialog<bool>(
                                   context: context,
                                   builder: (context) => AlertDialog(
                                     title: const Text('Delete All Chats'),
                                     content: Text('Are you sure you want to delete these $_deletableChatsCount chats? This will remove them from your list. Community chats will remain.'),
                                     actions: [
                                       TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                       TextButton(
                                          onPressed: () => Navigator.pop(context, true), 
                                          child: const Text('Delete', style: TextStyle(color: Colors.red))
                                       ),
                                     ],
                                   )
                                 );

                                 if (confirm == true) {
                                   await ref.read(chatRepositoryProvider).clearAllChats();
                                   await _fetchDeletableChatsCount();
                                   if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chats cleared.')));
                                   }
                                 }
                             }
                           ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // --- App Info ---
                    GlassContainer(
                      child: Column(
                         children: [
                            ColorFiltered(
                              colorFilter: ColorFilter.mode(
                                theme.colorScheme.primary, // Sage green
                                BlendMode.srcIn,
                              ),
                              child: Image.asset('assets/icons/logo-original.png', width: 80, height: 80),
                            ),
                            const SizedBox(height: 12),
                            const Text('Diaspora Nearby', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16)),
                            const SizedBox(height: 4),
                            Text('Version 1.0.0', style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color)),
                            Text('Connecting diaspora communities worldwide', style: TextStyle(fontSize: 10, color: theme.textTheme.bodySmall?.color)),
                         ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // --- Logout ---
                     GlassContainer(
                      padding: EdgeInsets.zero,
                      child: _buildMenuItem(
                        icon: LucideIcons.logOut,
                        iconColor: const Color(0xFFEF4444),
                        title: 'Log Out',
                        titleColor: const Color(0xFFEF4444),
                        subtitle: 'Sign out of your account',
                        onTap: () {
                           setState(() => _showLogoutConfirm = true);
                        }
                      ),
                    ),

                  ]),
                ),
               ),
            ],
          ),

          // Header (Fixed/Glass)
          Positioned(
            top: 0, left: 0, right: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  height: topPadding + headerHeight,
                  padding: EdgeInsets.only(top: topPadding),
                  color: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Back Button & Title
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => context.pop(), 
                              icon: const Icon(LucideIcons.arrowLeft),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            const SizedBox(width: 12),
                            const Text('Account', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          ],
                        ),

                        // Theme Toggles
                        Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface, // Or accent
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.all(4),
                          child: Row(
                            children: [
                               _buildThemeToggle(LucideIcons.sun, ThemeMode.light), 
                               _buildThemeToggle(LucideIcons.moon, ThemeMode.dark),  
                               _buildThemeToggle(LucideIcons.monitor, ThemeMode.system),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          
          if (_showLogoutConfirm)
            _buildLogoutConfirmation(),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12, 
          fontWeight: FontWeight.w600, 
          color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7),
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required Color iconColor,
    required String title, 
    required String subtitle,
    required VoidCallback onTap,

    Color? titleColor,
    Color? subtitleColor,
    Widget? iconWidget, // [NEW] Optional custom widget
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
       child: Padding(
         padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
         child: Row(
           children: [
             // Icon Circle
             Container(
               width: 40, height: 40,
               decoration: BoxDecoration(
                 color: iconColor.withOpacity(0.1),
                 shape: BoxShape.circle,
               ),
               child: iconWidget ?? Icon(icon, color: iconColor, size: 20),
             ),
             const SizedBox(width: 12),
             
             // Text
             Expanded(
               child: Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                   Text(
                     title, 
                     style: TextStyle(
                       fontWeight: FontWeight.w500, 
                       fontSize: 16,
                       color: titleColor ?? theme.textTheme.bodyMedium?.color
                     )
                   ),
                   if (subtitle.isNotEmpty)
                    Text(
                      subtitle, 
                      style: TextStyle(
                        fontSize: 13, 
                        color: subtitleColor ?? theme.textTheme.bodySmall?.color?.withOpacity(0.7)
                      )
                    ),
                 ],
               ),
             ),
             
             Icon(LucideIcons.chevronRight, size: 16, color: theme.iconTheme.color?.withOpacity(0.3)),
           ],
         ),
       ),
    );
  }

  Widget _buildThemeToggle(IconData icon, ThemeMode mode) {
     final currentTheme = ref.watch(themeProvider);
     final isActive = currentTheme == mode;

     return GestureDetector(
       onTap: () {
         ref.read(themeProvider.notifier).setTheme(mode);
       },
       child: Container(
         width: 36, height: 36,
         decoration: isActive ? BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
               BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 2),
            ]
         ) : null,
         child: Icon(icon, size: 16, color: isActive ? Theme.of(context).colorScheme.primary : Theme.of(context).disabledColor),
       ),
     );
  }

  Widget _buildLogoutConfirmation() {
    final theme = Theme.of(context);
    return Container(
      color: Colors.black54, // Modal barrier
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: GlassContainer(
            color: theme.cardTheme.color, // Ensure opacity is handled by GlassContainer logic if needed, or pass explicit
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(LucideIcons.logOut, color: theme.colorScheme.error, size: 24),
                ),
                const SizedBox(height: 16),
                const Text('Log Out', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  'Are you sure you want to log out? You\'ll need to sign in again to access your account.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.textTheme.bodySmall?.color?.withOpacity(0.7)),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() => _showLogoutConfirm = false),
                        style: OutlinedButton.styleFrom(
                           padding: const EdgeInsets.symmetric(vertical: 12),
                           side: BorderSide(color: theme.dividerColor.withOpacity(0.2)), // Or transparent if no border desired
                           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                           foregroundColor: theme.textTheme.bodyMedium?.color, // Button text color
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                           ref.read(authRepositoryProvider).signOut();
                           // Router automatically handles redirect
                        },
                        style: ElevatedButton.styleFrom(
                           backgroundColor: theme.colorScheme.error,
                           padding: const EdgeInsets.symmetric(vertical: 12),
                           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                           foregroundColor: theme.colorScheme.onError,
                        ),
                        child: const Text('Log Out'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  void _showNotificationDialog(ProfileData userProfile) {
    showDialog(
      context: context,
      builder: (context) {
        bool isEnabled = userProfile.notificationsEnabled ?? false;
        
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(children: [Icon(LucideIcons.bell), SizedBox(width: 8), Text('Notifications')]),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                     title: const Text('Enable Notifications'),
                     subtitle: Text(isEnabled ? 'You will receive updates' : 'Notifications are disabled'),
                     value: isEnabled,
                     activeColor: Colors.purple,
                     onChanged: (val) async {
                        setDialogState(() => isEnabled = val); 
                        if (val) {
                           await ref.read(pushNotificationServiceProvider).registerForUser(userProfile.uid!);
                        } else {
                           await ref.read(pushNotificationServiceProvider).disableNotifications(userProfile.uid!);
                        }
                     },
                  ),
                  const SizedBox(height: 8),
                  const Text('Customize individual alerts in system settings.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
              ],
            );
          }
        );
      },
    );
  }

  void _showOrganizationsMenu(BuildContext context, ThemeData theme) {
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 16,
          left: 16, right: 16, top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            
            // Header
            Row(
              children: [
                Icon(LucideIcons.building2, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  'Organizations',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Browse Organizations
            _buildOrgMenuItem(
              context,
              icon: LucideIcons.search,
              title: 'Browse Organizations',
              subtitle: 'Discover and join organizations',
              onTap: () {
                Navigator.pop(context);
                context.push('/organizations');
              },
            ),
            const Divider(height: 1),

            // Register Organization
            _buildOrgMenuItem(
              context,
              icon: LucideIcons.plus,
              title: 'Register Organization',
              subtitle: 'Create a new business or organization',
              onTap: () {
                Navigator.pop(context);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => const BusinessRegistrationModal(),
                );
              },
            ),
            const Divider(height: 1),

            // Manage My Organizations
            _buildOrgMenuItem(
              context,
              icon: LucideIcons.settings,
              title: 'Manage My Organizations',
              subtitle: 'View and manage organizations you admin',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const OrganizationManagementScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrgMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: theme.colorScheme.primary, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.6))),
      trailing: const Icon(LucideIcons.chevronRight, size: 18),
      onTap: onTap,
    );
  }
}

