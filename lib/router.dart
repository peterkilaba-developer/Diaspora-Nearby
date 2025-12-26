import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/auth/screens/phone_auth_screen.dart';
import 'features/auth/screens/otp_verification_screen.dart';
import 'features/auth/repository/auth_repository.dart';
import 'features/profile/repository/profile_repository.dart';
import 'features/profile/screens/profile_setup_screen.dart';
import 'features/profile/screens/user_profile_screen.dart';
import 'features/home/screens/home_screen.dart';
import 'features/chat/screens/chats_list_screen.dart';
import 'features/chat/screens/chat_screen.dart';
import 'features/chat/screens/group_info_screen.dart';
import 'features/chat/screens/forward_chat_selection_screen.dart';
import 'features/chat/screens/start_direct_chat_screen.dart';
import 'features/community/screens/communities_screen.dart';
import 'features/community/screens/community_members_screen.dart';
import 'package:diaspora_nearby/services/session_service.dart';
import 'package:diaspora_nearby/models/community_data.dart';
import 'package:geolocator/geolocator.dart'; // Added for strict enforcement
import 'features/events/screens/events_screen.dart';
import 'features/events/screens/event_detail_screen.dart';
import 'features/events/screens/create_event_screen.dart';
import 'features/events/screens/qr_attendance_screen.dart';
import 'package:diaspora_nearby/features/events/screens/event_attendees_screen.dart'; 
import 'package:diaspora_nearby/services/local_cache_service.dart'; 
import 'package:diaspora_nearby/features/events/screens/organizer_events_screen.dart'; // [NEW]
import 'features/more/screens/more_screen.dart';
import 'features/auth/screens/banned_screen.dart'; // [NEW]
import 'package:diaspora_nearby/features/notifications/screens/notifications_screen.dart';
import 'features/radio/screens/radio_screen.dart';
import 'features/shared/screens/scaffold_with_nav_bar.dart';
import 'features/shared/screens/splash_screen.dart';
import 'package:diaspora_nearby/models/event_data.dart';
import 'package:diaspora_nearby/features/admin_dashboard/screens/admin_dashboard_screen.dart';
import 'package:diaspora_nearby/features/admin_dashboard/screens/admin_overview_screen.dart';
import 'package:diaspora_nearby/features/admin_dashboard/screens/admin_users_screen.dart';
import 'package:diaspora_nearby/features/admin_dashboard/screens/admin_communities_screen.dart';
import 'package:diaspora_nearby/features/organization/screens/organizations_list_screen.dart';
import 'package:diaspora_nearby/features/organization/screens/organization_management_screen.dart';
import 'package:diaspora_nearby/features/organization/screens/organization_detail_screen.dart';
import 'package:diaspora_nearby/features/more/widgets/business_registration_modal.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  final userProfileAsync = ref.watch(userProfileProvider);
  
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/auth/phone', 
    redirect: (context, state) async {
      final isLoading = authState.isLoading || userProfileAsync.isLoading;
      final hasError = authState.hasError || userProfileAsync.hasError;
      final isAuthenticated = authState.value != null;
      
      final isAuthRoute = state.matchedLocation.startsWith('/auth');
      
      // Explicitly handle loading state
      // Explicitly handle loading state
      // if (isLoading) return '/splash'; // MOVED logic below
      
      
      // Only show global splash if we are in an "initializing" phase
      // i.e. we are at root/auth or we explicitly need to block.
      // Doing this prevents disrupting UX on pages like Communities that handle their own loading/error states.
      final isBootstrapping = state.matchedLocation == '/' || state.matchedLocation.startsWith('/auth') || state.matchedLocation == '/splash';

      if (authState.isLoading || (isBootstrapping && userProfileAsync.isLoading)) {
         return '/splash';
      }
      
      if (hasError) return null; // Or error page

      if (!isAuthenticated && !isAuthRoute) {
        return '/auth/phone';
      }

      if (isAuthenticated) {
        final user = authState.value!;
        final profile = userProfileAsync.value;

        // Allow OTP screen to show even when Firebase Auth detects phone number
        // User is not fully authenticated until OTP is verified
        if (isAuthRoute && state.matchedLocation != '/auth/otp') {
           // Check profile exists
            final uidExists = await ref.read(profileRepositoryProvider).profileExists(user.uid) || LocalCacheService.prefs.containsKey('cached_user_${user.uid}');
    if (!uidExists) return '/profile-setup';
           
           // Check returning user status
           final sessionService = ref.read(sessionServiceProvider);
           final isReturning = await sessionService.isReturningUser();
           return isReturning ? '/chats' : '/nearby';
        }
        
        if (state.matchedLocation == '/profile-setup' && userProfileAsync.value != null) {
           // Check for community memberships integrity
           final profile = userProfileAsync.value!;
           if (profile.communityMemberships == null || profile.communityMemberships!.isEmpty) {
              return null; // Stay on cleanup/setup screen
           }
           
           final sessionService = ref.read(sessionServiceProvider);
           final isReturning = await sessionService.isReturningUser();
           return isReturning ? '/chats' : '/nearby';
        }
        
        // --- STRICT LOCATION ENFORCEMENT ---
        // If user is authenticated and setup is complete, we check permission.
        // We skip this check if we are already going to /profile or /profile-setup
        if (!state.matchedLocation.startsWith('/auth') && 
            state.matchedLocation != '/profile-setup') {
            
          final permission = await Geolocator.checkPermission();
          if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
             // Block navigation and force to profile if not already there
             if (state.matchedLocation != '/profile') {
                return '/profile?enforceLocation=true';
             }
          }
        }
        // -----------------------------------
        
        // Check for Ban
        if (profile?.isBanned == true) {
           return '/banned';
        }
        
        // Data Integrity Guard for Root/Auth redirect
        if (state.matchedLocation == '/' || state.matchedLocation.startsWith('/auth')) {
           if (profile?.communityMemberships == null || profile!.communityMemberships!.isEmpty) {
              return '/profile-setup';
           }
           
           final sessionService = ref.read(sessionServiceProvider);
           final isReturning = await sessionService.isReturningUser();
           return isReturning ? '/chats' : '/nearby';
        }
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      
      // Profile Setup (No Shell)
      GoRoute(
        path: '/profile-setup',
        builder: (context, state) => const ProfileSetupScreen(),
      ),

      // Auth Routes (No Shell)
      GoRoute(
        path: '/auth/phone',
        builder: (context, state) => const PhoneAuthScreen(),
      ),
      GoRoute(
        path: '/auth/otp',
        builder: (context, state) {
          final extras = state.extra as Map<String, dynamic>;
          return OTPVerificationScreen(
            verificationId: extras['verificationId'] as String,
            phoneNumber: extras['phoneNumber'] as String,
          );
        },
      ),

      // Redirect /download to home (For Invite Links)
      GoRoute(
        path: '/download',
        redirect: (context, state) => '/', 
        builder: (context, state) => const SizedBox.shrink(),
      ),

      GoRoute(
        path: '/communities/:id',
        redirect: (context, state) {
           final id = state.pathParameters['id'];
           return '/communities/$id/members';
        }, 
         builder: (context, state) => const SizedBox.shrink(),
      ),

      // Organizations List Screen
      GoRoute(
        path: '/organizations',
        builder: (context, state) => const OrganizationsListScreen(),
      ),

      // Organization Detail Route
      GoRoute(
        path: '/organization/:orgId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final orgId = state.pathParameters['orgId']!;
          final extra = state.extra as Map<String, dynamic>?;
          return OrganizationDetailScreen(orgId: orgId, initialData: extra);
        },
      ),

      // Organization Management Route
      GoRoute(
        path: '/organization/manage',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final orgId = state.uri.queryParameters['orgId'];
          return OrganizationManagementScreen(initialOrgId: orgId);
        },
      ),

      // Main App Shell - 3 Tabs (Chats, Nearby, Events)
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return ScaffoldWithNavBar(navigationShell: navigationShell);
        },
        branches: [
          // 0: Chats
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/chats',
                builder: (context, state) => const ChatsListScreen(),
                routes: [
                   GoRoute(
                      path: 'forward_selection',
                      parentNavigatorKey: _rootNavigatorKey,
                      builder: (context, state) => const ForwardChatSelectionScreen(),
                   ),
                  GoRoute(
                    path: ':chatId',
                    parentNavigatorKey: _rootNavigatorKey, // Hide bottom nav
                    builder: (context, state) {
                      final chatId = state.pathParameters['chatId']!;
                      return ChatScreen(chatId: chatId);
                    },
                    routes: [
                       GoRoute(
                          path: 'info',
                          parentNavigatorKey: _rootNavigatorKey,
                          builder: (context, state) {
                             final chatId = state.pathParameters['chatId']!;
                             final extra = state.extra as Map<String, dynamic>;
                             return GroupInfoScreen(
                                chatId: chatId,
                                groupName: extra['name'],
                                groupImage: extra['image'],
                                currentUserId: ref.read(authRepositoryProvider).currentUser!.uid,
                             );
                          }
                       ),
                    ],
                  ),
                ],
              ),
            ],
          ),

          // 1: Communities
          StatefulShellBranch(
            routes: [
               GoRoute(
                path: '/communities',
                builder: (context, state) => const CommunitiesScreen(),
                routes: [
                   GoRoute(
                    path: ':communityId/members',
                    parentNavigatorKey: _rootNavigatorKey,
                    pageBuilder: (context, state) {
                      final communityId = state.pathParameters['communityId']!;
                      final communityExtra = state.extra as Community;
                      return MaterialPage(
                        fullscreenDialog: true,
                        child: CommunityMembersScreen(
                          communityId: communityId,
                          community: communityExtra,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ]
          ),

          // 2: Nearby (Home)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/nearby',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),

          // 3: Radio
          StatefulShellBranch(
            routes: [
                GoRoute(
                path: '/radio',
                builder: (context, state) => const RadioScreen(),
              ),
            ]
          ),

          // 4: Events
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/events',
                builder: (context, state) => const EventsScreen(),
                routes: [
                  GoRoute(
                     path: 'create',
                     parentNavigatorKey: _rootNavigatorKey,
                     builder: (context, state) => const CreateEventScreen(),
                  ),
                  GoRoute(
                     path: 'manage',
                     parentNavigatorKey: _rootNavigatorKey,
                     builder: (context, state) => const OrganizerEventsScreen(),
                  ),
                  GoRoute(
                     path: 'edit/:eventId',
                     parentNavigatorKey: _rootNavigatorKey,
                     builder: (context, state) {
                        final eventExtra = state.extra as Event?;
                        // If no extra, we might need to fetch by ID in screen or force pass it.
                        // For now assuming extra is passed from manage screen.
                        return CreateEventScreen(eventToEdit: eventExtra);
                     },
                  ),
                  GoRoute(
                    path: ':eventId',
                     parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) {
                      final eventId = state.pathParameters['eventId']!;
                      final eventExtra = state.extra as Event?;
                      return EventDetailScreen(eventId: eventId, event: eventExtra);
                    },
                    routes: [
                        GoRoute(
                          path: 'attendees',
                          parentNavigatorKey: _rootNavigatorKey,
                          pageBuilder: (context, state) {
                             final eventId = state.pathParameters['eventId']!;
                             final eventExtra = state.extra as Event?;
                             return MaterialPage(
                               fullscreenDialog: true,
                               child: EventAttendeesScreen(
                                 eventId: eventId,
                                 event: eventExtra,
                               ),
                             );
                          },
                        ),
                    ],
                  ),
                  GoRoute(
                    path: 'qr/:eventId',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) {
                      final eventId = state.pathParameters['eventId']!;
                      final extra = state.extra as Map<String, dynamic>;
                      return QRAttendanceScreen(
                        eventId: eventId,
                        eventTitle: extra['title'],
                        isCreator: extra['isCreator'],
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/more',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const MoreScreen(),
      ),
       GoRoute(
        path: '/notifications',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const NotificationsScreen(),
      ),

      // Direct chat - creates/gets DM and redirects to chat
      GoRoute(
        path: '/chat/direct/:userId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final userId = state.pathParameters['userId']!;
          return StartDirectChatScreen(otherUserId: userId);
        },
      ),
      
      // Current User Profile (Self)
      GoRoute(
        path: '/profile',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final userId = ref.read(authRepositoryProvider).currentUser?.uid ?? '';
          final enforce = state.uri.queryParameters['enforceLocation'] == 'true';
          return UserProfileScreen(userId: userId, isEnforced: enforce);
        },
      ),
      
      // User Profile Route (Other or Self by ID)
      GoRoute(
        path: '/profile/:userId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final userId = state.pathParameters['userId']!;
          return UserProfileScreen(userId: userId);
        },
      ),

      
      // Admin Dashboard Routes
      ShellRoute(
        builder: (context, state, child) {
           return AdminDashboardScreen(child: child);
        },
        routes: [
           GoRoute(
             path: '/admin',
             redirect: (_, __) => '/admin/overview',
           ),
           GoRoute(
             path: '/admin/overview',
             pageBuilder: (context, state) => const NoTransitionPage(child: AdminOverviewScreen()),
           ),
           GoRoute(
             path: '/admin/users',
             pageBuilder: (context, state) => const NoTransitionPage(child: AdminUsersScreen()),
           ),
           GoRoute(
             path: '/admin/communities',
             pageBuilder: (context, state) => const NoTransitionPage(child: AdminCommunitiesScreen()),
           ),
        ],
      ),
    ],
  );
});
