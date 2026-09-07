import 'package:flutter/material.dart';

import '../application/analyze_opponent_intent_use_case.dart';
import '../domain/game_situation.dart';
import '../domain/opponent.dart';
import '../domain/opponent_analysis_context.dart';
import '../domain/opponent_intent.dart';
import '../domain/round_action_history.dart';
import '../domain/round_progress.dart';
import '../domain/round_result.dart';
import 'discard_metadata_editor.dart';
import 'intent_reason_formatter.dart';
import 'tile_presentation.dart';

/// 選択中の相手について狙い役、待ち牌、入力履歴を表示します。
class OpponentIntentView extends StatefulWidget {
  /// 現在局面と分析条件を受け取って生成します。
  const OpponentIntentView({
    super.key,
    required this.situation,
    required this.opponent,
    required this.roundWind,
    required this.dealer,
    required this.turn,
    this.actionHistory,
    this.useCase = const AnalyzeOpponentIntentUseCase(),
  });

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

  /// 詳細属性を含む局内アクション履歴です。
  final RoundActionHistory? actionHistory;

  /// 相手分析を実行するアプリケーションサービスです。
  final AnalyzeOpponentIntentUseCase useCase;

  @override
  State<OpponentIntentView> createState() => _OpponentIntentViewState();
}

/// 履歴訂正後に分析を再実行するための画面状態です。
class _OpponentIntentViewState extends State<OpponentIntentView> {
  final IntentReasonFormatter _formatter = const IntentReasonFormatter();

  /// 打牌のメタデータを訂正し、表示中の分析を再計算します。
  Future<void> _editDiscard(DiscardAction action) async {
    final selection = await showDialog<DiscardMetadataSelection>(
      context: context,
      builder: (context) => DiscardMetadataEditor(
        tile: action.tile,
        initialSource: action.source,
        initialDeclaresRiichi: action.declaresRiichi,
      ),
    );
    if (!mounted || selection == null) return;
    widget.actionHistory?.updateDiscard(
      action.id,
      source: selection.source,
      declaresRiichi: selection.declaresRiichi,
    );
    setState(() {});
  }

  /// 役候補の肯定根拠と反証を下部シートへ表示します。
  void _showYakuEvidence(YakuHypothesis hypothesis) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => _EvidenceSheet(
        title: _formatter.yakuLabel(hypothesis.yaku),
        positive: hypothesis.positiveReasons
            .map(_formatter.formatIntentReason)
            .toList(),
        negative: hypothesis.negativeReasons
            .map(_formatter.formatIntentReason)
            .toList(),
      ),
    );
  }

  /// 待ち牌候補の根拠を下部シートへ表示します。
  void _showWaitEvidence(WaitCandidate candidate) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => _EvidenceSheet(
        title: '${tileLabel(candidate.tile)}の待ち候補',
        positive: candidate.reasons
            .where((reason) => reason.scoreDelta >= 0)
            .map(_formatter.formatWaitReason)
            .toList(),
        negative: candidate.reasons
            .where((reason) => reason.scoreDelta < 0)
            .map(_formatter.formatWaitReason)
            .toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    late final OpponentIntentAnalysis analysis;
    try {
      analysis = widget.useCase(
        situation: widget.situation,
        opponent: widget.opponent,
        roundWind: widget.roundWind,
        dealer: widget.dealer,
        turn: widget.turn,
        actionHistory: widget.actionHistory,
      );
    } on OpponentAnalysisException catch (error) {
      return Center(
        key: const Key('opponentIntentError'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(error.message, textAlign: TextAlign.center),
        ),
      );
    }

    final discards =
        widget.actionHistory?.actions
            .whereType<DiscardAction>()
            .where((action) => action.actor == widget.opponent.river)
            .toList() ??
        const <DiscardAction>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Card(
          key: Key('intentNotice'),
          child: Padding(
            padding: EdgeInsets.all(10),
            child: Text('役・待ち候補は公開情報から求めた推定です。実際の手牌や和了を保証しません。'),
          ),
        ),
        if (analysis.warnings.contains(
          OpponentAnalysisWarning.inconsistentHistory,
        ))
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('履歴と河が一致しません。入力履歴を訂正してください。'),
          ),
        _YakuSection(
          hypotheses: analysis.yakuHypotheses,
          emptyMessage: _formatter.emptyMessage(analysis.evidenceSufficiency),
          formatter: _formatter,
          onSelected: _showYakuEvidence,
        ),
        const SizedBox(height: 10),
        _WaitSection(
          candidates: analysis.waitCandidates,
          emptyMessage: _formatter.emptyMessage(analysis.evidenceSufficiency),
          formatter: _formatter,
          onSelected: _showWaitEvidence,
        ),
        if (discards.isNotEmpty) ...[
          const SizedBox(height: 10),
          _DiscardHistorySection(discards: discards, onEdit: _editDiscard),
        ],
      ],
    );
  }
}

