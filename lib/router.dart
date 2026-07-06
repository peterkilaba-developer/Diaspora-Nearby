import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
import 'package:diaspora_nearby/features/chat/models/message.dart'; // [NEW]
// Added for strict enforcement
import 'features/events/screens/events_screen.dart';
import 'features/events/screens/event_detail_screen.dart';
import 'features/events/screens/create_event_screen.dart';
import 'features/events/screens/qr_attendance_screen.dart';
import 'package:diaspora_nearby/features/events/screens/event_attendees_screen.dart';
// import 'package:diaspora_nearby/core/services/local_cache_service.dart'; // Deprecated
import 'package:diaspora_nearby/features/events/screens/organizer_events_screen.dart'; // [NEW]
// [NEW]
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
import 'features/sharing/screens/share_chat_selection_screen.dart'; // [NEW]
import 'features/marketplace/screens/marketplace_screen.dart';
import 'features/marketplace/screens/create_listing_screen.dart';
import 'features/marketplace/models/marketplace_listing.dart';
import 'features/marketplace/screens/listing_detail_screen.dart';
import 'features/marketplace/screens/my_listings_screen.dart';
import 'features/marketplace/screens/saved_listings_screen.dart';
import 'features/marketplace/screens/compatible_parts_screen.dart';
// [NEW]
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'features/hosting/screens/hosting_request_detail_screen.dart';
import 'features/notifications/screens/notifications_screen.dart';
import 'features/real_estate/models/real_estate_listing.dart';
import 'features/real_estate/screens/real_estate_search_screen.dart';
import 'features/real_estate/screens/real_estate_detail_screen.dart';
import 'features/real_estate/screens/create_real_estate_listing_screen.dart';

// [PERF] Cache permission status to avoid platform channel call on every route change
PermissionStatus? _cachedPermissionStatus;
DateTime _lastPermissionCheck = DateTime(2000);

// [PERF FIX] Re-entrancy guard to prevent redirect loop.
// When ref.invalidate(userProfileProvider) fires, RouterNotifier.notifyListeners()
// causes GoRouter to re-evaluate redirect() while the previous one is still running.
bool _isRedirecting = false;

