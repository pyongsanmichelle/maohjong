import 'tile.dart';

/// 麻雀牌の種類や数を分析ルールから共通利用するための属性です。
extension TileTraits on Tile {
  /// 字牌かどうかを返します。
  bool get isHonor => index >= 27;

  /// 数牌かどうかを返します。
  bool get isNumber => !isHonor;

  /// 萬子・筒子・索子を0から2で返します。字牌では null です。
  int? get suitIndex => isNumber ? index ~/ 9 : null;

  /// 数牌の1から9を返します。字牌では null です。
  int? get rank => isNumber ? index % 9 + 1 : null;

  /// 一九牌かどうかを返します。
  bool get isTerminal => isNumber && (rank == 1 || rank == 9);

  /// 么九牌かどうかを返します。
  bool get isTerminalOrHonor => isTerminal || isHonor;

  /// 2から8の中張牌かどうかを返します。
  bool get isSimple => isNumber && !isTerminal;

  /// 同じ色の指定された数字の牌を返します。
  Tile tileAtRank(int value) {
    final suit = suitIndex;
    if (suit == null || value < 1 || value > 9) {
      throw ArgumentError.value(value, 'value', '数牌の1から9を指定してください。');
    }
    return Tile.values[suit * 9 + value - 1];
  }
}
