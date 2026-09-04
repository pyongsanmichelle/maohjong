import 'package:flutter/material.dart';

import 'domain/game_situation.dart';
import 'domain/match_input_flow.dart';
import 'domain/meld.dart';
import 'domain/round_progress.dart';
import 'domain/situation_editor.dart';
import 'domain/tile.dart';
import 'presentation/danger_analysis_page.dart';
import 'presentation/kan_dialog.dart';
import 'presentation/tile_presentation.dart';

void main() => runApp(const MaohjongApp());

/// 局面入力を提供するアプリケーションのルートです。
class MaohjongApp extends StatelessWidget {
  /// ルートウィジェットを生成します。
  const MaohjongApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Maohjong',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff0f5f4f)),
      useMaterial3: true,
    ),
    home: const SituationInputPage(),
  );
}

/// 牌パレットで手牌と各家の河を編集する画面です。
class SituationInputPage extends StatefulWidget {
  /// 局面入力画面を生成します。
  const SituationInputPage({super.key});

  @override
  State<SituationInputPage> createState() => _SituationInputPageState();
}

/// 画面の選択先と局面編集状態を保持します。
class _SituationInputPageState extends State<SituationInputPage> {
  InputTarget _target = InputTarget.hand;
  late final SituationEditor _editor;
  late final MatchInputFlow _flow;

  /// 現在画面に表示して牌を追加する入力先です。
  InputTarget get _visibleTarget =>
      _flow.started ? _flow.currentRiver : _target;

  /// 開始後に自分の河へ打牌する番かどうかです。
  bool get _isOwnDiscardTurn =>
      _flow.started && _flow.currentRiver == InputTarget.ownRiver;

  /// 現在の入力段階で自分の手牌に保持できる最大枚数です。
  int get _currentHandLimit =>
      _flow.started ? _flow.activeHandLimit : _flow.handLimit;

  @override
  void initState() {
    super.initState();
    final situation = GameSituation();
    _editor = SituationEditor(situation);
    _flow = MatchInputFlow(situation);
  }

