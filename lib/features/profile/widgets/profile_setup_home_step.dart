import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/shared/models/google_places_models.dart';
import 'package:diaspora_nearby/features/shared/models/location.dart'
    as loc_model;

class ProfileSetupHomeStep extends StatelessWidget {
  final TextEditingController searchController;
  final FocusNode focusNode;
  final List<AutocompletePrediction> predictions;
  final loc_model.UserLocation? selectedLocation;
  final Function(String) onSearchChanged;
  final Function(String) onSelectPlace;
  final VoidCallback onNext;

  const ProfileSetupHomeStep({
    super.key,
    required this.searchController,
    required this.focusNode,
    required this.predictions,
    required this.selectedLocation,
    required this.onSearchChanged,
    required this.onSelectPlace,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(LucideIcons.home, size: 64, color: Colors.orange),
        const SizedBox(height: 16),
        Text(
          'Where are you from?',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'This helps us connect you with others from your home country',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),

        TextFormField(
          controller: searchController,
          focusNode: focusNode,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'Search your hometown',
            prefixIcon: const Icon(LucideIcons.search),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
          ),
          onChanged: onSearchChanged,
        ),

        if (predictions.isNotEmpty) _buildSuggestionsList(theme),

        if (selectedLocation != null &&
            predictions.isEmpty &&
            searchController.text.isNotEmpty) ...[
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onNext,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.green,
              side: const BorderSide(color: Colors.green, width: 2),
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
