import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/core/theme/astra_theme.dart';
import 'package:astra_hub/features/clients/data/clients.dart';
import 'package:astra_hub/features/clients/data/clients_repository.dart';

/// Pastille colorée (statuts du domaine client).
class Pill extends StatelessWidget {
  const Pill(this.label, {this.color = AstraTheme.textSecondary, this.icon, super.key});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

Color deliverableColor(DeliverableStatus status) => switch (status) {
  DeliverableStatus.draft => AstraTheme.textSecondary,
  DeliverableStatus.published => AstraTheme.secondary,
  DeliverableStatus.awaitingValidation => AstraTheme.warning,
  DeliverableStatus.approved => AstraTheme.accent,
  DeliverableStatus.changesRequested => AstraTheme.error,
};

Color ticketColor(TicketStatus status) => switch (status) {
  TicketStatus.newTicket => AstraTheme.warning,
  TicketStatus.waitingClient => AstraTheme.secondary,
  TicketStatus.resolved || TicketStatus.closed => AstraTheme.accent,
  _ => AstraTheme.primary,
};

Color paymentColor(String status) => switch (status) {
  'confirmed' => AstraTheme.accent,
  'rejected' || 'unpaid' => AstraTheme.error,
  'partially_confirmed' => AstraTheme.warning,
  _ => AstraTheme.secondary,
};

String formatMoney(num amount, String currency) {
  if (currency == 'XOF' || currency == 'XAF') {
    return '${NumberFormat.decimalPattern('fr').format(amount.round())} FCFA';
  }
  return NumberFormat.currency(locale: 'fr', symbol: currency).format(amount);
}

void showMessage(BuildContext context, Object messageOrError) {
  final message = switch (messageOrError) {
    ApiException(:final message) => message,
    String() => messageOrError,
    _ => 'Une erreur est survenue.',
  };
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Télécharge et ouvre un fichier protégé de l'API.
Future<void> openClientFile(BuildContext context, WidgetRef ref, String path, String name) async {
  try {
    await ref.read(clientsRepositoryProvider).openFile(path, name);
  } on Exception catch (error) {
    if (context.mounted) showMessage(context, error);
  }
}

/// Lien d'activation à transmettre au client (affiché une seule fois).
Future<void> showInvitationDialog(
  BuildContext context,
  InvitationLink invitation,
  String fullName,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(invitation.isReset ? 'Lien de nouveau mot de passe' : 'Lien d\'activation'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Transmettez ce lien à $fullName (WhatsApp, email…). Il est valable '
            '${invitation.hours} heures et ne fonctionne qu\'une fois. Il ne sera plus affiché.',
          ),
          const SizedBox(height: 16),
          SelectableText(
            invitation.link,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          const SizedBox(height: 12),
          Text(
            'Si le lien ne s\'ouvre pas, le client peut coller ce code dans l\'application :',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          SelectableText(
            invitation.token,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: invitation.link));
            if (context.mounted) showMessage(context, 'Lien copié.');
          },
          icon: const Icon(Icons.copy),
          label: const Text('Copier le lien'),
        ),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Terminé')),
      ],
    ),
  );
}

/// Titre de section dans les listes.
class ListSectionTitle extends StatelessWidget {
  const ListSectionTitle(this.title, {this.trailing, super.key});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 8),
      child: Row(
        children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          ?trailing,
        ],
      ),
    );
  }
}
