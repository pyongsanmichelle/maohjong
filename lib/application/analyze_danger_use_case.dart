import '../domain/danger_analyzer.dart';
import '../domain/danger_assessment.dart';
import '../domain/game_situation.dart';
import '../domain/opponent.dart';

/// 守備分析結果の表示順です。
enum DangerSortOrder { hand, danger }

/// 画面から守備分析を実行するアプリケーション層の窓口です。
class AnalyzeDangerUseCase {
  /// 指定した分析器を使うユースケースを生成します。
  const AnalyzeDangerUseCase({this.analyzer = const DangerAnalyzer()});

  /// UIへ依存しない危険度分析器です。
  final DangerAnalyzer analyzer;

  /// 指定相手の評価を計算し、表示順に並べて返します。
  List<DangerAssessment> call({
    required GameSituation situation,
    required Opponent opponent,
    required DangerSortOrder sortOrder,
  }) {
    final assessments = analyzer.analyze(situation, opponent);
    if (sortOrder == DangerSortOrder.danger) {
      assessments.sort((first, second) {
        final score = second.score.compareTo(first.score);
        return score != 0
            ? score
            : first.tile.index.compareTo(second.tile.index);
      });
    }
    return assessments;
  }
}
