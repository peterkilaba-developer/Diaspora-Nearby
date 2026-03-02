import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

/// A beautiful, scrollable date picker shown as a bottom sheet.
///
/// Shows a calendar with quick-select shortcuts (Today, Tomorrow, +1 Week, etc.)
/// and returns the selected [DateTime] or null if dismissed.
class SmartDatePicker {
  SmartDatePicker._();

  static const _radius = 20.0;

  /// Show the smart date picker as a modal bottom sheet.
  ///
  /// [context] — Build context.
  /// [title] — Title displayed at top (e.g. "Departure Date").
  /// [initialDate] — The initially selected date.
  /// [firstDate] — Earliest selectable date.
  /// [lastDate] — Latest selectable date.
  /// [shortcuts] — Optional list of quick-select shortcut labels + dates.
  static Future<DateTime?> show({
    required BuildContext context,
    required String title,
    DateTime? initialDate,
    DateTime? firstDate,
    DateTime? lastDate,
    List<_DateShortcut>? shortcuts,
  }) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final first = firstDate ?? today;
    final last = lastDate ?? today.add(const Duration(days: 365));
    final initial = initialDate ?? today;

    // Clamp initial
    final clamped = initial.isBefore(first)
        ? first
        : (initial.isAfter(last) ? last : initial);

    // Build default shortcuts if none provided
    final effectiveShortcuts = shortcuts ??
        _buildDefaultShortcuts(first, last);

    return showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SmartDatePickerSheet(
        title: title,
        initialDate: clamped,
        firstDate: first,
        lastDate: last,
        shortcuts: effectiveShortcuts,
      ),
    );
  }

  static List<_DateShortcut> _buildDefaultShortcuts(
      DateTime first, DateTime last) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final shortcuts = <_DateShortcut>[];

    if (!today.isBefore(first) && !today.isAfter(last)) {
      shortcuts.add(_DateShortcut('Today', today));
    }

    final tomorrow = today.add(const Duration(days: 1));
    if (!tomorrow.isBefore(first) && !tomorrow.isAfter(last)) {
      shortcuts.add(_DateShortcut('Tomorrow', tomorrow));
    }

    final nextWeek = today.add(const Duration(days: 7));
    if (!nextWeek.isBefore(first) && !nextWeek.isAfter(last)) {
      shortcuts.add(_DateShortcut('+1 Week', nextWeek));
    }

    final twoWeeks = today.add(const Duration(days: 14));
    if (!twoWeeks.isBefore(first) && !twoWeeks.isAfter(last)) {
      shortcuts.add(_DateShortcut('+2 Weeks', twoWeeks));
    }

    final oneMonth = DateTime(today.year, today.month + 1, today.day);
    if (!oneMonth.isBefore(first) && !oneMonth.isAfter(last)) {
      shortcuts.add(_DateShortcut('+1 Month', oneMonth));
    }

    return shortcuts;
  }
}

class _DateShortcut {
  final String label;
  final DateTime date;
  const _DateShortcut(this.label, this.date);
}

class _SmartDatePickerSheet extends StatefulWidget {
  final String title;
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final List<_DateShortcut> shortcuts;

  const _SmartDatePickerSheet({
    required this.title,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.shortcuts,
  });

  @override
  State<_SmartDatePickerSheet> createState() => _SmartDatePickerSheetState();
}

class _SmartDatePickerSheetState extends State<_SmartDatePickerSheet> {
  late DateTime _selectedDate;
  late DateTime _currentMonth;

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _currentMonth = DateTime(_selectedDate.year, _selectedDate.month);
  }

  void _goToPreviousMonth() {
    final prev = DateTime(_currentMonth.year, _currentMonth.month - 1);
    if (!prev.isBefore(DateTime(widget.firstDate.year, widget.firstDate.month))) {
      setState(() => _currentMonth = prev);
    }
  }

  void _goToNextMonth() {
    final next = DateTime(_currentMonth.year, _currentMonth.month + 1);
    if (!next.isAfter(DateTime(widget.lastDate.year, widget.lastDate.month))) {
      setState(() => _currentMonth = next);
    }
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.elevationColor(context, 1),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(SmartDatePicker._radius)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withOpacity(0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                const Icon(LucideIcons.calendarDays, size: 18, color: AppTheme.accent),
                const SizedBox(width: 10),
                Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),

          // Quick shortcuts
          if (widget.shortcuts.isNotEmpty)
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: widget.shortcuts.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final sc = widget.shortcuts[i];
                  final isSelected = _isSameDay(sc.date, _selectedDate);
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedDate = sc.date;
                        _currentMonth = DateTime(sc.date.year, sc.date.month);
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.accent.withOpacity(0.15)
                            : AppTheme.elevationColor(context, 2),
                        borderRadius: BorderRadius.circular(20),
                        border: isSelected
                            ? Border.all(color: AppTheme.accent.withOpacity(0.4))
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          sc.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? AppTheme.accent
                                : theme.colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 12),

          // Month navigation
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: _goToPreviousMonth,
                  child: Icon(LucideIcons.chevronLeft, size: 20,
                      color: theme.colorScheme.onSurface.withOpacity(0.5)),
                ),
                Text(
                  '${_months[_currentMonth.month - 1]} ${_currentMonth.year}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                GestureDetector(
                  onTap: _goToNextMonth,
                  child: Icon(LucideIcons.chevronRight, size: 20,
                      color: theme.colorScheme.onSurface.withOpacity(0.5)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Day-of-week headers
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: _days.map((d) => Expanded(
                child: Center(
                  child: Text(
                    d,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface.withOpacity(0.3),
                    ),
                  ),
                ),
              )).toList(),
            ),
          ),
          const SizedBox(height: 6),

          // Calendar grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildCalendarGrid(theme),
          ),
          const SizedBox(height: 16),

          // Selected date + confirm button
          Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + bottomPad),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, _selectedDate),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: Text(
                  'Select ${_formatDisplay(_selectedDate)}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid(ThemeData theme) {
    final firstDayOfMonth = DateTime(_currentMonth.year, _currentMonth.month, 1);
    // Monday = 1, Sunday = 7
    final startWeekday = firstDayOfMonth.weekday; // 1-7
    final daysInMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day;

    final cells = <Widget>[];

    // Leading empty cells
    for (int i = 1; i < startWeekday; i++) {
      cells.add(const SizedBox());
    }

    // Day cells
    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_currentMonth.year, _currentMonth.month, day);
      final isSelectable = !date.isBefore(widget.firstDate) && !date.isAfter(widget.lastDate);
      final isSelected = _isSameDay(date, _selectedDate);
      final today = _isToday(date);

      cells.add(
        GestureDetector(
          onTap: isSelectable
              ? () => setState(() => _selectedDate = date)
              : null,
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.accent
                  : today
                      ? AppTheme.accent.withOpacity(0.08)
                      : null,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$day',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected || today ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? Colors.white
                      : !isSelectable
                          ? theme.colorScheme.onSurface.withOpacity(0.15)
                          : today
                              ? AppTheme.accent
                              : theme.colorScheme.onSurface.withOpacity(0.8),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Build rows of 7
    final rows = <Widget>[];
    for (int i = 0; i < cells.length; i += 7) {
      final rowCells = cells.sublist(i, (i + 7).clamp(0, cells.length));
      while (rowCells.length < 7) {
        rowCells.add(const SizedBox());
      }
      rows.add(
        SizedBox(
          height: 40,
          child: Row(children: rowCells.map((c) => Expanded(child: c)).toList()),
        ),
      );
    }

    return Column(children: rows);
  }

  String _formatDisplay(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${weekdays[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}';
  }
}