/// 狙い役の上位候補を順位付きで表示します。
class _YakuSection extends StatelessWidget {
  /// 役候補欄を生成します。
  const _YakuSection({
    required this.hypotheses,
    required this.emptyMessage,
    required this.formatter,
    required this.onSelected,
  });

  final List<YakuHypothesis> hypotheses;
  final String emptyMessage;
  final IntentReasonFormatter formatter;
  final ValueChanged<YakuHypothesis> onSelected;

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('yakuHypothesisSection'),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('狙い役', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          if (hypotheses.isEmpty)
            Text(emptyMessage, key: const Key('yakuEmptyMessage'))
          else
            for (var index = 0; index < hypotheses.length; index++)
              ListTile(
                key: Key('yaku-${hypotheses[index].yaku.name}'),
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${index + 1}. ${formatter.yakuLabel(hypotheses[index].yaku)}',
                ),
                subtitle: Text(
                  formatter.confidenceLabel(hypotheses[index].level),
                ),
                trailing: Text(
                  '${hypotheses[index].score}/100',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                onTap: () => onSelected(hypotheses[index]),
                onLongPress: () => onSelected(hypotheses[index]),
              ),
        ],
      ),
    ),
  );
}

/// 待ち牌の上位候補を残数と形候補付きで表示します。
class _WaitSection extends StatelessWidget {
  /// 待ち候補欄を生成します。
  const _WaitSection({
    required this.candidates,
    required this.emptyMessage,
    required this.formatter,
    required this.onSelected,
  });

  final List<WaitCandidate> candidates;
  final String emptyMessage;
  final IntentReasonFormatter formatter;
  final ValueChanged<WaitCandidate> onSelected;

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('waitCandidateSection'),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('待ち牌候補', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (candidates.isEmpty)
            Text(emptyMessage, key: const Key('waitEmptyMessage'))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final candidate in candidates)
                  ActionChip(
                    key: Key('wait-${candidate.tile.name}'),
                    label: Text(
                      '${tileLabel(candidate.tile)} ${candidate.score}/100 '
                      '${formatter.confidenceLabel(intentLevelForScore(candidate.score))} '
                      '残${candidate.remainingCopies}\n'
                      '${candidate.possibleShapes.map(formatter.waitShapeLabel).join('・')}',
                    ),
                    onPressed: () => onSelected(candidate),
                  ),
              ],
            ),
        ],
      ),
    ),
  );
}

/// 対象相手の打牌履歴と編集ボタンを表示します。
class _DiscardHistorySection extends StatelessWidget {
  /// 打牌履歴欄を生成します。
  const _DiscardHistorySection({required this.discards, required this.onEdit});

  final List<DiscardAction> discards;
  final ValueChanged<DiscardAction> onEdit;

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('discardHistorySection'),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('打牌履歴', style: Theme.of(context).textTheme.titleMedium),
          for (final action in discards)
            ListTile(
              key: Key('discardHistory-${action.id}'),
              contentPadding: EdgeInsets.zero,
              title: Text('${action.sequence}. ${tileLabel(action.tile)}'),
              subtitle: Text(
                '${discardSourceLabel(action.source)}'
                '${action.declaresRiichi ? '・リーチ宣言牌' : ''}',
              ),
              trailing: IconButton(
                tooltip: '打牌情報を編集',
                onPressed: () => onEdit(action),
                icon: const Icon(Icons.edit_outlined),
              ),
            ),
        ],
      ),
    ),
  );
}

/// 候補の肯定根拠と反証を分けて表示します。
class _EvidenceSheet extends StatelessWidget {
  /// 詳細表示するタイトルと根拠文を受け取ります。
  const _EvidenceSheet({
    required this.title,
    required this.positive,
    required this.negative,
  });

  final String title;
  final List<String> positive;
  final List<String> negative;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        key: const Key('intentEvidenceSheet'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text('根拠', style: Theme.of(context).textTheme.titleMedium),
          if (positive.isEmpty) const Text('・明確な肯定根拠はありません'),
          for (final line in positive) Text('・$line'),
          const SizedBox(height: 10),
          Text('反証・注意', style: Theme.of(context).textTheme.titleMedium),
          if (negative.isEmpty) const Text('・明確な反証はありません'),
          for (final line in negative) Text('・$line'),
        ],
      ),
    ),
  );
}
