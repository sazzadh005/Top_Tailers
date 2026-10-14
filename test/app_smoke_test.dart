import 'package:flutter_test/flutter_test.dart';
import 'package:top_tailers_/main.dart';

void main() {
  testWidgets('shows the splash, then the sign-in screen', (tester) async {
    await tester.pumpWidget(const TopTailersApp());

    // Splash screen is visible while the session is being restored.
    expect(find.text('Top Tailers & Fabrics'), findsOneWidget);

    // Let the splash delay elapse.
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump();

    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('Register'), findsOneWidget);
  });
}
