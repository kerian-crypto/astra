import 'package:flutter/material.dart';

/// Le « A » du logo Astra (orbite et étoile).
class AstraMark extends StatelessWidget {
  const AstraMark({this.width = 120, super.key});

  static const asset = 'assets/branding/astra_mark.png';

  final double width;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      width: width,
      semanticLabel: 'Logo Astra',
      filterQuality: FilterQuality.medium,
    );
  }
}
