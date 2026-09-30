import 'package:intl/intl.dart';

final _date = DateFormat('d MMM yyyy', 'fr');
final _shortDate = DateFormat('d MMM', 'fr');
final _dateTime = DateFormat('EEE d MMM · HH:mm', 'fr');
final _time = DateFormat('HH:mm', 'fr');

String formatDate(DateTime date) => _date.format(date);

String formatDateTime(DateTime date) => _dateTime.format(date.toLocal());

/// « 14:05 » aujourd'hui, « 3 oct. » sinon.
String formatShortMoment(DateTime date, {DateTime? now}) {
  final local = date.toLocal();
  final reference = now ?? DateTime.now();
  final sameDay =
      local.year == reference.year && local.month == reference.month && local.day == reference.day;
  return sameDay ? _time.format(local) : _shortDate.format(local);
}

/// « aujourd'hui », « demain », « il y a 2 j », « dans 5 j ».
String relativeDay(DateTime date, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final today = DateTime(reference.year, reference.month, reference.day);
  final days = DateTime(date.year, date.month, date.day).difference(today).inDays;
  return switch (days) {
    0 => 'aujourd\'hui',
    1 => 'demain',
    -1 => 'hier',
    > 1 => 'dans $days j',
    _ => 'il y a ${-days} j',
  };
}
