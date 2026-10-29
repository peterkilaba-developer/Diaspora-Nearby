import 'dart:async';
import 'package:flutter/material.dart';

/// Mixin to simplify repeating loading-state boilerplate in StatefulWidgets.
///
/// Usage:
/// ```dart
/// class _MyScreenState extends State<MyScreen> with LoadingMixin {
///   Future<void> _save() => withLoading(() async {
///     await repository.save(data);
///     // On success...
///   });
///
///   @override
///   Widget build(BuildContext context) {
///     return ElevatedButton(
///       onPressed: isLoading ? null : _save,
///       child: isLoading
///           ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
///           : const Text('Save'),
///     );
///   }
/// }
/// ```
mixin LoadingMixin<T extends StatefulWidget> on State<T> {
  bool _isLoading = false;

  /// Whether an async operation is in progress.
  bool get isLoading => _isLoading;

  /// Execute [action] while showing loading state.
  ///
  /// Automatically sets [isLoading] to `true` before the action and
  /// `false` after it completes (success or error). Checks `mounted`
  /// before calling `setState`.
  ///
  /// Returns the result of [action], or `null` if an error was caught
  /// and [onError] was provided.
  Future<R?> withLoading<R>(
    Future<R> Function() action, {
    void Function(Object error, StackTrace stack)? onError,
  }) async {
    if (_isLoading) return null; // Prevent double-taps
    if (mounted) setState(() => _isLoading = true);
    try {
      final result = await action();
      return result;
    } catch (e, stack) {
      if (onError != null) {
        onError(e, stack);
      } else {
        rethrow;
      }
      return null;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Apply [optimisticApply] immediately in 0ms on frame 0, run [action] in
  /// the background, and invoke [rollback] if [action] throws.
  Future<R?> withOptimisticUpdate<R>({
    required VoidCallback optimisticApply,
    required Future<R> Function() action,
    required VoidCallback rollback,
    void Function(Object error, StackTrace stack)? onError,
  }) async {
    if (mounted) setState(optimisticApply);
    try {
      return await action();
    } catch (e, stack) {
      if (mounted) setState(rollback);
      if (onError != null) {
        onError(e, stack);
      } else {
        rethrow;
      }
      return null;
    }
  }
}

/// Same mixin for ConsumerStatefulWidget (Riverpod).
///
/// Usage:
/// ```dart
/// class _MyScreenState extends ConsumerState<MyScreen> with ConsumerLoadingMixin {
///   Future<void> _save() => withLoading(() async { ... });
/// }
/// ```
mixin ConsumerLoadingMixin<T extends StatefulWidget> on State<T> {
  bool _isLoading = false;

  bool get isLoading => _isLoading;

  Future<R?> withLoading<R>(
    Future<R> Function() action, {
    void Function(Object error, StackTrace stack)? onError,
  }) async {
    if (_isLoading) return null;
    if (mounted) setState(() => _isLoading = true);
    try {
      final result = await action();
      return result;
    } catch (e, stack) {
      if (onError != null) {
        onError(e, stack);
      } else {
        rethrow;
      }
      return null;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Apply [optimisticApply] immediately in 0ms on frame 0, run [action] in
  /// the background, and invoke [rollback] if [action] throws.
  Future<R?> withOptimisticUpdate<R>({
    required VoidCallback optimisticApply,
    required Future<R> Function() action,
    required VoidCallback rollback,
    void Function(Object error, StackTrace stack)? onError,
  }) async {
    if (mounted) setState(optimisticApply);
    try {
      return await action();
    } catch (e, stack) {
      if (mounted) setState(rollback);
      if (onError != null) {
        onError(e, stack);
      } else {
        rethrow;
      }
      return null;
    }
  }
}
