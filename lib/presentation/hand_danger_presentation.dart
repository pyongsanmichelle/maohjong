import 'package:flutter/material.dart';

import '../application/analyze_danger_use_case.dart';
import '../domain/danger_assessment.dart';
import '../domain/game_situation.dart';
import '../domain/opponent.dart';
import '../domain/tile.dart';
import 'danger_reason_formatter.dart';
import 'tile_presentation.dart';

/// 手牌の危険情報を表示する相手の順序です。
const handDangerOpponentOrder = [
  Opponent.lower,
  Opponent.across,
  Opponent.upper,
];

/// 1種類の手牌について、代表値と相手別評価を保持します。
class HandDangerSummary {
  /// 牌と3人分の評価から表示用の集約結果を生成します。
  HandDangerSummary({
    required this.tile,
    required this.maximumAssessment,
    required Map<Opponent, DangerAssessment> assessments,
  }) : assessments = Map.unmodifiable(assessments);

  /// 評価対象の牌です。
  final Tile tile;

  /// 3人の中で最も高い危険スコアの評価です。
  final DangerAssessment maximumAssessment;

  /// 下家、対面、上家それぞれの評価です。
  final Map<Opponent, DangerAssessment> assessments;
}

/// 既存の危険分析結果を固定手牌向けの代表値へ集約します。
class HandDangerPresenter {
  /// 危険分析ユースケースを受け取って表示用集約器を生成します。
  const HandDangerPresenter({this.useCase = const AnalyzeDangerUseCase()});

  /// 相手別の危険分析を実行する既存ユースケースです。
  final AnalyzeDangerUseCase useCase;

  /// 手牌の牌種ごとに、3人の最大値と相手別評価を返します。
  List<HandDangerSummary> summarize(GameSituation situation) {
    final assessmentsByOpponent = <Opponent, Map<Tile, DangerAssessment>>{
      for (final opponent in handDangerOpponentOrder)
        opponent: {
          for (final assessment in useCase(
            situation: situation,
            opponent: opponent,
            sortOrder: DangerSortOrder.hand,
          ))
            assessment.tile: assessment,
        },
    };
    final tiles = situation.hand.toSet().toList()
      ..sort((first, second) => first.index.compareTo(second.index));
    return [for (final tile in tiles) _summaryFor(tile, assessmentsByOpponent)];
  }

  /// 1種類の牌について最大値と相手別評価をまとめます。
  HandDangerSummary _summaryFor(
    Tile tile,
    Map<Opponent, Map<Tile, DangerAssessment>> assessmentsByOpponent,
  ) {
    final assessments = <Opponent, DangerAssessment>{
      for (final opponent in handDangerOpponentOrder)
        opponent: assessmentsByOpponent[opponent]![tile]!,
    };
    final maximum = assessments.values.reduce(
      (current, candidate) =>
          candidate.score > current.score ? candidate : current,
    );
    return HandDangerSummary(
      tile: tile,
      maximumAssessment: maximum,
      assessments: assessments,
    );
  }
}

/// 固定手牌を長押ししたときに、3人分の危険情報を表示します。
class HandDangerDetailDialog extends StatelessWidget {
  /// 牌の集約済み危険情報を受け取ってダイアログを生成します。
  const HandDangerDetailDialog({
    super.key,
    required this.summary,
    this.formatter = const DangerReasonFormatter(),
  });

  /// 表示する牌の代表値と相手別評価です。
  final HandDangerSummary summary;

  /// 理由コードと根拠を日本語へ変換する既存フォーマッターです。
  final DangerReasonFormatter formatter;

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: Key('handDangerDetail-${summary.tile.name}'),
    title: Text('${tileLabel(summary.tile)}の危険情報'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '代表危険率：${summary.maximumAssessment.score}%'
            '（${dangerLevelLabel(summary.maximumAssessment.level)}）',
            key: const Key('handDangerMaximum'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          for (final opponent in handDangerOpponentOrder)
            _OpponentDangerDetail(
              assessment: summary.assessments[opponent]!,
              formatter: formatter,
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('閉じる'),
      ),
    ],
  );
}

/// 1人の相手に対する危険率、危険度、理由を表示します。
class _OpponentDangerDetail extends StatelessWidget {
  /// 相手別評価と理由フォーマッターを受け取って生成します。
  const _OpponentDangerDetail({
    required this.assessment,
    required this.formatter,
  });

  /// 表示する相手別評価です。
  final DangerAssessment assessment;

  /// 判定理由を日本語へ変換するフォーマッターです。
  final DangerReasonFormatter formatter;

  @override
  Widget build(BuildContext context) => Padding(
    key: Key('handDangerOpponent-${assessment.opponent.name}'),
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${dangerOpponentLabel(assessment.opponent)}：危険率 '
          '${assessment.score}%（${dangerLevelLabel(assessment.level)}）',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        for (final reason in assessment.reasons)
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 2),
            child: Text('・${formatter.format(reason)}'),
          ),
      ],
    ),
  );
}

/// 分析対象の相手名を返します。
String dangerOpponentLabel(Opponent opponent) => switch (opponent) {
  Opponent.lower => '下家',
  Opponent.across => '対面',
  Opponent.upper => '上家',
};

/// 危険度区分の日本語表示を返します。
String dangerLevelLabel(DangerLevel level) => switch (level) {
  DangerLevel.safe => '安全',
  DangerLevel.caution => '注意',
  DangerLevel.danger => '危険',
};
