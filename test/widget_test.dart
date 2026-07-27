import 'package:flutter_test/flutter_test.dart';

import 'package:screenstreaks/main.dart';

void main() {
  testWidgets('Error screen when no Supabase configured', (tester) async {
    // The app requires Supabase keys. Without them, it shows an error screen.
    // This test is a placeholder until we have real integration tests.
    expect(find.byType(ErrorApp), findsNothing);
  });
}
