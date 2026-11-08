import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'die_tile.dart';

class DiceBoard extends StatelessWidget {
  const DiceBoard({
    super.key,
    required this.tiles,
    required this.editing,
    this.availableHeight,
  });

  final List<DieTile> tiles;
  final bool editing;
  final double? availableHeight;

  double _height(BuildContext context, int columns, double width, double gap) {
    var height = 0.0;
    for (var start = 0; start < tiles.length; start += columns) {
      var rowHeight = 0.0;
      for (var i = start; i < math.min(start + columns, tiles.length); i++) {
        rowHeight = math.max(
          rowHeight,
          tiles[i].heightForWidth(context, width),
        );
      }
      height += rowHeight + (start == 0 ? 0 : gap);
    }
    return height;
  }

  (int, double) _fittedLayout(BuildContext context, double width) {
    const gap = 12.0;
    final minimumWidth = editing ? 144.0 : 112.0;
    final maximumColumns = math.min(
      tiles.length,
      ((width + gap) / (minimumWidth + gap)).floor().clamp(1, 8),
    );
    var bestColumns = 0;
    var bestWidth = 0.0;
    for (var columns = 1; columns <= maximumColumns; columns++) {
      var tileWidth = (width - (columns - 1) * gap) / columns;
      final rows = (tiles.length / columns).ceil();
      while (tileWidth >= minimumWidth) {
        final height = _height(context, columns, tileWidth, gap);
        if (height <= availableHeight! + .01) {
          if (tileWidth > bestWidth) {
            bestColumns = columns;
            bestWidth = tileWidth;
          }
          break;
        }
        tileWidth -= math.max(1, (height - availableHeight!) / rows);
      }
    }
    if (bestColumns != 0) return (bestColumns, bestWidth);

    final overhead = tiles
        .map(
          (tile) => tile.heightForWidth(context, minimumWidth) - minimumWidth,
        )
        .reduce(math.max);
    final targetWidth = math.max(minimumWidth, availableHeight! - overhead);
    return (
      maximumColumns,
      math.min(
        targetWidth,
        (width - (maximumColumns - 1) * gap) / maximumColumns,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final fitted = availableHeight != null;
      final largeText = MediaQuery.textScalerOf(context).scale(16) > 22;
      final columns =
          largeText
              ? 1
              : width < (editing ? 320 : 280)
              ? 1
              : math.min(tiles.length, (width / 190).floor().clamp(2, 5));
      final (columnCount, tileWidth) =
          fitted
              ? _fittedLayout(context, width)
              : (
                columns,
                math.min(260.0, (width - (columns - 1) * 16) / columns),
              );
      final gap = fitted ? 12.0 : 16.0;
      return Center(
        child: SizedBox(
          width: columnCount * tileWidth + (columnCount - 1) * gap,
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: gap,
            runSpacing: fitted ? gap : 20,
            children: [
              for (final tile in tiles) SizedBox(width: tileWidth, child: tile),
            ],
          ),
        ),
      );
    },
  );
}
