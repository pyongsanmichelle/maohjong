import 'package:flutter/material.dart';

import '../domain/round_result.dart';

/// 局終了ダイアログで確定した終了理由と和了者です。
class RoundEndSelection {
  /// ツモまたはロンと和了者を保持する選択結果を生成します。
  const RoundEndSelection({required this.reason, required this.winner});

  /// ツモまたはロンの終了理由です。
  final RoundEndReason reason;

  /// 選択された和了者です。
  final SeatPosition winner;
}

/// 対局中にツモまたはロンによる局終了を選ぶダイアログです。
class RoundEndDialog extends StatefulWidget {
  /// 直前打牌から求めた放銃者を受け取ってダイアログを生成します。
  const RoundEndDialog({super.key, required this.discarder});

  /// 直前打牌のプレイヤーです。直前打牌がない場合は null です。
  final SeatPosition? discarder;

  @override
  State<RoundEndDialog> createState() => _RoundEndDialogState();
}

/// 選択中の終了理由と和了者を保持します。
class _RoundEndDialogState extends State<RoundEndDialog> {
  RoundEndReason _reason = RoundEndReason.tsumo;
  SeatPosition _winner = SeatPosition.self;

  /// ツモまたはロンを選び直し、放銃者と同じ和了者を避けます。
  void _selectReason(RoundEndReason reason) => setState(() {
    _reason = reason;
    if (reason == RoundEndReason.ron && _winner == widget.discarder) {
      _winner = SeatPosition.values.firstWhere(
        (seat) => seat != widget.discarder,
      );
    }
  });

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('roundEndDialog'),
    title: const Text('局終了'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('終了理由'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                key: const Key('roundEndType-tsumo'),
                label: const Text('ツモ'),
                selected: _reason == RoundEndReason.tsumo,
                onSelected: (_) => _selectReason(RoundEndReason.tsumo),
              ),
              ChoiceChip(
                key: const Key('roundEndType-ron'),
                label: const Text('ロン'),
                selected: _reason == RoundEndReason.ron,
                onSelected: widget.discarder == null
                    ? null
                    : (_) => _selectReason(RoundEndReason.ron),
              ),
            ],
          ),
          if (widget.discarder == null)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('ロンは直前の打牌がある場合だけ選択できます。'),
            ),
          const SizedBox(height: 14),
          const Text('和了者'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final seat in SeatPosition.values)
                ChoiceChip(
                  key: Key('roundEndWinner-${seat.name}'),
                  label: Text(roundSeatLabel(seat)),
                  selected: _winner == seat,
                  onSelected:
                      _reason == RoundEndReason.ron && seat == widget.discarder
                      ? null
                      : (_) => setState(() => _winner = seat),
                ),
            ],
          ),
          if (_reason == RoundEndReason.ron && widget.discarder != null)
            Padding(
              key: const Key('roundEndDiscarder'),
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '放銃者：${roundSeatLabel(widget.discarder!)}'
                '（直前の打牌から自動判定）',
              ),
            ),
          const SizedBox(height: 12),
          const Text('簡易進行のため、親の連荘と点数計算は行いません。'),
        ],
      ),
    ),
    actions: [
      TextButton(
        key: const Key('cancelRoundEndButton'),
        onPressed: () => Navigator.pop(context),
        child: const Text('キャンセル'),
      ),
      FilledButton(
        key: const Key('confirmRoundEndButton'),
        onPressed: () => Navigator.pop(
          context,
          RoundEndSelection(reason: _reason, winner: _winner),
        ),
        child: const Text('確定'),
      ),
    ],
  );
}

/// プレイヤー位置の表示名を返します。
String roundSeatLabel(SeatPosition seat) => switch (seat) {
  SeatPosition.self => '自分',
  SeatPosition.lower => '下家',
  SeatPosition.across => '対面',
  SeatPosition.upper => '上家',
};

/// 局終了理由の表示名を返します。
String roundEndReasonLabel(RoundEndReason reason) => switch (reason) {
  RoundEndReason.tsumo => 'ツモ',
  RoundEndReason.ron => 'ロン',
  RoundEndReason.exhaustiveDraw => '流局',
};
