import 'meld.dart';
import 'opponent.dart';
import 'opponent_analysis_context.dart';
import 'opponent_intent.dart';
import 'round_progress.dart';
import 'round_result.dart';
import 'tile.dart';
import 'tile_traits.dart';

/// 公開情報を役ごとの決定的なルールで比較します。
class YakuIntentAnalyzer {
  /// 状態を持たない役推定器を生成します。
  const YakuIntentAnalyzer();

  /// 表示対象となる最低スコアです。
  static const minimumDisplayScore = 30;

  /// 対象相手についてスコア順の役候補を返します。
  List<YakuHypothesis> analyze(OpponentAnalysisContext context) {
    if (context.evidenceSufficiency == EvidenceSufficiency.none) {
      return const [];
    }
    final candidates = <YakuHypothesis>[
      ..._flushCandidates(context),
      ..._yakuhai(context),
    ].where((candidate) => candidate.score >= minimumDisplayScore).toList();
    candidates.addAll(
      <YakuHypothesis?>[
        _toitoi(context),
        _tanyao(context),
        _outsideHand(context, pure: false),
        _outsideHand(context, pure: true),
        _ittsuu(context),
        _sanshoku(context),
        _closedSpeculation(context, YakuKind.chiitoitsu),
        _closedSpeculation(context, YakuKind.kokushiMusou),
      ].nonNulls.where((candidate) => candidate.score >= minimumDisplayScore),
    );
    final uniqueCandidates = _strongestByYaku(candidates);
    uniqueCandidates.sort((first, second) {
      final score = second.score.compareTo(first.score);
      return score != 0 ? score : first.yaku.index.compareTo(second.yaku.index);
    });
    return uniqueCandidates;
  }

  /// 混一色と清一色を色ごとに評価します。
  List<YakuHypothesis> _flushCandidates(OpponentAnalysisContext context) {
    final results = <YakuHypothesis>[];
    for (var suit = 0; suit < 3; suit++) {
      final sameSuitMelds = context.melds
          .where(
            (meld) =>
                meld.tiles.any(
                  (tile) => tile.isNumber && tile.suitIndex == suit,
                ) &&
                meld.tiles.every(
                  (tile) => tile.isHonor || tile.suitIndex == suit,
                ),
          )
          .toList();
      if (sameSuitMelds.isEmpty) continue;
      final contradicting = context.melds
          .where(
            (meld) => meld.tiles.any(
              (tile) => tile.isNumber && tile.suitIndex != suit,
            ),
          )
          .length;
      final offSuitDiscards = context.discardHistory
          .where(
            (action) => action.tile.isNumber && action.tile.suitIndex != suit,
          )
          .length;
      final honorMelds = context.melds
          .where((meld) => meld.tiles.any((tile) => tile.isHonor))
          .length;
      final commonPositive = <IntentReason>[
        _reason(
          IntentReasonCode.sameSuitMelds,
          sameSuitMelds.length * 24,
          10,
          count: sameSuitMelds.length,
        ),
        if (offSuitDiscards >= 2)
          _reason(
            IntentReasonCode.offSuitDiscards,
            offSuitDiscards.clamp(0, 8) * 3,
            20,
            count: offSuitDiscards,
          ),
      ];
      final honitsuPositive = <IntentReason>[
        ...commonPositive,
        if (honorMelds > 0)
          _reason(
            IntentReasonCode.honorsRetainedPattern,
            honorMelds * 10,
            25,
            count: honorMelds,
          ),
      ];
      final commonNegative = <IntentReason>[
        if (contradicting > 0)
          _reason(
            IntentReasonCode.contradictingMeld,
            -60,
            10,
            count: contradicting,
          ),
      ];
      results.add(
        _candidate(
          context,
          YakuKind.honitsu,
          12 + _sum(honitsuPositive) + _sum(commonNegative),
          honitsuPositive,
          commonNegative,
          relatedTiles: [
            for (final tile in Tile.values)
              if (tile.isNumber && tile.suitIndex == suit) tile,
          ],
        ),
      );
      final chinitsuNegative = [
        ...commonNegative,
        if (honorMelds > 0)
          _reason(
            IntentReasonCode.contradictingMeld,
            -45,
            11,
            count: honorMelds,
          ),
      ];
      results.add(
        _candidate(
          context,
          YakuKind.chinitsu,
          8 + _sum(commonPositive) + _sum(chinitsuNegative),
          commonPositive,
          chinitsuNegative,
          relatedTiles: [
            for (final tile in Tile.values)
              if (tile.isNumber && tile.suitIndex == suit) tile,
          ],
        ),
      );
    }
    return results;
  }

  /// 刻子・槓子と順子の公開数から対々和を評価します。
  YakuHypothesis? _toitoi(OpponentAnalysisContext context) {
    final triplets = context.melds
        .where((meld) => meld.type != MeldType.chi)
        .length;
    final sequences = context.melds
        .where((meld) => meld.type == MeldType.chi)
        .length;
    if (triplets == 0) return null;
    final positive = [
      _reason(
        IntentReasonCode.tripletMelds,
        triplets * 27,
        10,
        count: triplets,
      ),
    ];
    final negative = [
      if (sequences > 0)
        _reason(IntentReasonCode.sequenceMelds, -45, 10, count: sequences),
    ];
    return _candidate(
      context,
      YakuKind.toitoi,
      12 + _sum(positive) + _sum(negative),
      positive,
      negative,
    );
  }

