import 'package:flutter/material.dart';

/// Consistent reading width and gutters for forms and task lists.
EdgeInsets appPageInsets(BuildContext context, {double vertical = 24}) {
  final width = MediaQuery.sizeOf(context).width;
  return EdgeInsets.symmetric(
    horizontal: width > 728 ? (width - 680) / 2 : 24,
    vertical: vertical,
  );
}

class AppPageIntro extends StatelessWidget {
  const AppPageIntro({required this.title, this.subtitle, super.key});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineLarge),
            if (subtitle != null) ...[
              const SizedBox(height: 10),
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ],
        ),
      );
}

/// A section on the page surface, separated by a fine rule rather than a card.
class AppSection extends StatelessWidget {
  const AppSection({required this.child, this.title, super.key});
  final Widget child;
  final String? title;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border(
            top:
                BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Text(title!, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 20),
            ],
            child,
          ],
        ),
      );
}
