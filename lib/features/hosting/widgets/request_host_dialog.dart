import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:diaspora_nearby/features/hosting/services/hosting_service.dart';
import 'package:diaspora_nearby/features/trust/services/trust_service.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

/// Bottom sheet dialog for travelers to request hosting in a community.
///
/// Collects travel dates, purpose, guest count, and optional notes.
/// On submit, creates a [HostingRequest] and broadcasts to the community chat.
class RequestHostDialog extends ConsumerStatefulWidget {
  final String communityId;
  final String communityName;
  final String? communityChatId;

  const RequestHostDialog({
    super.key,
    required this.communityId,
    required this.communityName,
    this.communityChatId,
  });

  /// Shows the dialog as a modal bottom sheet.
  static Future<bool?> show(
    BuildContext context, {
    required String communityId,
    required String communityName,
    String? communityChatId,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (context) => RequestHostDialog(
        communityId: communityId,
        communityName: communityName,
        communityChatId: communityChatId,
      ),
    );
  }

  @override
  ConsumerState<RequestHostDialog> createState() => _RequestHostDialogState();
}

class _RequestHostDialogState extends ConsumerState<RequestHostDialog> {
  DateTime? _arrivalDate;
  DateTime? _departureDate;
  String? _purpose;
  final _notesController = TextEditingController();
  int _guestCount = 1;
  bool _isSubmitting = false;

  final _purposes = [
    'Vacation',
    'Business',
    'Family Visit',
    'Education',
    'Transit',
    'Event',
    'Other',
  ];

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  bool get _isValid =>
      _arrivalDate != null &&
      _departureDate != null &&
      _departureDate!.isAfter(_arrivalDate!);

  int get _stayDuration {
    if (_arrivalDate == null || _departureDate == null) return 0;
    return _departureDate!.difference(_arrivalDate!).inDays;
  }

  Future<void> _pickDate(bool isArrival) async {
    final now = DateTime.now();
    final initial = isArrival
        ? (_arrivalDate ?? now.add(const Duration(days: 1)))
        : (_departureDate ??
              (_arrivalDate?.add(const Duration(days: 3)) ??
                  now.add(const Duration(days: 4))));

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: isArrival ? now : (_arrivalDate ?? now),
      lastDate: now.add(const Duration(days: 365)),
    );

