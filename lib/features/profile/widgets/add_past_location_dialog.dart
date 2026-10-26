import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/shared/models/google_places_models.dart';
import 'package:diaspora_nearby/features/shared/models/location.dart'
    as loc_model;
import 'package:diaspora_nearby/core/services/google_places_service.dart';

import 'package:diaspora_nearby/core/utils/location_utils.dart';

class AddPastLocationDialog extends StatefulWidget {
  final List<String> yearRange;
  final Function(loc_model.PastLocation) onAdd;
  final GooglePlacesService placesService;
  final String? homeCountryCode;

  const AddPastLocationDialog({
    super.key,
    required this.yearRange,
    required this.onAdd,
    required this.placesService,
    this.homeCountryCode,
  });

  @override
  State<AddPastLocationDialog> createState() => _AddPastLocationDialogState();
}

class _AddPastLocationDialogState extends State<AddPastLocationDialog> {
  final _searchController = TextEditingController();
  List<AutocompletePrediction> _predictions = [];
  int _searchSeq = 0;
  loc_model.UserLocation? _selectedLocation;
  String? _selectedYear;
  bool _isLoading = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String v) async {
    final trimmed = v.trim();
    final seq = ++_searchSeq;
    if (trimmed.isEmpty) {
      setState(() {
        _predictions = [];
        _selectedLocation = null;
      });
      return;
    }
    if (_selectedLocation != null &&
        trimmed != _selectedLocation!.formattedAddress.trim()) {
      setState(() => _selectedLocation = null);
    }
    final res = await widget.placesService.autocomplete(trimmed);
    if (mounted &&
        seq == _searchSeq &&
        _searchController.text.trim().isNotEmpty) {
      setState(() => _predictions = res);
    }
  }

  Future<void> _selectPlace(String id) async {
    _searchSeq++;
    setState(() {
      _predictions = [];
      _isLoading = true;
    });
    try {
      final res = await widget.placesService.getPlaceDetails(id);
      if (res?.place != null && mounted) {
        final place = res!.place;
        final components = place.addressComponents ?? [];
        final parsed = parseLocationComponents(place.address ?? '', components);

        if (parsed == null) throw Exception('Could not parse location');

        // Validation: Cannot be in home country
        if (widget.homeCountryCode != null) {
          if (widget.homeCountryCode!.toUpperCase() ==
              parsed.countryCode.toUpperCase()) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Past locations cannot be in your home country.'),
              ),
            );
            _searchController.clear();
            setState(() {
              _predictions = [];
              _isLoading = false;
            });
            return;
          }
        }

        setState(() {
          _selectedLocation = loc_model.UserLocation(
            formattedAddress: place.address ?? '',
            placeId: id,
            countryCode: parsed
                .countryCode, // CRITICAL: Populate this for community logic
            country: parsed.country,
            city: parsed.city,
            state: parsed.state,
            geometry: loc_model.UserLocationGeometry(
              location: loc_model.UserLocationCoordinates(
                lat: place.latLng?.lat ?? 0,
                lng: place.latLng?.lng ?? 0,
              ),
            ),
          );
          _predictions = [];
          _searchController.text = place.address ?? '';
        });
      }
    } catch (e) {
      debugPrint('Error selecting place: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Add Past Location',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                textCapitalization: TextCapitalization.sentences,
                autofillHints: const <String>[],
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'City/Location',
                  hintText: 'Search city...',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  prefixIcon: const Icon(LucideIcons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  suffixIcon: _isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                ),
              ),
              if (_predictions.isNotEmpty &&
                  _searchController.text.trim().isNotEmpty &&
                  _selectedLocation == null)
                Container(
                  constraints: const BoxConstraints(maxHeight: 150),
                  margin: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(
                    color: const Color(0x14888888),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    physics:
                        const NeverScrollableScrollPhysics(), // Important: Nested list
                    children: _predictions
                        .map(
                          (p) => ListTile(
                            title: Text(p.primaryText),
                            subtitle: Text(p.secondaryText),
                            onTap: () => _selectPlace(p.placeId),
                          ),
                        )
                        .toList(),
                  ),
                ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedYear,
                items: widget.yearRange
                    .map((y) => DropdownMenuItem(value: y, child: Text(y)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedYear = v),
                decoration: InputDecoration(
                  labelText: 'Lived until',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed:
                        (_selectedLocation != null && _selectedYear != null)
                        ? () {
                            widget.onAdd(
                              loc_model.PastLocation(
                                location: _selectedLocation!,
                                until: _selectedYear!,
                              ),
                            );
                            Navigator.pop(context);
                          }
                        : null,
                    child: const Text('Add'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
