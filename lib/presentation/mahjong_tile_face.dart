import 'package:flutter/material.dart';

import '../domain/tile.dart';
import 'tile_presentation.dart';

/// 同梱PNGの元寸法（幅600、高さ800）に基づく高さと幅の比率です。
const mahjongTileHeightToWidthRatio = 4 / 3;

/// 牌ごとに対応する同梱PNGアセットです。
const tileAssetPaths = <Tile, String>{
  Tile.m1: 'assets/images/mahjong_tiles/regular/Man1.png',
  Tile.m2: 'assets/images/mahjong_tiles/regular/Man2.png',
  Tile.m3: 'assets/images/mahjong_tiles/regular/Man3.png',
  Tile.m4: 'assets/images/mahjong_tiles/regular/Man4.png',
  Tile.m5: 'assets/images/mahjong_tiles/regular/Man5.png',
  Tile.m6: 'assets/images/mahjong_tiles/regular/Man6.png',
  Tile.m7: 'assets/images/mahjong_tiles/regular/Man7.png',
  Tile.m8: 'assets/images/mahjong_tiles/regular/Man8.png',
  Tile.m9: 'assets/images/mahjong_tiles/regular/Man9.png',
  Tile.p1: 'assets/images/mahjong_tiles/regular/Pin1.png',
  Tile.p2: 'assets/images/mahjong_tiles/regular/Pin2.png',
  Tile.p3: 'assets/images/mahjong_tiles/regular/Pin3.png',
  Tile.p4: 'assets/images/mahjong_tiles/regular/Pin4.png',
  Tile.p5: 'assets/images/mahjong_tiles/regular/Pin5.png',
  Tile.p6: 'assets/images/mahjong_tiles/regular/Pin6.png',
  Tile.p7: 'assets/images/mahjong_tiles/regular/Pin7.png',
  Tile.p8: 'assets/images/mahjong_tiles/regular/Pin8.png',
  Tile.p9: 'assets/images/mahjong_tiles/regular/Pin9.png',
  Tile.s1: 'assets/images/mahjong_tiles/regular/Sou1.png',
  Tile.s2: 'assets/images/mahjong_tiles/regular/Sou2.png',
  Tile.s3: 'assets/images/mahjong_tiles/regular/Sou3.png',
  Tile.s4: 'assets/images/mahjong_tiles/regular/Sou4.png',
  Tile.s5: 'assets/images/mahjong_tiles/regular/Sou5.png',
  Tile.s6: 'assets/images/mahjong_tiles/regular/Sou6.png',
  Tile.s7: 'assets/images/mahjong_tiles/regular/Sou7.png',
  Tile.s8: 'assets/images/mahjong_tiles/regular/Sou8.png',
  Tile.s9: 'assets/images/mahjong_tiles/regular/Sou9.png',
  Tile.east: 'assets/images/mahjong_tiles/regular/Ton.png',
  Tile.south: 'assets/images/mahjong_tiles/regular/Nan.png',
  Tile.west: 'assets/images/mahjong_tiles/regular/Shaa.png',
  Tile.north: 'assets/images/mahjong_tiles/regular/Pei.png',
  Tile.white: 'assets/images/mahjong_tiles/regular/Haku.png',
  Tile.green: 'assets/images/mahjong_tiles/regular/Hatsu.png',
  Tile.red: 'assets/images/mahjong_tiles/regular/Chun.png',
};

/// 指定した牌に対応する同梱PNGアセットのパスを返します。
String tileAssetPath(Tile tile) {
  final path = tileAssetPaths[tile];
  if (path == null) {
    throw StateError('${tile.name}に対応する牌画像がありません。');
  }
  return path;
}

/// 同梱PNGまたは文字フォールバックで牌面だけを描画します。
class MahjongTileFace extends StatelessWidget {
  /// 指定した牌を親レイアウトの寸法内へ描画します。
  const MahjongTileFace({
    super.key,
    required this.tile,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.excludeFromSemantics = true,
    @visibleForTesting this.assetPathOverride,
  });

  /// 表示する牌です。
  final Tile tile;

  /// 牌面を描画する幅です。nullの場合は親の制約へ従います。
  final double? width;

  /// 牌面を描画する高さです。nullの場合は親の制約へ従います。
  final double? height;

  /// 指定領域へPNGを収める方法です。
  final BoxFit fit;

  /// 外側の操作部品が読み上げを担当する場合に二重読み上げを防ぎます。
  final bool excludeFromSemantics;

  /// 読込失敗のテストでだけ利用するアセットパスの上書きです。
  @visibleForTesting
  final String? assetPathOverride;

  /// PNGを読めない場合に従来の文字牌を表示します。
  Widget _fallback(BuildContext context) => Container(
    width: width,
    height: height,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xff5b5b5b)),
      borderRadius: BorderRadius.circular(4),
    ),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        tileLabel(tile),
        style: TextStyle(color: tileColor(tile), fontWeight: FontWeight.bold),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Image.asset(
    assetPathOverride ?? tileAssetPath(tile),
    width: width,
    height: height,
    fit: fit,
    excludeFromSemantics: excludeFromSemantics,
    semanticLabel: excludeFromSemantics ? null : tileLabel(tile),
    filterQuality: FilterQuality.medium,
    gaplessPlayback: true,
    errorBuilder: (context, error, stackTrace) => _fallback(context),
  );
}
