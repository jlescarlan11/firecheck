import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class SubmittedBanner extends StatelessWidget {
  const SubmittedBanner({required this.submittedAt, super.key});
  final DateTime submittedAt;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final formatted =
        '${submittedAt.year}-${submittedAt.month.toString().padLeft(2, '0')}-${submittedAt.day.toString().padLeft(2, '0')}';
    return Card(
      color: const Color(0xFFE6FFFA),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF276749)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.submittedBadge,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF276749),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l.submittedAt(formatted),
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