/// Call this to force the router to re-check permissions on the next navigation.
/// Used by the permissions screen after the user grants all permissions.
void invalidatePermissionCache() {
  _cachedPermissionStatus = null;
  _lastPermissionCheck = DateTime(2000);
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
    redirect: (context, state) async {
      // [PERF FIX] Re-entrancy guard — prevent infinite redirect loop.
      // Without this, ref.invalidate(userProfileProvider) → RouterNotifier.notifyListeners()
      // → GoRouter.redirect() fires again while the previous one is still running.
      if (_isRedirecting) {
        debugPrint('Router: ═══ REDIRECT SKIPPED (re-entrant) ═══');
        return null;
      }
      _isRedirecting = true;

      try {
        debugPrint(
          'Router: ═══ REDIRECT START ═══ route: ${state.matchedLocation}, URI: ${state.uri}',
        );

        // [NEW] Capture referral code from ANY incoming link with ?code=...
        final referralCode = state.uri.queryParameters['code'];
        if (referralCode != null && referralCode.isNotEmpty) {
          debugPrint('Router: Captured Referral Code: $referralCode');
          ref.read(pendingReferralCodeProvider.notifier).set(referralCode);
        }

        final authState = ref.read(authStateProvider);
        final userProfileAsync = ref.read(userProfileProvider);

        final isAuthenticated = authState.value != null;
        final canUseCachedSession =
            isAuthenticated &&
            ref.read(sessionServiceProvider).isUserCached(authState.value!.uid);

        final isAuthRoute = state.matchedLocation.startsWith('/auth');

        debugPrint(
          'Router: state=[isAuth=$isAuthenticated, authLoading=${authState.isLoading}, authError=${authState.hasError}, profileLoading=${userProfileAsync.isLoading}, profileError=${userProfileAsync.hasError}, profileValue=${userProfileAsync.value != null ? "exists" : "null"}, isAuthRoute=$isAuthRoute]',
        );

        // Only show global splash if we are in an "initializing" phase
        final isBootstrapping =
            state.matchedLocation == '/' ||
            state.matchedLocation.startsWith('/auth') ||
            state.matchedLocation == '/splash';

        // Allow error screen to render
        if (state.matchedLocation.startsWith('/error')) return null;

        // Authentication failures prevent the app from deciding which session
        // to show and remain fatal. Profile refresh failures are recoverable:
        // screens and guards below can use locally cached/session-backed data.
        if (authState.hasError) {
          final error = authState.error;
          debugPrint('Router: ══► AUTH ERROR → /error');
          return '/error?message=${Uri.encodeComponent(error.toString())}';
        }
        if (userProfileAsync.hasError) {
          debugPrint(
            'Router: profile refresh failed; continuing with cached session: ${userProfileAsync.error}',
          );
        }

        // [FIX] Wait for profile to load before making redirect decisions.
        // Previously only waited on 'bootstrapping' routes, but profile loading
        // also races when navigating directly to /chats after OTP verification.
        final shouldWaitForProfile =
            isBootstrapping ||
            state.matchedLocation == '/chats' ||
            state.matchedLocation == '/permissions';

        if (authState.isLoading ||
            (shouldWaitForProfile &&
                userProfileAsync.isLoading &&
                !canUseCachedSession)) {
          debugPrint('Router: ══► LOADING → /splash');
          return '/splash';
        }

        if (!isAuthenticated && !isAuthRoute) {
          debugPrint('Router: ══► NOT AUTHENTICATED → /auth/phone');
          return '/auth/phone';
        }

        if (isAuthenticated) {
          final user = authState.value!;
          final profile = userProfileAsync.value;

          // --- PERMISSION ENFORCEMENT ---
          // Check permissions for ALL authenticated users (except on /permissions itself)
          // We do this BEFORE profile checks to ensure environment is ready.
          // [PERF] Cache permission status to avoid platform channel call on every navigation
          if (!kIsWeb && state.matchedLocation != '/permissions') {
            final now = DateTime.now();
            if (_cachedPermissionStatus == null ||
                now.difference(_lastPermissionCheck) >
                    const Duration(seconds: 30)) {
              _cachedPermissionStatus = await Permission.location.status;
              _lastPermissionCheck = now;
            }
            if (!_cachedPermissionStatus!.isGranted &&
                !_cachedPermissionStatus!.isLimited) {
              return '/permissions';
            }
          }

          // Allow OTP screen to show even when Firebase Auth detects phone number
          // User is not fully authenticated until OTP is verified
          // [FIX] Don't intercept navigation to profile-setup or chats after OTP success
          debugPrint(
            'Router: Checking auth route block: isAuthRoute=$isAuthRoute, loc=${state.matchedLocation}',
          );
          if (isAuthRoute &&
              state.matchedLocation != '/auth/otp' &&
              state.matchedLocation != '/profile-setup' &&
              state.matchedLocation != '/chats') {
            debugPrint('Router: ══► ENTERED auth-route-check block');
            // [PERF] Check profile exists — prefer in-memory/local checks before Firestore
            bool uidExists = false;
            try {
              // [PERF] Tier 0: Check if provider already has a valid profile loaded
              // This avoids the expensive profileExists() server-first Firestore call
              // when we already have the data in memory.
              final loadedProfile = userProfileAsync.value;
              if (loadedProfile != null && loadedProfile.firstName.isNotEmpty) {
                debugPrint(
                  'Router: ══► Provider has valid profile (firstName="${loadedProfile.firstName}") → skipping Firestore',
                );
                uidExists = true;
              }

              // [PERF] Tier 1: Check local session cache (SharedPreferences)
              if (!uidExists) {
                uidExists = ref
                    .read(sessionServiceProvider)
                    .isUserCached(user.uid);
                if (uidExists) {
                  debugPrint(
                    'Router: uidExists=true via session cache for ${user.uid}',
                  );
                }
              }

              // Tier 2: Firestore check (only if local checks failed)
              if (!uidExists) {
                uidExists = await ref
                    .read(profileRepositoryProvider)
                    .profileExists(user.uid);
                debugPrint(
                  'Router: uidExists=$uidExists via Firestore for ${user.uid}',
                );
                if (uidExists) {
                  await ref
                      .read(sessionServiceProvider)
                      .setUserCached(user.uid);
                }
              }

              if (!uidExists) {
                debugPrint('Router: ══► Profile NOT found → /profile-setup');
                return '/profile-setup';
              }
            } catch (e) {
              debugPrint('Router: ══► Profile check ERROR: $e → null (stay)');
              return null;
            }

            ref.read(sessionServiceProvider);

            if (isAuthRoute) {
              debugPrint('Router: ══► Profile EXISTS, auth route → /chats');
              return '/chats';
            }
          } else {
            debugPrint('Router: auth-route-check SKIPPED');
          }

          if (state.matchedLocation == '/profile-setup' &&
              userProfileAsync.value != null) {
            // Check for community memberships integrity
            final setupProfile = userProfileAsync.value!;

            // [FIX] If the provider loaded a bare FCM-only doc (firstName empty),
            // check Firestore directly to see if the real profile exists.
            // This prevents keeping an existing user stuck on profile-setup.
            if (setupProfile.firstName.isEmpty) {
              final isKnownLocally = ref
                  .read(sessionServiceProvider)
                  .isUserCached(user.uid);
              if (isKnownLocally) {
                debugPrint(
                  'Router: ══► On /profile-setup but user cached locally (bare FCM doc loaded) → letting through to /chats',
                );
                ref
                    .read(profileRepositoryProvider)
                    .invalidateProfileCache(user.uid);
                // [PERF FIX] Defer invalidation to break redirect loop
                Future.microtask(() => ref.invalidate(userProfileProvider));
                return '/chats';
              }
              try {
                final existsInFirestore = await ref
                    .read(profileRepositoryProvider)
                    .profileExists(user.uid);
                if (existsInFirestore) {
                  debugPrint(
                    'Router: ══► On /profile-setup but profile exists in Firestore (bare FCM doc loaded) → /chats',
                  );
                  await ref
                      .read(sessionServiceProvider)
                      .setUserCached(user.uid);
                  ref
                      .read(profileRepositoryProvider)
                      .invalidateProfileCache(user.uid);
                  // [PERF FIX] Defer invalidation to break redirect loop
                  Future.microtask(() => ref.invalidate(userProfileProvider));
                  return '/chats';
                }
              } catch (e) {
                debugPrint(
                  'Router: ══► Firestore check on /profile-setup failed: $e',
                );
              }
              // Truly new user with bare doc → stay on profile-setup
              return null;
            }

            if (setupProfile.communityMemberships == null ||
                setupProfile.communityMemberships!.isEmpty) {
              return null; // Stay on cleanup/setup screen
            }

            return '/chats';
          }

          // Check for Ban
          if (profile?.isBanned == true) {
            return '/banned';
          }

          // Data Integrity Guard for Root/Auth redirect
          // [FIX] Don't intercept navigation from OTP verification
          // Also don't intercept deep links! Only redirect to chats if user is on a "starting" path.
          if ((state.matchedLocation == '/' ||
              (state.matchedLocation.startsWith('/auth') &&
                  state.matchedLocation != '/auth/otp') ||
              state.matchedLocation == '/splash')) {
            debugPrint(
              'Router: ══► Data Integrity Guard HIT for root/auth/splash',
            );

            // [FIX] When profile is null (parse error) or memberships empty,
            // verify directly in Firestore before redirecting to profile-setup.
            // This prevents users with valid profiles from being locked out
            // due to a ProfileData.fromJson parse failure.
            bool hasMemberships =
                profile?.communityMemberships != null &&
                profile!.communityMemberships!.isNotEmpty;

            if (!hasMemberships) {
              // [FIX] Fast path: check local session cache first to avoid
              // unnecessary Firestore network call on every router evaluation
              final isKnownLocally = ref
                  .read(sessionServiceProvider)
                  .isUserCached(user.uid);
              if (isKnownLocally) {
                hasMemberships = true;
                debugPrint(
                  'Router: ══► Data Integrity Guard: memberships empty in provider but user cached locally → allowing through',
                );
                // Invalidate stale profile so provider re-fetches
                ref
                    .read(profileRepositoryProvider)
                    .invalidateProfileCache(user.uid);
                // [PERF FIX] Defer invalidation to break redirect loop
                Future.microtask(() => ref.invalidate(userProfileProvider));
              } else {
                // Fallback: Check Firestore directly for communityMemberships
                // [PERF] Use cache-first to avoid network roundtrip on every router evaluation
                try {
                  DocumentSnapshot<Map<String, dynamic>> userDoc;
                  try {
                    userDoc = await FirebaseFirestore.instance
                        .collection('users')
                        .doc(user.uid)
                        .get(const GetOptions(source: Source.cache))
                        .timeout(const Duration(seconds: 2));
                  } catch (_) {
                    userDoc = await FirebaseFirestore.instance
                        .collection('users')
                        .doc(user.uid)
                        .get();
                  }
                  if (userDoc.exists) {
                    final data = userDoc.data();
                    final memberships = data?['communityMemberships'] as List?;
                    if (memberships != null && memberships.isNotEmpty) {
                      hasMemberships = true;
                      debugPrint(
                        'Router: ══► Profile parse may have failed but Firestore has ${memberships.length} memberships → allowing through',
                      );
                      // Cache locally for fast future checks
                      await ref
                          .read(sessionServiceProvider)
                          .setUserCached(user.uid);
                      // Invalidate stale profile so provider re-fetches
                      ref
                          .read(profileRepositoryProvider)
                          .invalidateProfileCache(user.uid);
                      // [PERF FIX] Defer invalidation to break redirect loop
                      Future.microtask(
                        () => ref.invalidate(userProfileProvider),
                      );
                    }
                  }
                } catch (e) {
                  debugPrint(
                    'Router: ══► Firestore membership check failed: $e → safe fallback to /chats',
                  );
                  // On network error, assume user has profile (don't send to setup)
                  hasMemberships = true;
                }
              }
            }

            if (!hasMemberships) {
              debugPrint('Router: ══► Profile setup required → /profile-setup');
              return '/profile-setup';
            }
            debugPrint('Router: ══► Has profile+communities → /chats');
            return '/chats';
          }

          // Global Profile Integrity Guard
          // [FIX] Also skip this guard on /permissions — the user may have a valid
          // profile but the provider hasn't loaded it yet during the permissions flow.
          // [FIX] Two-tier fallback when profile provider resolves to null OR
          // appears incomplete (bare/FCM-only doc):
          //   1. Fast local check: sessionService.isUserCached (SharedPreferences)
          //   2. Server fallback: profileExists (Firestore) — survives cache clear
          // Only redirect to /profile-setup if BOTH checks confirm no profile.
          //
          // [CRITICAL FIX] Previously, isProfileIncomplete immediately returned
          // /profile-setup WITHOUT any Firestore fallback. This caused existing
          // users to be wrongly redirected after reinstalling the app, because
          // the FCM token save creates a bare user doc ({fcmToken, notificationsEnabled})
          // that parses as ProfileData with firstName='' via defensive defaults.
          // Now BOTH paths (profile==null AND isProfileIncomplete) use the same
          // two-tier fallback before redirecting.
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
            debugPrint(
              'Router: ══► Global guard triggered: profile=${profile == null ? "null" : "incomplete(firstName=\"${profile.firstName}\")"}, checking fallbacks...',
            );

            // Tier 1: Fast local check (survives app restarts but not cache clear)
            final isKnownUser = ref
                .read(sessionServiceProvider)
                .isUserCached(user.uid);
            if (isKnownUser) {
              debugPrint(
                'Router: ══► Global guard: profile ${isProfileIncomplete ? "incomplete" : "null"} but user cached locally → allowing through',
              );
              // [FIX] If profile is incomplete (bare FCM doc), invalidate the
              // profile cache so the provider re-fetches from server on next read.
              // This ensures the real profile data replaces the stale bare doc.
              if (isProfileIncomplete) {
                ref
                    .read(profileRepositoryProvider)
                    .invalidateProfileCache(user.uid);
                // [PERF FIX] Defer invalidation to break redirect loop
                Future.microtask(() => ref.invalidate(userProfileProvider));
              }
            } else {
              // Tier 2: Firestore check (survives cache clear)
              try {
                final existsInFirestore = await ref
                    .read(profileRepositoryProvider)
                    .profileExists(user.uid);
                if (existsInFirestore) {
                  debugPrint(
                    'Router: ══► Global guard: profile ${isProfileIncomplete ? "incomplete" : "null"} but exists in Firestore → allowing through',
                  );
                  // Re-cache locally so future checks are fast
                  await ref
                      .read(sessionServiceProvider)
                      .setUserCached(user.uid);
                  // [FIX] Invalidate stale profile cache to force fresh read
                  ref
                      .read(profileRepositoryProvider)
                      .invalidateProfileCache(user.uid);
                  // [PERF FIX] Defer invalidation to break redirect loop
                  Future.microtask(() => ref.invalidate(userProfileProvider));
                } else {
                  debugPrint(
                    'Router: ══► Global guard: profile ${isProfileIncomplete ? "incomplete" : "null"} + not in Firestore → /profile-setup',
                  );
                  return '/profile-setup';
                }
              } catch (e) {
                debugPrint(
                  'Router: ══► Global guard: Firestore check failed: $e → allowing through (safe fallback)',
                );
                // On network error, don't redirect — the user likely has a profile
                // and the provider will catch up. Sending to profile-setup on a
                // transient error would be worse than briefly showing an empty screen.
              }
            }
          }
        }

        debugPrint(
          'Router: ══► FALLTHROUGH → null (stay on ${state.matchedLocation})',
        );
        return null;
      } finally {
        _isRedirecting = false;
      }
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
        builder: (context, state) => const UserPermissionsScreen(),
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
                    builder: (context, state) {
                      final message = state.extra as Message;
                      return ForwardChatSelectionScreen(message: message);
                    },
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
                            groupName:
                                extra?['name'] ??
                                'Group Info', // [FIX] Provide non-null fallback
                            groupImage: extra?['image'],
                            currentUserId: ref
                                .read(authRepositoryProvider)
                                .currentUser!
                                .uid,
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

      // [NEW] Root Route
      // This is crucial for handling deep links that resolve to '/' (like /invite or /download redirections)
      // or simply opening the app via a generic link.
      GoRoute(
        path: '/',
        builder: (context, state) {
          debugPrint('Router: Rendering Root Route builder');
          final isAuthenticated = ref.watch(authStateProvider).value != null;

          // Failsafe: if we ended up here and are authenticated, force move to chats
          if (isAuthenticated) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              debugPrint('Router: Root Builder Failsafe - Going to /chats');
              context.go('/chats');
            });
          }

          return Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Redirecting Root...',
                    style: TextStyle(color: Colors.white, fontSize: 20),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Path: ${state.matchedLocation}',
                    style: const TextStyle(color: Colors.amber),
                  ),
                  Text(
                    'Uri: ${state.uri}',
                    style: const TextStyle(color: Colors.amber),
                  ),
                  Text(
                    'Auth: ${ref.read(authStateProvider).value != null}',
                    style: const TextStyle(color: Colors.green),
                  ),
                  Text(
                    'Profile: ${ref.read(userProfileProvider).value != null}',
                    style: const TextStyle(color: Colors.cyan),
                  ),
                  Text(
                    'Memberships: ${ref.read(userProfileProvider).value?.communityMemberships?.length ?? "null"}',
                    style: const TextStyle(color: Colors.cyan),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => context.go('/chats'),
                    child: const Text('Force Go to Home'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ],
  );
});
