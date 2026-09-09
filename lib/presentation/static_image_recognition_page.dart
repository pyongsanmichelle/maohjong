import 'dart:io';

import 'package:flutter/material.dart';

import '../application/recognition_draft_use_cases.dart';
import '../domain/tile.dart';
import '../domain/tile_recognition.dart';
import 'mahjong_tile_face.dart';
import 'tile_presentation.dart';

/// 静止画の認識候補を画像と領域別一覧で確認・訂正する画面です。
class StaticImageRecognitionPage extends StatefulWidget {
  /// 認識対象画像と認識処理を受け取って確認画面を生成します。
  const StaticImageRecognitionPage({
    super.key,
    required this.imagePath,
    required this.recognizer,
    this.draftBuilder = const BuildRecognitionDraftUseCase(),
  });

  /// 端末内にある認識対象画像の一時パスです。
  final String imagePath;

  /// 端末内で牌を認識するサービスです。
  final MahjongTileRecognizer recognizer;

  /// 認識結果を局面候補へ割り当てるUseCaseです。
  final BuildRecognitionDraftUseCase draftBuilder;

  @override
  State<StaticImageRecognitionPage> createState() =>
      _StaticImageRecognitionPageState();
}

/// 認識中、確認中、失敗の画面状態を管理します。
class _StaticImageRecognitionPageState
    extends State<StaticImageRecognitionPage> {
  RecognitionDraft? _draft;
  String? _selectedTileId;
  String? _errorMessage;
  var _recognizing = true;
  var _requestSerial = 0;

  @override
  void initState() {
    super.initState();
    _recognize();
  }

  /// 同じ画像を認識し、古い非同期結果を破棄します。
  Future<void> _recognize() async {
    final serial = ++_requestSerial;
    setState(() {
      _recognizing = true;
      _errorMessage = null;
      _draft = null;
    });
    try {
      final result = await widget.recognizer.recognize(widget.imagePath);
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _draft = widget.draftBuilder(
          imagePath: widget.imagePath,
          result: result,
        );
        _recognizing = false;
      });
    } catch (_) {
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _recognizing = false;
        _errorMessage = '画像を認識できませんでした。撮影条件を変えるか、手入力を利用してください。';
      });
    }
  }

  /// 現在の候補一覧から警告を再計算します。
  void _replaceTiles(List<RecognizedTile> tiles) {
    final draft = _draft;
    if (draft == null) return;
    setState(() {
      _draft = widget.draftBuilder.rebuild(
        imagePath: draft.imagePath,
        imageWidth: draft.imageWidth,
        imageHeight: draft.imageHeight,
        tiles: tiles,
        modelVersion: draft.modelVersion,
      );
      if (!tiles.any((tile) => tile.id == _selectedTileId)) {
        _selectedTileId = null;
      }
    });
  }

  /// 選択候補の牌種を既存34種から変更します。
  Future<void> _editTile(RecognizedTile candidate) async {
    final tile = await showModalBottomSheet<Tile>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _RecognitionTilePicker(),
    );
    if (!mounted || tile == null) return;
    final draft = _draft;
    if (draft == null) return;
    _replaceTiles([
      for (final item in draft.tiles)
        if (item.id == candidate.id)
          item.copyWith(tile: tile, editedByUser: true)
        else
          item,
    ]);
  }

  /// 選択候補を別の卓上領域へ移動します。
  void _moveTile(RecognizedTile candidate, RecognitionRegion region) {
    final draft = _draft;
    if (draft == null) return;
    _replaceTiles([
      for (final item in draft.tiles)
        if (item.id == candidate.id)
          item.copyWith(region: region, editedByUser: true)
        else
          item,
    ]);
  }

  /// 誤検出した候補を下書きから削除します。
  void _removeTile(RecognizedTile candidate) {
    final draft = _draft;
    if (draft == null) return;
    _replaceTiles([
      for (final item in draft.tiles)
        if (item.id != candidate.id) item,
    ]);
  }

  /// 未検出の牌を利用者操作で追加します。
  Future<void> _addTile() async {
    final tile = await showModalBottomSheet<Tile>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _RecognitionTilePicker(),
    );
    if (!mounted || tile == null) return;
    final draft = _draft;
    if (draft == null) return;
    final id = 'user-${DateTime.now().microsecondsSinceEpoch}';
    _replaceTiles([
      ...draft.tiles,
      RecognizedTile(
        id: id,
        tile: tile,
        boundingBox: const NormalizedRect(
          left: 0.45,
          top: 0.80,
          width: 0.10,
          height: 0.15,
        ),
        confidence: 1,
        region: RecognitionRegion.ownHand,
        source: RecognitionSource.user,
        editedByUser: true,
      ),
    ]);
  }

  /// 確定可能な下書きを呼び出し元へ返します。
  void _apply() {
    final draft = _draft;
    if (draft == null || !draft.canApply) return;
    Navigator.of(context).pop(draft);
  }

  @override
  void dispose() {
    _requestSerial++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('静止画から局面を入力'),
      actions: [
        TextButton(
          key: const Key('recognitionCancelButton'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('中止'),
        ),
      ],
    ),
    body: SafeArea(child: _buildBody()),
  );

  /// 現在の認識状態に対応する内容を返します。
  Widget _buildBody() {
    if (_recognizing) {
      return const Center(
        key: Key('recognitionProgress'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('端末内で牌を認識しています…'),
          ],
        ),
      );
    }
    final error = _errorMessage;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.image_not_supported_outlined, size: 48),
              const SizedBox(height: 12),
              Text(error, key: const Key('recognitionError')),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('recognitionRetryButton'),
                onPressed: _recognize,
                icon: const Icon(Icons.refresh),
                label: const Text('もう一度認識'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('手入力へ戻る'),
              ),
            ],
          ),
        ),
      );
    }
    final draft = _draft!;
    return Column(
      children: [
        Expanded(
          child: ListView(
            key: const Key('recognitionReviewList'),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            children: [
              _RecognitionOverlay(
                draft: draft,
                selectedTileId: _selectedTileId,
                onSelect: (id) => setState(() => _selectedTileId = id),
              ),
              const SizedBox(height: 10),
              _IssueSummary(issues: draft.issues),
              const SizedBox(height: 8),
              for (final region in RecognitionRegion.values)
                if (draft.tiles.any((tile) => tile.region == region))
                  _RegionCard(
                    region: region,
                    tiles: [
                      for (final tile in draft.tiles)
                        if (tile.region == region) tile,
                    ],
                    selectedTileId: _selectedTileId,
                    onSelect: (id) => setState(() => _selectedTileId = id),
                    onEdit: _editTile,
                    onMove: _moveTile,
                    onRemove: _removeTile,
                  ),
              OutlinedButton.icon(
                key: const Key('recognitionAddTileButton'),
                onPressed: _addTile,
                icon: const Icon(Icons.add),
                label: const Text('認識されなかった牌を追加'),
              ),
              const SizedBox(height: 6),
              Text(
                '${draft.tiles.length}枚を検出・追加 / ${draft.modelVersion}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
          ),
          child: FilledButton.icon(
            key: const Key('recognitionApplyButton'),
            onPressed: draft.canApply ? _apply : null,
            icon: const Icon(Icons.check),
            label: const Text('局面に反映'),
          ),
        ),
      ],
    );
  }
}

