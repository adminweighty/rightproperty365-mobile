import 'dart:ui' show Locale;

/// The `Accept-Language` header for the phone's languages, in the phone's
/// order (API 0.43.0 negotiates from it; only English exists today, and the
/// API falls back to it). English is always offered last.
String acceptLanguageHeader(List<Locale> locales) {
  final tags = <String>[];
  for (final locale in locales) {
    final tag = locale.toLanguageTag();
    if (tag.isEmpty || tag == 'und' || tags.contains(tag)) continue;
    tags.add(tag);
    if (tags.length == 5) break;
  }
  if (!tags.any((t) => t == 'en' || t.startsWith('en-'))) tags.add('en');
  return [
    for (var i = 0; i < tags.length; i++)
      i == 0 ? tags[i] : '${tags[i]};q=${(1 - i / 10).toStringAsFixed(1)}',
  ].join(', ');
}
