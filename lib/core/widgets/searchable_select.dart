import 'package:material_ui/material_ui.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/tokens.dart';

/// One choice in a [SearchableSelectField].
class SelectOption<T> {
  const SelectOption(this.value, this.label, {this.group, this.keywords = ''});

  final T value;
  final String label;

  /// Heading the option is listed under, when the list is grouped.
  final String? group;

  /// Extra words that also find this option, for example a country code.
  final String keywords;
}

const _folds = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'ā': 'a',
  'ç': 'c',
  'č': 'c',
  'ć': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ē': 'e',
  'ě': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ī': 'i',
  'ñ': 'n',
  'ń': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'ō': 'o',
  'š': 's',
  'ś': 's',
  'ß': 'ss',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ū': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'ž': 'z',
  'ź': 'z',
  'ż': 'z',
};

/// Lower-cased with accents removed, so "Sao" finds "São Paulo".
String foldForSearch(String text) =>
    text.toLowerCase().split('').map((c) => _folds[c] ?? c).join();

/// The options whose label or keywords contain every word of [query],
/// anywhere, ignoring case and accents. Order is kept.
List<SelectOption<T>> filterOptions<T>(
  List<SelectOption<T>> options,
  String query,
) {
  final words = foldForSearch(query)
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) return options;
  return options.where((option) {
    final haystack = foldForSearch('${option.label} ${option.keywords}');
    return words.every(haystack.contains);
  }).toList();
}

/// How many options are shown before asking the person to keep typing.
const selectPageSize = 100;

/// The app's dropdown: a field that opens a sheet with a search box and the
/// list of options. Use it for every pick-one list, short or long, so they
/// all behave the same way.
///
/// - Typing filters by any part of the label or keywords, ignoring case and
///   accents. Group headings stay while any of their options match.
/// - "No matches" is shown when nothing fits.
/// - With [anyLabel] the field can be cleared back to "any".
/// - Long lists show [selectPageSize] options and ask for more typing.
class SearchableSelectField<T> extends FormField<T> {
  SearchableSelectField({
    super.key,
    required String label,
    required List<SelectOption<T>> options,
    required ValueChanged<T?> onChanged,
    T? value,
    String? anyLabel,
    String? helperText,
    super.validator,
    super.enabled,
  }) : super(
         initialValue: value,
         builder: (state) {
           final selected = state.value;
           SelectOption<T>? current;
           for (final option in options) {
             if (option.value == selected) current = option;
           }
           final shown = current?.label ?? anyLabel;

           Future<void> open() async {
             final picked = await showModalBottomSheet<_Picked<T>>(
               context: state.context,
               isScrollControlled: true,
               useSafeArea: true,
               showDragHandle: true,
               builder: (context) => _SelectSheet<T>(
                 title: label,
                 options: options,
                 selected: selected,
                 anyLabel: anyLabel,
               ),
             );
             if (picked == null) return; // Dismissed: keep the value.
             state.didChange(picked.value);
             onChanged(picked.value);
           }

           return Semantics(
             button: true,
             enabled: enabled,
             label: '$label, ${shown ?? 'not chosen'}',
             excludeSemantics: true,
             child: InkWell(
               onTap: enabled ? open : null,
               borderRadius: BorderRadius.circular(Radii.md),
               child: InputDecorator(
                 isEmpty: shown == null,
                 decoration: InputDecoration(
                   labelText: label,
                   helperText: helperText,
                   errorText: state.errorText,
                   enabled: enabled,
                   suffixIcon: const Icon(Icons.search),
                 ),
                 child: shown == null
                     ? null
                     : Text(
                         shown,
                         style: Theme.of(state.context).textTheme.bodyLarge,
                       ),
               ),
             ),
           );
         },
       );
}

/// The sheet's result. Wrapped so "any" (null) differs from dismissing.
class _Picked<T> {
  const _Picked(this.value);
  final T? value;
}

class _SelectSheet<T> extends StatefulWidget {
  const _SelectSheet({
    required this.title,
    required this.options,
    required this.selected,
    required this.anyLabel,
  });

  final String title;
  final List<SelectOption<T>> options;
  final T? selected;
  final String? anyLabel;

  @override
  State<_SelectSheet<T>> createState() => _SelectSheetState<T>();
}

class _SelectSheetState<T> extends State<_SelectSheet<T>> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final matches = filterOptions(widget.options, _query.text);
    final shown = matches.take(selectPageSize).toList();
    final searching = _query.text.trim().isNotEmpty;

    final rows = <Widget>[
      // "Any" clears the choice. It is hidden while searching, where it
      // would look like a result.
      if (widget.anyLabel != null && !searching)
        _OptionTile(
          key: const Key('select-any'),
          label: widget.anyLabel!,
          selected: widget.selected == null,
          onTap: () => Navigator.pop(context, _Picked<T>(null)),
        ),
    ];
    String? heading;
    for (final option in shown) {
      if (option.group != null && option.group != heading) {
        heading = option.group;
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.x4,
              Space.x4,
              Space.x4,
              Space.x1,
            ),
            child: Semantics(
              header: true,
              child: Text(heading!, style: text.titleSmall),
            ),
          ),
        );
      }
      rows.add(
        _OptionTile(
          label: option.label,
          selected: option.value == widget.selected,
          onTap: () => Navigator.pop(context, _Picked<T>(option.value)),
        ),
      );
    }
    if (matches.isEmpty) {
      rows.add(
        Padding(
          padding: const EdgeInsets.all(Space.x4),
          child: Semantics(
            liveRegion: true,
            child: Text('No matches', style: text.bodyLarge),
          ),
        ),
      );
    } else if (matches.length > shown.length) {
      rows.add(
        Padding(
          padding: const EdgeInsets.all(Space.x4),
          child: Text('Keep typing to narrow the list', style: text.bodyMedium),
        ),
      );
    }

    return Padding(
      // Lift the sheet above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.x4),
              child: Semantics(
                header: true,
                child: Text(widget.title, style: text.titleLarge),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Space.x4),
              child: TextField(
                key: const Key('select-search'),
                controller: _query,
                autofocus: widget.options.length > 8,
                textInputAction: TextInputAction.search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Search',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: searching
                      ? IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(_query.clear),
                        )
                      : null,
                ),
              ),
            ),
            Divider(color: c.line),
            Expanded(child: ListView(children: rows)),
          ],
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListTile(
      // At least 48dp tall, and taller when large text wraps.
      minTileHeight: 48,
      selected: selected,
      selectedColor: c.primaryInk,
      title: Text(label),
      trailing: selected ? Icon(Icons.check, color: c.primaryInk) : null,
      onTap: onTap,
    );
  }
}
