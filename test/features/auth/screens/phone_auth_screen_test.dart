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

  await tester.scrollUntilVisible(
    find.text('Sign in with WhatsApp'),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}

void main() {
  testWidgets('shows WhatsApp sign-in as an explicit auth choice', (
    tester,
  ) async {
    await _pumpPhoneAuth(tester);

    expect(find.text('Send Verification Code'), findsOneWidget);
    expect(find.text('Sign in with WhatsApp'), findsOneWidget);
  });

  testWidgets('keeps WhatsApp choice visible while authentication is loading', (
    tester,
  ) async {
    await _pumpPhoneAuth(tester, loading: true);

    expect(find.text('Securing connection...'), findsOneWidget);
    expect(find.text('Sign in with WhatsApp'), findsOneWidget);

    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Sign in with WhatsApp'),
    );
    expect(button.onPressed, isNull);
  });
}
