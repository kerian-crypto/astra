import 'package:intl/intl.dart';

final _day = DateFormat('d MMM yyyy', 'fr');
final _dayShort = DateFormat('d MMM', 'fr');
final _time = DateFormat('HH:mm', 'fr');

String formatDate(DateTime date) => _day.format(date.toLocal());

String formatDateShort(DateTime date) => _dayShort.format(date.toLocal());

String formatDateTime(DateTime date) =>
    '${_day.format(date.toLocal())} à ${_time.format(date.toLocal())}';

/// « à l'instant », « il y a 5 min », « hier », sinon la date.
String formatRelative(DateTime date, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final local = date.toLocal();
  final diff = reference.difference(local);
  if (diff.inMinutes < 1) return 'à l\'instant';
  if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
  if (diff.inHours < 24 && reference.day == local.day) {
    return 'aujourd\'hui à ${_time.format(local)}';
  }
  if (diff.inDays < 2) return 'hier à ${_time.format(local)}';
  if (diff.inDays < 7) return 'il y a ${diff.inDays} jours';
  return _day.format(local);
}

/// Échéance relative : « dans 3 jours », « aujourd'hui », « en retard de 2 jours ».
String formatDue(DateTime due, {DateTime? today}) {
  final now = today ?? DateTime.now();
  final start = DateTime(now.year, now.month, now.day);
  final days = DateTime(due.year, due.month, due.day).difference(start).inDays;
  if (days == 0) return 'aujourd\'hui';
  if (days == 1) return 'demain';
  if (days > 1) return 'dans $days jours';
  if (days == -1) return 'en retard d\'un jour';
  return 'en retard de ${-days} jours';
}

/// Montants : FCFA sans décimales, les autres devises avec 2 décimales.
String formatMoney(num amount, String currency) {
  if (currency == 'XOF' || currency == 'XAF') {
    return '${NumberFormat.decimalPattern('fr').format(amount.round())} FCFA';
  }
  return NumberFormat.currency(locale: 'fr', symbol: currency).format(amount);
}

String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes o';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} Ko';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
}

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}
