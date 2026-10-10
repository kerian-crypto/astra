import 'package:flutter/widgets.dart';

/// Classes de largeur (Material 3) : téléphone, tablette, grand écran.
enum WindowSize { compact, medium, expanded }

abstract final class Breakpoints {
  static const medium = 600.0;
  static const expanded = 1024.0;
  static const contentMaxWidth = 1180.0;
  static const readingMaxWidth = 860.0;

  static WindowSize fromWidth(double width) {
    if (width >= expanded) return WindowSize.expanded;
    if (width >= medium) return WindowSize.medium;
    return WindowSize.compact;
  }

  static WindowSize of(BuildContext context) => fromWidth(MediaQuery.sizeOf(context).width);

  static double gutter(BuildContext context) => switch (of(context)) {
    WindowSize.compact => 16,
    WindowSize.medium => 24,
    WindowSize.expanded => 32,
  };
}

extension WindowSizeContext on BuildContext {
  WindowSize get windowSize => Breakpoints.of(this);
  bool get isCompact => windowSize == WindowSize.compact;
}

/// Centre le contenu d'une page et limite sa largeur sur grand écran, pour
/// garder des lignes lisibles au lieu d'étirer les listes sur 2 000 px.
class ResponsiveCenter extends StatelessWidget {
  const ResponsiveCenter({
    required this.child,
    this.maxWidth = Breakpoints.contentMaxWidth,
    super.key,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(height: double.infinity, child: child),
      ),
    );
  }
}

/// Grille de cartes : une colonne sur téléphone, plusieurs sur grand écran.
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    required this.children,
    this.minItemWidth = 320,
    this.spacing = 12,
    super.key,
  });

  final List<Widget> children;
  final double minItemWidth;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / minItemWidth).floor().clamp(1, 4);
        if (columns == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, child) in children.indexed) ...[
                if (i > 0) SizedBox(height: spacing),
                child,
              ],
            ],
          );
        }
        final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [for (final child in children) SizedBox(width: width, child: child)],
        );
      },
    );
  }
}
