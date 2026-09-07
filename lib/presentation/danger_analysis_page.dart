import 'package:flutter/material.dart';

import '../application/analyze_danger_use_case.dart';
import '../domain/danger_assessment.dart';
import '../domain/game_situation.dart';
import '../domain/opponent.dart';
import '../domain/round_action_history.dart';
import '../domain/round_progress.dart';
import '../domain/round_result.dart';
import '../domain/tile.dart';
import 'danger_reason_formatter.dart';
import 'hand_danger_presentation.dart';
import 'opponent_intent_view.dart';
import 'tile_presentation.dart';

/// 相手分析画面で切り替える分析の種類です。
enum OpponentAnalysisMode { danger, intent }

/// 自分の手牌について、相手別の危険度と理由を表示する画面です。
class DangerAnalysisPage extends StatefulWidget {
  /// 分析対象の局面を受け取って画面を生成します。
  const DangerAnalysisPage({
    super.key,
    required this.situation,
    this.useCase = const AnalyzeDangerUseCase(),
    this.roundWind = RoundWind.east,
    this.dealer = SeatPosition.self,
    this.turn = 1,
    this.actionHistory,
  });

  /// 局面入力画面で作成された現在の局面です。
  final GameSituation situation;

  /// 守備分析を実行するアプリケーションサービスです。
  final AnalyzeDangerUseCase useCase;

  /// 現在の場風です。
  final RoundWind roundWind;

  /// 現在の親位置です。
  final SeatPosition dealer;

  /// 現在の巡目です。
  final int turn;

  /// 手出し・ツモ切り・リーチを含む公開アクション履歴です。
  final RoundActionHistory? actionHistory;

  @override
  State<DangerAnalysisPage> createState() => _DangerAnalysisPageState();
}

/// 分析対象、並び順、詳細表示中の牌を保持します。
class _DangerAnalysisPageState extends State<DangerAnalysisPage> {
  Opponent _opponent = Opponent.upper;
  DangerSortOrder _sortOrder = DangerSortOrder.hand;
  OpponentAnalysisMode _mode = OpponentAnalysisMode.danger;
  Tile? _selectedTile;
  final DangerReasonFormatter _formatter = const DangerReasonFormatter();

  /// 相手を変更し、先頭の評価を詳細表示の対象にします。
  void _selectOpponent(Opponent opponent) => setState(() {
    _opponent = opponent;
    _selectedTile = null;
  });

  /// 分析結果の表示順を変更します。
  void _selectSortOrder(DangerSortOrder sortOrder) => setState(() {
    _sortOrder = sortOrder;
  });

  /// 危険牌表示と狙い役・待ち表示を切り替えます。
  void _selectMode(OpponentAnalysisMode mode) => setState(() {
    _mode = mode;
  });

  /// 指定した牌の判定理由を詳細欄に表示します。
  void _selectTile(Tile tile) => setState(() {
    _selectedTile = tile;
  });

  @override
  Widget build(BuildContext context) {
    if (_mode == OpponentAnalysisMode.intent) {
      return Scaffold(
        appBar: AppBar(title: const Text('相手分析')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _OpponentSelector(
                opponent: _opponent,
                onChanged: _selectOpponent,
              ),
              const SizedBox(height: 10),
              _AnalysisModeSelector(mode: _mode, onChanged: _selectMode),
              const SizedBox(height: 10),
              OpponentIntentView(
                key: ValueKey(_opponent),
                situation: widget.situation,
                opponent: _opponent,
                roundWind: widget.roundWind,
                dealer: widget.dealer,
                turn: widget.turn,
                actionHistory: widget.actionHistory,
              ),
            ],
          ),
        ),
      );
    }
    if (widget.situation.hand.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('相手分析')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _OpponentSelector(
                opponent: _opponent,
                onChanged: _selectOpponent,
              ),
              const SizedBox(height: 10),
              _AnalysisModeSelector(mode: _mode, onChanged: _selectMode),
              const SizedBox(height: 24),
              const Center(
                key: Key('dangerEmptyHand'),
                child: Text('手牌を入力してください。'),
              ),
            ],
          ),
        ),
      );
    }

    late final List<DangerAssessment> assessments;
    try {
      assessments = widget.useCase(
        situation: widget.situation,
        opponent: _opponent,
        sortOrder: _sortOrder,
      );
    } on DangerAnalysisException catch (error) {
      return Scaffold(
        appBar: AppBar(title: const Text('相手分析')),
        body: Center(
          key: const Key('dangerAnalysisError'),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(error.message, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final selected = assessments.firstWhere(
      (assessment) => assessment.tile == _selectedTile,
      orElse: () => assessments.first,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('相手分析')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _OpponentSelector(opponent: _opponent, onChanged: _selectOpponent),
            const SizedBox(height: 10),
            _AnalysisModeSelector(mode: _mode, onChanged: _selectMode),
            const SizedBox(height: 10),
            const Card(
              key: Key('dangerNotice'),
              child: Padding(
                padding: EdgeInsets.all(10),
                child: Text('危険度は入力済み情報に基づく目安です。安全を保証するものではありません。'),
              ),
            ),
            if (!_hasOpponentInformation(widget.situation, _opponent))
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  '相手の捨て牌情報が未入力です。利用可能な情報だけで評価しています。',
                  key: Key('opponentInformationWarning'),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<DangerSortOrder>(
                key: const Key('dangerSortSelector'),
                segments: const [
                  ButtonSegment(
                    value: DangerSortOrder.hand,
                    label: Text('手牌順'),
                  ),
                  ButtonSegment(
                    value: DangerSortOrder.danger,
                    label: Text('危険度順'),
                  ),
                ],
                selected: {_sortOrder},
                onSelectionChanged: (values) => _selectSortOrder(values.first),
              ),
            ),
            const SizedBox(height: 12),
            _AssessmentGrid(
              assessments: assessments,
              selectedTile: selected.tile,
              onSelected: _selectTile,
            ),
            const SizedBox(height: 12),
            _ReasonPanel(assessment: selected, formatter: _formatter),
          ],
        ),
      ),
    );
  }

  /// 対象相手に河、副露、鳴かれた捨て牌のいずれかがあるか確認します。
  bool _hasOpponentInformation(GameSituation situation, Opponent opponent) =>
      situation.tilesFor(opponent.river).isNotEmpty ||
      situation.meldsFor(opponent.river).isNotEmpty ||
      situation.melds.any((meld) => meld.fromRiver == opponent.river);
}

