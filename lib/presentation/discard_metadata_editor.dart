import 'package:flutter/material.dart';

import '../domain/round_action_history.dart';
import '../domain/tile.dart';
import 'tile_presentation.dart';

/// 打牌へ設定する手出し区分とリーチ属性です。
class DiscardMetadataSelection {
  /// 編集結果を生成します。
  const DiscardMetadataSelection({
    required this.source,
    required this.declaresRiichi,
  });

  /// 手出し、ツモ切り、または不明です。
  final DiscardSource source;

  /// リーチ宣言牌として扱うかどうかです。
  final bool declaresRiichi;
}

/// 打牌の詳細属性を新規入力または訂正するダイアログです。
class DiscardMetadataEditor extends StatefulWidget {
  /// 編集する牌と現在値を受け取って生成します。
  const DiscardMetadataEditor({
    super.key,
    required this.tile,
    this.initialSource = DiscardSource.unknown,
    this.initialDeclaresRiichi = false,
  });

  /// 属性を設定する打牌です。
  final Tile tile;

  /// 初期表示する打牌元です。
  final DiscardSource initialSource;

  /// 初期表示するリーチ属性です。
  final bool initialDeclaresRiichi;

  @override
  State<DiscardMetadataEditor> createState() => _DiscardMetadataEditorState();
}

/// ダイアログ内の一時的な選択値を保持します。
class _DiscardMetadataEditorState extends State<DiscardMetadataEditor> {
  late DiscardSource _source;
  late bool _declaresRiichi;

  @override
  void initState() {
    super.initState();
    _source = widget.initialSource;
    _declaresRiichi = widget.initialDeclaresRiichi;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${tileLabel(widget.tile)}の打牌情報'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('打牌元'),
        const SizedBox(height: 6),
        SegmentedButton<DiscardSource>(
          key: const Key('discardSourceSelector'),
          segments: const [
            ButtonSegment(value: DiscardSource.unknown, label: Text('不明')),
            ButtonSegment(value: DiscardSource.fromHand, label: Text('手出し')),
            ButtonSegment(value: DiscardSource.drawn, label: Text('ツモ切り')),
          ],
          selected: {_source},
          onSelectionChanged: (values) =>
              setState(() => _source = values.first),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          key: const Key('riichiDiscardSwitch'),
          contentPadding: EdgeInsets.zero,
          title: const Text('リーチ宣言牌'),
          value: _declaresRiichi,
          onChanged: (value) => setState(() => _declaresRiichi = value),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('キャンセル'),
      ),
      FilledButton(
        key: const Key('saveDiscardMetadataButton'),
        onPressed: () => Navigator.pop(
          context,
          DiscardMetadataSelection(
            source: _source,
            declaresRiichi: _declaresRiichi,
          ),
        ),
        child: const Text('保存'),
      ),
    ],
  );
}

/// 打牌元を短い日本語へ変換します。
String discardSourceLabel(DiscardSource source) => switch (source) {
  DiscardSource.unknown => '不明',
  DiscardSource.drawn => 'ツモ切り',
  DiscardSource.fromHand => '手出し',
};