  /// 選択中の編集先へ牌を追加し、上限時には理由を表示します。
  void _add(Tile tile) {
    final target = _isOwnDiscardTurn ? InputTarget.hand : _visibleTarget;
    if (_isOwnDiscardTurn && !_flow.ownDrawRequired) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ツモ入力は完了しています。先に手牌から打牌してください。')),
      );
      return;
    }
    if (_isOwnDiscardTurn && _flow.progress.remainingDraws <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('通常の山にツモ牌が残っていません。')));
      return;
    }
    if (target == InputTarget.hand &&
        _editor.situation.hand.length >= _currentHandLimit) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('手牌は最大$_currentHandLimit枚です。')));
      return;
    }
    if (_editor.add(target, tile)) {
      var roundAdvanced = false;
      setState(() {
        if (_isOwnDiscardTurn && target == InputTarget.hand) {
          _flow.markOwnDrawn();
        } else if (_flow.started && target != InputTarget.hand) {
          roundAdvanced = _flow.recordDiscard(target, tile);
        }
      });
      if (roundAdvanced) _finishRoundInput();
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('同じ牌は4枚までです。')));
  }

  /// 指定領域の指定位置にある牌を削除します。
  void _remove(InputTarget target, int index) => setState(() {
    _editor.removeAt(target, index);
  });

  /// 自分の手牌から選んだ牌を河へ移し、次の打牌者へ進めます。
  void _discardFromHand(int index) {
    if (_isOwnDiscardTurn && !_flow.canOwnDiscard) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('先にツモ牌を選択してください。')));
      return;
    }
    if (!_isOwnDiscardTurn ||
        index < 0 ||
        index >= _editor.situation.hand.length) {
      return;
    }
    final tile = _editor.situation.hand[index];
    var roundAdvanced = false;
    setState(() {
      if (_editor.discardFromHand(index)) {
        roundAdvanced = _flow.recordDiscard(InputTarget.ownRiver, tile);
      }
    });
    if (roundAdvanced) _finishRoundInput();
  }

  /// 自動で次局または半荘終了へ進んだことを表示します。
  void _finishRoundInput() {
    _editor.clearHistory();
    final progress = _flow.progress;
    final message = progress.matchFinished
        ? '南4局が終了しました。'
        : '${_roundWindLabel(progress.roundWind)}${progress.kyoku}局へ進みました。手牌とドラを入力してください。';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// 直前の打牌に対する鳴きの内容を選択します。
  Future<void> _showCallDialog() async {
    final discard = _flow.lastDiscard;
    if (discard == null) return;
    final selection = await showDialog<_CallSelection>(
      context: context,
      builder: (context) => _CallDialog(flow: _flow, discard: discard),
    );
    if (!mounted || selection == null) return;
    final tiles = switch (selection.type) {
      MeldType.chi => selection.sequence!,
      MeldType.pon => List.filled(3, discard.tile),
      MeldType.kan => List.filled(4, discard.tile),
    };
    final meld = _editor.declareMeld(
      type: selection.type,
      callerRiver: selection.callerRiver,
      fromRiver: discard.river,
      calledTile: discard.tile,
      tiles: tiles,
    );
    if (meld == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('副露に必要な牌または残り枚数が不足しています。')));
      return;
    }
    setState(() => _flow.acceptCall(selection.type, selection.callerRiver));
  }

  /// 開始時点ですでに成立しているカンを登録します。
  Future<void> _showSetupKanDialog() async {
    final availableTiles = Tile.values
        .where((tile) => _editor.situation.count(tile) == 0)
        .toList();
    final selection = await showDialog<SetupKanSelection>(
      context: context,
      builder: (context) => SetupKanDialog(availableTiles: availableTiles),
    );
    if (!mounted || selection == null) return;
    if (selection.ownerRiver == InputTarget.ownRiver &&
        _editor.situation.hand.length > _flow.handLimit - 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('自分のカンを登録するには、手牌を副露後の枚数まで減らしてください。')),
      );
      return;
    }
    final meld = _editor.registerSetupKan(
      ownerRiver: selection.ownerRiver,
      tile: selection.tile,
      type: selection.type,
    );
    if (meld == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('その牌は局面内ですでに使われているため、カンを登録できません。')),
      );
      return;
    }
    setState(() {});
  }

  /// 自分の打牌可能な番に暗槓または加槓を確定します。
  Future<void> _showSelfKanDialog() async {
    if (!_flow.canOwnDiscard) return;
    final options = _editor.selfKanOptions;
    if (options.isEmpty) return;
    final selection = await showDialog<SelfKanOption>(
      context: context,
      builder: (context) => SelfKanDialog(options: options),
    );
    if (!mounted || selection == null) return;
    final meld = _editor.declareSelfKan(selection);
    if (meld == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('手牌またはポンが変わったため、カンを確定できません。')),
      );
      return;
    }
    setState(_flow.acceptSelfKan);
  }

  /// 副露を取り消して、鳴かれた打牌と通常の手番を復元します。
  void _removeMeld(Meld meld) {
    if (_flow.started && meld.origin == MeldOrigin.setup) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('開始時点のカンは「設定に戻る」から訂正してください。')),
      );
      return;
    }
    if (meld.origin == MeldOrigin.selfKan && !_flow.ownDrawRequired) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('嶺上牌を入力した後はカンを取り消せません。')));
      return;
    }
    setState(() {
      if (!_editor.removeMeld(meld)) return;
      switch (meld.origin) {
        case MeldOrigin.call:
          final fromRiver = meld.fromRiver;
          if (fromRiver != null) {
            _flow.restoreCallOpportunity(fromRiver, meld.calledTile);
          }
          break;
        case MeldOrigin.setup:
          break;
        case MeldOrigin.selfKan:
          _flow.cancelSelfKan();
          break;
      }
    });
  }

  /// 最後の有効な追加操作を取り消します。
  void _undo() {
    final target = _editor.undoLastAddition();
    if (target == null) return;
    setState(() {
      if (_flow.started &&
          target == InputTarget.hand &&
          _flow.currentRiver == InputTarget.ownRiver) {
        _flow.cancelOwnDraw();
      } else if (_flow.started) {
        _flow.rewindTo(target);
      }
    });
  }

  /// 手牌上限を満たす場合に親を変更します。
  void _selectDealer(SeatPosition dealer) {
    if (_flow.selectDealer(dealer)) {
      setState(() {});
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('子の開始時手牌は13枚までです。')));
  }

  /// 準備入力を確定して、親の河から連続入力を開始します。
  void _start() => setState(() {
    _editor.clearHistory();
    _flow.start();
  });

  /// 入力済みの牌を保持したまま準備画面へ戻ります。
  void _returnToSetup() => setState(() {
    _flow.returnToSetup();
    _target = InputTarget.hand;
  });

  /// 現在の入力局面を使う守備分析画面を開きます。
  void _openDangerAnalysis() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => DangerAnalysisPage(situation: _editor.situation),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Maohjong 局面入力')),
    bottomNavigationBar: _PersistentHand(
      tiles: _editor.situation.hand,
      limit: _currentHandLimit,
      started: _flow.started,
      isOwnDiscardTurn: _isOwnDiscardTurn,
      ownDrawRequired: _flow.ownDrawRequired,
      melds: _editor.situation.meldsFor(InputTarget.ownRiver).toList(),
      onTileTap: _flow.started
          ? (_isOwnDiscardTurn ? _discardFromHand : null)
          : (index) => _remove(InputTarget.hand, index),
      onMeldTap: _removeMeld,
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _RoundInput(
            roundWind: _flow.progress.roundWind,
            kyoku: _flow.progress.kyoku,
            turn: _flow.progress.turn,
            remainingDraws: _flow.progress.remainingDraws,
            enabled: !_flow.started,
            onRoundWindChanged: (value) =>
                setState(() => _flow.progress.selectRoundWind(value)),
            onKyokuChanged: (value) =>
                setState(() => _flow.progress.selectKyoku(value)),
            onTurnChanged: (value) =>
                setState(() => _flow.progress.selectTurn(value)),
          ),
          const SizedBox(height: 12),
          _DealerSelector(
            dealer: _flow.dealer,
            enabled: !_flow.started,
            onChanged: _selectDealer,
          ),
          const SizedBox(height: 8),
          if (!_flow.started)
            DefaultTabController(
              key: ValueKey(_target),
              length: InputTarget.values.length,
              initialIndex: _target.index,
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                onTap: (index) =>
                    setState(() => _target = InputTarget.values[index]),
                tabs: InputTarget.values
                    .map(
                      (target) => Tab(
                        key: Key('targetTab-${target.name}'),
                        text: _targetTabLabel(target),
                      ),
                    )
                    .toList(),
              ),
            )
          else
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  _isOwnDiscardTurn
                      ? _flow.ownDrawRequired
                            ? '対局入力中：ツモ牌を選択'
                            : '対局入力中：手牌から自分の打牌を選択'
                      : '対局入力中：${_targetLabel(_flow.currentRiver)}を選択',
                  key: const Key('matchInputStatus'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          const SizedBox(height: 12),
          if (_visibleTarget == InputTarget.hand)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(10),
                child: Text('自分の手牌は画面下部に常時表示しています。'),
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TileArea(
                  key: Key('targetArea-${_visibleTarget.name}'),
                  label: _targetLabel(_visibleTarget),
                  tiles: _editor.situation.tilesFor(_visibleTarget),
                  selected: true,
                  onRemove: (index) => _remove(_visibleTarget, index),
                ),
                if (_isRiverTarget(_visibleTarget) &&
                    _visibleTarget != InputTarget.ownRiver)
                  _MeldArea(
                    river: _visibleTarget,
                    melds: _editor.situation.meldsFor(_visibleTarget).toList(),
                    onRemove: _removeMeld,
                  ),
              ],
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _editor.canUndo ? _undo : null,
                icon: const Icon(Icons.undo),
                label: const Text('取り消し'),
              ),
              if (_flow.started && _flow.lastDiscard != null)
                FilledButton.tonalIcon(
                  key: const Key('callButton'),
                  onPressed: _showCallDialog,
                  icon: const Icon(Icons.call_split),
                  label: const Text('チー・ポン・カン'),
                ),
              if (!_flow.started)
                OutlinedButton.icon(
                  key: const Key('setupKanButton'),
                  onPressed: _showSetupKanDialog,
                  icon: const Icon(Icons.view_module_outlined),
                  label: const Text('開始時点のカン'),
                ),
              if (_isOwnDiscardTurn &&
                  _flow.canOwnDiscard &&
                  _editor.selfKanOptions.isNotEmpty)
                FilledButton.tonalIcon(
                  key: const Key('selfKanButton'),
                  onPressed: _showSelfKanDialog,
                  icon: const Icon(Icons.view_module),
                  label: const Text('カン'),
                ),
              if (_flow.started)
                OutlinedButton.icon(
                  key: const Key('dangerAnalysisButton'),
                  onPressed: _editor.situation.hand.isEmpty
                      ? null
                      : _openDangerAnalysis,
                  icon: const Icon(Icons.shield_outlined),
                  label: const Text('守備分析'),
                ),
              if (!_flow.started)
                FilledButton.icon(
                  key: const Key('startButton'),
                  onPressed: _flow.canStart ? _start : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('開始'),
                )
              else
                OutlinedButton.icon(
                  key: const Key('returnToSetupButton'),
                  onPressed: _returnToSetup,
                  icon: const Icon(Icons.settings),
                  label: const Text('設定に戻る'),
                ),
              Text(
                _flow.started
                    ? _isOwnDiscardTurn
                          ? _flow.ownDrawRequired
                                ? '下の牌パレットからツモ牌を1枚選択'
                                : 'ツモ済み：手牌をタップして打牌'
                          : '次: ${_targetLabel(_flow.currentRiver)}'
                    : '手牌 ${_editor.situation.hand.length}/${_flow.handLimit}枚',
                key: const Key('inputGuide'),
              ),
            ],
          ),
          if (!_flow.started && _flow.progress.matchFinished)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('半荘終了です。新しく始める場合は場・局・巡目を選び直してください。'),
            )
          else if (!_flow.started && !_flow.canStart)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('開始するには、ドラ表示牌と自分の手牌を入力してください。'),
            ),
          const SizedBox(height: 20),
          const Text(
            '牌を選ぶ',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _TilePalette(onTap: _add, remainingCopies: _editor.remainingCopies),
        ],
      ),
    ),
  );
}