/// 上家・対面・下家を共通の位置で切り替えます。
class _OpponentSelector extends StatelessWidget {
  /// 選択中の相手と変更処理を受け取ります。
  const _OpponentSelector({required this.opponent, required this.onChanged});

  final Opponent opponent;
  final ValueChanged<Opponent> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<Opponent>(
    key: const Key('opponentSelector'),
    segments: Opponent.values
        .map(
          (value) => ButtonSegment(
            value: value,
            label: Text(dangerOpponentLabel(value)),
          ),
        )
        .toList(),
    selected: {opponent},
    onSelectionChanged: (values) => onChanged(values.first),
  );
}

/// 危険牌と狙い役・待ちの表示を切り替えます。
class _AnalysisModeSelector extends StatelessWidget {
  /// 選択中の分析種別と変更処理を受け取ります。
  const _AnalysisModeSelector({required this.mode, required this.onChanged});

  final OpponentAnalysisMode mode;
  final ValueChanged<OpponentAnalysisMode> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<OpponentAnalysisMode>(
    key: const Key('analysisModeSelector'),
    segments: const [
      ButtonSegment(value: OpponentAnalysisMode.danger, label: Text('危険牌')),
      ButtonSegment(value: OpponentAnalysisMode.intent, label: Text('狙い役・待ち')),
    ],
    selected: {mode},
    onSelectionChanged: (values) => onChanged(values.first),
  );
}

/// 最大7列で、牌ごとの危険度カードを表示します。
class _AssessmentGrid extends StatelessWidget {
  /// 評価一覧を表示するグリッドを生成します。
  const _AssessmentGrid({
    required this.assessments,
    required this.selectedTile,
    required this.onSelected,
  });

  /// 表示順へ整列済みの評価です。
  final List<DangerAssessment> assessments;

  /// 詳細欄で選択中の牌です。
  final Tile selectedTile;

  /// 牌カードが選択されたときの処理です。
  final ValueChanged<Tile> onSelected;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => GridView.builder(
      key: const Key('dangerAssessmentGrid'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: assessments.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        crossAxisSpacing: 4,
        mainAxisSpacing: 6,
        mainAxisExtent: 86,
      ),
      itemBuilder: (context, index) {
        final assessment = assessments[index];
        final selected = assessment.tile == selectedTile;
        return Semantics(
          button: true,
          selected: selected,
          label:
              '${tileLabel(assessment.tile)}、${dangerLevelLabel(assessment.level)}、${assessment.score}',
          child: InkWell(
            key: Key('dangerTile-${assessment.tile.name}'),
            borderRadius: BorderRadius.circular(8),
            onTap: () => onSelected(assessment.tile),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
              decoration: BoxDecoration(
                color: _levelColor(context, assessment.level),
                border: Border.all(
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outlineVariant,
                  width: selected ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    child: Text(
                      tileLabel(assessment.tile),
                      style: TextStyle(
                        color: tileColor(assessment.tile),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  FittedBox(
                    child: Text(
                      dangerLevelLabel(assessment.level),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  Text(
                    '${assessment.score}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// 選択した牌の判定理由を重要度順に表示します。
class _ReasonPanel extends StatelessWidget {
  /// 指定評価の詳細欄を生成します。
  const _ReasonPanel({required this.assessment, required this.formatter});

  /// 詳細表示する評価です。
  final DangerAssessment assessment;

  /// 構造化された理由を日本語へ変換します。
  final DangerReasonFormatter formatter;

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('dangerReasonPanel'),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '選択：${tileLabel(assessment.tile)}　${dangerLevelLabel(assessment.level)} ${assessment.score}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final reason in assessment.reasons)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text('・${formatter.format(reason)}'),
            ),
        ],
      ),
    ),
  );
}

/// 危険度区分に対応する背景色を返します。
Color _levelColor(BuildContext context, DangerLevel level) => switch (level) {
  DangerLevel.safe => Colors.green.shade50,
  DangerLevel.caution => Colors.amber.shade50,
  DangerLevel.danger => Colors.red.shade50,
};
