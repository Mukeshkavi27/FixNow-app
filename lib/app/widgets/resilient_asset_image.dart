import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ResilientAssetImage extends StatelessWidget {
  const ResilientAssetImage({
    super.key,
    required this.assetName,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.color,
    this.colorBlendMode,
    this.filterQuality = FilterQuality.low,
    this.fallbackIcon = Icons.image_outlined,
    this.fallbackIconSize = 28,
    this.fallbackColor = AppTheme.primary,
    this.fallbackBackgroundColor = const Color(0xFFF4F8FF),
    this.width,
    this.height,
  });

  final String assetName;
  final BoxFit fit;
  final Alignment alignment;
  final Color? color;
  final BlendMode? colorBlendMode;
  final FilterQuality filterQuality;
  final IconData fallbackIcon;
  final double fallbackIconSize;
  final Color fallbackColor;
  final Color fallbackBackgroundColor;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetName,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      color: color,
      colorBlendMode: colorBlendMode,
      filterQuality: filterQuality,
      errorBuilder: (_, __, ___) => DecoratedBox(
        decoration: BoxDecoration(color: fallbackBackgroundColor),
        child: Center(
          child: Icon(
            fallbackIcon,
            size: fallbackIconSize,
            color: fallbackColor,
          ),
        ),
      ),
    );
  }
}
