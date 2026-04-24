import 'package:firecheck/core/db/database.dart';
import 'package:flutter/material.dart';

class SubmissionTabs extends StatelessWidget {
  const SubmissionTabs({
    required this.submissions,
    required this.activeIndex,
    required this.onTap,
    required this.onAdd,
    required this.canAddMore,
    required this.softCapTooltip,
    super.key,
  });

  final List<Submission> submissions;
  final int activeIndex;
  final void Function(int) onTap;
  final VoidCallback onAdd;
  final bool canAddMore;
  final String softCapTooltip;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < submissions.length; i++)
              _Tab(
                label: 'Structure ${i + 1}',
                active: i == activeIndex,
                onTap: () => onTap(i),
              ),
            Tooltip(
              message: canAddMore ? '' : softCapTooltip,
              child: Opacity(
                opacity: canAddMore ? 1 : 0.4,
                child: GestureDetector(
                  key: const Key('submission-tabs.add'),
                  onTap: canAddMore ? onAdd : null,
                  child: const Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Text(
                      '+',
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFF3B82F6),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: 2,
              color: active ? const Color(0xFFC94A23) : Colors.transparent,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: active ? const Color(0xFFC94A23) : Colors.grey.shade700,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
