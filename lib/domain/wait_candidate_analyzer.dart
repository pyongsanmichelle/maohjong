import 'meld.dart';
import 'opponent_analysis_context.dart';
import 'opponent_intent.dart';
import 'round_action_history.dart';
import 'tile.dart';
import 'tile_traits.dart';
import 'visible_risk_rules.dart';

/// 公開情報と既存守備材料から、矛盾しない待ち牌候補を比較します。
class WaitCandidateAnalyzer {
  /// 共通の見える牌ルールを使う分析器を生成します。
  const WaitCandidateAnalyzer({
    this.visibleRiskRules = const VisibleRiskRules(),
  });

  /// 既存守備分析と共有するルールです。
  final VisibleRiskRules visibleRiskRules;

  /// 表示対象となる最低スコアです。
  static const minimumDisplayScore = 30;

  /// 34種類を評価し、決定的な順序で最大3件を返します。
  List<WaitCandidate> analyze(
    OpponentAnalysisContext context,
    List<YakuHypothesis> yakuHypotheses,
  ) {
    if (context.evidenceSufficiency != EvidenceSufficiency.usable) {
      return const [];
    }
    final candidates = <WaitCandidate>[];
    for (final tile in Tile.values) {
      final remaining = context.remainingCopiesByTile[tile] ?? 0;
      if (remaining == 0) continue;
      final reasons = <WaitReason>[];
      final shapes = <WaitShape>{};
      var score = 0;

      final danger = visibleRiskRules.assess(
        context.situation,
        context.opponent,
        tile,
      );
      final dangerDelta = danger.score >= 60
          ? 15
          : danger.score >= 45
          ? 8
          : 0;
      if (dangerDelta > 0) {
        score += dangerDelta;
        reasons.add(
          WaitReason(
            code: WaitReasonCode.dangerAssessment,
            scoreDelta: dangerDelta,
            priority: 10,
            relatedTiles: [tile],
            evidenceCount: danger.score,
          ),
        );
      }

      final alignment = _yakuAlignment(tile, yakuHypotheses, shapes);
      if (alignment > 0) {
        score += alignment;
        reasons.add(
          WaitReason(
            code: WaitReasonCode.yakuAlignment,
            scoreDelta: alignment,
            priority: 20,
            relatedTiles: [tile],
          ),
        );
      }

      final neighborhood = _meldNeighborhood(tile, context.melds, shapes);
      if (neighborhood > 0) {
        score += neighborhood;
        reasons.add(
          WaitReason(
            code: WaitReasonCode.meldNeighborhood,
            scoreDelta: neighborhood,
            priority: 30,
            relatedTiles: [tile],
          ),
        );
      }

      final riichi = context.riichiDiscard;
      if (riichi != null &&
          riichi.source != DiscardSource.unknown &&
          _isNear(tile, riichi.tile)) {
        const delta = 10;
        score += delta;
        reasons.add(
          WaitReason(
            code: WaitReasonCode.riichiDiscardNeighborhood,
            scoreDelta: delta,
            priority: 40,
            relatedTiles: [riichi.tile],
          ),
        );
      }

      final remainingDelta = remaining * 2;
      score += remainingDelta;
      reasons.add(
        WaitReason(
          code: WaitReasonCode.remainingCopies,
          scoreDelta: remainingDelta,
          priority: 50,
          relatedTiles: [tile],
          evidenceCount: remaining,
        ),
      );

      final furiten = context.discardHistory.any(
        (action) => action.tile == tile,
      );
      if (furiten) {
        const delta = -25;
        score += delta;
        reasons.add(
          WaitReason(
            code: WaitReasonCode.furitenRisk,
            scoreDelta: delta,
            priority: 5,
            relatedTiles: [tile],
          ),
        );
      }
      if (score < minimumDisplayScore) continue;
      if (shapes.isEmpty) _addNonCommittalShapes(shapes);
      reasons.sort(_compareReasons);
      candidates.add(
        WaitCandidate(
          tile: tile,
          opponent: context.opponent,
          score: score.clamp(0, 100),
          remainingCopies: remaining,
          possibleShapes: shapes.toList()
            ..sort((a, b) => a.index.compareTo(b.index)),
          reasons: reasons,
          furitenRisk: furiten,
        ),
      );
    }
    candidates.sort((first, second) {
      final score = second.score.compareTo(first.score);
      return score != 0 ? score : first.tile.index.compareTo(second.tile.index);
    });
    return candidates.take(3).toList();
  }

