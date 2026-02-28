import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memorylens/main.dart';

void main() {
  testWidgets('App shell smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MemoryLensApp());

    // Verify search tab is active initially
    expect(
      find.text('Find coffee receipts, travel tickets...'),
      findsOneWidget,
    );

    // Tap the Timeline icon and trigger a frame
    await tester.tap(find.byIcon(Icons.photo_library_outlined));
    await tester.pumpAndSettle();

    // Verify timeline placeholder is shown
    expect(find.text('Your photo timeline will appear here'), findsOneWidget);

    // Tap Settings icon and trigger a frame
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    // Verify settings placeholder is shown
    expect(find.text('Settings coming soon'), findsOneWidget);
  });
}
