import 'package:flutter_test/flutter_test.dart';
import 'package:photolink_app/main.dart';

void main() {
  testWidgets('PhotoLinkApp smoke', (WidgetTester tester) async {
    await tester.pumpWidget(const PhotoLinkApp());
    expect(find.textContaining('PhotoLink'), findsWidgets);
  });
}
