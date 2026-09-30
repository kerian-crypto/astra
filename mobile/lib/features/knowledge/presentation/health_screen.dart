import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/core/router/routes.dart';
import 'package:astra_hub/core/theme/astra_theme.dart';
import 'package:astra_hub/core/widgets/async_value_view.dart';
import 'package:astra_hub/features/ai/data/ai_repository.dart';
import 'package:astra_hub/features/knowledge/data/knowledge.dart';
import 'package:astra_hub/features/knowledge/data/knowledge_repository.dart';
import 'package:astra_hub/features/tasks/presentation/task_widgets.dart';

/// « État de santé d'Astra » (spec §18) : indicateurs calculés, et synthèse
/// rédigée par ASTRA AI à la demande.
class HealthScreen extends ConsumerStatefulWidget {
  const HealthScreen({super.key});

  @override
  ConsumerState<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends ConsumerState<HealthScreen> {
  String? _report;
  bool _isWriting = false;

  Future<void> _writeReport() async {
    setState(() => _isWriting = true);
    try {
      final report = await ref.read(aiRepositoryProvider).healthReport();
      if (mounted) setState(() => _report = report);
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _isWriting = false);
    }
  }

  void _open(HealthItem item) {
    if (item.taskId != null) {
      context.push(Routes.task(item.taskId!));
    } else if (item.projectId != null) {
      context.go(Routes.project(item.projectId!));
    }
  }

  @override
  Widget build(BuildContext context) {
    final health = ref.watch(healthProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('État de santé d\'Astra')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(healthProvider.future),
        child: AsyncValueView(
          value: health,
          onRetry: () => ref.invalidate(healthProvider),
          data: (data) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              OutlinedButton.icon(
                onPressed: _isWriting ? null : _writeReport,
                icon: _isWriting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(_isWriting ? 'Ronda rédige la synthèse…' : 'Synthèse par ASTRA AI'),
              ),
              if (_report != null)
                Card(
                  margin: const EdgeInsets.only(top: 12),
                  child: Padding(padding: const EdgeInsets.all(16), child: Text(_report!)),
                ),
              if (data.isHealthy)
                const Padding(
                  padding: EdgeInsets.only(top: 32),
                  child: Text('Aucun signal d\'alerte : tout est sous contrôle.'),
                ),
              for (final MapEntry(key: title, value: items) in data.sections.entries)
                if (items.isNotEmpty) ...[
                  SectionTitle(title, count: items.length),
                  for (final item in items)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.warning_amber, color: AstraTheme.warning),
                      title: Text(item.title),
                      subtitle: Text(item.subtitle),
                      onTap: item.taskId == null && item.projectId == null
                          ? null
                          : () => _open(item),
                    ),
                ],
            ],
          ),
        ),
      ),
    );
  }
}
