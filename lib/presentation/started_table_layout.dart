import 'package:flutter/material.dart';

import '../domain/game_situation.dart';
import '../domain/meld.dart';
import '../domain/round_progress.dart';
import '../domain/round_result.dart';
import '../domain/tile.dart';
import 'tile_presentation.dart';

/// 対局開始後の局情報と卓上の牌を、実際の席順に近い位置へ配置します。
class StartedTableLayout extends StatelessWidget {
  /// 現在の局面と進行状態を受け取って卓レイアウトを生成します。
  const StartedTableLayout({
    super.key,
    required this.situation,
    required this.progress,
    required this.dealer,
    required this.activeRiver,
    required this.onRemoveTile,
    required this.onRemoveMeld,
    required this.onRemoveDora,
  });

  /// 表示する手牌、河、ドラ表示牌、副露を含む局面です。
  final GameSituation situation;

  /// 表示する場、局、巡目、残りツモ回数です。
  final RoundProgress progress;

  /// 現在の親の位置です。
  final SeatPosition dealer;

  /// 現在牌を入力する河です。ツモ入力中は null です。
  final InputTarget? activeRiver;

  /// 河の牌を訂正する処理です。
  final void Function(InputTarget river, int index) onRemoveTile;

  /// 副露を訂正する処理です。
  final ValueChanged<Meld> onRemoveMeld;

  /// ドラ表示牌を訂正する処理です。
  final ValueChanged<int> onRemoveDora;

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('startedTableLayout'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      CompactRoundStatus(progress: progress, dealer: dealer),
      const SizedBox(height: 4),
      Expanded(
        child: _TableBoard(
          situation: situation,
          activeRiver: activeRiver,
          onRemoveTile: onRemoveTile,
          onRemoveMeld: onRemoveMeld,
          onRemoveDora: onRemoveDora,
        ),
      ),
    ],
  );
}

/// 局、巡目、親、残りツモ回数を省スペースで表示します。
class CompactRoundStatus extends StatelessWidget {
  /// 現在の進行状態を表示する領域を生成します。
  const CompactRoundStatus({
    super.key,
    required this.progress,
    required this.dealer,
  });

  /// 表示する局進行です。
  final RoundProgress progress;

  /// 表示する親の位置です。
  final SeatPosition dealer;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('compactRoundStatus'),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      children: [
        Text(
          '${_roundWindLabel(progress.roundWind)}${progress.kyoku}局・'
          '${progress.turn}巡目',
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 10),
        Text(
          '親: ${_seatLabel(dealer)}',
          key: const Key('compactDealer'),
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const Spacer(),
        Text(
          '残りツモ ${progress.remainingDraws}回',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    ),
  );
}

/// 4人分の河・副露とドラ表示牌を卓上の位置関係へ配置します。
class _TableBoard extends StatelessWidget {
  /// 卓上表示に必要な局面と操作を受け取ります。
  const _TableBoard({
    required this.situation,
    required this.activeRiver,
    required this.onRemoveTile,
    required this.onRemoveMeld,
    required this.onRemoveDora,
  });

  /// 表示対象の局面です。
  final GameSituation situation;

  /// 強調する河です。
  final InputTarget? activeRiver;

  /// 河牌を訂正する処理です。
  final void Function(InputTarget river, int index) onRemoveTile;

  /// 副露を訂正する処理です。
  final ValueChanged<Meld> onRemoveMeld;

