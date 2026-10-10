import 'package:flutter/widgets.dart';

/// Classes de largeur (Material 3) : téléphone, tablette / pliable, grand écran.
enum WindowSize { compact, medium, expanded }

abstract final class Breakpoints {
  static const medium = 600.0;
  static const expanded = 1024.0;

  /// Largeur de lecture confortable du contenu principal.
  static const contentMaxWidth = 1180.0;
  static const formMaxWidth = 560.0;

  static WindowSize of(BuildContext context) => fromWidth(MediaQuery.sizeOf(context).width);

  static WindowSize fromWidth(double width) {
    if (width >= expanded) return WindowSize.expanded;
    if (width >= medium) return WindowSize.medium;
    return WindowSize.compact;
  }

  /// Marge latérale de page selon la largeur.
  static double gutter(BuildContext context) => switch (of(context)) {
    WindowSize.compact => 16,
    WindowSize.medium => 24,
    WindowSize.expanded => 32,
  };
}

extension WindowSizeContext on BuildContext {
  WindowSize get windowSize => Breakpoints.of(this);
  bool get isCompact => windowSize == WindowSize.compact;
  bool get isExpanded => windowSize == WindowSize.expanded;
}
