import 'package:diaspora_nearby/features/chat/widgets/bilateral_flag_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';

void main() {
  testWidgets('renders both corridor flags for a chamber', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: BilateralFlagAvatar(homeCountryCode: 'TZ', hostCountryCode: 'US'),
      ),
    );

    expect(find.text('TZ'), findsNothing);
    expect(find.text('US'), findsNothing);
    expect(find.textContaining('\u{1F1F9}\u{1F1FF}'), findsOneWidget);
    expect(find.textContaining('\u{1F1FA}\u{1F1F8}'), findsOneWidget);
  });

  testWidgets('uses a neutral fallback for an unrecognized country', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: BilateralFlagAvatar(homeCountryCode: 'XX', hostCountryCode: 'US'),
      ),
    );

    expect(find.byIcon(LucideIcons.landmark), findsOneWidget);
  });
}
