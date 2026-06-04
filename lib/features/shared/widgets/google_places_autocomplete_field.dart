import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/core/services/google_places_service.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/shared/models/google_places_models.dart';

class GooglePlacesAutocompleteField extends ConsumerStatefulWidget {
  final String label;
  final Function(String description, String placeId) onSelected;
  final TextEditingController? controller;
  final String? initialValue;
  final PlaceTypeFilter? filter; // [NEW] Support filtering
  final String? Function(String?)? validator;
  final bool isHighlighted;

  const GooglePlacesAutocompleteField({
    super.key,
    required this.label,
    required this.onSelected,
    this.controller,
    this.initialValue,
    this.filter,
    this.validator,
    this.isHighlighted = false,
  });

  @override
  ConsumerState<GooglePlacesAutocompleteField> createState() =>
      _GooglePlacesAutocompleteFieldState();
}

class _GooglePlacesAutocompleteFieldState
    extends ConsumerState<GooglePlacesAutocompleteField> {
  // ... existing state items ...
  late TextEditingController _controller;
  Timer? _debounce;
  List<dynamic> _predictions = [];
  bool _isLoading = false;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ?? TextEditingController(text: widget.initialValue);
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        _removeOverlay();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (widget.controller == null) _controller.dispose();
    _removeOverlay();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    if (query.isEmpty) {
      setState(() {
        _predictions = [];
        _removeOverlay();
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      setState(() => _isLoading = true);

      try {
        final service = ref.read(googlePlacesServiceProvider);
        final results = await service.autocomplete(
          query,
          filter: widget.filter,
        ); // [FIX] Pass filter

        if (!mounted) return;

        setState(() {
          _predictions = results;
          _isLoading = false;
        });

        if (_predictions.isNotEmpty) {
          _showOverlay();
        } else {
          _removeOverlay();
        }
      } catch (e) {
        if (mounted) setState(() => _isLoading = false);
      }
    });
  }

  void _showOverlay() {
    if (!mounted) return;
    _removeOverlay();

    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final theme = Theme.of(context); // [FIX] Get theme

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: size.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0.0, size.height + 5.0),
          child: Material(
            elevation: 4.0,
            borderRadius: BorderRadius.circular(8),
            color: theme.cardColor, // [FIX] Theme-aware background
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: _predictions.length,
                itemBuilder: (context, index) {
                  final prediction = _predictions[index];
                  final mainText = prediction.primaryText;
                  final secondaryText = prediction.secondaryText;
                  final placeId = prediction.placeId;

                  return ListTile(
                    leading: Icon(
                      LucideIcons.mapPin,
                      size: 20,
                      color:
                          theme.iconTheme.color?.withValues(alpha: 0.6) ??
                          Colors.grey,
                    ),
                    title: Text(
                      mainText,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ), // [FIX] Theme-aware text
                    subtitle: secondaryText.isNotEmpty
                        ? Text(
                            secondaryText,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.textTheme.bodySmall?.color
                                  ?.withValues(alpha: 0.7),
                            ),
                          )
                        : null,
                    dense: true,
                    onTap: () {
                      _controller.text = '$mainText, $secondaryText';
                      widget.onSelected(_controller.text, placeId);
                      _removeOverlay();
                      _focusNode.unfocus();
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextFormField(
        controller: _controller,
        focusNode: _focusNode,
        autofocus: false, // [FIX] Disable auto-focus
        textCapitalization: TextCapitalization.words,
        validator: widget.validator,
        decoration: InputDecoration(
          labelText: widget.label,
          filled: true,
          fillColor: Theme.of(context).primaryColor.withValues(alpha: 0.05),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: widget.isHighlighted
                ? const BorderSide(color: Colors.red, width: 1.5)
                : BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: widget.isHighlighted
                ? const BorderSide(color: Colors.red, width: 1.5)
                : BorderSide.none,
          ),
          suffixIcon: _isLoading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : const Icon(LucideIcons.search, size: 20),
        ),
        onChanged: _onSearchChanged,
      ),
    );
  }
}
