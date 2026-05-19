import 'package:firecheck/features/remote_activity/presentation/attribute_kv_table.dart';
import 'package:flutter/material.dart';

/// Two-column "Yours / Theirs" view with differing values highlighted in
/// both panels. Used by:
///   - the existing-feature conflict review screen, with action buttons
///     wired by the parent;
///   - the new-feature dedup compare (parent supplies a mini-map header).
///
/// "Hide identical fields" toggle defaults to ON when at least
/// [hideThreshold] fields are identical, to keep cognitive load down on
/// long forms.
class SideBySideCompare extends StatefulWidget {
  const SideBySideCompare({
    required this.mine,
    required this.theirs,
    required this.differingKeys,
    super.key,
    this.mineLabel = 'Yours',
    this.theirsLabel = 'Theirs',
    this.hideThreshold = 5,
  });

  final Map<String, Object?> mine;
  final Map<String, Object?> theirs;
  final Set<String> differingKeys;
  final String mineLabel;
  final String theirsLabel;
  final int hideThreshold;

  @override
  State<SideBySideCompare> createState() => _SideBySideCompareState();
}

class _SideBySideCompareState extends State<SideBySideCompare> {
  bool? _hideIdentical;

  @override
  Widget build(BuildContext context) {
    final allKeys = {...widget.mine.keys, ...widget.theirs.keys}.toList();
    final identicalCount = allKeys.length - widget.differingKeys.length;
    final defaultHide = identicalCount >= widget.hideThreshold;
    final hide = _hideIdentical ?? defaultHide;

    final visibleKeys = hide
        ? allKeys.where(widget.differingKeys.contains).toList()
        : allKeys;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              _DiffSummaryChip(
                differing: widget.differingKeys.length,
                total: allKeys.length,
              ),
              const Spacer(),
              if (identicalCount > 0)
                TextButton.icon(
                  key: const Key('conflict-review.hide-identical-toggle'),
                  icon: Icon(hide ? Icons.visibility : Icons.visibility_off),
                  label: Text(hide
                      ? 'Show identical fields'
                      : 'Hide identical fields'),
                  onPressed: () =>
                      setState(() => _hideIdentical = !hide),
                ),
            ],
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Column(
                title: widget.mineLabel,
                values: _onlyKeys(widget.mine, visibleKeys),
                highlightKeys: widget.differingKeys,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Column(
                title: widget.theirsLabel,
                values: _onlyKeys(widget.theirs, visibleKeys),
                highlightKeys: widget.differingKeys,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Map<String, Object?> _onlyKeys(
    Map<String, Object?> src,
    List<String> keys,
  ) {
    return {for (final k in keys) k: src[k]};
  }
}

class _Column extends StatelessWidget {
  const _Column({
    required this.title,
    required this.values,
    required this.highlightKeys,
  });
  final String title;
  final Map<String, Object?> values;
  final Set<String> highlightKeys;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: AttributeKvTable(
        title: title,
        values: values,
        highlightKeys: highlightKeys,
      ),
    );
  }
}

class _DiffSummaryChip extends StatelessWidget {
  const _DiffSummaryChip({required this.differing, required this.total});
  final int differing;
  final int total;

  @override
  Widget build(BuildContext context) {
    final label = differing == 0
        ? 'Identical'
        : '$differing of $total fields differ';
    final color = differing == 0
        ? Colors.green.shade100
        : Colors.amber.shade100;
    final fg =
        differing == 0 ? Colors.green.shade900 : Colors.amber.shade900;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
