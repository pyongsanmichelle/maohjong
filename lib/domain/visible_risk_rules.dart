import 'danger_assessment.dart';
import 'game_situation.dart';
import 'opponent.dart';
import 'tile.dart';
import 'tile_traits.dart';

/// 見えている牌だけで評価できる守備材料を共通提供します。
class VisibleRiskRules {
  /// 状態を持たない共通ルールを生成します。
  const VisibleRiskRules();

  /// 数牌の判定開始時に使う比較用スコアです。
  static const numberTileBaseScore = 50;

  /// 字牌の判定開始時に使う比較用スコアです。
  static const honorTileBaseScore = 55;

  /// 「安全」と「注意」の境界値です。
  static const safeMaxScore = 25;

  /// 「注意」と「危険」の境界値です。
  static const cautionMaxScore = 59;

  /// 指定した候補牌について、既存の守備評価と同じ結果を返します。
  DangerAssessment assess(
    GameSituation situation,
    Opponent opponent,
    Tile tile,
  ) {
    final discardHistory = discardsFor(situation, opponent);
    final visibleCount = situation.count(tile);
    final priorityReasons = <DangerReason>[
      if (discardHistory.contains(tile))
        DangerReason(
          code: DangerReasonCode.genbutsu,
          scoreDelta: 0,
          priority: 0,
          relatedTiles: [tile],
        ),
      if (visibleCount >= 4)
        DangerReason(
          code: DangerReasonCode.allCopiesVisible,
          scoreDelta: 0,
          priority: 1,
          relatedTiles: [tile],
          evidenceCount: visibleCount,
        ),
    ];
    if (priorityReasons.isNotEmpty) {
      return DangerAssessment(
        tile: tile,
        opponent: opponent,
        score: 0,
        level: DangerLevel.safe,
        reasons: priorityReasons,
      );
    }

    var score = tile.isHonor ? honorTileBaseScore : numberTileBaseScore;
    final reasons = <DangerReason>[];
    if (tile.isHonor) {
      score += _addHonorVisibilityReason(reasons, tile, visibleCount);
    } else {
      score += _addSujiReason(reasons, tile, discardHistory);
      score += _addShapeVisibilityReasons(reasons, situation, tile);
    }
    score += _addDoraReason(reasons, situation, tile);
    score += _addOpenSuitPressureReason(reasons, situation, opponent, tile);
    if (reasons.isEmpty) {
      reasons.add(
        DangerReason(
          code: DangerReasonCode.noStrongEvidence,
          scoreDelta: 0,
          priority: 90,
        ),
      );
    }
    reasons.sort(_compareReasons);
    final normalizedScore = score.clamp(0, 100);
    return DangerAssessment(
      tile: tile,
      opponent: opponent,
      score: normalizedScore,
      level: levelForScore(normalizedScore),
      reasons: reasons,
    );
  }

  /// 対象相手の河と、他家に鳴かれた同相手の捨て牌を返します。
  List<Tile> discardsFor(GameSituation situation, Opponent opponent) => [
    ...situation.tilesFor(opponent.river),
    ...situation.melds
        .where((meld) => meld.fromRiver == opponent.river)
        .map((meld) => meld.calledTile),
  ];

  /// 比較用スコアを利用者向けの3段階へ変換します。
  static DangerLevel levelForScore(int score) {
    if (score <= safeMaxScore) return DangerLevel.safe;
    if (score <= cautionMaxScore) return DangerLevel.caution;
    return DangerLevel.danger;
  }

  /// 筋に該当する理由を加え、スコア差分を返します。
  int _addSujiReason(
    List<DangerReason> reasons,
    Tile tile,
    List<Tile> discards,
  ) {
    final rank = tile.rank!;
    final references = switch (rank) {
      <= 3 => [tile.tileAtRank(rank + 3)],
      >= 7 => [tile.tileAtRank(rank - 3)],
      _ => [tile.tileAtRank(rank - 3), tile.tileAtRank(rank + 3)],
    };
    final matched = references.where(discards.contains).toList();
    if (matched.isEmpty) return 0;
    final isFull = references.length == 2 && matched.length == 2;
    final delta = isFull ? -20 : -10;
    reasons.add(
      DangerReason(
        code: isFull ? DangerReasonCode.fullSuji : DangerReasonCode.suji,
        scoreDelta: delta,
        priority: 20,
        relatedTiles: matched,
      ),
    );
    return delta;
  }

