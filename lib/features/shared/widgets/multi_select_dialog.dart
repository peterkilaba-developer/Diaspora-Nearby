import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

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
  bool _isAddingCustom = false;

  @override
  void initState() {
    super.initState();
    _selectedItems = List.from(widget.initialSelectedItems);
    _currentItems = List.from(widget.items);
    if (!_currentItems.contains('Other')) {
      _currentItems.add('Other');
    }
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  void _addCustomItem(String value) {
    if (value.isNotEmpty && !_currentItems.contains(value)) {
      setState(() {
        // Insert before 'Other'
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
    return AlertDialog(
      title: Text('Select ${widget.title}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isAddingCustom)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _customController,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Specify Other',
                          border: OutlineInputBorder(),
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
            ListBody(
              children: _currentItems.map((item) {
                final checked = _selectedItems.contains(item);
                return CheckboxListTile(
                  value: checked,
                  title: Text(item),
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (checked) => _onItemCheckedChange(item, checked!),
                );
              }).toList(),
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
    );
  }
}
