import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/dsp/providers/referral_provider.dart';
import 'features/shared/screens/user_permissions_screen.dart';
import 'features/auth/screens/phone_auth_screen.dart';
import 'features/auth/screens/otp_verification_screen.dart';
import 'features/auth/repository/auth_repository.dart';
import 'features/profile/repository/profile_repository.dart';
import 'features/profile/screens/profile_setup_screen.dart';
import 'features/profile/screens/user_profile_screen.dart';
import 'features/chat/screens/chats_list_screen.dart';
import 'features/chat/screens/chat_screen.dart';
import 'features/chat/screens/group_info_screen.dart';
import 'features/chat/screens/organization_info_screen.dart';

import 'features/chat/screens/forward_chat_selection_screen.dart';
import 'features/chat/screens/start_direct_chat_screen.dart';
import 'features/community/screens/communities_screen.dart';
import 'features/community/screens/community_members_screen.dart';
import 'package:diaspora_nearby/features/auth/services/session_service.dart';
import 'package:diaspora_nearby/features/community/models/community_data.dart';
import 'package:diaspora_nearby/features/chat/models/message.dart';
import 'features/events/screens/events_screen.dart';
import 'features/events/screens/event_detail_screen.dart';
import 'features/events/screens/create_event_screen.dart';
import 'features/events/screens/qr_attendance_screen.dart';
import 'package:diaspora_nearby/features/events/screens/event_attendees_screen.dart';
import 'package:diaspora_nearby/features/events/screens/organizer_events_screen.dart';
import 'features/radio/screens/radio_screen.dart';
import 'features/shared/screens/scaffold_with_nav_bar.dart';
import 'features/shared/screens/splash_screen.dart';
import 'package:diaspora_nearby/features/events/models/event_data.dart';
import 'package:diaspora_nearby/features/admin_dashboard/screens/admin_dashboard_screen.dart';
import 'package:diaspora_nearby/features/admin_dashboard/screens/admin_overview_screen.dart';
import 'package:diaspora_nearby/features/admin_dashboard/screens/admin_users_screen.dart';
import 'package:diaspora_nearby/features/admin_dashboard/screens/admin_communities_screen.dart';
import 'package:diaspora_nearby/features/admin_dashboard/screens/admin_chamber_requests_screen.dart';
import 'package:diaspora_nearby/features/organization/screens/organizations_list_screen.dart';
import 'package:diaspora_nearby/features/organization/screens/organization_management_screen.dart';
import 'package:diaspora_nearby/features/organization/screens/organization_detail_screen.dart';
import 'features/shared/screens/error_screen.dart';
import 'features/home/screens/home_screen.dart';
import 'features/dsp/screens/points_system_screen.dart';
import 'features/dsp/screens/remittances_screen.dart';
import 'features/dsp/screens/emergency_fund_screen.dart';
import 'features/dsp/screens/emergency_fund_transparency_screen.dart';
import 'features/dsp/screens/airline_portal_screen.dart';
import 'features/dsp/screens/dfdi_screen.dart';
import 'features/dsp/screens/diaspora_crypto_screen.dart';
import 'features/dsp/screens/economy_hub_screen.dart';
import 'features/travel/screens/flight_search_screen.dart';
import 'features/travel/screens/hotel_search_screen.dart';
import 'features/travel/screens/stay_search_screen.dart';
import 'features/travel/screens/car_rental_search_screen.dart';
import 'features/settings/screens/settings_screen.dart';
import 'features/sharing/screens/share_chat_selection_screen.dart';
import 'features/marketplace/screens/marketplace_screen.dart';
import 'features/marketplace/screens/create_listing_screen.dart';
import 'features/marketplace/models/marketplace_listing.dart';
import 'features/marketplace/screens/listing_detail_screen.dart';
import 'features/marketplace/screens/my_listings_screen.dart';
import 'features/marketplace/screens/saved_listings_screen.dart';
import 'features/marketplace/screens/compatible_parts_screen.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'features/hosting/screens/hosting_request_detail_screen.dart';
import 'features/notifications/screens/notifications_screen.dart';
import 'features/real_estate/models/real_estate_listing.dart';
import 'features/real_estate/screens/real_estate_search_screen.dart';
import 'features/real_estate/screens/real_estate_detail_screen.dart';
import 'features/real_estate/screens/create_real_estate_listing_screen.dart';

