import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/shared/models/google_places_models.dart';
import 'package:diaspora_nearby/features/shared/models/location.dart'
    as loc_model;

class ProfileSetupLocationStep extends StatelessWidget {
  final TextEditingController homeSearchController;
  final FocusNode homeFocusNode;
  final List<AutocompletePrediction> homePredictions;
  final loc_model.UserLocation? homeLocation;
  final loc_model.UserLocation? hostLocation;
  final Function(String) onHomeSearchChanged;
  final Function(String) onHomeSelectPlace;
  final VoidCallback onNext;
  final VoidCallback onRetryHostLocation;

  const ProfileSetupLocationStep({
    super.key,
    required this.homeSearchController,
    required this.homeFocusNode,
    required this.homePredictions,
    required this.homeLocation,
    required this.hostLocation,
    required this.onHomeSearchChanged,
    required this.onHomeSelectPlace,
    required this.onNext,
    required this.onRetryHostLocation,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(LucideIcons.map, size: 64, color: Colors.blue),
        const SizedBox(height: 16),
        Text(
          'Your Location Details',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Set up your current residence and original hometown to connect with your community.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),

        // Host Location (Read-Only)
        Text(
          'Host Location',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 4),
        Text(
          'This is where you currently live, securely captured via your device GPS.',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.5,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              const Icon(LucideIcons.mapPin, color: Colors.blue),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  hostLocation?.formattedAddress ?? 'Locating...',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
              if (hostLocation != null && hostLocation!.countryCode != 'XX')
                const Icon(LucideIcons.checkCircle, color: Colors.green)
              else
                IconButton(
                  icon: const Icon(LucideIcons.refreshCw, color: Colors.blue),
                  tooltip: 'Retry GPS',
                  onPressed: onRetryHostLocation,
                ),
            ],
          ),
        ),

        const SizedBox(height: 32),

        // Home Location (Autocomplete)
        Text(
          'Home Location',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 4),
        Text(
          'This is your origin locality (where you are from). For diaspora, this is usually a different country from your current location, but it can be the same country for locals.',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: homeSearchController,
          focusNode: homeFocusNode,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'Search your original hometown',
            prefixIcon: const Icon(LucideIcons.home),
            suffixIcon: homeSearchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(LucideIcons.x, size: 18),
                    onPressed: () {
                      homeSearchController.clear();
                      onHomeSearchChanged('');
                    },
                  )
                : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
          ),
          onChanged: onHomeSearchChanged,
        ),

        // Suggestions List
        if (homePredictions.isNotEmpty) _buildSuggestionsList(theme),

        // Selection Confirmation
        if (homeLocation != null && homePredictions.isEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade300),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.check, color: Colors.orange),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    homeLocation!.formattedAddress,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 32),

        // Next Button
        if (hostLocation != null &&
            homeLocation != null &&
            homePredictions.isEmpty)
          FilledButton(
            onPressed: onNext,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Continue to Profile',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
      ],
    );
  }

  Widget _buildSuggestionsList(ThemeData theme) {
    return Card(
      margin: const EdgeInsets.only(top: 8),
      elevation: 4,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: homePredictions.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final prediction = homePredictions[index];
          return ListTile(
            leading: const Icon(
              LucideIcons.mapPin,
              size: 20,
              color: Colors.grey,
            ),
            title: Text(prediction.primaryText),
            subtitle: Text(prediction.secondaryText),
            onTap: () => onHomeSelectPlace(prediction.placeId),
          );
        },
      ),
    );
  }
}
