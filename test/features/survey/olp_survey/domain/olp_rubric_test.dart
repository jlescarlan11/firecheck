import 'package:firecheck/features/survey/olp_survey/domain/olp_rubric.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rubric has exactly 35 items', () {
    expect(OlpRubric.items.length, 35);
  });

  test('section counts match the spec (B=15, C=9, D=5, E=6)', () {
    final byCount = <OlpSection, int>{};
    for (final item in OlpRubric.items) {
      byCount[item.section] = (byCount[item.section] ?? 0) + 1;
    }
    expect(byCount[OlpSection.b], 15);
    expect(byCount[OlpSection.c], 9);
    expect(byCount[OlpSection.d], 5);
    expect(byCount[OlpSection.e], 6);
  });

  test('all item codes are unique', () {
    final codes = OlpRubric.items.map((i) => i.code).toSet();
    expect(codes.length, 35);
  });

  test('thresholds are 12 and 24', () {
    expect(OlpRubric.mayroongThreshold, 12);
    expect(OlpRubric.ligtasThreshold, 24);
  });

  test('there are 10 construction elements', () {
    expect(OlpRubric.constructionElements.length, 10);
  });

  test('there are 4 materials', () {
    expect(OlpRubric.materials, ['kahoy', 'semento', 'bakal', 'others']);
  });
}
