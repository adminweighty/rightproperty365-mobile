import 'package:material_ui/material_ui.dart';

/// Stamp shapes, in the order they are offered.
const stampShapes = ['ROUND', 'OVAL', 'RECTANGLE'];

String stampShapeLabel(String shape) => switch (shape) {
  'ROUND' => 'Round',
  'OVAL' => 'Oval',
  'RECTANGLE' => 'Rectangle',
  _ => shape,
};

/// Stamp inks and the colours the API prints them in.
const stampInks = {
  'BLUE': Color(0xFF1C3A9E),
  'RED': Color(0xFFBA1C26),
  'BLACK': Color(0xFF1C1C1E),
  'GREEN': Color(0xFF16723A),
  'PURPLE': Color(0xFF60268A),
};

String stampInkLabel(String ink) => switch (ink) {
  'BLUE' => 'Blue',
  'RED' => 'Red',
  'BLACK' => 'Black',
  'GREEN' => 'Green',
  'PURPLE' => 'Purple',
  _ => ink,
};

/// The API's limits on stamp text, in characters.
abstract final class StampLimits {
  static const text = 60;
  static const line = 30;
  static const lines = 3;
}

/// A generated company stamp: the person types the text and the API draws
/// it, like a rubber stamp (API 0.26 `Stamp`).
@immutable
class Stamp {
  const Stamp({
    this.shape = 'ROUND',
    this.colour = 'BLUE',
    required this.topText,
    this.centreLines = const [],
    this.bottomText = '',
    this.includeDate = true,
  });

  /// The starting stamp for someone with no saved stamp: their name.
  factory Stamp.forName(String name) {
    final top = name.trim().toUpperCase();
    return Stamp(
      topText: top.characters.length > StampLimits.text
          ? top.characters.take(StampLimits.text).toString()
          : top,
    );
  }

  factory Stamp.fromJson(Map<String, dynamic> json) => Stamp(
    shape: switch (json['shape']) {
      final String s when stampShapes.contains(s) => s,
      _ => 'ROUND',
    },
    colour: switch (json['colour']) {
      final String c when stampInks.containsKey(c) => c,
      _ => 'BLUE',
    },
    topText: json['top_text'] as String? ?? '',
    centreLines: [
      for (final line in (json['centre_lines'] as List?) ?? const [])
        line as String,
    ],
    bottomText: json['bottom_text'] as String? ?? '',
    includeDate: json['include_date'] == true,
  );

  final String shape;
  final String colour;
  final String topText;
  final List<String> centreLines;
  final String bottomText;
  final bool includeDate;

  /// Trimmed and upper-cased, empty centre lines left out, as the API keeps
  /// it.
  Map<String, dynamic> toJson() => {
    'shape': shape,
    'colour': colour,
    'top_text': topText.trim().toUpperCase(),
    'centre_lines': [
      for (final line in centreLines)
        if (line.trim().isNotEmpty) line.trim().toUpperCase(),
    ],
    'bottom_text': bottomText.trim().toUpperCase(),
    'include_date': includeDate,
  };

  Stamp copyWith({
    String? shape,
    String? colour,
    String? topText,
    List<String>? centreLines,
    String? bottomText,
    bool? includeDate,
  }) => Stamp(
    shape: shape ?? this.shape,
    colour: colour ?? this.colour,
    topText: topText ?? this.topText,
    centreLines: centreLines ?? this.centreLines,
    bottomText: bottomText ?? this.bottomText,
    includeDate: includeDate ?? this.includeDate,
  );

  /// What is wrong with it before it is sent, or null.
  String? get problem {
    final top = topText.trim();
    if (top.isEmpty) return 'Type the name on the stamp.';
    if (top.characters.length > StampLimits.text) {
      return 'The name can be at most ${StampLimits.text} characters.';
    }
    if (centreLines.where((l) => l.trim().isNotEmpty).length >
        StampLimits.lines) {
      return 'A stamp has at most ${StampLimits.lines} middle lines.';
    }
    if (centreLines.any((l) => l.trim().characters.length > StampLimits.line)) {
      return 'Each middle line can be at most ${StampLimits.line} characters.';
    }
    if (bottomText.trim().characters.length > StampLimits.text) {
      return 'The bottom text can be at most ${StampLimits.text} characters.';
    }
    return null;
  }

  /// The same stamp as the API would print it.
  String get key => toJson().toString();

  @override
  bool operator ==(Object other) => other is Stamp && other.key == key;

  @override
  int get hashCode => key.hashCode;
}
