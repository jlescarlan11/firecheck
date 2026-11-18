import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firecheck/core/forms/assignment_form_store.dart';
import 'package:firecheck/core/forms/field_requirements.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/form_store_directory.dart';

void main() {
  late Directory directory;
  Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));
  setUp(() async {
    directory = await useTemporaryFormDirectory();
  });
  test('same version names in two maps retain different forms and requirements',
      () async {
    await writeAssignmentForms(
      'cebu',
      requirements: bytes('cebu rules'),
      definition: bytes('{"version":"v1","title":"Cebu"}'),
    );
    await writeAssignmentForms(
      'guadalupe',
      requirements: bytes('guadalupe rules'),
      definition: bytes('{"version":"v1","title":"Guadalupe"}'),
    );
    expect(await readAssignmentForm('cebu', requirements: true), 'cebu rules');
    expect(await readAssignmentForm('cebu', version: 'v1'), contains('Cebu'));
    expect(
      await readAssignmentForm('guadalupe', version: 'v1'),
      contains('Guadalupe'),
    );
    await writeAssignmentForms('cebu', definition: bytes('{"version":"v2"}'));
    expect(await readAssignmentForm('cebu', version: 'v1'), contains('Cebu'));
    expect(
      await readAssignmentForm('guadalupe', requirements: true),
      'guadalupe rules',
    );
  });
  test(
      'offline reload and map switching preserve distinct requirement snapshots',
      () async {
    await writeAssignmentForms(
      'legacy',
      requirements: bytes('building.buildingName=required'),
    );
    await writeAssignmentForms(
      'strict',
      requirements: bytes(
        'building.cbmsId=required\nbuilding.fireFightingFacilities=required',
      ),
    );
    for (final id in ['legacy', 'strict', 'legacy']) {
      final body = await readAssignmentForm(id, requirements: true);
      final requirements = parseFieldRequirements(body!);
      expect(
        requirements.isRequired(FieldRequirementKeys.buildingCbmsId),
        id == 'strict',
      );
      expect(
        requirements
            .isRequired(FieldRequirementKeys.buildingFireFightingFacilities),
        id == 'strict',
      );
    }
  });
  test('failed config refresh preserves the prior complete snapshot', () async {
    await writeAssignmentForms('cebu', requirements: bytes('valid'));
    await expectLater(
      writeAssignmentForms(
        'cebu',
        requirements: bytes('replacement'),
        definition: bytes('invalid'),
      ),
      throwsFormatException,
    );
    expect(await readAssignmentForm('cebu', requirements: true), 'valid');
  });
  test('legacy shared settings require refresh and remain on disk', () async {
    final legacy = File('${directory.path}/field_requirements.txt');
    await legacy.writeAsString('unknown owner');
    await expectLater(readAssignmentForm('cebu'), throwsStateError);
    await writeAssignmentForms('cebu');
    expect(await readAssignmentForm('cebu'), isNull);
    await expectLater(readAssignmentForm('guadalupe'), throwsStateError);
    expect(await legacy.readAsString(), 'unknown owner');
  });
}
