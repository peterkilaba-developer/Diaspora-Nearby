import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/radio/providers/radio_provider.dart';
import 'package:diaspora_nearby/features/radio/repository/radio_repository.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/data/countries.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:diaspora_nearby/features/radio/screens/radio_screen.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final radioState = ref.watch(radioProvider);
    final station = radioState.currentStation;

    if (station == null) return const SizedBox.shrink();

    // Check if station is favorited
    final favoriteStations = ref.watch(favoriteStationsProvider).asData?.value ?? [];
    final isFavorite = favoriteStations.any((s) => s.stationuuid == station.stationuuid);

    // Standardize Country Name
    final countryObj = getCountryByCode(station.countrycode);
    final countryName = countryObj?.name ?? station.country;
    final flag = countryObj?.flag ?? '🌐';

    // Random listener count (100-10,000) and countries count (1-100) based on station hash for consistency
    final stationHash = station.stationuuid.hashCode.abs();
    final listeners = 100 + (stationHash % 9901); // 100 to 10,000
    final countriesCount = 1 + (stationHash % 100); // 1 to 100

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // User requested off-black for bottom row in light mode for visibility
    final bottomContentColor = isDark ? Colors.white70 : Colors.black87;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.primary.withAlpha(isDark ? 230 : 217),
              theme.colorScheme.primaryContainer.withAlpha(isDark ? 242 : 230),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.primary.withAlpha(isDark ? 76 : 51),
              blurRadius: 16,
              offset: const Offset(0, 4),
              spreadRadius: 2,
            ),
          ],
        ),
        padding: const EdgeInsets.only(left: 8, right: 6, top: 12, bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                // 1. Album Art / Station Logo (50px circle to match card)
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: theme.inputDecorationTheme.fillColor,
                    shape: BoxShape.circle,
                    image: (station.favicon.isNotEmpty && station.favicon.startsWith('http'))
                        ? DecorationImage(image: NetworkImage(station.favicon), fit: BoxFit.cover)
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: theme.shadowColor.withAlpha(isDark ? 76 : 25),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                  child: station.favicon.isEmpty
                      ? const Icon(Icons.radio, color: Colors.white)
                      : null,
                ),

                const SizedBox(width: 8), // 8px gap to match card horizontalTitleGap

                // 2. Station Info
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Line 1: Name
                        Text(station.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              height: 1.1,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),

                        // Line 2: Country
                        Row(
                          children: [
                            Text(flag, style: const TextStyle(fontSize: 12)),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(countryName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w400,
                                    fontSize: 11,
                                    height: 1.1,
                                    color: Colors.white,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),

                        // Line 3: Status
                        Row(
                          children: [
                            if (radioState.isLoading)
                              const SizedBox(
                                  width: 10,
                                  height: 10,
                                  child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white))
                            else if (radioState.isPlaying)
                              const Icon(LucideIcons.activity, size: 10, color: Colors.greenAccent)
                            else
                              const Icon(LucideIcons.pauseCircle, size: 10, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              radioState.error != null
                                  ? 'Connection Failed'
                                  : radioState.isLoading
                                      ? 'Buffering...'
                                      : radioState.isPlaying
                                          ? 'Broadcasting Live'
                                          : 'Paused',
                              style: TextStyle(
                                  fontSize: 10,
                                  height: 1.1,
                                  color: radioState.error != null
                                      ? Colors.redAccent
                                      : radioState.isPlaying
                                          ? Colors.greenAccent
                                          : Colors.white,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // 3. Controls - play/pause + heart (close moved to bottom row)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Play/Pause button (matches card play button position)
                    IconButton(
                      icon: radioState.isPlaying 
                          ? const AnimatedBars(color: Colors.white, size: 24)
                          : const Icon(LucideIcons.play, size: 24, color: Colors.white),
                      onPressed: () {
                        if (radioState.isPlaying) {
                          ref.read(radioProvider.notifier).pause();
                        } else {
                          ref.read(radioProvider.notifier).resume();
                        }
                      },
                    ),
                    // Heart button (favorite toggle - matches card implementation)
                    IconButton(
                      icon: Icon(
                        LucideIcons.heart,
                        size: 20,
                        color: isFavorite ? Theme.of(context).colorScheme.primary : Colors.white,
                      ),
                      onPressed: () async {
                        final user = ref.read(authStateProvider).value;
                        if (user != null) {
                          await ref.read(radioRepositoryProvider).toggleFavorite(user.uid, station);
                          ref.invalidate(favoriteStationsProvider);
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),

            // 4. Bottom Row: Listener count / Countries, Close under heart
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  // Empty space matching logo width (50) + gap (8) to align text with station info
                  const SizedBox(width: 58),

                  // Listeners count
                  Icon(LucideIcons.headphones, size: 12, color: bottomContentColor),
                  const SizedBox(width: 4),
                  Text(
                    '${NumberFormat.compact().format(listeners)} listeners • $countriesCount countries',
                    style: TextStyle(color: bottomContentColor, fontSize: 12),
                  ),

                  const Spacer(),

                  // Close button
                  IconButton(
                    icon: Icon(LucideIcons.x, size: 20, color: bottomContentColor),
                    onPressed: () {
                      ref.read(radioProvider.notifier).stop();
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 6), // Right padding matching card
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
