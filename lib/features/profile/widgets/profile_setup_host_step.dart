import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/shared/models/google_places_models.dart';
import 'package:diaspora_nearby/features/shared/models/location.dart'
    as loc_model;

class ProfileSetupHostStep extends StatelessWidget {
  final TextEditingController searchController;
  final FocusNode focusNode;
  final List<AutocompletePrediction> predictions;
  final loc_model.UserLocation? selectedLocation;
  final Function(String) onSearchChanged;
  final Function(String) onSelectPlace;
  final VoidCallback onNext;
  final VoidCallback onBack;

  const ProfileSetupHostStep({
    super.key,
    required this.searchController,
    required this.focusNode,
    required this.predictions,
    required this.selectedLocation,
    required this.onSearchChanged,
    required this.onSelectPlace,
    required this.onNext,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(LucideIcons.mapPin, size: 64, color: Colors.blue),
        const SizedBox(height: 16),
        Text(
          'Where do you live now?',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Search for your host city. We will verify you are nearby.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),

        // 1. Search Bar
        TextFormField(
          controller: searchController,
          focusNode: focusNode,
          textCapitalization: TextCapitalization.sentences,
          autofillHints: const <String>[],
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            hintText: 'Search your current city',
            prefixIcon: const Icon(LucideIcons.search),
            suffixIcon: searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(LucideIcons.x, size: 18),
                    onPressed: () {
                      searchController.clear();
                      onSearchChanged(''); // Clear predictions
                    },
                  )
                : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
          ),
          onChanged: onSearchChanged,
        ),

        // 2. Suggestions List
        if (predictions.isNotEmpty &&
            searchController.text.trim().isNotEmpty &&
            selectedLocation == null)
          _buildSuggestionsList(theme, context),

        // 3. Selection Confirmation
        if (selectedLocation != null &&
            predictions.isEmpty &&
            searchController.text.isNotEmpty) ...[
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onNext,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.green,
              side: BorderSide.none,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(LucideIcons.check, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    selectedLocation!.formattedAddress,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(LucideIcons.arrowRight, size: 20),
              ],
            ),
          ),
        ],

        const SizedBox(height: 24),

        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: onBack,
          icon: const Icon(LucideIcons.arrowLeft, size: 18),
          label: const Text('Back'),
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildSuggestionsList(ThemeData theme, BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 8),
      elevation: 4,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: predictions.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final prediction = predictions[index];
          return ListTile(
            leading: const Icon(
              LucideIcons.mapPin,
              size: 20,
              color: Colors.grey,
            ),
            title: Text(prediction.primaryText),
            subtitle: Text(prediction.secondaryText),
            onTap: () => onSelectPlace(prediction.placeId),
          );
        },
      ),
    );
  }
}