  /// 上位役候補と牌属性が整合する場合の寄与値を返します。
  int _yakuAlignment(
    Tile tile,
    List<YakuHypothesis> hypotheses,
    Set<WaitShape> shapes,
  ) {
    var best = 0;
    for (final hypothesis in hypotheses.take(3)) {
      final aligned = switch (hypothesis.yaku) {
        YakuKind.honitsu =>
          tile.isHonor || _matchesDominantSuit(tile, hypothesis),
        YakuKind.chinitsu => _matchesDominantSuit(tile, hypothesis),
        YakuKind.toitoi => true,
        YakuKind.yakuhai => hypothesis.relatedTiles.contains(tile),
        YakuKind.tanyao => tile.isSimple,
        YakuKind.chanta => tile.isTerminalOrHonor,
        YakuKind.junchan => tile.isTerminal,
        YakuKind.ittsuu ||
        YakuKind.sanshokuDoujun => hypothesis.relatedTiles.contains(tile),
        YakuKind.chiitoitsu => true,
        YakuKind.kokushiMusou => tile.isTerminalOrHonor,
      };
      if (!aligned) continue;
      final value = hypothesis.score >= 65 ? 28 : 20;
      if (value > best) best = value;
      if (hypothesis.yaku == YakuKind.toitoi ||
          hypothesis.yaku == YakuKind.chiitoitsu) {
        shapes.add(WaitShape.shanpon);
        shapes.add(WaitShape.tanki);
      }
    }
    return best;
  }

  /// 清一色・混一色の根拠となった公開副露の色と一致するか確認します。
  bool _matchesDominantSuit(Tile tile, YakuHypothesis hypothesis) {
    return tile.isNumber && hypothesis.relatedTiles.contains(tile);
  }

  /// 公開副露の近傍にある牌へ弱い寄与値を加えます。
  int _meldNeighborhood(Tile tile, List<Meld> melds, Set<WaitShape> shapes) {
    var matches = 0;
    for (final meld in melds) {
      if (meld.type != MeldType.chi) {
        if (meld.calledTile == tile) {
          matches++;
        }
        continue;
      }
      if (!tile.isNumber || meld.tiles.first.suitIndex != tile.suitIndex) {
        continue;
      }
      final ranks = meld.tiles.map((item) => item.rank!).toList()..sort();
      final low = ranks.first;
      final high = ranks.last;
      if (tile.rank == low - 1 || tile.rank == high + 1) {
        matches++;
      } else if (tile.rank != null && tile.rank! > low && tile.rank! < high) {
        matches++;
      }
    }
    return (matches * 18).clamp(0, 30);
  }

  /// 二つの牌が同色で数字2以内かどうかを返します。
  bool _isNear(Tile candidate, Tile reference) =>
      candidate.isNumber &&
      reference.isNumber &&
      candidate.suitIndex == reference.suitIndex &&
      (candidate.rank! - reference.rank!).abs() <= 2;

  /// 公開情報だけで具体的な形を絞れないことを明示します。
  void _addNonCommittalShapes(Set<WaitShape> shapes) {
    shapes.add(WaitShape.unknown);
  }

  /// 理由を優先度とコード定義順で比較します。
  int _compareReasons(WaitReason first, WaitReason second) {
    final priority = first.priority.compareTo(second.priority);
    return priority != 0
        ? priority
        : first.code.index.compareTo(second.code.index);
  }
}
