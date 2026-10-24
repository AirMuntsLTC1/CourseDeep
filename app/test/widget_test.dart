import 'package:flutter_test/flutter_test.dart';
import 'package:coursedeep/main.dart';

void main() {
  testWidgets('CourseDeep app builds', (tester) async {
    await tester.pumpWidget(const CourseDeepApp());
    expect(find.text('CourseDeep'), findsOneWidget);
  });
}
