import 'package:firecheck/core/db/database.dart';
import 'package:flutter/material.dart';

/// Minimal surface the map screen actually needs. Lets tests substitute a
/// renderer that doesn't require a GL context. Intentionally an abstract
/// class rather than a typedef so concrete implementations (Fake + real
/// Mapbox) can be distinguished by type in tests and provider overrides.
// ignore: one_member_abstracts
abstract class MapRenderer {
  Widget build(
    BuildContext context, {
    required List<Feature> features,
    required String boundaryGeojson,
    required void Function(Feature) onFeatureTap,
  });
}

/// Fake for widget tests — renders one tappable tile per feature instead of
/// a real map. Matches the real renderer's tap contract.
class FakeMapRenderer implements MapRenderer {
  @override
  Widget build(
    BuildContext context, {
    required List<Feature> features,
    required String boundaryGeojson,
    required void Function(Feature) onFeatureTap,
  }) {
    return ListView(
      shrinkWrap: true,
      children: features.map((f) {
        return GestureDetector(
          key: Key('fake-map-feature-${f.id}'),
          onTap: () => onFeatureTap(f),
          child: Container(
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.all(8),
            color: _colorForStatus(f.status),
            child: Text('feature ${f.id}'),
          ),
        );
      }).toList(),
    );
  }

  Color _colorForStatus(String status) {
    switch (status) {
      case 'complete':
        return const Color(0x66276749);
      case 'in_progress':
        return const Color(0x66B7791F);
      default:
        return const Color(0x66C53030);
    }
  }
}