/// 画面最下部に固定して現在の自分の手牌を表示します。
class _PersistentHand extends StatelessWidget {
  /// 常時表示する手牌領域を生成します。
  const _PersistentHand({
    required this.tiles,
    required this.limit,
    required this.started,
    required this.isOwnDiscardTurn,
    required this.ownDrawRequired,
    required this.melds,
    required this.onTileTap,
    required this.onMeldTap,
  });

  /// 現在の自分の手牌です。
  final List<Tile> tiles;

  /// 現在の入力段階における手牌上限です。
  final int limit;

  /// 対局入力を開始済みかどうかです。
  final bool started;

  /// 手牌をタップして打牌できる番かどうかです。
  final bool isOwnDiscardTurn;

  /// 自分が打牌する前にツモ入力を必要としているかどうかです。
  final bool ownDrawRequired;

  /// 自分が公開している副露です。
  final List<Meld> melds;

  /// 手牌タップ時の処理です。相手の番は null です。
  final ValueChanged<int>? onTileTap;

  /// 副露をタップして訂正するときの処理です。
  final ValueChanged<Meld> onMeldTap;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Material(
      key: const Key('persistentHand'),
      elevation: 12,
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '自分の手牌 ${tiles.length}/$limit枚',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  isOwnDiscardTurn
                      ? ownDrawRequired
                            ? '先にツモ牌を選択'
                            : 'タップして打牌'
                      : started
                      ? '相手の打牌を入力中'
                      : 'タップして削除',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
            const SizedBox(height: 4),
            SizedBox(
              key: const Key('targetArea-hand'),
              height: 48,
              child: tiles.isEmpty
                  ? const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('牌パレットから手牌を追加'),
                    )
                  : LayoutBuilder(
                      key: const Key('persistentHandList'),
                      builder: (context, constraints) {
                        const spacing = 2.0;
                        final tileWidth =
                            (constraints.maxWidth - spacing * 13) / 14;
                        return Row(
                          children: List.generate(
                            tiles.length,
                            (index) => Padding(
                              padding: EdgeInsets.only(
                                right: index == tiles.length - 1 ? 0 : spacing,
                              ),
                              child: _TileButton(
                                key: Key('handTile-$index'),
                                tile: tiles[index],
                                fitWidth: tileWidth,
                                fitHeight: 48,
                                onTap: onTileTap == null
                                    ? null
                                    : () => onTileTap!(index),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (melds.isNotEmpty) ...[
              const SizedBox(height: 6),
              _MeldArea(
                river: InputTarget.ownRiver,
                melds: melds,
                compact: true,
                onRemove: onMeldTap,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// 河とは別の場所に公開副露をまとめて表示します。
class _MeldArea extends StatelessWidget {
  /// 指定プレイヤーの副露表示を生成します。
  const _MeldArea({
    required this.river,
    required this.melds,
    required this.onRemove,
    this.compact = false,
  });

  /// 副露したプレイヤーに対応する河です。
  final InputTarget river;

  /// 表示する副露です。
  final List<Meld> melds;

  /// 訂正のため副露を削除するときの処理です。
  final ValueChanged<Meld> onRemove;

  /// 固定手牌内で余白を小さく表示するかどうかです。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (melds.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: compact ? EdgeInsets.zero : const EdgeInsets.only(top: 8),
      child: Padding(
        padding: EdgeInsets.all(compact ? 6 : 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              compact ? '自分の副露' : '${_riverOwnerLabel(river)}の副露',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: List.generate(melds.length, (index) {
                final meld = melds[index];
                return InkWell(
                  key: Key('meld-${river.name}-$index'),
                  onTap: () => onRemove(meld),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${_meldLabel(meld)} '),
                        ...meld.tiles.map(
                          (tile) => Padding(
                            padding: const EdgeInsets.only(left: 2),
                            child: Text(
                              tileLabel(tile),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: tileColor(tile),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

/// 鳴きダイアログから返す種別、鳴いた人、順子の選択です。
class _CallSelection {
  /// 選択結果を生成します。
  const _CallSelection(this.type, this.callerRiver, this.sequence);

  final MeldType type;
  final InputTarget callerRiver;
  final List<Tile>? sequence;
}

/// 直前の打牌に対するチー・ポン・大明槓を選択するダイアログです。
class _CallDialog extends StatefulWidget {
  /// 鳴き選択ダイアログを生成します。
  const _CallDialog({required this.flow, required this.discard});

  /// 鳴ける人と順子候補を計算する入力フローです。
  final MatchInputFlow flow;

  /// 鳴き対象の直前打牌です。
  final DiscardEvent discard;

  @override
  State<_CallDialog> createState() => _CallDialogState();
}

/// 鳴き選択中の種別、プレイヤー、順子を保持します。
class _CallDialogState extends State<_CallDialog> {
  late MeldType _type;
  late InputTarget _callerRiver;
  List<Tile>? _sequence;

  @override
  void initState() {
    super.initState();
    final sequences = widget.flow.chiSequences(widget.discard.tile);
    _type = sequences.isEmpty ? MeldType.pon : MeldType.chi;
    _callerRiver = widget.flow.callersFor(_type).first;
    _sequence = sequences.firstOrNull;
  }

  /// 鳴き種別を変更し、選べる人と順子を初期化します。
  void _selectType(MeldType type) => setState(() {
    _type = type;
    _callerRiver = widget.flow.callersFor(type).first;
    final sequences = widget.flow.chiSequences(widget.discard.tile);
    _sequence = type == MeldType.chi ? sequences.firstOrNull : null;
  });

  @override
  Widget build(BuildContext context) {
    final callers = widget.flow.callersFor(_type);
    final sequences = widget.flow.chiSequences(widget.discard.tile);
    final chiEnabled = sequences.isNotEmpty;
    return AlertDialog(
      title: Text('${tileLabel(widget.discard.tile)}を鳴く'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              children: MeldType.values.map((type) {
                final enabled = type != MeldType.chi || chiEnabled;
                return ChoiceChip(
                  key: Key('callType-${type.name}'),
                  label: Text(_meldTypeLabel(type)),
                  selected: _type == type,
                  onSelected: enabled ? (_) => _selectType(type) : null,
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            const Text('鳴いた人'),
            DropdownButton<InputTarget>(
              key: const Key('callPlayerSelector'),
              value: _callerRiver,
              isExpanded: true,
              items: callers
                  .map(
                    (river) => DropdownMenuItem(
                      value: river,
                      child: Text(_riverOwnerLabel(river)),
                    ),
                  )
                  .toList(),
              onChanged: _type == MeldType.chi
                  ? null
                  : (value) {
                      if (value != null) setState(() => _callerRiver = value);
                    },
            ),
            if (_type == MeldType.chi) ...[
              const SizedBox(height: 8),
              const Text('順子'),
              Wrap(
                spacing: 6,
                children: sequences
                    .map(
                      (sequence) => ChoiceChip(
                        key: Key(
                          'chi-${sequence.map((tile) => tile.name).join('-')}',
                        ),
                        label: Text(sequence.map(tileLabel).join(' ')),
                        selected: _sameTiles(_sequence, sequence),
                        onSelected: (_) => setState(() => _sequence = sequence),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          key: const Key('confirmCallButton'),
          onPressed: _type != MeldType.chi || _sequence != null
              ? () => Navigator.pop(
                  context,
                  _CallSelection(_type, _callerRiver, _sequence),
                )
              : null,
          child: const Text('確定'),
        ),
      ],
    );
  }
}

/// 自分から見た親の位置を選択する入力部品です。
class _DealerSelector extends StatelessWidget {
  /// 親選択部品を生成します。
  const _DealerSelector({
    required this.dealer,
    required this.enabled,
    required this.onChanged,
  });

  /// 選択中の親です。
  final SeatPosition dealer;

  /// 親を変更可能かどうかです。
  final bool enabled;

  /// 親の選択変更を通知します。
  final ValueChanged<SeatPosition> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('親の位置', style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: SeatPosition.values
            .map(
              (seat) => ChoiceChip(
                key: Key('dealer-${seat.name}'),
                label: Text(_seatLabel(seat)),
                selected: dealer == seat,
                onSelected: enabled ? (_) => onChanged(seat) : null,
              ),
            )
            .toList(),
      ),
    ],
  );
}

/// 東場・南場、局番号、巡目を選択する局面情報の入力部品です。
class _RoundInput extends StatelessWidget {
  /// 局面情報の入力部品を生成します。
  const _RoundInput({
    required this.roundWind,
    required this.kyoku,
    required this.turn,
    required this.remainingDraws,
    required this.enabled,
    required this.onRoundWindChanged,
    required this.onKyokuChanged,
    required this.onTurnChanged,
  });

  /// 選択中の場風です。
  final RoundWind roundWind;

  /// 選択中の局番号です。
  final int kyoku;

  /// 選択中の巡目です。
  final int turn;

  /// 通常の山からツモできる残り回数です。
  final int remainingDraws;

  /// 開始前の局情報を変更可能かどうかです。
  final bool enabled;

  /// 場風の選択変更を通知します。
  final ValueChanged<RoundWind> onRoundWindChanged;

  /// 局番号の選択変更を通知します。
  final ValueChanged<int> onKyokuChanged;

  /// 巡目の選択変更を通知します。
  final ValueChanged<int> onTurnChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '${_roundWindLabel(roundWind)}$kyoku局・$turn巡目',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      Text(
        '残りツモ $remainingDraws回',
        key: const Key('remainingDraws'),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<RoundWind>(
            segments: const [
              ButtonSegment(value: RoundWind.east, label: Text('東場')),
              ButtonSegment(value: RoundWind.south, label: Text('南場')),
            ],
            selected: {roundWind},
            onSelectionChanged: enabled
                ? (items) => onRoundWindChanged(items.first)
                : null,
          ),
          DropdownButton<int>(
            key: const Key('kyokuSelector'),
            value: kyoku,
            items: List.generate(
              4,
              (index) => DropdownMenuItem(
                value: index + 1,
                child: Text('${index + 1}局'),
              ),
            ),
            onChanged: enabled
                ? (value) {
                    if (value != null) onKyokuChanged(value);
                  }
                : null,
          ),
          DropdownButton<int>(
            key: const Key('turnSelector'),
            value: turn,
            items: List.generate(
              18,
              (index) => DropdownMenuItem(
                value: index + 1,
                child: Text('${index + 1}巡目'),
              ),
            ),
            onChanged: enabled
                ? (value) {
                    if (value != null) onTurnChanged(value);
                  }
                : null,
          ),
        ],
      ),
    ],
  );
}

/// 一つの手牌または河を表示する領域です。
class _TileArea extends StatelessWidget {
  /// 表示領域を生成します。
  const _TileArea({
    super.key,
    required this.label,
    required this.tiles,
    required this.selected,
    required this.onRemove,
  });

  final String label;
  final List<Tile> tiles;
  final bool selected;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) => Card(
    color: selected ? Theme.of(context).colorScheme.secondaryContainer : null,
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: tiles.isEmpty
                ? const [Text('牌をタップして追加')]
                : List.generate(
                    tiles.length,
                    (index) => _TileButton(
                      tile: tiles[index],
                      onTap: () => onRemove(index),
                    ),
                  ),
          ),
        ],
      ),
    ),
  );
}

/// 34種類の牌をタップ可能なパレットとして表示します。
class _TilePalette extends StatelessWidget {
  /// 牌パレットを生成します。
  const _TilePalette({required this.onTap, required this.remainingCopies});

  final ValueChanged<Tile> onTap;

  /// 見えている牌を差し引いた、各牌の未確認枚数を返します。
  final int Function(Tile) remainingCopies;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const spacing = 3.0;
      final tileWidth = (constraints.maxWidth - spacing * 8) / 9;
      return Column(
        children: [
          _row(Tile.values.sublist(0, 9), tileWidth, spacing),
          _row(Tile.values.sublist(9, 18), tileWidth, spacing),
          _row(Tile.values.sublist(18, 27), tileWidth, spacing),
          _row(Tile.values.sublist(27), tileWidth, spacing),
        ],
      );
    },
  );

  /// 同じ種類の牌を一行に並べます。
  Widget _row(List<Tile> tiles, double tileWidth, double spacing) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: List.generate(tiles.length, (index) {
        final tile = tiles[index];
        final remaining = remainingCopies(tile);
        return Padding(
          padding: EdgeInsets.only(
            right: index == tiles.length - 1 ? 0 : spacing,
          ),
          child: _TileButton(
            tile: tile,
            paletteWidth: tileWidth,
            remainingCopies: remaining,
            onTap: remaining == 0 ? null : () => onTap(tile),
          ),
        );
      }).toList(),
    ),
  );
}

/// 牌を模したタップ可能なUI部品です。
class _TileButton extends StatelessWidget {
  /// 牌ボタンを生成します。
  const _TileButton({
    super.key,
    required this.tile,
    required this.onTap,
    this.remainingCopies,
    this.paletteWidth,
    this.fitWidth,
    this.fitHeight,
  });

  final Tile tile;

  /// タップ時の処理です。残数0のパレット牌では null になります。
  final VoidCallback? onTap;

  /// パレットで表示する未確認枚数です。入力済み牌では null です。
  final int? remainingCopies;

  /// 横9枚表示のために計算されたパレット牌の幅です。
  final double? paletteWidth;

  /// 手牌などで親領域の横幅へ合わせるための幅です。
  final double? fitWidth;

  /// 親領域の高さへ合わせるための高さです。
  final double? fitHeight;

  @override
  Widget build(BuildContext context) {
    final isPaletteTile = remainingCopies != null;
    final isEnabled = onTap != null;
    return Semantics(
      button: true,
      enabled: isEnabled,
      label: isPaletteTile
          ? '${tileLabel(tile)}、残り$remainingCopies枚'
          : tileLabel(tile),
      child: InkWell(
        key: isPaletteTile ? Key('palette-${tile.name}') : null,
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          width: fitWidth ?? (isPaletteTile ? paletteWidth : 38),
          height: fitHeight ?? (isPaletteTile ? 56 : 52),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isEnabled ? Colors.white : Colors.grey.shade300,
            border: Border.all(color: const Color(0xff5b5b5b)),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  tileLabel(tile),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: fitWidth != null && fitWidth! < 30 ? 11 : null,
                    color: isEnabled ? tileColor(tile) : Colors.grey.shade600,
                  ),
                ),
              ),
              if (isPaletteTile)
                Text(
                  '残$remainingCopies',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 編集先の表示名を返します。
String _targetLabel(InputTarget target) => switch (target) {
  InputTarget.hand => '手牌',
  InputTarget.ownRiver => '自分の河',
  InputTarget.upperRiver => '上家の河',
  InputTarget.acrossRiver => '対面の河',
  InputTarget.lowerRiver => '下家の河',
  InputTarget.doraIndicators => 'ドラ表示牌',
};

/// 入力先タブに表示する短い名前を返します。
String _targetTabLabel(InputTarget target) => switch (target) {
  InputTarget.hand => '手牌',
  InputTarget.ownRiver => '自分',
  InputTarget.upperRiver => '上家',
  InputTarget.acrossRiver => '対面',
  InputTarget.lowerRiver => '下家',
  InputTarget.doraIndicators => 'ドラ',
};

/// 河の入力先に対応するプレイヤー名を返します。
String _riverOwnerLabel(InputTarget river) => switch (river) {
  InputTarget.ownRiver => '自分',
  InputTarget.lowerRiver => '下家',
  InputTarget.acrossRiver => '対面',
  InputTarget.upperRiver => '上家',
  _ => '',
};

/// 指定した入力先が4人いずれかの河かどうかを返します。
bool _isRiverTarget(InputTarget target) =>
    MatchInputFlow.riverTargets.contains(target);

/// 副露種別の表示名を返します。
String _meldTypeLabel(MeldType type) => switch (type) {
  MeldType.chi => 'チー',
  MeldType.pon => 'ポン',
  MeldType.kan => 'カン',
};

/// カンの成立方法を含む副露の表示名を返します。
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

/// 二つの牌一覧が同じ順序と内容かどうかを返します。
bool _sameTiles(List<Tile>? first, List<Tile> second) {
  if (first == null || first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}

/// 親の位置に表示する名前を返します。
String _seatLabel(SeatPosition seat) => switch (seat) {
  SeatPosition.self => '自分',
  SeatPosition.lower => '下家',
  SeatPosition.across => '対面',
  SeatPosition.upper => '上家',
};

/// 場風の表示名を返します。
String _roundWindLabel(RoundWind wind) => switch (wind) {
  RoundWind.east => '東',
  RoundWind.south => '南',
};
