import 'package:firecheck/features/remote_activity/domain/remote_attribution_view.dart';

/// Flattens a [RemoteAttributionView] into a single label → value map for
/// display in [AttributeKvTable]. Picks the typed sub-shape that matches
/// the feature type; falls back to the shared submission fields when no
/// typed row was present (e.g. "does not exist" submissions).
Map<String, Object?> flattenRemoteAttributionForDisplay(
  RemoteAttributionView view,
) {
  final Map<String, Object?> out = {};

  // Shared submission-level fields surface first.
  if (view.doesNotExist) {
    out['Does not exist'] = true;
  }
  if (view.remarks != null && (view.remarks?.isNotEmpty ?? false)) {
    out['Remarks'] = view.remarks;
  }

  switch (view.featureType) {
    case 'building':
      final b = view.building;
      if (b != null) {
        out.addAll({
          'CBMS ID': b['cbms_id'],
          'Building name': b['building_name'],
          'RA 9514 type': b['ra_9514_type'],
          'Storeys': b['storeys'],
          'Material': b['material'],
          if (b['cost_is_exact'] == true)
            'Estimated cost': b['cost_amount']
          else if (b['cost_estimate_range'] != null)
            'Cost range': b['cost_estimate_range'],
          'Fire-fighting facilities': b['fire_fighting_facilities'],
          'Fire load': b['fire_load'],
        });
      }
      final h = view.household;
      if (h != null) {
        out['Homeowner acknowledged'] = h['homeowner_acknowledged'];
        if (h['lebel_ng_kahinaan'] != null) {
          out['Lebel ng kahinaan'] = h['lebel_ng_kahinaan'];
        }
        if (h['safety_suggestions'] != null) {
          out['Safety suggestions'] = h['safety_suggestions'];
        }
      }
    case 'road':
      final r = view.road;
      if (r != null) {
        out.addAll({
          'Road name': r['road_name'],
          'Is bridge': r['is_bridge'],
          'Width (m)': r['width_meters'],
          'Road features': r['road_features'],
          if (r['others_description'] != null)
            'Other description': r['others_description'],
        });
      }
  }

  // Strip explicit null entries so the table doesn't show "Key: —" for
  // truly absent fields.
  out.removeWhere((_, v) => v == null);
  return out;
}
