import 'package:firecheck/features/conflict_review/domain/local_attribution_flatten.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('diffAttributionKeys returns differing keys', () {
    final mine = {
      'roof': 'tile',
      'floors': 3,
      'use': 'residential',
    };
    final theirs = {
      'roof': 'tile',
      'floors': 2,
      'use': 'residential',
    };
    expect(diffAttributionKeys(mine, theirs), {'floors'});
  });

  test('diffAttributionKeys treats null and missing as equal', () {
    expect(diffAttributionKeys({'a': null}, {}), isEmpty);
  });

  test('diffAttributionKeys treats lists order-insensitively', () {
    expect(
      diffAttributionKeys(
        {'features': ['a', 'b']},
        {'features': ['b', 'a']},
      ),
      isEmpty,
    );
  });

  test('diffAttributionKeys detects list length differences', () {
    expect(
      diffAttributionKeys(
        {'features': ['a', 'b']},
        {'features': ['a']},
      ),
      {'features'},
    );
  });

  test('keys present on only one side count as differing', () {
    expect(
      diffAttributionKeys({'a': 1, 'b': 2}, {'a': 1}),
      {'b'},
    );
  });
}
