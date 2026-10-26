import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

class MultiSelectDialog extends StatefulWidget {
  final String title;
  final List<String> items;
  final List<String> initialSelectedItems;

  const MultiSelectDialog({
    super.key,
    required this.title,
    required this.items,
    required this.initialSelectedItems,
  });

  @override
  State<MultiSelectDialog> createState() => _MultiSelectDialogState();
}

class _MultiSelectDialogState extends State<MultiSelectDialog> {
  late List<String> _selectedItems;
  late List<String> _currentItems;
  final TextEditingController _customController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isAddingCustom = false;

  @override
  void initState() {
    super.initState();
    _selectedItems = List.from(widget.initialSelectedItems);
    _currentItems = List.from(widget.items);
    for (final existing in _selectedItems) {
      if (!_currentItems.contains(existing)) {
        _currentItems.insert(0, existing);
      }
    }
    if (!_currentItems.contains('Other')) {
      _currentItems.add('Other');
    }
  }

  @override
  void dispose() {
    _customController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _addCustomItem(String value) {
    if (value.isNotEmpty && !_currentItems.contains(value)) {
      setState(() {
        final otherIndex = _currentItems.indexOf('Other');
        if (otherIndex != -1) {
          _currentItems.insert(otherIndex, value);
        } else {
          _currentItems.add(value);
        }
        _selectedItems.add(value);
        _isAddingCustom = false;
        _customController.clear();
      });
    }
  }

  void _onItemCheckedChange(String item, bool checked) {
    if (item == 'Other' && checked) {
      setState(() => _isAddingCustom = true);
    } else {
      setState(() {
        if (checked) {
          _selectedItems.add(item);
        } else {
          _selectedItems.remove(item);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _searchQuery.trim().toLowerCase();
    final filteredItems = q.isEmpty
        ? _currentItems
        : _currentItems
              .where(
                (item) => item.toLowerCase().contains(q) || item == 'Other',
              )
              .toList();

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
        title: Text('Select ${widget.title}'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_currentItems.length > 10)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      hintText: 'Search ${widget.title.toLowerCase()}...',
                      prefixIcon: const Icon(LucideIcons.search, size: 18),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(LucideIcons.x, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      isDense: true,
                      filled: true,
                      fillColor: AppTheme.elevationColor(context, 1),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              if (_isAddingCustom)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _customController,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            labelText: 'Specify Other',
                            filled: true,
                            fillColor: AppTheme.elevationColor(context, 1),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.check),
                        onPressed: () =>
                            _addCustomItem(_customController.text.trim()),
                      ),
                    ],
                  ),
                ),
              Flexible(
                child: SingleChildScrollView(
                  child: ListBody(
                    children: filteredItems.map((item) {
                      final checked = _selectedItems.contains(item);
                      return CheckboxListTile(
                        value: checked,
                        title: Text(item),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (checked) =>
                            _onItemCheckedChange(item, checked!),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, _selectedItems),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
