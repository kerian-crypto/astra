/// Petits utilitaires de lecture JSON (sans génération de code).
library;

typedef Json = Map<String, dynamic>;

T enumFromJson<T extends Enum>(List<T> values, Object? value, T fallback) =>
    values.firstWhere((e) => e.name == value, orElse: () => fallback);

DateTime? dateOrNull(Object? value) => value == null ? null : DateTime.parse(value as String);

List<T> listOf<T>(Object? value, T Function(Json json) parse) =>
    List.unmodifiable(((value as List<dynamic>?) ?? const []).map((item) => parse(item as Json)));

List<String> stringsOf(Object? value) =>
    List.unmodifiable(((value as List<dynamic>?) ?? const []).cast<String>());

/// Date seule au format attendu par l'API (AAAA-MM-JJ).
String isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
