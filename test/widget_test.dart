import 'package:flutter_test/flutter_test.dart';
import 'package:portal/main.dart';

void main() {
  testWidgets('Portal app starts successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const PortalApp());
    expect(find.byType(PortalApp), findsOneWidget);
  });
}
