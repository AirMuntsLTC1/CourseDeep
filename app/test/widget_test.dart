import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:coursedeep/main.dart';

void main() {
  testWidgets('CourseDeep app builds', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const CourseDeepApp());
    await tester.pumpAndSettle();
    expect(find.text('CourseDeep'), findsWidgets);
  });
}
