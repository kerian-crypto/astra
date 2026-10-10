import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_client/core/router/routes.dart';
import 'package:astra_client/core/theme/client_theme.dart';
import 'package:astra_client/core/utils/formatting.dart';
import 'package:astra_client/core/widgets/ui.dart';
import 'package:astra_client/features/deliverables/data/deliverable.dart';

class DeliverableCard extends StatelessWidget {
  const DeliverableCard({required this.deliverable, this.showProject = true, super.key});

  final Deliverable deliverable;
  final bool showProject;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final version = deliverable.currentVersion;
    final meta = [
      if (showProject) deliverable.projectName,
      if (version != null) 'Version ${version.number} · ${formatDateShort(version.publishedAt)}',
    ].join(' · ');
    final pending = deliverable.status == DeliverableStatus.awaitingValidation;
    return Card(
      shape: pending
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ClientTheme.radius),
              side: BorderSide(
                color: Tone.warning.foreground(scheme).withValues(alpha: 0.5),
                width: 1.5,
              ),
            )
          : null,
      child: InkWell(
        onTap: () => context.push(Routes.deliverable(deliverable.id)),
        child: Padding(
          padding: const EdgeInsets.all(Space.md),
          child: Row(
            children: [
              ToneIcon(Icons.inventory_2_outlined, tone: deliverable.status.tone, size: 44),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(deliverable.title, style: Theme.of(context).textTheme.titleSmall),
                    if (meta.isNotEmpty)
                      Text(
                        meta,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: Space.xs),
                    StatusPill(label: deliverable.status.label, tone: deliverable.status.tone),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