  /// 三元牌、場風、自風の公開刻子・槓子を役牌として評価します。
  List<YakuHypothesis> _yakuhai(OpponentAnalysisContext context) {
    final valueTiles = <Tile>{
      Tile.white,
      Tile.green,
      Tile.red,
      context.roundWind == RoundWind.east ? Tile.east : Tile.south,
      _seatWind(context),
    };
    return [
      for (final tile in valueTiles)
        if (context.melds.any(
          (meld) =>
              meld.type != MeldType.chi &&
              meld.tiles.length >= 3 &&
              meld.tiles.every((item) => item == tile),
        ))
          _candidate(
            context,
            YakuKind.yakuhai,
            95,
            [
              _reason(
                IntentReasonCode.yakuhaiMeld,
                95,
                0,
                tiles: [tile],
                count: 1,
              ),
            ],
            const [],
            relatedTiles: [tile],
          ),
    ];
  }

  /// 中張牌のみの副露と么九牌の処理傾向から断么九を評価します。
  YakuHypothesis? _tanyao(OpponentAnalysisContext context) {
    if (context.melds.isEmpty) return null;
    final simpleMelds = context.melds
        .where((meld) => meld.tiles.every((tile) => tile.isSimple))
        .length;
    final contradictions = context.melds.length - simpleMelds;
    if (simpleMelds == 0) return null;
    final terminalDiscards = context.discardHistory
        .where((action) => action.tile.isTerminalOrHonor)
        .length;
    final positive = [
      _reason(
        IntentReasonCode.allSimpleMelds,
        simpleMelds * 24,
        10,
        count: simpleMelds,
      ),
      if (terminalDiscards >= 3)
        _reason(
          IntentReasonCode.contradictingDiscardPattern,
          terminalDiscards.clamp(0, 6) * 3,
          30,
          count: terminalDiscards,
        ),
    ];
    final negative = [
      if (contradictions > 0)
        _reason(
          IntentReasonCode.contradictingMeld,
          -60,
          10,
          count: contradictions,
        ),
    ];
    return _candidate(
      context,
      YakuKind.tanyao,
      12 + _sum(positive) + _sum(negative),
      positive,
      negative,
    );
  }

  /// 混全帯么九または純全帯么九を公開副露から評価します。
  YakuHypothesis? _outsideHand(
    OpponentAnalysisContext context, {
    required bool pure,
  }) {
    if (context.melds.isEmpty) return null;
    final matching = context.melds.where((meld) {
      final hasTerminal = meld.tiles.any((tile) => tile.isTerminal);
      final hasHonor = meld.tiles.any((tile) => tile.isHonor);
      return pure ? hasTerminal && !hasHonor : hasTerminal || hasHonor;
    }).length;
    if (matching == 0) return null;
    final contradictions = context.melds.length - matching;
    final positive = [
      _reason(
        IntentReasonCode.terminalHonorMelds,
        matching * 24,
        10,
        count: matching,
      ),
    ];
    final negative = [
      if (contradictions > 0)
        _reason(
          IntentReasonCode.contradictingMeld,
          -45,
          10,
          count: contradictions,
        ),
    ];
    return _candidate(
      context,
      pure ? YakuKind.junchan : YakuKind.chanta,
      12 + _sum(positive) + _sum(negative),
      positive,
      negative,
    );
  }

  /// 同色の123・456・789の公開順子から一気通貫を評価します。
  YakuHypothesis? _ittsuu(OpponentAnalysisContext context) {
    var bestComponents = 0;
    int? bestSuit;
    for (var suit = 0; suit < 3; suit++) {
      final starts = context.melds
          .where((meld) => meld.type == MeldType.chi)
          .where((meld) => meld.tiles.every((tile) => tile.suitIndex == suit))
          .map(_sequenceStart)
          .toSet();
      final components = [1, 4, 7].where(starts.contains).length;
      if (components > bestComponents) {
        bestComponents = components;
        bestSuit = suit;
      }
    }
    if (bestComponents == 0) return null;
    final componentSuit = bestSuit!;
    final positive = [
      _reason(
        IntentReasonCode.straightComponents,
        bestComponents * 27,
        10,
        count: bestComponents,
      ),
    ];
    return _candidate(
      context,
      YakuKind.ittsuu,
      5 + _sum(positive),
      positive,
      const [],
      relatedTiles: [
        for (final tile in Tile.values)
          if (tile.suitIndex == componentSuit) tile,
      ],
    );
  }

