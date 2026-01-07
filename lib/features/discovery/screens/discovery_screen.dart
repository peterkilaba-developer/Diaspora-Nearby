import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:go_router/go_router.dart';
import 'package:diaspora_nearby/features/discovery/services/discovery_service.dart';
import 'package:diaspora_nearby/features/shared/widgets/user_card.dart';
import 'package:diaspora_nearby/models/profile_data.dart';
import 'package:geolocator/geolocator.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';

// Providers

final userLocationProvider = FutureProvider<GeoPoint>((ref) async {
  final position = await Geolocator.getCurrentPosition();
  return GeoPoint(position.latitude, position.longitude);
});

final nearbyUsersStreamProvider = StreamProvider.autoDispose<List<ProfileData>>((ref) {
  // Fixed large radius for "automatic" filtering (5000km covers effective proximity logic)
  const double fixedRadius = 5000.0;
  
  final centerAsync = ref.watch(userLocationProvider);
  final currentUser = ref.watch(authRepositoryProvider).currentUser;

  return centerAsync.when(
    data: (center) {
      return DiscoveryService().getUsersNearby(
        center: center,
        radiusInKm: fixedRadius,
        excludeUserId: currentUser?.uid,
      ).map((snapshots) {
        final users = snapshots.map((doc) {
          
          final data = doc.data();
          if (data == null) return null;

          double? distance;
          try {
             // We need to safely extract the geopoint.
             // Structure is: geo: { geopoint: GeoPoint(...), geohash: "..." }
             if (data['geo'] != null && data['geo'] is Map) {
                final geoMap = data['geo'] as Map<String, dynamic>; 
                if (geoMap['geopoint'] is GeoPoint) {
                    final gp = geoMap['geopoint'] as GeoPoint;
                    final distInMeters = Geolocator.distanceBetween(
                      center.latitude, 
                      center.longitude, 
                      gp.latitude, 
                      gp.longitude
                    );
                    distance = distInMeters / 1000.0;
                }
             }
          } catch (e) {
             debugPrint('Error calculating distance: $e');
          }

          final profile = ProfileData.fromJson({...data, 'uid': doc.id});
          if (distance != null) {
             return profile.copyWith(distance: distance);
          }
          return profile;
        })
        .whereType<ProfileData>()
        .toList();

        // Sort by distance (closest first)
        // Null distances push to the end
        users.sort((a, b) {
          final distA = a.distance ?? double.infinity;
          final distB = b.distance ?? double.infinity;
          return distA.compareTo(distB);
        });

        return users;
      });
    },
    loading: () => Stream.value(<ProfileData>[]),
    error: (error, stackTrace) => Stream.value(<ProfileData>[]),
  );
});

class DiscoveryScreen extends ConsumerWidget {
  const DiscoveryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nearbyUsersAsync = ref.watch(nearbyUsersStreamProvider);

    return Column(
      children: [
        // Header / Info (Optional, kept minimal per request)
        // We could add a simple "People Nearby" text if needed, but per request just auto-list.
        
        // Results List
        Expanded(
          child: nearbyUsersAsync.when(
            data: (users) {
              if (users.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.location_off_outlined, size: 48, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('No users found nearby.'),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () {
                           // Force refresh location
                           ref.invalidate(userLocationProvider);
                        }, 
                        child: const Text('Refresh Location')
                      ),
                    ],
                  ),
                );
              }
              
              return ListView.separated(
                padding: const EdgeInsets.all(8),
                itemCount: users.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final user = users[index];
                  return UserCardView(
                    user: user,
                    onNameTap: () => context.push('/profile/${user.uid}'),
                    onChatTap: () => context.push('/chat/direct/${user.uid}'),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Center(child: Text('Error: $err')),
          ),
        ),
      ],
    );
  }
}