/// 元画像へ認識枠を重ねて表示します。
class _RecognitionOverlay extends StatelessWidget {
  /// オーバーレイを生成します。
  const _RecognitionOverlay({
    required this.draft,
    required this.selectedTileId,
    required this.onSelect,
  });

  /// 表示する認識下書きです。
  final RecognitionDraft draft;

  /// 領域一覧と同期する選択候補です。
  final String? selectedTileId;

  /// 検出枠を選択する処理です。
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: draft.imageWidth / draft.imageHeight,
    child: LayoutBuilder(
      builder: (context, constraints) => Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            File(draft.imagePath),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Center(child: Icon(Icons.broken_image_outlined)),
            ),
          ),
          for (final candidate in draft.tiles)
            Positioned(
              left: candidate.boundingBox.left * constraints.maxWidth,
              top: candidate.boundingBox.top * constraints.maxHeight,
              width: candidate.boundingBox.width * constraints.maxWidth,
              height: candidate.boundingBox.height * constraints.maxHeight,
              child: Semantics(
                button: true,
                label:
                    '${candidate.tile == null ? '不明牌' : tileLabel(candidate.tile!)}, '
                    '${(candidate.confidence * 100).round()}パーセント, '
                    '${_regionLabel(candidate.region)}',
                child: InkWell(
                  key: Key('recognitionBox-${candidate.id}'),
                  onTap: () => onSelect(candidate.id),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: candidate.id == selectedTileId
                            ? Theme.of(context).colorScheme.tertiary
                            : candidate.tile == null ||
                                  candidate.region == RecognitionRegion.unknown
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.primary,
                        width: candidate.id == selectedTileId ? 3 : 2,
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.75),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Text(
                            candidate.tile == null
                                ? '?'
                                : tileLabel(candidate.tile!),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// 現在の警告件数と確定可否を表示します。
class _IssueSummary extends StatelessWidget {
  /// 警告表示を生成します。
  const _IssueSummary({required this.issues});

  /// 認識下書きに残っている確認理由です。
  final List<RecognitionIssue> issues;

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) {
      return const Card(
        color: Color(0xffd9f2e5),
        child: ListTile(
          leading: Icon(Icons.check_circle_outline),
          title: Text('確定できます'),
          subtitle: Text('画像と候補を確認してから局面へ反映してください。'),
        ),
      );
    }
    final blocking = issues.where((issue) => issue.blocksApply).length;
    return Card(
      color: blocking > 0
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.tertiaryContainer,
      child: ListTile(
        leading: Icon(blocking > 0 ? Icons.warning_amber : Icons.info_outline),
        title: Text('要確認 ${issues.length}件'),
        subtitle: Text(
          blocking > 0 ? '未確定の牌または配置を修正してください。' : '低信頼度の候補があります。画像と照合してください。',
        ),
      ),
    );
  }
}

/// 一つの卓上領域に割り当てられた候補を編集します。
class _RegionCard extends StatelessWidget {
  /// 領域カードを生成します。
  const _RegionCard({
    required this.region,
    required this.tiles,
    required this.selectedTileId,
    required this.onSelect,
    required this.onEdit,
    required this.onMove,
    required this.onRemove,
  });

  /// 表示する卓上領域です。
  final RecognitionRegion region;

  /// 領域内の牌候補です。
  final List<RecognizedTile> tiles;

  /// 現在選択している候補IDです。
  final String? selectedTileId;

  /// 候補選択処理です。
  final ValueChanged<String> onSelect;

  /// 牌種変更処理です。
  final ValueChanged<RecognizedTile> onEdit;

  /// 配置先変更処理です。
  final void Function(RecognizedTile, RecognitionRegion) onMove;

  /// 候補削除処理です。
  final ValueChanged<RecognizedTile> onRemove;

  @override
  Widget build(BuildContext context) => Card(
    key: Key('recognitionRegion-${region.name}'),
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_regionLabel(region)} ${tiles.length}枚',
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final candidate in tiles)
                _RecognitionCandidateChip(
                  candidate: candidate,
                  selected: candidate.id == selectedTileId,
                  onTap: () => onSelect(candidate.id),
                  onEdit: () => onEdit(candidate),
                  onMove: (region) => onMove(candidate, region),
                  onRemove: () => onRemove(candidate),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// 牌画像、信頼度、訂正メニューをまとめた候補表示です。
class _RecognitionCandidateChip extends StatelessWidget {
  /// 1枚の候補表示を生成します。
  const _RecognitionCandidateChip({
    required this.candidate,
    required this.selected,
    required this.onTap,
    required this.onEdit,
    required this.onMove,
    required this.onRemove,
  });

  /// 表示する候補です。
  final RecognizedTile candidate;

  /// 画像側と同期して選択されているかどうかです。
  final bool selected;

  /// 候補を選択する処理です。
  final VoidCallback onTap;

  /// 牌種を変更する処理です。
  final VoidCallback onEdit;

  /// 配置先を変更する処理です。
  final ValueChanged<RecognitionRegion> onMove;

  /// 候補を削除する処理です。
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
    width: 92,
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      border: Border.all(
        color: selected
            ? Theme.of(context).colorScheme.tertiary
            : Theme.of(context).colorScheme.outlineVariant,
        width: selected ? 2 : 1,
      ),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          key: Key('recognitionTile-${candidate.id}'),
          onTap: onTap,
          onDoubleTap: onEdit,
          child: candidate.tile == null
              ? const SizedBox(
                  width: 36,
                  height: 48,
                  child: Center(
                    child: Text('?', style: TextStyle(fontSize: 28)),
                  ),
                )
              : MahjongTileFace(tile: candidate.tile!, width: 36, height: 48),
        ),
        Text('${(candidate.confidence * 100).round()}%'),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: IconButton(
                key: Key('recognitionEdit-${candidate.id}'),
                tooltip: '牌を選び直す',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 40,
                  height: 40,
                ),
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 19),
              ),
            ),
            SizedBox(
              width: 40,
              height: 40,
              child: PopupMenuButton<Object>(
                key: Key('recognitionMenu-${candidate.id}'),
                tooltip: '配置変更または削除',
                padding: EdgeInsets.zero,
                iconSize: 19,
                onSelected: (value) {
                  if (value == _removeCommand) {
                    onRemove();
                  } else if (value is RecognitionRegion) {
                    onMove(value);
                  }
                },
                itemBuilder: (context) => [
                  for (final region in RecognitionRegion.values)
                    PopupMenuItem(
                      value: region,
                      child: Text(_regionLabel(region)),
                    ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: _removeCommand,
                    child: Text('誤検出として削除'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

/// 削除メニューを領域列挙と区別する値です。
const _removeCommand = 'remove';

/// 既存と同じ牌画像を9列で選択する訂正用パレットです。
class _RecognitionTilePicker extends StatelessWidget {
  /// 牌種選択パレットを生成します。
  const _RecognitionTilePicker();

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('牌を選び直す', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 9,
              childAspectRatio: 0.70,
              crossAxisSpacing: 2,
              mainAxisSpacing: 2,
            ),
            itemCount: Tile.values.length,
            itemBuilder: (context, index) {
              final tile = Tile.values[index];
              return Semantics(
                button: true,
                label: '${tileLabel(tile)}を選択',
                child: InkWell(
                  key: Key('recognitionPicker-${tile.name}'),
                  onTap: () => Navigator.of(context).pop(tile),
                  child: MahjongTileFace(tile: tile),
                ),
              );
            },
          ),
        ],
      ),
    ),
  );
}

/// 認識領域を利用者向けの名称へ変換します。
String _regionLabel(RecognitionRegion region) => switch (region) {
  RecognitionRegion.ownHand => '自分の手牌',
  RecognitionRegion.ownRiver => '自分の河',
  RecognitionRegion.upperRiver => '上家の河',
  RecognitionRegion.acrossRiver => '対面の河',
  RecognitionRegion.lowerRiver => '下家の河',
  RecognitionRegion.ownMelds => '自分の副露',
  RecognitionRegion.upperMelds => '上家の副露',
  RecognitionRegion.acrossMelds => '対面の副露',
  RecognitionRegion.lowerMelds => '下家の副露',
  RecognitionRegion.doraIndicators => 'ドラ表示牌',
  RecognitionRegion.unknown => '配置不明',
};