// [PERF] Cache permission status in memory so route redirects are 100% synchronous
PermissionStatus? _cachedPermissionStatus;
DateTime _lastPermissionCheck = DateTime(2000);
final Set<String> _verifyingUids = <String>{};

/// Pre-warms or refreshes the cached location permission status in the background.
Future<void> warmPermissionCache() async {
  if (kIsWeb) return;
  try {
    _cachedPermissionStatus = await Permission.location.status;
    _lastPermissionCheck = DateTime.now();
  } catch (_) {}
}

/// Call this to force the router to re-check permissions on the next navigation.
/// Used by the permissions screen after the user grants all permissions.
void invalidatePermissionCache({bool assumeGranted = true}) {
  if (assumeGranted) {
    _cachedPermissionStatus = PermissionStatus.granted;
    _lastPermissionCheck = DateTime.now();
  } else {
    _cachedPermissionStatus = null;
    _lastPermissionCheck = DateTime(2000);
  }
  unawaited(warmPermissionCache());
}

Future<void> _verifyAndCacheProfileInBackground(Ref ref, String uid) async {
  if (_verifyingUids.contains(uid)) return;
  _verifyingUids.add(uid);
  try {
    final exists = await ref.read(profileRepositoryProvider).profileExists(uid);
    if (exists) {
      await ref.read(sessionServiceProvider).setUserCached(uid);
      ref.read(profileRepositoryProvider).invalidateProfileCache(uid);
      ref.invalidate(userProfileProvider);
    }
  } catch (_) {
  } finally {
    _verifyingUids.remove(uid);
  }
}

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final routerNotifierProvider = Provider<RouterNotifier>((ref) {
  return RouterNotifier(ref);
});

class RouterNotifier extends ChangeNotifier {
  final Ref _ref;

