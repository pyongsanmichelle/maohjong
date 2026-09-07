import 'game_situation.dart';
import 'meld.dart';
import 'opponent.dart';
import 'round_action_history.dart';
import 'round_progress.dart';
import 'round_result.dart';
import 'tile.dart';

/// 公開情報が推定に十分かを表します。
enum EvidenceSufficiency { none, low, usable }

/// 分析結果に添える入力上の注意コードです。
enum OpponentAnalysisWarning {
  compatibilityHistory,
  inconsistentHistory,
  lowEvidence,
}

/// 相手分析を継続できない入力エラーです。
class OpponentAnalysisException implements Exception {
  /// 利用者へ表示できる内容を持つ例外を生成します。
  const OpponentAnalysisException(this.message);

  /// 入力修正を促すメッセージです。
  final String message;

  @override
  String toString() => message;
}

/// 役と待ちの推定器が共有する読み取り専用の局面スナップショットです。
class OpponentAnalysisContext {
  /// 検証済みの分析入力を生成します。
  OpponentAnalysisContext({
    required this.situation,
    required this.opponent,
    required this.roundWind,
    required this.dealer,
    required this.turn,
    required List<DiscardAction> discardHistory,
    required List<MeldAction> meldActions,
    required this.riichiDiscard,
    required Map<Tile, int> visibleCountByTile,
    required Map<Tile, int> remainingCopiesByTile,
    required this.evidenceSufficiency,
    required List<OpponentAnalysisWarning> warnings,
  }) : discardHistory = List.unmodifiable(discardHistory),
       meldActions = List.unmodifiable(meldActions),
       visibleCountByTile = Map.unmodifiable(visibleCountByTile),
       remainingCopiesByTile = Map.unmodifiable(remainingCopiesByTile),
       warnings = List.unmodifiable(warnings);

  /// 現在の公開局面です。
  final GameSituation situation;

  /// 分析対象の相手です。
  final Opponent opponent;

  /// 現在の場風です。
  final RoundWind roundWind;

  /// 現在の親位置です。
  final SeatPosition dealer;

  /// 現在の巡目です。
  final int turn;

  /// 対象相手の打牌履歴です。
  final List<DiscardAction> discardHistory;

  /// 対象相手の副露履歴です。
  final List<MeldAction> meldActions;

  /// リーチ宣言牌です。未宣言では null です。
  final DiscardAction? riichiDiscard;

  /// 34種類それぞれの見えている枚数です。
  final Map<Tile, int> visibleCountByTile;

  /// 34種類それぞれの見込み残数です。
  final Map<Tile, int> remainingCopiesByTile;

  /// 公開情報の充足度です。
  final EvidenceSufficiency evidenceSufficiency;

  /// 互換履歴や情報不足を示す注意コードです。
  final List<OpponentAnalysisWarning> warnings;

  /// 対象相手の公開副露を返します。
  List<Meld> get melds => meldActions.map((action) => action.meld).toList();
}

/// 現在局面と任意の詳細履歴から検証済みコンテキストを生成します。
class OpponentAnalysisContextFactory {
  /// 状態を持たないファクトリーを生成します。
  const OpponentAnalysisContextFactory();

  /// 既存局面との互換性を保ちながら分析入力を構築します。
  OpponentAnalysisContext create({
    required GameSituation situation,
    required Opponent opponent,
    required RoundWind roundWind,
    required SeatPosition dealer,
    required int turn,
    RoundActionHistory? actionHistory,
  }) {
    final visibleCounts = <Tile, int>{};
    final remainingCounts = <Tile, int>{};
    for (final tile in Tile.values) {
      final count = situation.count(tile);
      if (count > 4) {
        throw const OpponentAnalysisException('同じ牌が5枚以上あります。局面入力を修正してください。');
      }
      visibleCounts[tile] = count;
      remainingCounts[tile] = (4 - count).clamp(0, 4);
    }

    final warnings = <OpponentAnalysisWarning>[];
    var discards =
        actionHistory?.actions
            .whereType<DiscardAction>()
            .where((action) => action.actor == opponent.river)
            .toList() ??
        <DiscardAction>[];
    var melds =
        actionHistory?.actions
            .whereType<MeldAction>()
            .where((action) => action.actor == opponent.river)
            .toList() ??
        <MeldAction>[];
    final hasDetailedHistory =
        actionHistory != null && actionHistory.actions.isNotEmpty;
    if (!hasDetailedHistory) {
      warnings.add(OpponentAnalysisWarning.compatibilityHistory);
      discards = _compatibilityDiscards(situation, opponent);
      melds = _compatibilityMelds(situation, opponent, discards.length);
    } else if (!_matchesVisibleRiver(situation, opponent, discards) ||
        !_matchesMelds(situation, opponent, melds)) {
      warnings.add(OpponentAnalysisWarning.inconsistentHistory);
      discards = _compatibilityDiscards(situation, opponent);
      melds = _compatibilityMelds(situation, opponent, discards.length);
    }

    discards.sort((a, b) => a.sequence.compareTo(b.sequence));
    melds.sort((a, b) => a.sequence.compareTo(b.sequence));
    final riichi = discards.where((action) => action.declaresRiichi).lastOrNull;
    final sufficiency = _sufficiency(discards, melds, riichi);
    if (sufficiency != EvidenceSufficiency.usable) {
      warnings.add(OpponentAnalysisWarning.lowEvidence);
    }
    return OpponentAnalysisContext(
      situation: situation,
      opponent: opponent,
      roundWind: roundWind,
      dealer: dealer,
      turn: turn,
      discardHistory: discards,
      meldActions: melds,
      riichiDiscard: riichi,
      visibleCountByTile: visibleCounts,
      remainingCopiesByTile: remainingCounts,
      evidenceSufficiency: sufficiency,
      warnings: warnings,
    );
  }

