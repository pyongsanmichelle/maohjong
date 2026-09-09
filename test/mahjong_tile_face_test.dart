import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maohjong/domain/tile.dart';
import 'package:maohjong/main.dart';
import 'package:maohjong/presentation/mahjong_tile_face.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('34種すべてに一意のPNGアセットを割り当てる', () async {
    expect(tileAssetPaths.keys.toSet(), Tile.values.toSet());
    expect(tileAssetPaths.values.toSet().length, Tile.values.length);
    expect(tileAssetPath(Tile.m1), endsWith('/Man1.png'));
    expect(tileAssetPath(Tile.p9), endsWith('/Pin9.png'));
    expect(tileAssetPath(Tile.s5), endsWith('/Sou5.png'));
    expect(tileAssetPath(Tile.east), endsWith('/Ton.png'));
    expect(tileAssetPath(Tile.red), endsWith('/Chun.png'));

    for (final path in tileAssetPaths.values) {
      final data = await rootBundle.load(path);
      expect(data.lengthInBytes, greaterThan(0), reason: path);
    }
  });

  test('34種すべてのPNGが空でない牌面を描画する', () async {
    for (final tile in Tile.values) {
      final data = await rootBundle.load(tileAssetPath(tile));
      final codec = await instantiateImageCodec(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        targetWidth: 60,
        targetHeight: 80,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final bytes = await image.toByteData(format: ImageByteFormat.rawRgba);
      final pixels = bytes!.buffer.asUint8List();
      var visiblePixels = 0;
      var coloredPixels = 0;
      for (var index = 0; index < pixels.length; index += 4) {
        final red = pixels[index];
        final green = pixels[index + 1];
        final blue = pixels[index + 2];
        final alpha = pixels[index + 3];
        if (alpha > 16) visiblePixels++;
        if (alpha > 16 && (red < 235 || green < 235 || blue < 235)) {
          coloredPixels++;
        }
      }
      image.dispose();
      codec.dispose();

      if (tile == Tile.white) {
        expect(visiblePixels, 0, reason: '白牌は無地の牌面です');
      } else {
        expect(visiblePixels, greaterThan(100), reason: tile.name);
        expect(coloredPixels, greaterThan(20), reason: tile.name);
      }
    }
  });

  testWidgets('同梱PNGで牌面を描画する', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MahjongTileFace(
            tile: Tile.m1,
            width: 30,
            height: 40,
            excludeFromSemantics: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('1萬'), findsNothing);
  });

  testWidgets('牌パレットと選択済み手牌が共通PNGを使う', (tester) async {
    await tester.pumpWidget(const MaohjongApp());
    await tester.pumpAndSettle();

    final paletteTile = find.byKey(const Key('palette-m1'));
    expect(
      find.descendant(of: paletteTile, matching: find.byType(Image)),
      findsOneWidget,
    );

    await tester.tap(paletteTile);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('handTile-0')),
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );
  });

  testWidgets('PNGを読めない場合は文字牌へフォールバックする', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MahjongTileFace(
            tile: Tile.m1,
            width: 30,
            height: 40,
            assetPathOverride: 'assets/images/mahjong_tiles/missing.png',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1萬'), findsOneWidget);
  });
}
