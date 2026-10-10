import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_client/core/layout/page_frame.dart';
import 'package:astra_client/core/theme/client_theme.dart';
import 'package:astra_client/core/widgets/state_views.dart';
import 'package:astra_client/features/billing/data/billing_repository.dart';
import 'package:astra_client/features/billing/presentation/invoice_screen.dart';

/// Historique des paiements déclarés et de leur vérification (§32).
class PaymentsScreen extends ConsumerWidget {
  const PaymentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final declarations = ref.watch(declarationsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Historique des paiements')),
      body: AsyncView(
        value: declarations,
        onRetry: () => ref.invalidate(declarationsProvider),
        isEmpty: (list) => list.isEmpty,
        empty: const StateMessage(
          icon: Icons.history_rounded,
          title: 'Aucun paiement déclaré',
          message:
              'Les paiements que vous déclarez apparaîtront ici avec leur statut de vérification.',
        ),
        builder: (list) => FramedListView(
          maxWidth: 860,
          onRefresh: () => ref.refresh(declarationsProvider.future),
          children: [
            for (final declaration in list) ...[
              DeclarationCard(declaration: declaration, showInvoice: true),
              const SizedBox(height: Space.sm),
            ],
          ],
        ),
      ),
    );
  }
}
