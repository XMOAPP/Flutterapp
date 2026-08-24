import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class ChatSpaceBackground extends StatelessWidget {
  static const _assetPath = 'assets/images/space_line.svg';
  static const _background = Color(0xFF0B1014);
  static const _tileWidth = 320.0;
  static const _svgWidth = 1440.0;
  static const _svgHeight = 2960.0;
  static const _opacity = 0.32;
  static const _colors = [
    Color(0xFFDBDDBB),
    Color(0xFF6BA587),
    Color(0xFFD5D88D),
    Color(0xFF88B884),
  ];

  const ChatSpaceBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const RepaintBoundary(
      child: ColoredBox(color: _background, child: _TiledSpacePattern()),
    );
  }
}

class _TiledSpacePattern extends StatelessWidget {
  const _TiledSpacePattern();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const tileWidth = ChatSpaceBackground._tileWidth;
        const tileHeight =
            tileWidth *
            ChatSpaceBackground._svgHeight /
            ChatSpaceBackground._svgWidth;
        final columns = (constraints.maxWidth / tileWidth).ceil() + 1;
        final rows = (constraints.maxHeight / tileHeight).ceil() + 1;
        final tiles = <Widget>[];

        for (var row = 0; row < rows; row++) {
          for (var column = 0; column < columns; column++) {
            tiles.add(
              Positioned(
                left: column * tileWidth,
                top: row * tileHeight,
                width: tileWidth,
                height: tileHeight,
                child: const _SpacePatternTile(),
              ),
            );
          }
        }

        return Stack(clipBehavior: Clip.hardEdge, children: tiles);
      },
    );
  }
}

class _SpacePatternTile extends StatelessWidget {
  const _SpacePatternTile();

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: ChatSpaceBackground._opacity,
      child: ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) {
          return const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: ChatSpaceBackground._colors,
          ).createShader(bounds);
        },
        child: SvgPicture.asset(
          ChatSpaceBackground._assetPath,
          fit: BoxFit.fill,
          allowDrawingOutsideViewBox: false,
        ),
      ),
    );
  }
}