  /// ドラ表示牌を訂正する処理です。
  final ValueChanged<int> onRemoveDora;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final metrics = _TableTileMetrics.fromWidth(constraints.maxWidth);
      return Container(
        key: const Key('tableBoard'),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: const Color(0xffdcefdc),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Expanded(
              flex: 3,
              child: FractionallySizedBox(
                widthFactor: 0.64,
                child: _PlayerZone(
                  river: InputTarget.acrossRiver,
                  label: '対面',
                  situation: situation,
                  active: activeRiver == InputTarget.acrossRiver,
                  metrics: metrics,
                  onRemoveTile: onRemoveTile,
                  onRemoveMeld: onRemoveMeld,
                ),
              ),
            ),
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  Expanded(
                    child: _PlayerZone(
                      river: InputTarget.upperRiver,
                      label: '上家',
                      situation: situation,
                      active: activeRiver == InputTarget.upperRiver,
                      metrics: metrics,
                      onRemoveTile: onRemoveTile,
                      onRemoveMeld: onRemoveMeld,
                    ),
                  ),
                  SizedBox(
                    width: constraints.maxWidth * 0.28,
                    child: _DoraZone(
                      tiles: situation.doraIndicators,
                      metrics: metrics,
                      onRemove: onRemoveDora,
                    ),
                  ),
                  Expanded(
                    child: _PlayerZone(
                      river: InputTarget.lowerRiver,
                      label: '下家',
                      situation: situation,
                      active: activeRiver == InputTarget.lowerRiver,
                      metrics: metrics,
                      onRemoveTile: onRemoveTile,
                      onRemoveMeld: onRemoveMeld,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: FractionallySizedBox(
                widthFactor: 0.64,
                child: _PlayerZone(
                  river: InputTarget.ownRiver,
                  label: '自分',
                  situation: situation,
                  active: activeRiver == InputTarget.ownRiver,
                  metrics: metrics,
                  onRemoveTile: onRemoveTile,
                  onRemoveMeld: onRemoveMeld,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// 1人分の河と副露を、入力状態とともに表示します。
class _PlayerZone extends StatelessWidget {
  /// 指定したプレイヤーの卓上領域を生成します。
  const _PlayerZone({
    required this.river,
    required this.label,
    required this.situation,
    required this.active,
    required this.metrics,
    required this.onRemoveTile,
    required this.onRemoveMeld,
  });

  /// プレイヤーに対応する河です。
  final InputTarget river;

  /// 画面へ表示するプレイヤー名です。
  final String label;

  /// 河と副露を取得する局面です。
  final GameSituation situation;

  /// 現在の入力対象かどうかです。
  final bool active;

  /// 卓上で共通利用する牌サイズです。
  final _TableTileMetrics metrics;

  /// 河牌を訂正する処理です。
  final void Function(InputTarget river, int index) onRemoveTile;

  /// 副露を訂正する処理です。
  final ValueChanged<Meld> onRemoveMeld;

  @override
  Widget build(BuildContext context) {
    final tiles = situation.tilesFor(river);
    final melds = situation.meldsFor(river).toList();
    return AnimatedContainer(
      key: Key('playerZone-${river.name}'),
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.all(1),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: active
            ? Theme.of(context).colorScheme.primaryContainer
            : Colors.white.withValues(alpha: 0.5),
        border: Border.all(
          color: active
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          width: active ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (active) ...[
                const SizedBox(width: 3),
                Text(
                  '入力中',
                  key: Key('activeInput-${river.name}'),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: Wrap(
                key: Key('targetArea-${river.name}'),
                spacing: metrics.spacing,
                runSpacing: metrics.spacing,
                children: List.generate(
                  tiles.length,
                  (index) => _TableTile(
                    key: Key('tableTile-${river.name}-$index'),
                    tile: tiles[index],
                    width: metrics.width,
                    height: metrics.height,
                    semanticPrefix: '$labelの河${index + 1}枚目',
                    onTap: () => onRemoveTile(river, index),
                  ),
                ),
              ),
            ),
          ),
          if (melds.isNotEmpty)
            _CompactMeldStrip(
              river: river,
              melds: melds,
              metrics: metrics,
              onRemove: onRemoveMeld,
            ),
        ],
      ),
    );
  }
}

/// 卓中央に複数のドラ表示牌を並べます。
class _DoraZone extends StatelessWidget {
  /// ドラ表示牌の領域を生成します。
  const _DoraZone({
    required this.tiles,
    required this.metrics,
    required this.onRemove,
  });

  /// 表示するドラ表示牌です。
  final List<Tile> tiles;

  /// 卓上牌の共通サイズです。
  final _TableTileMetrics metrics;

  /// タップしたドラ表示牌を削除する処理です。
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('doraZone'),
    margin: const EdgeInsets.all(2),
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('ドラ', style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 2),
        Wrap(
          key: const Key('targetArea-doraIndicators'),
          alignment: WrapAlignment.center,
          spacing: metrics.spacing,
          runSpacing: metrics.spacing,
          children: List.generate(
            tiles.length,
            (index) => _TableTile(
              key: Key('tableTile-doraIndicators-$index'),
              tile: tiles[index],
              width: metrics.width,
              height: metrics.height,
              semanticPrefix: 'ドラ表示牌${index + 1}枚目',
              onTap: () => onRemove(index),
            ),
          ),
        ),
      ],
    ),
  );
}

/// 1人分の副露を河と区別できる小さな帯として表示します。
class _CompactMeldStrip extends StatelessWidget {
  /// 指定プレイヤーの副露を生成します。
  const _CompactMeldStrip({
    required this.river,
    required this.melds,
    required this.metrics,
    required this.onRemove,
  });

  /// 副露したプレイヤーに対応する河です。
  final InputTarget river;

  /// 表示する副露です。
  final List<Meld> melds;

  /// 卓上牌の共通サイズです。
  final _TableTileMetrics metrics;

  /// 副露を訂正する処理です。
  final ValueChanged<Meld> onRemove;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: metrics.height + 4,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: melds.length,
      separatorBuilder: (_, _) => const SizedBox(width: 3),
      itemBuilder: (context, index) {
        final meld = melds[index];
        return Semantics(
          button: true,
          label: '${_meldLabel(meld)}、タップして訂正',
          child: InkWell(
            key: Key('meld-${river.name}-$index'),
            onTap: () => onRemove(meld),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_meldLabel(meld), style: const TextStyle(fontSize: 8)),
                  ...meld.tiles.map(
                    (tile) => Padding(
                      padding: const EdgeInsets.only(left: 1),
                      child: Text(
                        tileLabel(tile),
                        style: TextStyle(
                          color: tileColor(tile),
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
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

/// 河・ドラに使う、回転しない小さな牌表示です。
class _TableTile extends StatelessWidget {
  /// 牌と表示サイズを受け取って卓上牌を生成します。
  const _TableTile({
    super.key,
    required this.tile,
    required this.width,
    required this.height,
    required this.semanticPrefix,
    this.onTap,
  });

  /// 表示する牌です。
  final Tile tile;

  /// 描画する幅です。
  final double width;

  /// 描画する高さです。
  final double height;

  /// 読み上げ時に牌の所属を伝える接頭辞です。
  final String semanticPrefix;

  /// 牌の訂正操作です。操作できない場合は null です。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: onTap != null,
    label: '$semanticPrefix、${tileLabel(tile)}',
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        width: width,
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xff5b5b5b), width: 0.7),
          borderRadius: BorderRadius.circular(3),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            tileLabel(tile),
            style: TextStyle(
              color: tileColor(tile),
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    ),
  );
}

/// 牌パレット幅を基準に卓上牌を約50%へ縮小する寸法です。
class _TableTileMetrics {
  /// 算出済みの卓上牌寸法を生成します。
  const _TableTileMetrics({
    required this.width,
    required this.height,
    required this.spacing,
  });

  /// 卓上牌の幅です。
  final double width;

  /// 卓上牌の高さです。
  final double height;

  /// 牌同士の間隔です。
  final double spacing;

  /// 画面幅から9枚パレットの牌幅を推定し、約50%の寸法を返します。
  factory _TableTileMetrics.fromWidth(double availableWidth) {
    const pageHorizontalPadding = 24.0;
    const paletteSpacing = 3.0;
    final paletteWidth =
        (availableWidth - pageHorizontalPadding - paletteSpacing * 8) / 9;
    final width = (paletteWidth * 0.5).clamp(14.0, 24.0).toDouble();
    return _TableTileMetrics(width: width, height: width * 1.28, spacing: 1);
  }
}

/// 場風を短い日本語表示へ変換します。
String _roundWindLabel(RoundWind wind) => switch (wind) {
  RoundWind.east => '東',
  RoundWind.south => '南',
};

/// 自分から見た席を短い日本語表示へ変換します。
String _seatLabel(SeatPosition seat) => switch (seat) {
  SeatPosition.self => '自分',
  SeatPosition.lower => '下家',
  SeatPosition.across => '対面',
  SeatPosition.upper => '上家',
};

/// 副露の種類を短い日本語表示へ変換します。
String _meldLabel(Meld meld) => switch (meld.type) {
  MeldType.chi => 'チー',
  MeldType.pon => 'ポン',
  MeldType.kan => switch (meld.kanType) {
    KanType.open => '明槓',
    KanType.concealed => '暗槓',
    KanType.added => '加槓',
    null => 'カン',
  },
};
