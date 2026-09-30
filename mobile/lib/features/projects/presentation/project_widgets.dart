import 'package:flutter/material.dart';

import 'package:astra_hub/core/theme/astra_theme.dart';
import 'package:astra_hub/features/projects/data/project.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({required this.status, super.key});

  final ProjectStatus status;

  Color get _color => switch (status) {
    ProjectStatus.idea => AstraTheme.textSecondary,
    ProjectStatus.planning => AstraTheme.secondary,
    ProjectStatus.active => AstraTheme.accent,
    ProjectStatus.review => AstraTheme.warning,
    ProjectStatus.done => AstraTheme.primary,
    ProjectStatus.archived => AstraTheme.textSecondary,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(color: _color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
