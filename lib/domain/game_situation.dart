import 'meld.dart';
import 'tile.dart';

/// 将来の分析機能へ渡す、手牌、各家の河、ドラ表示牌を含む局面データです。
class GameSituation {
  /// 空の局面を生成します。
  GameSituation()
    : hand = [],
      ownRiver = [],
      upperRiver = [],
      acrossRiver = [],
      lowerRiver = [],
      doraIndicators = [],
      melds = [];

  /// 自分の手牌です。
  final List<Tile> hand;

  /// 自分の河です。
  final List<Tile> ownRiver;

  /// 上家の河です。
  final List<Tile> upperRiver;

  /// 対面の河です。
  final List<Tile> acrossRiver;

  /// 下家の河です。
  final List<Tile> lowerRiver;

  /// 表示されているドラ表示牌です。カンによる複数表示にも対応します。
  final List<Tile> doraIndicators;

  /// 全プレイヤーの公開副露です。
  final List<Meld> melds;

  /// 指定した河に対応するプレイヤーの副露を返します。
  Iterable<Meld> meldsFor(InputTarget river) =>
      melds.where((meld) => meld.ownerRiver == river);

  /// 次局の入力に備えて、局ごとに変わる牌情報を空にします。
  void clearForNextRound() {
    hand.clear();
    ownRiver.clear();
    upperRiver.clear();
    acrossRiver.clear();
    lowerRiver.clear();
    doraIndicators.clear();
    melds.clear();
  }

  /// 指定した編集先の牌一覧を返します。
  List<Tile> tilesFor(InputTarget target) => switch (target) {
    InputTarget.hand => hand,
    InputTarget.ownRiver => ownRiver,
    InputTarget.upperRiver => upperRiver,
    InputTarget.acrossRiver => acrossRiver,
    InputTarget.lowerRiver => lowerRiver,
    InputTarget.doraIndicators => doraIndicators,
  };

  /// 局面全体にある指定牌の枚数を返します。
  int count(Tile tile) => [
    hand,
    ownRiver,
    upperRiver,
    acrossRiver,
    lowerRiver,
    doraIndicators,
    ...melds.map((meld) => meld.tiles),
  ].expand((tiles) => tiles).where((item) => item == tile).length;
}
