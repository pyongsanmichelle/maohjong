import '../domain/game_situation.dart';
import '../domain/opponent.dart';
import '../domain/opponent_analysis_context.dart';
import '../domain/opponent_intent.dart';
import '../domain/round_action_history.dart';
import '../domain/round_progress.dart';
import '../domain/round_result.dart';
import '../domain/wait_candidate_analyzer.dart';
import '../domain/yaku_intent_analyzer.dart';

/// 画面から相手の狙い役と待ち牌候補を分析する唯一の窓口です。
class AnalyzeOpponentIntentUseCase {
  /// コンテキスト生成、役推定、待ち推定の各サービスを受け取ります。
  const AnalyzeOpponentIntentUseCase({
    this.contextFactory = const OpponentAnalysisContextFactory(),
    this.yakuAnalyzer = const YakuIntentAnalyzer(),
    this.waitAnalyzer = const WaitCandidateAnalyzer(),
  });

  /// 入力検証済みコンテキストを生成します。
  final OpponentAnalysisContextFactory contextFactory;

  /// 役候補を評価します。
  final YakuIntentAnalyzer yakuAnalyzer;

  /// 待ち牌候補を評価します。
  final WaitCandidateAnalyzer waitAnalyzer;

  /// 現在局面から表示可能な上位候補を返します。
  OpponentIntentAnalysis call({
    required GameSituation situation,
    required Opponent opponent,
    required RoundWind roundWind,
    required SeatPosition dealer,
    required int turn,
    RoundActionHistory? actionHistory,
  }) {
    final context = contextFactory.create(
      situation: situation,
      opponent: opponent,
      roundWind: roundWind,
      dealer: dealer,
      turn: turn,
      actionHistory: actionHistory,
    );
    final yaku = yakuAnalyzer.analyze(context).take(3).toList();
    final waits = waitAnalyzer.analyze(context, yaku);
    return OpponentIntentAnalysis(
      opponent: opponent,
      evidenceSufficiency: context.evidenceSufficiency,
      yakuHypotheses: yaku,
      waitCandidates: waits,
      warnings: context.warnings,
    );
  }
}
