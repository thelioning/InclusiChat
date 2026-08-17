import 'package:flutter/material.dart';

class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Logo de InclusiChat',
      image: true,
      child: Image.asset(
        'assets/branding/inclusichat-logo-hd.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        isAntiAlias: true,
      ),
    );
  }
}
