import 'tile.dart';

/// 公開された副露の種類です。
enum MeldType { chi, pon, kan }

/// 鳴いた人、牌構成、鳴き元を保持する公開副露です。
class Meld {
  /// 公開副露を生成します。
  Meld({
    required this.type,
    required this.ownerRiver,
    required this.tiles,
    required this.calledTile,
    required this.fromRiver,
  });

  /// チー・ポン・カンの種別です。
  final MeldType type;

  /// 鳴いた人に対応する河の入力先です。
  final InputTarget ownerRiver;

  /// 公開されている3枚または4枚の牌です。
  final List<Tile> tiles;

  /// 河から取得した牌です。
  final Tile calledTile;

  /// 鳴かれた牌が元々置かれていた河です。
  final InputTarget fromRiver;
}
