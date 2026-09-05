import 'tile.dart';

/// 公開された副露の種類です。
enum MeldType { chi, pon, kan }

/// カンの成立方法です。
enum KanType { open, concealed, added }

/// 副露またはカンが局面へ追加された経路です。
enum MeldOrigin { call, setup, selfKan }

/// 鳴いた人、牌構成、鳴き元を保持する公開副露です。
class Meld {
  /// 公開副露を生成します。
  Meld({
    required this.type,
    required this.ownerRiver,
    required this.tiles,
    required this.calledTile,
    required this.fromRiver,
    this.kanType,
    this.origin = MeldOrigin.call,
  });

  /// チー・ポン・カンの種別です。
  final MeldType type;

  /// 鳴いた人に対応する河の入力先です。
  final InputTarget ownerRiver;

  /// 公開されている3枚または4枚の牌です。
  final List<Tile> tiles;

  /// 河から取得した牌です。
  final Tile calledTile;

  /// 鳴かれた牌が元々置かれていた河です。暗槓と開始前登録では null です。
  final InputTarget? fromRiver;

  /// カンの場合の成立方法です。チーとポンでは null です。
  final KanType? kanType;

  /// この副露またはカンを追加した操作の種類です。
  final MeldOrigin origin;
}
