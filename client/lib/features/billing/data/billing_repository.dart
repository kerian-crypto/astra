import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_client/core/network/api_client.dart';
import 'package:astra_client/core/utils/json.dart';
import 'package:astra_client/core/utils/picked_file.dart';
import 'package:astra_client/features/billing/data/billing.dart';

final billingRepositoryProvider = Provider<BillingRepository>(
  (ref) => BillingRepository(ref.watch(apiProvider)),
);

class BillingRepository {
  BillingRepository(this._api);

  final Api _api;

  Future<List<Invoice>> invoices() =>
      _api.get('/client/invoices', parse: (data) => listOf(data, Invoice.fromJson));

  Future<InvoiceDetail> invoice(String id) =>
      _api.get('/client/invoices/$id', parse: (data) => InvoiceDetail.fromJson(data! as Json));

  Future<List<PaymentDeclaration>> declarations() => _api.get(
    '/client/payment-declarations',
    parse: (data) => listOf(data, PaymentDeclaration.fromJson),
  );

  /// Déclare un paiement effectué hors de l'application (aucun paiement en
  /// ligne, §27). Il reste « déclaré » jusqu'à la vérification par Astra.
  Future<PaymentDeclaration> declarePayment(
    String invoiceId, {
    required double amount,
    required DateTime paidOn,
    required PaymentMethod method,
    String? reference,
    String? note,
    PickedFile? proof,
  }) async {
    final form = FormData.fromMap({
      'amount': amount.toStringAsFixed(2),
      'paid_on': isoDate(paidOn),
      'method': method.value,
      if (reference != null && reference.trim().isNotEmpty) 'reference': reference.trim(),
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      if (proof != null) 'proof': await proof.toMultipart(),
    });
    return _api.post(
      '/client/invoices/$invoiceId/payment-declarations',
      data: form,
      parse: (data) => PaymentDeclaration.fromJson(data! as Json),
    );
  }

  Future<List<Contract>> contracts() =>
      _api.get('/client/contracts', parse: (data) => listOf(data, Contract.fromJson));

  Future<Contract> contract(String id) =>
      _api.get('/client/contracts/$id', parse: (data) => Contract.fromJson(data! as Json));
}

final invoicesProvider = FutureProvider.autoDispose<List<Invoice>>(
  (ref) => ref.watch(billingRepositoryProvider).invoices(),
);

final invoiceProvider = FutureProvider.autoDispose.family<InvoiceDetail, String>(
  (ref, id) => ref.watch(billingRepositoryProvider).invoice(id),
);

final declarationsProvider = FutureProvider.autoDispose<List<PaymentDeclaration>>(
  (ref) => ref.watch(billingRepositoryProvider).declarations(),
);

final contractsProvider = FutureProvider.autoDispose<List<Contract>>(
  (ref) => ref.watch(billingRepositoryProvider).contracts(),
);

final contractProvider = FutureProvider.autoDispose.family<Contract, String>(
  (ref, id) => ref.watch(billingRepositoryProvider).contract(id),
);
