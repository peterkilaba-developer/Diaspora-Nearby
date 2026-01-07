import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/models/location.dart' as loc_model;

/// Auto-capitalize first letter formatter
class CapitalizeFirstLetterFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;
    return TextEditingValue(
      text: newValue.text[0].toUpperCase() + newValue.text.substring(1),
      selection: newValue.selection,
    );
  }
}

class ProfileSetupDetailsStep extends StatelessWidget {
  final TextEditingController firstNameController;
  final TextEditingController lastNameController;
  final File? profileImage;
  final loc_model.UserLocation? homeLocation;
  final loc_model.UserLocation? hostLocation;
  final VoidCallback onPickImage;
  final VoidCallback onSubmit;
  final bool isSubmitting;
  final bool showLocation;
  final ValueChanged<bool> onLocationToggleChanged;

  const ProfileSetupDetailsStep({
    super.key,
    required this.firstNameController,
    required this.lastNameController,
    required this.profileImage,
    required this.homeLocation,
    required this.hostLocation,
    required this.onPickImage,
    required this.onSubmit,
    required this.isSubmitting,
    required this.showLocation,
    required this.onLocationToggleChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Profile Photo
        Center(
          child: GestureDetector(
            onTap: onPickImage,
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 60,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  backgroundImage: profileImage != null ? FileImage(profileImage!) : null,
                  child: profileImage == null
                    ? Icon(LucideIcons.user, size: 48, color: theme.colorScheme.onSurfaceVariant)
                    : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(LucideIcons.camera, size: 20, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Tap to add photo',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        
        // Name Fields with auto-capitalize
        TextFormField(
          controller: firstNameController,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'First Name',
            prefixIcon: const Icon(LucideIcons.user),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
          ),
          inputFormatters: [CapitalizeFirstLetterFormatter()],
          validator: (v) => v?.isEmpty == true ? 'Required' : null,
        ),
        const SizedBox(height: 16),
        
        TextFormField(
          controller: lastNameController,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Last Name',
            prefixIcon: const Icon(LucideIcons.user),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
          ),
          inputFormatters: [CapitalizeFirstLetterFormatter()],
          validator: (v) => v?.isEmpty == true ? 'Required' : null,
        ),
        
        const SizedBox(height: 24),
        
        // Location summary
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.home, size: 20, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        homeLocation?.formattedAddress ?? 'Home not set',
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(LucideIcons.mapPin, size: 20, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hostLocation?.formattedAddress ?? 'Host not set',
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        
        SwitchListTile(
          title: const Text('Show my current city name'),
          subtitle: const Text('If off, other users will only see your country and distance away.'),
          value: showLocation,
          onChanged: onLocationToggleChanged,
          secondary: const Icon(LucideIcons.eye),
          contentPadding: EdgeInsets.zero,
        ),
        
        const SizedBox(height: 24),
        
        SizedBox(
          height: 56,
          child: FilledButton(
            onPressed: isSubmitting ? null : onSubmit,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: isSubmitting 
              ? const SizedBox(
                  height: 24, 
                  width: 24, 
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : const Text('Complete Profile', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }
}
