import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:coursedeep/main.dart';
import 'package:coursedeep/util/segments.dart';

void main() {
  testWidgets('CourseDeep app builds', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const CourseDeepApp(supabaseConfigured: false));
    await tester.pump(const Duration(milliseconds: 400)); // the logo animates forever: no pumpAndSettle
    expect(find.text('CourseDeep'), findsWidgets);
  });

  test('file blocks are parsed', () {
    final s = parseSegments('Here you go\n<<<FILE: a/b.txt>>>\nhello\n<<<END FILE>>>\nDone');
    expect(s.whereType<FileSeg>().single.name, 'a/b.txt');
    expect(s.whereType<FileSeg>().single.content, 'hello');
    expect(s.whereType<FileSeg>().single.done, true);
  });
}