  RouterNotifier(this._ref) {
    _ref.listen<AsyncValue<User?>>(
      authStateProvider,
      (_, _) => notifyListeners(),
    );
    _ref.listen<AsyncValue<ProfileData?>>(
      userProfileProvider,
      (_, _) => notifyListeners(),
    );
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(routerNotifierProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    refreshListenable: notifier,
    initialLocation: '/auth/phone',
    redirect: (context, state) {
      // [PERF] 100% synchronous redirect — zero platform-channel or Firestore
      // awaits on the critical navigation path.
      final referralCode =
          state.uri.queryParameters['code'] ?? state.uri.queryParameters['ref'];
      if (referralCode != null && referralCode.isNotEmpty) {
        ref.read(pendingReferralCodeProvider.notifier).set(referralCode);
      }

      final authState = ref.read(authStateProvider);
      final userProfileAsync = ref.read(userProfileProvider);
      final currentUser =
          authState.value ?? ref.read(authRepositoryProvider).currentUser;

      final isAuthenticated = currentUser != null;
      final cachedProfile = isAuthenticated
          ? ref.read(profileRepositoryProvider).getCachedProfile(currentUser.uid)
          : null;
      final canUseCachedSession =
          isAuthenticated &&
          (cachedProfile != null ||
              ref.read(sessionServiceProvider).isUserCached(currentUser.uid));

      final isAuthRoute = state.matchedLocation.startsWith('/auth');

      final isBootstrapping =
          state.matchedLocation == '/' ||
          state.matchedLocation.startsWith('/auth') ||
          state.matchedLocation == '/splash';

      if (state.matchedLocation.startsWith('/error')) return null;

      if (authState.hasError) {
        final error = authState.error;
        return '/error?message=${Uri.encodeComponent(error.toString())}';
      }

      final shouldWaitForProfile =
          isBootstrapping ||
          state.matchedLocation == '/chats' ||
          state.matchedLocation == '/permissions';

      if ((authState.isLoading && currentUser == null) ||
          (shouldWaitForProfile &&
              userProfileAsync.isLoading &&
              !canUseCachedSession)) {
        return '/splash';
      }

      if (!isAuthenticated && !isAuthRoute) {
        return '/auth/phone';
      }

      if (isAuthenticated) {
        final user = currentUser;
        final profile = userProfileAsync.value ?? cachedProfile;

        // --- PERMISSION ENFORCEMENT (Synchronous via pre-warmed memory cache) ---
        if (!kIsWeb && state.matchedLocation != '/permissions') {
          final now = DateTime.now();
          if (_cachedPermissionStatus == null ||
              now.difference(_lastPermissionCheck) >
                  const Duration(seconds: 30)) {
            _lastPermissionCheck = now;
            unawaited(warmPermissionCache());
          }
          if (_cachedPermissionStatus != null &&
              !_cachedPermissionStatus!.isGranted &&
              !_cachedPermissionStatus!.isLimited) {
            return '/permissions';
          }
        }

        if (isAuthRoute &&
            state.matchedLocation != '/auth/otp' &&
            state.matchedLocation != '/profile-setup' &&
            state.matchedLocation != '/chats') {
          final hasLoadedProfile =
              profile != null && profile.firstName.isNotEmpty;
          final uidExists = hasLoadedProfile || canUseCachedSession;

          if (!uidExists) {
            unawaited(_verifyAndCacheProfileInBackground(ref, user.uid));
            return '/profile-setup';
          }

          if (hasLoadedProfile) {
            unawaited(ref.read(sessionServiceProvider).setUserCached(user.uid));
          }
          return '/chats';
        }

        if (state.matchedLocation == '/profile-setup' && profile != null) {
          if (profile.firstName.isEmpty) {
            if (canUseCachedSession) {
              ref
                  .read(profileRepositoryProvider)
                  .invalidateProfileCache(user.uid);
              Future.microtask(() => ref.invalidate(userProfileProvider));
              return '/chats';
            }
            unawaited(_verifyAndCacheProfileInBackground(ref, user.uid));
            return null;
          }

          if (profile.communityMemberships == null ||
              profile.communityMemberships!.isEmpty) {
            return null;
          }

          return '/chats';
        }

        if (profile?.isBanned == true) {
          return '/banned';
        }

        if ((state.matchedLocation == '/' ||
            (state.matchedLocation.startsWith('/auth') &&
                state.matchedLocation != '/auth/otp') ||
            state.matchedLocation == '/splash')) {
          final hasMemberships =
              (profile?.communityMemberships != null &&
                  profile!.communityMemberships!.isNotEmpty) ||
              canUseCachedSession;

          if (!hasMemberships) {
            unawaited(_verifyAndCacheProfileInBackground(ref, user.uid));
            return '/profile-setup';
          }
          return '/chats';
        }

        final isProfileIncomplete =
            profile != null &&
            profile.firstName.isEmpty &&
            (profile.communityMemberships == null ||
                profile.communityMemberships!.isEmpty);

        if (state.matchedLocation != '/profile-setup' &&
            state.matchedLocation != '/permissions' &&
            !state.matchedLocation.startsWith('/auth') &&
            !userProfileAsync.isLoading &&
            !userProfileAsync.hasError &&
            (profile == null || isProfileIncomplete)) {
          if (canUseCachedSession) {
            if (isProfileIncomplete) {
              ref
                  .read(profileRepositoryProvider)
                  .invalidateProfileCache(user.uid);
              Future.microtask(() => ref.invalidate(userProfileProvider));
            }
          } else {
            unawaited(_verifyAndCacheProfileInBackground(ref, user.uid));
            return '/profile-setup';
          }
        }
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),

      GoRoute(
        path: '/error',
        builder: (context, state) {
          final msg = state.uri.queryParameters['message'];
          return ErrorScreen(message: msg);
        },
      ),

      GoRoute(
        path: '/permissions',
        builder: (context, state) => UserPermissionsScreen(
          isReviewMode: state.uri.queryParameters['review'] == '1',
        ),
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
            verificationId: (extras['verificationId'] as String?) ?? '',
            phoneNumber: extras['phoneNumber'] as String,
            isWhatsApp: extras['isWhatsApp'] as bool? ?? false,
          );
        },
      ),

      // Redirect /download and /invite to home (For Invite Links)
      GoRoute(
        path: '/download',
        redirect: (context, state) => '/',
        builder: (context, state) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: '/invite',
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

      // Share Destination Route
      GoRoute(
        name: 'share_destination',
        path: '/share',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final files = state.extra as List<SharedMediaFile>;
          return ShareChatSelectionScreen(sharedFiles: files);
        },
      ),

      // Organizations List Screen
      GoRoute(
        path: '/organizations',
        builder: (context, state) => const OrganizationsListScreen(),
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

      // Notifications Hub
      GoRoute(
        path: '/notifications',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const NotificationsScreen(),
      ),

      // Hosting Request Detail (from push notification)
      GoRoute(
        path: '/hosting/request/:requestId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final requestId = state.pathParameters['requestId']!;
          return HostingRequestDetailScreen(requestId: requestId);
        },
      ),

      // Main App Shell - 5 Tabs
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
                    builder: (context, state) {
                      final message = state.extra as Message;
                      return ForwardChatSelectionScreen(message: message);
                    },
                  ),
                  GoRoute(
                    path: ':chatId',
                    parentNavigatorKey: _rootNavigatorKey,
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
                          final extra = state.extra as Map<String, dynamic>?;
                          final type = extra?['type'] as String? ?? 'group';

                          if (type == 'organization') {
                            return OrganizationInfoScreen(
                              chatId: chatId,
                              orgName: extra?['name'] ?? 'Organization',
                              orgImage: extra?['image'],
                              currentUserId: ref
                                  .read(authRepositoryProvider)
                                  .currentUser!
                                  .uid,
                            );
                          }

                          return GroupInfoScreen(
                            chatId: chatId,
                            groupName: extra?['name'] ?? 'Group Info',
                            groupImage: extra?['image'],
                            currentUserId: ref
                                .read(authRepositoryProvider)
                                .currentUser!
                                .uid,
                            initialEdit: extra?['initialEdit'] == true,
                          );
                        },
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
            ],
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
            ],
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
                    builder: (context, state) {
                      final communityId =
                          state.uri.queryParameters['communityId'];
                      final groupId = state.uri.queryParameters['groupId'];
                      return CreateEventScreen(
                        communityId: communityId,
                        groupId: groupId,
                      );
                    },
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
                      final eventId = state.pathParameters['eventId'];
                      final eventExtra = state.extra as Event?;
                      return CreateEventScreen(
                        eventToEdit: eventExtra,
                        eventIdToEdit: eventId,
                      );
                    },
                  ),
                  GoRoute(
                    path: ':eventId',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) {
                      final eventId = state.pathParameters['eventId']!;
                      final eventExtra = state.extra as Event?;
                      return EventDetailScreen(
                        eventId: eventId,
                        event: eventExtra,
                      );
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
      // Direct chat - creates/gets DM and redirects to chat
      GoRoute(
        path: '/chat/direct/:userId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final userId = state.pathParameters['userId']!;
          return StartDirectChatScreen(otherUserId: userId);
        },
      ),

      // DSP Feature Routes
      GoRoute(
        path: '/dsp/points',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const PointsSystemScreen(),
      ),
      GoRoute(
        path: '/dsp/remittances',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const RemittancesScreen(),
      ),
      GoRoute(
        path: '/dsp/emergency-fund',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const EmergencyFundScreen(),
      ),
      GoRoute(
        path: '/dsp/emergency-fund/transparency',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const EmergencyFundTransparencyScreen(),
      ),
      GoRoute(
        path: '/dsp/airline',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const AirlinePortalScreen(),
      ),

      // Travel Portal
      GoRoute(
        path: '/dsp/travel/flights',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const FlightSearchScreen(),
      ),
      GoRoute(
        path: '/dsp/travel/hotels',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const HotelSearchScreen(),
      ),
      GoRoute(
        path: '/dsp/travel/stays',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const StaySearchScreen(),
      ),
      GoRoute(
        path: '/dsp/travel/car-rental',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const CarRentalSearchScreen(),
      ),

      // Real Estate
      GoRoute(
        path: '/dsp/real-estate/:category',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final category = state.pathParameters['category'] ?? 'plot';
          return RealEstateSearchScreen(category: category);
        },
      ),
      GoRoute(
        path: '/dsp/real-estate-detail',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final listing = state.extra as RealEstateListing;
          return RealEstateDetailScreen(listing: listing);
        },
      ),
      GoRoute(
        path: '/dsp/real-estate-create',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final extras = state.extra as Map<String, dynamic>?;
          return CreateRealEstateListingScreen(
            defaultCategory: extras?['category'] as String? ?? 'plot',
            existing: extras?['listing'] as RealEstateListing?,
          );
        },
      ),

      GoRoute(
        path: '/dsp/dfdi',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const DFDIScreen(),
      ),
      GoRoute(
        path: '/dsp/crypto',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const DiasporaCryptoScreen(),
      ),

      // Economy Hub
      GoRoute(
        path: '/economy',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const EconomyHubScreen(),
      ),

      // Settings
      GoRoute(
        path: '/settings',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const SettingsScreen(),
      ),

      // ── Marketplace ──────────────────────────────────────────────
      GoRoute(
        path: '/marketplace',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final type = state.uri.queryParameters['type'];
          return MarketplaceScreen(initialType: type);
        },
      ),
      GoRoute(
        path: '/marketplace/create',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final extra = state.extra;
          if (extra is MarketplaceListing) {
            return CreateListingScreen(existingListing: extra);
          }
          return CreateListingScreen(
            defaultListingType: extra is String ? extra : null,
          );
        },
      ),
      GoRoute(
        path: '/marketplace/listing/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) =>
            ListingDetailScreen(listingId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/marketplace/my-listings',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const MyListingsScreen(),
      ),
      GoRoute(
        path: '/marketplace/saved',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const SavedListingsScreen(),
      ),
      GoRoute(
        path: '/marketplace/parts/:make',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => CompatiblePartsScreen(
          make: Uri.decodeComponent(state.pathParameters['make']!),
          model: state.uri.queryParameters['model'],
          year: state.uri.queryParameters['year'],
        ),
      ),
      GoRoute(
        path: '/marketplace/:id',
        parentNavigatorKey: _rootNavigatorKey,
        redirect: (context, state) =>
            '/marketplace/listing/${state.pathParameters['id']}',
      ),

      // Current User Profile (Self)
      GoRoute(
        path: '/profile',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final userId =
              ref.read(authRepositoryProvider).currentUser?.uid ?? '';
          final enforce =
              state.uri.queryParameters['enforceLocation'] == 'true';
          return UserProfileScreen(userId: userId, isEnforced: enforce);
        },
      ),

      // User Profile Route (Other or Self by ID)
      GoRoute(
        path: '/profile/:userId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final userId = state.pathParameters['userId']!;
          final extra = state.extra as Map<String, dynamic>?;
          final double? distance = extra?['distance'] as double?;
          return UserProfileScreen(userId: userId, initialDistance: distance);
        },
      ),

      // Admin Dashboard Routes
      ShellRoute(
        builder: (context, state, child) {
          return AdminDashboardScreen(child: child);
        },
        routes: [
          GoRoute(path: '/admin', redirect: (_, _) => '/admin/overview'),
          GoRoute(
            path: '/admin/overview',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: AdminOverviewScreen()),
          ),
          GoRoute(
            path: '/admin/users',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: AdminUsersScreen()),
          ),
          GoRoute(
            path: '/admin/communities',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: AdminCommunitiesScreen()),
          ),
          GoRoute(
            path: '/admin/chamber-requests',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: AdminChamberRequestsScreen()),
          ),
        ],
      ),

      // Root Route
      GoRoute(
        path: '/',
        builder: (context, state) {
          final isAuthenticated = ref.watch(authStateProvider).value != null;
          if (isAuthenticated) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              context.go('/chats');
            });
          }
          return const SizedBox.shrink();
        },
      ),
    ],
  );
});
