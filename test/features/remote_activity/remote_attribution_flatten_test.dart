import 'package:firecheck/features/remote_activity/domain/remote_attribution_flatten.dart';
import 'package:firecheck/features/remote_activity/domain/remote_attribution_view.dart';
import 'package:flutter_test/flutter_test.dart';

RemoteAttributionView _view({
  required String featureType,
  Map<String, dynamic>? building,
  Map<String, dynamic>? road,
  Map<String, dynamic>? household,
  bool doesNotExist = false,
  String? remarks,
}) {
  return RemoteAttributionView(
    id: 's1',
    assignmentId: 'a1',
    featureId: 'f1',
    featureType: featureType,
    attributeValues: {
      'does_not_exist': doesNotExist,
      'remarks': remarks,
      'building': building,
      'road': road,
      'household': household,
    },
    submittedBy: 'alice',
    submittedAt: DateTime.utc(2026, 5, 18, 10),
    supersededAt: null,
    updatedAt: DateTime.utc(2026, 5, 18, 10),
  );
}

void main() {
  test('building flattens into typed key/values', () {
    final v = _view(
      featureType: 'building',
      building: {
        'cbms_id': 'CBMS-001',
        'storeys': 3,
        'material': 'concrete',
        'cost_is_exact': true,
        'cost_amount': 1500000,
        'fire_fighting_facilities': ['extinguisher'],
      },
    );
    final flat = flattenRemoteAttributionForDisplay(v);
    expect(flat['CBMS ID'], 'CBMS-001');
    expect(flat['Storeys'], 3);
    expect(flat['Material'], 'concrete');
    expect(flat['Estimated cost'], 1500000);
    expect(flat['Fire-fighting facilities'], ['extinguisher']);
    expect(flat.containsKey('Cost range'), isFalse,
        reason: 'exact cost path excludes the estimate range');
  });

  test('cost range is shown only when cost_is_exact is false', () {
    final v = _view(
      featureType: 'building',
      building: {
        'cost_is_exact': false,
        'cost_estimate_range': '1M-2M',
      },
    );
    final flat = flattenRemoteAttributionForDisplay(v);
    expect(flat['Cost range'], '1M-2M');
    expect(flat.containsKey('Estimated cost'), isFalse);
  });

  test('road flattens typed fields', () {
    final v = _view(
      featureType: 'road',
      road: {
        'road_name': 'Rizal Ave.',
        'is_bridge': false,
        'width_meters': 6,
        'road_features': ['drainage'],
      },
    );
    final flat = flattenRemoteAttributionForDisplay(v);
    expect(flat['Road name'], 'Rizal Ave.');
    expect(flat['Is bridge'], false);
    expect(flat['Width (m)'], 6);
  });

  test('does_not_exist + remarks surface at the top', () {
    final v = _view(
      featureType: 'building',
      doesNotExist: true,
      remarks: 'demolished',
    );
    final flat = flattenRemoteAttributionForDisplay(v);
    expect(flat['Does not exist'], true);
    expect(flat['Remarks'], 'demolished');
  });

  test('null values are stripped — no "Key: —" rows', () {
    final v = _view(
      featureType: 'building',
      building: {
        'cbms_id': null,
        'storeys': 2,
        'material': null,
      },
    );
    final flat = flattenRemoteAttributionForDisplay(v);
    expect(flat.containsKey('CBMS ID'), isFalse);
    expect(flat.containsKey('Material'), isFalse);
    expect(flat['Storeys'], 2);
  });
}