  /// 同じ数字の並びを持つ三色の公開順子から三色同順を評価します。
  YakuHypothesis? _sanshoku(OpponentAnalysisContext context) {
    var bestComponents = 0;
    int? bestStart;
    for (var start = 1; start <= 7; start++) {
      final suits = context.melds
          .where(
            (meld) =>
                meld.type == MeldType.chi && _sequenceStart(meld) == start,
          )
          .map((meld) => meld.tiles.first.suitIndex)
          .whereType<int>()
          .toSet();
      if (suits.length > bestComponents) {
        bestComponents = suits.length;
        bestStart = start;
      }
    }
    if (bestComponents == 0) return null;
    final componentStart = bestStart!;
    final positive = [
      _reason(
        IntentReasonCode.threeColorComponents,
        bestComponents * 27,
        10,
        count: bestComponents,
      ),
    ];
    return _candidate(
      context,
      YakuKind.sanshokuDoujun,
      5 + _sum(positive),
      positive,
      const [],
      relatedTiles: [
        for (final tile in Tile.values)
          if (tile.rank != null &&
              tile.rank! >= componentStart &&
              tile.rank! <= componentStart + 2)
            tile,
      ],
    );
  }

  /// リーチ済み門前手に限り、非公開情報依存の役を弱い候補に留めます。
  YakuHypothesis? _closedSpeculation(
    OpponentAnalysisContext context,
    YakuKind yaku,
  ) {
    if (context.melds.isNotEmpty) return null;
    if (context.riichiDiscard == null) return null;
    final positive = [
      _reason(IntentReasonCode.insufficientHiddenInformation, 30, 80),
    ];
    return _candidate(context, yaku, 30, positive, const [], maximum: 39);
  }

  /// 現在の親位置から対象相手の自風牌を求めます。
  Tile _seatWind(OpponentAnalysisContext context) {
    const seats = [
      SeatPosition.self,
      SeatPosition.lower,
      SeatPosition.across,
      SeatPosition.upper,
    ];
    final actor = switch (context.opponent) {
      Opponent.lower => SeatPosition.lower,
      Opponent.across => SeatPosition.across,
      Opponent.upper => SeatPosition.upper,
    };
    final offset =
        (seats.indexOf(actor) - seats.indexOf(context.dealer) + 4) % 4;
    return [Tile.east, Tile.south, Tile.west, Tile.north][offset];
  }

  /// 公開順子の先頭数字を返します。
  int _sequenceStart(Meld meld) {
    final ranks = meld.tiles.map((tile) => tile.rank!).toList()..sort();
    return ranks.first;
  }

  /// 正負の理由を並べ、正規化済み候補を生成します。
  YakuHypothesis _candidate(
    OpponentAnalysisContext context,
    YakuKind yaku,
    int score,
    List<IntentReason> positive,
    List<IntentReason> negative, {
    int maximum = 100,
    List<Tile> relatedTiles = const [],
  }) {
    final sortedPositive = [...positive]..sort(_compareReasons);
    final sortedNegative = [...negative]..sort(_compareReasons);
    final normalized = score.clamp(0, maximum);
    return YakuHypothesis(
      yaku: yaku,
      opponent: context.opponent,
      score: normalized,
      level: intentLevelForScore(normalized),
      positiveReasons: sortedPositive,
      negativeReasons: sortedNegative,
      relatedTiles: relatedTiles,
    );
  }

  /// 理由オブジェクトを簡潔に生成します。
  IntentReason _reason(
    IntentReasonCode code,
    int delta,
    int priority, {
    int? count,
    List<Tile> tiles = const [],
  }) => IntentReason(
    code: code,
    scoreDelta: delta,
    priority: priority,
    evidenceCount: count,
    relatedTiles: tiles,
  );

  /// 理由一覧のスコア差分を合計します。
  int _sum(List<IntentReason> reasons) =>
      reasons.fold(0, (sum, reason) => sum + reason.scoreDelta);

  /// 同じ役の色違い候補から最も高いものだけを残します。
  List<YakuHypothesis> _strongestByYaku(List<YakuHypothesis> candidates) {
    final strongest = <YakuKind, YakuHypothesis>{};
    for (final candidate in candidates) {
      final current = strongest[candidate.yaku];
      if (current == null || candidate.score > current.score) {
        strongest[candidate.yaku] = candidate;
      } else if (candidate.yaku == YakuKind.yakuhai &&
          candidate.score == current.score) {
        strongest[candidate.yaku] = YakuHypothesis(
          yaku: current.yaku,
          opponent: current.opponent,
          score: current.score,
          level: current.level,
          positiveReasons: [
            ...current.positiveReasons,
            ...candidate.positiveReasons,
          ],
          negativeReasons: current.negativeReasons,
          relatedTiles: {
            ...current.relatedTiles,
            ...candidate.relatedTiles,
          }.toList()..sort((a, b) => a.index.compareTo(b.index)),
        );
      }
    }
    return strongest.values.toList();
  }

  /// 理由を優先度と定義順で比較します。
  int _compareReasons(IntentReason first, IntentReason second) {
    final priority = first.priority.compareTo(second.priority);
    return priority != 0
        ? priority
        : first.code.index.compareTo(second.code.index);
  }
}
