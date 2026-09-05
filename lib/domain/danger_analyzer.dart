import 'danger_assessment.dart';
import 'game_situation.dart';
import 'opponent.dart';
import 'tile.dart';

/// 入力済みの見える情報から、相手別の危険度を判定します。
class DangerAnalyzer {
  /// 状態を持たない分析器を生成します。
  const DangerAnalyzer();

  /// 数牌の判定開始時に使う比較用スコアです。
  static const numberTileBaseScore = 50;

  /// 字牌の判定開始時に使う比較用スコアです。
  static const honorTileBaseScore = 55;

  /// 「安全」と「注意」の境界値です。
  static const safeMaxScore = 25;

  /// 「注意」と「危険」の境界値です。
  static const cautionMaxScore = 59;

  /// 入力局面から、自分の手牌にある牌種ごとの評価を返します。
  List<DangerAssessment> analyze(GameSituation situation, Opponent opponent) {
    _validate(situation);
    final candidates = situation.hand.toSet().toList()
      ..sort((first, second) => first.index.compareTo(second.index));
    final discardHistory = _discardHistory(situation, opponent);
    return [
      for (final tile in candidates)
        _assess(situation, opponent, tile, discardHistory),
    ];
  }

  /// 牌ごとの評価を、優先判定と加減算ルールから作ります。
  DangerAssessment _assess(
    GameSituation situation,
    Opponent opponent,
    Tile tile,
    List<Tile> discardHistory,
  ) {
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

    var score = _isHonor(tile) ? honorTileBaseScore : numberTileBaseScore;
    final reasons = <DangerReason>[];
    if (_isHonor(tile)) {
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
    reasons.sort((first, second) {
      final priority = first.priority.compareTo(second.priority);
      return priority != 0
          ? priority
          : first.code.index.compareTo(second.code.index);
    });
    final normalizedScore = score.clamp(0, 100);
    return DangerAssessment(
      tile: tile,
      opponent: opponent,
      score: normalizedScore,
      level: levelForScore(normalizedScore),
      reasons: reasons,
    );
  }

  /// 比較用スコアを利用者向けの3段階へ変換します。
  static DangerLevel levelForScore(int score) {
    if (score <= safeMaxScore) return DangerLevel.safe;
    if (score <= cautionMaxScore) return DangerLevel.caution;
    return DangerLevel.danger;
  }

  /// 対象相手の河と、他家に鳴かれた同相手の捨て牌をまとめます。
  List<Tile> _discardHistory(GameSituation situation, Opponent opponent) => [
    ...situation.tilesFor(opponent.river),
    ...situation.melds
        .where((meld) => meld.fromRiver == opponent.river)
        .map((meld) => meld.calledTile),
  ];

  /// 筋に該当する場合の理由を追加し、スコア差分を返します。
  int _addSujiReason(
    List<DangerReason> reasons,
    Tile tile,
    List<Tile> discardHistory,
  ) {
    final rank = _rank(tile);
    final references = switch (rank) {
      <= 3 => [_tileInSameSuit(tile, rank + 3)],
      >= 7 => [_tileInSameSuit(tile, rank - 3)],
      _ => [_tileInSameSuit(tile, rank - 3), _tileInSameSuit(tile, rank + 3)],
    };
    final matched = references
        .where(discardHistory.contains)
        .toList(growable: false);
    if (matched.isEmpty) return 0;
    final isFullSuji = references.length == 2 && matched.length == 2;
    final delta = isFullSuji ? -20 : -10;
    reasons.add(
      DangerReason(
        code: isFullSuji ? DangerReasonCode.fullSuji : DangerReasonCode.suji,
        scoreDelta: delta,
        priority: 20,
        relatedTiles: matched,
      ),
    );
    return delta;
  }

  /// 壁とワンチャンスの理由を追加し、合計差分を返します。
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
        continue;
      }
      oneChanceTiles.addAll(group.where((item) => situation.count(item) == 3));
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
            ..sort((first, second) => first.index.compareTo(second.index)),
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
            ..sort((first, second) => first.index.compareTo(second.index)),
        ),
      );
    }
    return delta;
  }

  /// 字牌の見えている枚数による理由を追加して差分を返します。
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

  /// ドラに該当する回数を理由へ追加して差分を返します。
  int _addDoraReason(
    List<DangerReason> reasons,
    GameSituation situation,
    Tile tile,
  ) {
    final indicators = situation.doraIndicators
        .where((indicator) => doraForIndicator(indicator) == tile)
        .toList(growable: false);
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
    if (_isHonor(tile)) return 0;
    final suit = _suit(tile);
    final sameSuitMelds = situation
        .meldsFor(opponent.river)
        .where(
          (meld) => meld.tiles.every(
            (item) => !_isHonor(item) && _suit(item) == suit,
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

  /// 同種牌が4枚を超える不正局面を拒否します。
  void _validate(GameSituation situation) {
    for (final tile in Tile.values) {
      if (situation.count(tile) > 4) {
        throw const DangerAnalysisException('同じ牌が5枚以上あります。局面入力を修正してください。');
      }
    }
  }

  /// ドラ表示牌に対応するドラを返します。
  static Tile doraForIndicator(Tile indicator) {
    if (indicator.index < 27) {
      final suitStart = _suit(indicator) * 9;
      return Tile.values[suitStart + (_rank(indicator) % 9)];
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
    final ranks = switch (_rank(tile)) {
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
        [for (final rank in group) _tileInSameSuit(tile, rank)],
    ];
  }

  /// 指定した牌と同じ色の指定数字を返します。
  Tile _tileInSameSuit(Tile tile, int rank) =>
      Tile.values[_suit(tile) * 9 + rank - 1];

  /// 数牌の1から9を返します。
  static int _rank(Tile tile) => tile.index % 9 + 1;

  /// 萬子、筒子、索子を0から2で返します。
  static int _suit(Tile tile) => tile.index ~/ 9;

  /// 指定牌が字牌かどうかを返します。
  static bool _isHonor(Tile tile) => tile.index >= 27;
}
