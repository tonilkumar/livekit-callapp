import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_call_app/core/di/injection.dart';
import 'package:video_call_app/core/theme/app_theme.dart';
import 'package:video_call_app/features/call/presentation/pages/join_page.dart';

void main() {
  setUpAll(() {
    // JoinPage resolves its bloc from the service locator.
    configureDependencies();
  });

  tearDownAll(() => sl.reset());

  testWidgets('Join screen renders its branding, fields and CTA', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark, home: const JoinPage()),
    );

    expect(find.text('Video Call'), findsOneWidget);
    expect(find.text('Enter a room to start talking'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Join Call'), findsOneWidget);
    expect(find.byIcon(Icons.videocam_rounded), findsWidgets);
  });

  testWidgets('Join button is disabled until both fields are filled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark, home: const JoinPage()),
    );

    FilledButton cta() =>
        tester.widget<FilledButton>(find.byType(FilledButton));
    expect(cta().onPressed, isNull);

    await tester.enterText(find.byType(TextField).first, 'demo-room');
    await tester.enterText(find.byType(TextField).last, 'Alex');
    await tester.pump();

    expect(cta().onPressed, isNotNull);
  });
}
