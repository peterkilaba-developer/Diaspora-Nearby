import 'package:diaspora_nearby/features/auth/screens/auth_controller.dart';
import 'package:diaspora_nearby/features/auth/screens/phone_auth_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _LoadingAuthController extends AuthController {
  @override
  bool build() => true;
}

Future<void> _pumpPhoneAuth(WidgetTester tester, {bool loading = false}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (loading)
          authControllerProvider.overrideWith(_LoadingAuthController.new),
      ],
      child: const MaterialApp(home: PhoneAuthScreen()),
    ),
  );
  await tester.pump();

  final targetFinder =
      find.text(loading ? 'Connecting WhatsApp...' : 'Sign in with WhatsApp');
  await tester.scrollUntilVisible(
    targetFinder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}

void main() {
  testWidgets('shows WhatsApp sign-in button', (tester) async {
    await _pumpPhoneAuth(tester);

    expect(find.text('Sign in with WhatsApp'), findsOneWidget);
  });

  testWidgets('shows connecting state while authentication is loading', (
    tester,
  ) async {
    await _pumpPhoneAuth(tester, loading: true);

    expect(find.text('Connecting WhatsApp...'), findsOneWidget);

    final button = tester.widget<ElevatedButton>(
      find.byType(ElevatedButton),
    );
    expect(button.onPressed, isNull);
  });
}
