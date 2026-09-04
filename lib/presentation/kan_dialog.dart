import 'package:flutter/material.dart';

import '../domain/meld.dart';
import '../domain/situation_editor.dart';
import '../domain/tile.dart';
import 'tile_presentation.dart';

/// 開始時点ですでに成立しているカンの入力内容です。
class SetupKanSelection {
  /// 開始前カンの入力結果を生成します。
  const SetupKanSelection({
    required this.ownerRiver,
    required this.tile,
    required this.type,
  });

  /// カンしているプレイヤーに対応する河です。
  final InputTarget ownerRiver;

  /// カンしている牌です。
  final Tile tile;

  /// 明槓、暗槓、加槓の区別です。
  final KanType type;
}

/// 開始前に既存のカンを登録するダイアログです。
class SetupKanDialog extends StatefulWidget {
  /// 登録可能な牌を受け取ってダイアログを生成します。
  const SetupKanDialog({super.key, required this.availableTiles});

  /// 局面全体でまだ1枚も使われていない牌です。
  final List<Tile> availableTiles;

  @override
  State<SetupKanDialog> createState() => _SetupKanDialogState();
}

/// 開始前カンのプレイヤー、牌、種別を保持します。
class _SetupKanDialogState extends State<SetupKanDialog> {
  InputTarget _ownerRiver = InputTarget.ownRiver;
  KanType _type = KanType.concealed;
  Tile? _tile;

  @override
  void initState() {
    super.initState();
    _tile = widget.availableTiles.isEmpty ? null : widget.availableTiles.first;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('開始時点のカンを登録'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<InputTarget>(
            key: const Key('setupKanOwnerSelector'),
            initialValue: _ownerRiver,
            decoration: const InputDecoration(labelText: 'プレイヤー'),
            items: _playerRivers
                .map(
                  (river) => DropdownMenuItem(
                    value: river,
                    child: Text(_playerLabel(river)),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _ownerRiver = value);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<Tile>(
            key: const Key('setupKanTileSelector'),
            initialValue: _tile,
            decoration: const InputDecoration(labelText: '牌'),
            items: widget.availableTiles
                .map(
                  (tile) => DropdownMenuItem(
                    value: tile,
                    child: Text(tileLabel(tile)),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => _tile = value),
          ),
          const SizedBox(height: 12),
          SegmentedButton<KanType>(
            key: const Key('setupKanTypeSelector'),
            segments: const [
              ButtonSegment(value: KanType.open, label: Text('明槓')),
              ButtonSegment(value: KanType.concealed, label: Text('暗槓')),
              ButtonSegment(value: KanType.added, label: Text('加槓')),
            ],
            selected: {_type},
            onSelectionChanged: (values) =>
                setState(() => _type = values.first),
          ),
          const SizedBox(height: 8),
          const Text('登録する4枚は手牌や河へ重ねて入力しないでください。'),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('キャンセル'),
      ),
      FilledButton(
        key: const Key('confirmSetupKanButton'),
        onPressed: _tile == null
            ? null
            : () => Navigator.pop(
                context,
                SetupKanSelection(
                  ownerRiver: _ownerRiver,
                  tile: _tile!,
                  type: _type,
                ),
              ),
        child: const Text('登録'),
      ),
    ],
  );
}

/// 自分の番に成立可能な暗槓・加槓を選ぶダイアログです。
class SelfKanDialog extends StatelessWidget {
  /// 現在選べるカン候補を受け取って生成します。
  const SelfKanDialog({super.key, required this.options});

  /// 手牌とポンから求めた暗槓・加槓候補です。
  final List<SelfKanOption> options;

  @override
  Widget build(BuildContext context) => SimpleDialog(
    title: const Text('カンを選択'),
    children: [
      for (final option in options)
        SimpleDialogOption(
          key: Key('selfKan-${option.type.name}-${option.tile.name}'),
          onPressed: () => Navigator.pop(context, option),
          child: Text(
            '${_kanTypeLabel(option.type)} ${tileLabel(option.tile)}',
          ),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('キャンセル'),
      ),
    ],
  );
}

/// 開始前カンを登録できる4人分の河です。
const _playerRivers = [
  InputTarget.ownRiver,
  InputTarget.lowerRiver,
  InputTarget.acrossRiver,
  InputTarget.upperRiver,
];

/// 河に対応するプレイヤー名を返します。
String _playerLabel(InputTarget river) => switch (river) {
  InputTarget.ownRiver => '自分',
  InputTarget.lowerRiver => '下家',
  InputTarget.acrossRiver => '対面',
  InputTarget.upperRiver => '上家',
  _ => '',
};

/// カン種別の表示名を返します。
String _kanTypeLabel(KanType type) => switch (type) {
  KanType.open => '明槓',
  KanType.concealed => '暗槓',
  KanType.added => '加槓',
};
