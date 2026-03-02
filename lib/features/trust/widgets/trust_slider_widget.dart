import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/trust/services/trust_service.dart';
import 'package:diaspora_nearby/features/trust/models/trust_data.dart';

class TrustSliderWidget extends ConsumerStatefulWidget {
  final String targetUserId;
  final String currentUserId;
  final double? initialRating;

  const TrustSliderWidget({
    super.key,
    required this.targetUserId,
    required this.currentUserId,
    this.initialRating,
  });

  @override
  ConsumerState<TrustSliderWidget> createState() => _TrustSliderWidgetState();
}

class _TrustSliderWidgetState extends ConsumerState<TrustSliderWidget> {
  late double _currentValue;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // Default to neutral/white (0.0) if no rating, or middle (50.0)?
    // Spec says: "0-1 white... red... yellow... green".
    // 0 is "Not enough data". If user interacts, they likely want to set a value.
    _currentValue = widget.initialRating ?? 0.0;
  }

  Color _getColor(double value) {
    final level = TrustLevelExtension.fromScore(value);
    switch (level) {
      case TrustLevel.lowTrust:
        return AppTheme.error;
      case TrustLevel.basicTrust:
        return Colors.deepOrange;
      case TrustLevel.mediumTrust:
        return Colors.amber;
      case TrustLevel.standardTrust:
        return Colors.lightGreen;
      case TrustLevel.highTrust:
        return AppTheme.accent;
    }
    return AppTheme.error;
  }

  String _getLabel(double value) {
    return TrustLevelExtension.fromScore(value).displayName;
  }

  Future<void> _submitRating() async {
    setState(() {
      _isSubmitting = true;
    });

    try {
      await ref
          .read(trustServiceProvider)
          .rateUser(
            fromUserId: widget.currentUserId,
            toUserId: widget.targetUserId,
            score: _currentValue,
          );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Trust rating updated')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColor(_currentValue);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.pageHorizontalPadding * 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Community Trust',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  _getLabel(_currentValue),
                  style: TextStyle(
                    color: color == Colors.grey.shade300
                        ? Colors.black54
                        : color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: color,
                thumbColor: color,
                inactiveTrackColor: color.withOpacity(0.2),
                overlayColor: color.withOpacity(0.1),
                trackHeight: 8.0,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 12.0,
                ),
              ),
              child: Slider(
                value: _currentValue,
                min: 0.0,
                max: 100.0,
                divisions: 100,
                label: _currentValue.round().toString(),
                onChanged: (value) {
                  setState(() {
                    _currentValue = value;
                  });
                },
                onChangeEnd: (value) {
                  // Auto-submit on release or require button?
                  // Auto-submit is smoother UX for sliders usually,
                  // but "Confirm" prevents accidental slips.
                  // Let's hold off auto-submit and add a button or
                  // allow the user to settle.
                  // The prompt says "slide...".
                  // Let's try auto-submit on drag end for seamless feel.
                  _submitRating();
                },
              ),
            ),
            if (_isSubmitting)
              const Center(child: LinearProgressIndicator(minHeight: 2))
            else
              Center(
                child: Text(
                  '${_currentValue.round()}%',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: color == Colors.grey.shade300
                        ? Colors.black45
                        : color,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
