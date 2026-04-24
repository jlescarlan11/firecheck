import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class FeatureBottomSheet extends StatelessWidget {
  const FeatureBottomSheet({
    required this.feature,
    required this.distanceMeters,
    super.key,
  });

  final Feature feature;
  final double distanceMeters;

  String get _shortId {
    final id = feature.id;
    if (id.length <= 12) return id;
    return '${id.substring(0, 4)}…${id.substring(id.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final typeLabel = feature.featureType == 'building'
        ? l.featureTypeBuilding
        : l.featureTypeRoad;
    final statusLabel = switch (feature.status) {
      'complete' => l.statusComplete,
      'in_progress' => l.statusInProgress,
      _ => l.statusUnfilled,
    };
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '$typeLabel · $statusLabel',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _row('ID', _shortId),
            _row('Type', feature.featureType),
            _row('Status', feature.status),
            _row('New?', feature.isNew ? 'yes' : 'no'),
            _row('Distance', l.metersAway(distanceMeters.round())),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8ED),
                border: Border.all(color: const Color(0xFFF6D68E)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                l.phase2FormNote,
                style: const TextStyle(color: Color(0xFF92560A)),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.close),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
