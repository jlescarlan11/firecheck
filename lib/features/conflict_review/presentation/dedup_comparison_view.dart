import 'package:firecheck/core/geo/comparison_geometry.dart';
import 'package:firecheck/features/conflict_review/domain/dedup_comparison.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class DedupComparisonView extends StatelessWidget {
  const DedupComparisonView({required this.comparison, super.key});
  final DedupComparison comparison;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.dedupOfflineComparison),
        const SizedBox(height: 8),
        Semantics(
          label: l10n.dedupComparisonMap,
          image: true,
          child: SizedBox(
            height: 220,
            child: CustomPaint(
              key: const Key('dedup-review.geometry'),
              painter: _ComparisonPainter(comparison),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '● ${l10n.dedupMine}: ${comparison.mine.id} (${comparison.mine.featureType})',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        Text(
          '□ ${l10n.dedupExisting}: ${comparison.existing.id} (${comparison.existing.featureType})',
        ),
      ],
    );
  }
}

class _ComparisonPainter extends CustomPainter {
  _ComparisonPainter(this.comparison);
  final DedupComparison comparison;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFF1F5F9),
    );
    final projection = ComparisonProjection(
      [comparison.mine.geometry, comparison.existing.geometry],
      size,
    );
    // Existing: broad hollow square vertices. Mine: narrow line, round vertices.
    // Both remain identifiable when geometries coincide or printed grayscale.
    for (final (geometry, mine) in [
      (comparison.existing.geometry, false),
      (comparison.mine.geometry, true),
    ]) {
      final paint = Paint()
        ..color = mine ? const Color(0xFF075985) : const Color(0xFF9A3412)
        ..style = PaintingStyle.stroke
        ..strokeWidth = mine ? 2 : 5;
      for (final ring in geometry.paths) {
        final points = ring.map(projection.project).toList();
        final path = Path()..moveTo(points.first.dx, points.first.dy);
        for (final point in points.skip(1)) {
          path.lineTo(point.dx, point.dy);
        }
        canvas.drawPath(path, paint);
        for (final point in points) {
          if (mine) {
            canvas.drawCircle(point, 3, Paint()..color = paint.color);
          } else {
            canvas.drawRect(
              Rect.fromCenter(center: point, width: 12, height: 12),
              paint..strokeWidth = 2,
            );
            paint.strokeWidth = 5;
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ComparisonPainter oldDelegate) =>
      oldDelegate.comparison != comparison;
}
