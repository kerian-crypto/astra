import 'package:flutter/material.dart';

import 'package:astra_client/core/layout/breakpoints.dart';

/// Contenu centré, à largeur de lecture maximale et marges adaptées à
/// l'écran : identique sur téléphone, tablette et grand écran.
class PageFrame extends StatelessWidget {
  const PageFrame({
    required this.child,
    this.maxWidth = Breakpoints.contentMaxWidth,
    this.padTop = true,
    super.key,
  });

  final Widget child;
  final double maxWidth;
  final bool padTop;

  @override
  Widget build(BuildContext context) {
    final gutter = Breakpoints.gutter(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsets.fromLTRB(gutter, padTop ? gutter / 2 : 0, gutter, 0),
          child: child,
        ),
      ),
    );
  }
}

/// Liste défilante encadrée par [PageFrame], avec tirer-pour-rafraîchir.
class FramedListView extends StatelessWidget {
  const FramedListView({
    required this.children,
    this.onRefresh,
    this.maxWidth = Breakpoints.contentMaxWidth,
    super.key,
  });

  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final gutter = Breakpoints.gutter(context);
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.symmetric(vertical: gutter / 2),
      children: [
        for (final child in children)
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: gutter),
                child: child,
              ),
            ),
          ),
        const SizedBox(height: 96),
      ],
    );
    final refresh = onRefresh;
    return refresh == null ? list : RefreshIndicator(onRefresh: refresh, child: list);
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

/// Deux colonnes sur grand écran (contenu + panneau latéral), empilées sinon.
class SplitLayout extends StatelessWidget {
  const SplitLayout({required this.main, required this.side, this.sideWidth = 360, super.key});

  final Widget main;
  final Widget side;
  final double sideWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 860) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [main, const SizedBox(height: 16), side],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: main),
            const SizedBox(width: 24),
            SizedBox(width: sideWidth, child: side),
          ],
        );
      },
    );
  }
}
