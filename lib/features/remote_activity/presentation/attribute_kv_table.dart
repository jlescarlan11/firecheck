import 'package:flutter/material.dart';

/// Compact key/value table for attribute display. Renders nothing when
/// the map is empty so callers can short-circuit on "no typed data".
class AttributeKvTable extends StatelessWidget {
  const AttributeKvTable({
    required this.values,
    super.key,
    this.highlightKeys = const {},
    this.title,
  });

  /// Map from human-readable key → value (string-coerced).
  final Map<String, Object?> values;

  /// Keys to highlight (used in side-by-side compare to mark fields that
  /// differ from the other side).
  final Set<String> highlightKeys;

  final String? title;

  @override
  Widget build(BuildContext context) {
    final entries = values.entries.toList();
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'No typed values.',
          style: TextStyle(
            color: Colors.grey.shade600,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(title!,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
        Table(
          columnWidths: const {
            0: IntrinsicColumnWidth(),
            1: FlexColumnWidth(),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.top,
          children: [
            for (final e in entries)
              TableRow(
                decoration: highlightKeys.contains(e.key)
                    ? BoxDecoration(color: Colors.amber.shade50)
                    : null,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    child: Text(
                      e.key,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    child: Text(
                      _format(e.value),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  String _format(Object? v) {
    if (v == null) return '—';
    if (v is List) return v.isEmpty ? '—' : v.join(', ');
    if (v is bool) return v ? 'yes' : 'no';
    return v.toString();
  }
}