    if (picked != null) {
      setState(() {
        if (isArrival) {
          _arrivalDate = picked;
          // Auto-adjust departure if it's before arrival
          if (_departureDate != null && _departureDate!.isBefore(picked)) {
            _departureDate = picked.add(const Duration(days: 1));
          }
        } else {
          _departureDate = picked;
        }
      });
    }
  }

  Future<void> _submit() async {
    if (!_isValid || _isSubmitting) return;

    setState(() => _isSubmitting = true);

    // Validate 91+ Trust Score to Request Peer Hosting
    final trustService = ref.read(trustServiceProvider);
    final trustScore = await trustService.calculateTrustScore(
      null,
    ); // Passing null uses current user
    if (trustScore < 91) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Trust Score of 91+ required to request Peer Hosting.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final hostingService = ref.read(hostingServiceProvider);
    final result = await hostingService.createHostingRequest(
      communityId: widget.communityId,
      communityName: widget.communityName,
      communityChatId: widget.communityChatId,
      arrivalDate: _arrivalDate!,
      departureDate: _departureDate!,
      purpose: _purpose,
      notes: _notesController.text.isNotEmpty ? _notesController.text : null,
      guestCount: _guestCount,
    );

    setState(() => _isSubmitting = false);

    if (!mounted) return;

    if (result != null) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Hosting request sent to ${widget.communityName}! '
            'Community members will be notified.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to create hosting request. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dateFormat = DateFormat('MMM d, yyyy');

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Drag Handle ── (outside scroll so it always stays on top)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: (_) {},
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.hintColor.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),

              // ── Scrollable Content ──
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.fromLTRB(
                    20,
                    0,
                    20,
                    24 + MediaQuery.of(context).viewInsets.bottom,
                  ),
                  children: [
                    // Title
                    Row(
                      children: [
                        const Icon(
                          LucideIcons.plane,
                          color: AppTheme.accent,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Request Host in ${widget.communityName}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Your request will be broadcast to the community chat. '
                      'Interested hosts can view your profile and reach out.',
                      style: TextStyle(fontSize: 13, color: theme.hintColor),
                    ),
                    const SizedBox(height: 20),

                    // ── Date Pickers ──
                    Row(
                      children: [
                        Expanded(
                          child: _DateCard(
                            label: 'Arrival',
                            date: _arrivalDate,
                            dateFormat: dateFormat,
                            onTap: () => _pickDate(true),
                            isDark: isDark,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DateCard(
                            label: 'Departure',
                            date: _departureDate,
                            dateFormat: dateFormat,
                            onTap: () => _pickDate(false),
                            isDark: isDark,
                          ),
                        ),
                      ],
                    ),
                    if (_stayDuration > 0) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            LucideIcons.calendar,
                            size: 14,
                            color: theme.hintColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$_stayDuration day${_stayDuration == 1 ? '' : 's'} • '
                            '${_stayDuration * 10} DSP',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.accent,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),

                    // ── Purpose ──
                    Text(
                      'Purpose of Visit',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: theme.hintColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _purposes.map((p) {
                        final selected = _purpose == p;
                        return ChoiceChip(
                          label: Text(p),
                          selected: selected,
                          onSelected: (s) =>
                              setState(() => _purpose = s ? p : null),
                          selectedColor: AppTheme.accent.withValues(
                            alpha: 0.15,
                          ),
                          labelStyle: TextStyle(
                            color: selected
                                ? const Color(0xFF4A7A5A)
                                : theme.textTheme.bodyMedium?.color,
                            fontSize: 13,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // ── Guest Count ──
                    Row(
                      children: [
                        Text(
                          'Guests',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: theme.hintColor,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: _guestCount > 1
                              ? () => setState(() => _guestCount--)
                              : null,
                          icon: const Icon(LucideIcons.minus, size: 18),
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                        ),
                        Text(
                          '$_guestCount',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        IconButton(
                          onPressed: _guestCount < 10
                              ? () => setState(() => _guestCount++)
                              : null,
                          icon: const Icon(LucideIcons.plus, size: 18),
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // ── Notes ──
                    TextField(
                      controller: _notesController,
                      decoration: InputDecoration(
                        hintText: 'Additional notes (optional)',
                        hintStyle: TextStyle(color: theme.hintColor),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isDark ? Colors.white24 : Colors.black12,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isDark ? Colors.white24 : Colors.black12,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      maxLines: 3,
                      minLines: 1,
                    ),
                    const SizedBox(height: 20),

                    // ── Submit Button ──
                    ElevatedButton.icon(
                      onPressed: _isValid && !_isSubmitting ? _submit : null,
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(LucideIcons.send, size: 18),
                      label: Text(
                        _isSubmitting
                            ? 'Sending...'
                            : 'Send Request to Community',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Reusable date picker card
class _DateCard extends StatelessWidget {
  final String label;
  final DateTime? date;
  final DateFormat dateFormat;
  final VoidCallback onTap;
  final bool isDark;

  const _DateCard({
    required this.label,
    required this.date,
    required this.dateFormat,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: AppTheme.cardDecoration(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).hintColor,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  LucideIcons.calendarDays,
                  size: 16,
                  color: date != null
                      ? AppTheme.accent
                      : Theme.of(context).hintColor,
                ),
                const SizedBox(width: 6),
                Text(
                  date != null ? dateFormat.format(date!) : 'Select',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: date != null
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: date != null ? null : Theme.of(context).hintColor,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