  /// 河と鳴かれた牌から時系列不明の互換打牌を生成します。
  List<DiscardAction> _compatibilityDiscards(
    GameSituation situation,
    Opponent opponent,
  ) {
    final tiles = <Tile>[
      ...situation.tilesFor(opponent.river),
      ...situation.melds
          .where((meld) => meld.fromRiver == opponent.river)
          .map((meld) => meld.calledTile),
    ];
    return [
      for (var index = 0; index < tiles.length; index++)
        DiscardAction(
          id: index + 1,
          sequence: index + 1,
          actor: opponent.river,
          tile: tiles[index],
          source: DiscardSource.unknown,
          declaresRiichi: false,
          turn: index ~/ 4 + 1,
          visibleInRiver: index < situation.tilesFor(opponent.river).length,
        ),
    ];
  }

  /// 現在の副露から時系列不明の互換副露履歴を生成します。
  List<MeldAction> _compatibilityMelds(
    GameSituation situation,
    Opponent opponent,
    int sequenceOffset,
  ) => [
    for (
      var index = 0;
      index < situation.meldsFor(opponent.river).length;
      index++
    )
      MeldAction(
        id: sequenceOffset + index + 1,
        sequence: sequenceOffset + index + 1,
        actor: opponent.river,
        meld: situation.meldsFor(opponent.river).elementAt(index),
        calledDiscardId: null,
        declaredAfterSequence: sequenceOffset + index,
      ),
  ];

  /// 詳細履歴で河に表示中の牌が現在の河と一致するか確認します。
  bool _matchesVisibleRiver(
    GameSituation situation,
    Opponent opponent,
    List<DiscardAction> discards,
  ) {
    final actual = situation.tilesFor(opponent.river);
    final recorded = discards
        .where((action) => action.visibleInRiver)
        .map((action) => action.tile)
        .toList();
    if (actual.length != recorded.length) return false;
    for (var index = 0; index < actual.length; index++) {
      if (actual[index] != recorded[index]) return false;
    }
    return true;
  }

  /// 詳細履歴の副露が現在の副露と同じ順序・内容か確認します。
  bool _matchesMelds(
    GameSituation situation,
    Opponent opponent,
    List<MeldAction> melds,
  ) {
    final actual = situation.meldsFor(opponent.river).toList();
    final recorded = melds.map((action) => action.meld).toList();
    if (actual.length != recorded.length) return false;
    for (var index = 0; index < actual.length; index++) {
      if (!_sameMeld(actual[index], recorded[index])) return false;
    }
    return true;
  }

  /// 二つの副露の公開情報がすべて一致するか確認します。
  bool _sameMeld(Meld first, Meld second) {
    if (first.type != second.type ||
        first.ownerRiver != second.ownerRiver ||
        first.calledTile != second.calledTile ||
        first.fromRiver != second.fromRiver ||
        first.kanType != second.kanType ||
        first.origin != second.origin ||
        first.tiles.length != second.tiles.length) {
      return false;
    }
    for (var index = 0; index < first.tiles.length; index++) {
      if (first.tiles[index] != second.tiles[index]) return false;
    }
    return true;
  }

  /// 河、副露、リーチの量から情報充足度を判定します。
  EvidenceSufficiency _sufficiency(
    List<DiscardAction> discards,
    List<MeldAction> melds,
    DiscardAction? riichi,
  ) {
    if (discards.isEmpty && melds.isEmpty && riichi == null) {
      return EvidenceSufficiency.none;
    }
    if (riichi == null && melds.isEmpty && discards.length < 8) {
      return EvidenceSufficiency.low;
    }
    return EvidenceSufficiency.usable;
  }
}
