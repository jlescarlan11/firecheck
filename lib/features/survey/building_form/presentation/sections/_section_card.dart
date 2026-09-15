import 'package:firecheck/core/theme/app_layout.dart';
import 'package:flutter/material.dart';

/// Shared open section used by the building and road survey forms.
class SectionCard extends StatelessWidget {
  const SectionCard({required this.title, required this.child, super.key});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => AppSection(title: title, child: child);
}