  /// 壁とワンチャンスの理由を加え、合計差分を返します。
  int _addShapeVisibilityReasons(
    List<DangerReason> reasons,
    GameSituation situation,
    Tile tile,
  ) {
    final groups = _ryanmenSupportGroups(tile);
    final wallTiles = <Tile>{};
    final oneChanceTiles = <Tile>{};
    var blockedGroups = 0;
    for (final group in groups) {
      final walls = group.where((item) => situation.count(item) >= 4).toList();
      if (walls.isNotEmpty) {
        blockedGroups++;
        wallTiles.addAll(walls);
      } else {
        oneChanceTiles.addAll(
          group.where((item) => situation.count(item) == 3),
        );
      }
    }
    var delta = 0;
    if (blockedGroups > 0) {
      final wallDelta = blockedGroups == groups.length ? -20 : -10;
      delta += wallDelta;
      reasons.add(
        DangerReason(
          code: DangerReasonCode.kabe,
          scoreDelta: wallDelta,
          priority: 30,
          relatedTiles: wallTiles.toList()
            ..sort((a, b) => a.index.compareTo(b.index)),
          evidenceCount: blockedGroups,
        ),
      );
    }
    if (oneChanceTiles.isNotEmpty) {
      const oneChanceDelta = -5;
      delta += oneChanceDelta;
      reasons.add(
        DangerReason(
          code: DangerReasonCode.oneChance,
          scoreDelta: oneChanceDelta,
          priority: 40,
          relatedTiles: oneChanceTiles.toList()
            ..sort((a, b) => a.index.compareTo(b.index)),
        ),
      );
    }
    return delta;
  }

  /// 字牌の見えている枚数による理由を加えて差分を返します。
  int _addHonorVisibilityReason(
    List<DangerReason> reasons,
    Tile tile,
    int visibleCount,
  ) {
    final delta = switch (visibleCount) {
      3 => -20,
      2 => -10,
      _ => 0,
    };
    if (delta != 0) {
      reasons.add(
        DangerReason(
          code: DangerReasonCode.honorVisibility,
          scoreDelta: delta,
          priority: 50,
          relatedTiles: [tile],
          evidenceCount: visibleCount,
        ),
      );
    }
    return delta;
  }

  /// ドラに該当する回数を理由へ加えて差分を返します。
  int _addDoraReason(
    List<DangerReason> reasons,
    GameSituation situation,
    Tile tile,
  ) {
    final indicators = situation.doraIndicators
        .where((indicator) => doraForIndicator(indicator) == tile)
        .toList();
    if (indicators.isEmpty) return 0;
    final delta = indicators.length * 15;
    reasons.add(
      DangerReason(
        code: DangerReasonCode.dora,
        scoreDelta: delta,
        priority: 60,
        relatedTiles: indicators,
        evidenceCount: indicators.length,
      ),
    );
    return delta;
  }

  /// 対象相手の同色副露が複数ある場合の差分を返します。
  int _addOpenSuitPressureReason(
    List<DangerReason> reasons,
    GameSituation situation,
    Opponent opponent,
    Tile tile,
  ) {
    if (tile.isHonor) return 0;
    final sameSuitMelds = situation
        .meldsFor(opponent.river)
        .where(
          (meld) => meld.tiles.every(
            (item) => item.isNumber && item.suitIndex == tile.suitIndex,
          ),
        )
        .length;
    if (sameSuitMelds < 2) return 0;
    const delta = 10;
    reasons.add(
      DangerReason(
        code: DangerReasonCode.openSuitPressure,
        scoreDelta: delta,
        priority: 70,
        relatedTiles: [tile],
        evidenceCount: sameSuitMelds,
      ),
    );
    return delta;
  }

  /// ドラ表示牌に対応するドラを返します。
  static Tile doraForIndicator(Tile indicator) {
    if (indicator.isNumber) {
      return indicator.tileAtRank(indicator.rank! % 9 + 1);
    }
    return switch (indicator) {
      Tile.east => Tile.south,
      Tile.south => Tile.west,
      Tile.west => Tile.north,
      Tile.north => Tile.east,
      Tile.white => Tile.green,
      Tile.green => Tile.red,
      Tile.red => Tile.white,
      _ => throw StateError('数牌または字牌ではないドラ表示牌です。'),
    };
  }

  /// 候補牌を待ちに含む両面形で必要になる牌の組を返します。
  List<List<Tile>> _ryanmenSupportGroups(Tile tile) {
    final ranks = switch (tile.rank) {
      1 => const [
        [2, 3],
      ],
      2 => const [
        [3, 4],
      ],
      3 => const [
        [4, 5],
      ],
      4 => const [
        [2, 3],
        [5, 6],
      ],
      5 => const [
        [3, 4],
        [6, 7],
      ],
      6 => const [
        [4, 5],
        [7, 8],
      ],
      7 => const [
        [5, 6],
      ],
      8 => const [
        [6, 7],
      ],
      9 => const [
        [7, 8],
      ],
      _ => const <List<int>>[],
    };
    return [
      for (final group in ranks)
        [for (final rank in group) tile.tileAtRank(rank)],
    ];
  }

  /// 理由を優先度とコード定義順で比較します。
  int _compareReasons(DangerReason first, DangerReason second) {
    final priority = first.priority.compareTo(second.priority);
    return priority != 0
        ? priority
        : first.code.index.compareTo(second.code.index);
  }
}
