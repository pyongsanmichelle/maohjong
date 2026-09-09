import 'dart:io';

import 'package:flutter/material.dart';

import 'application/image_source_gateway.dart';
import 'application/recognition_draft_use_cases.dart';
import 'domain/game_situation.dart';
import 'domain/match_input_flow.dart';
import 'domain/match_setup_validation.dart';
import 'domain/meld.dart';
import 'domain/round_progress.dart';
import 'domain/round_action_history.dart';
import 'domain/situation_editor.dart';
import 'domain/tile.dart';
import 'domain/tile_recognition.dart';
import 'infrastructure/image_picker_source_gateway.dart';
import 'infrastructure/onnx_mahjong_tile_recognizer.dart';
import 'presentation/danger_analysis_page.dart';
import 'presentation/discard_metadata_editor.dart';
import 'presentation/hand_danger_presentation.dart';
import 'presentation/kan_dialog.dart';
import 'presentation/mahjong_tile_face.dart';
import 'presentation/match_action_bar.dart';
import 'presentation/round_end_dialog.dart';
import 'presentation/started_table_layout.dart';
import 'presentation/static_image_recognition_page.dart';
import 'presentation/tile_presentation.dart';

void main() => runApp(const MaohjongApp());

/// 局面入力を提供するアプリケーションのルートです。
class MaohjongApp extends StatelessWidget {
  /// ルートウィジェットを生成します。
  const MaohjongApp({super.key, this.imageSourceGateway, this.tileRecognizer});

  /// テストや別プラットフォームで差し替える画像取得処理です。
  final ImageSourceGateway? imageSourceGateway;

  /// テストや将来のモデル更新で差し替える牌認識処理です。
  final MahjongTileRecognizer? tileRecognizer;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Maohjong',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff0f5f4f)),
      useMaterial3: true,
    ),
    home: SituationInputPage(
      imageSourceGateway: imageSourceGateway,
      tileRecognizer: tileRecognizer,
    ),
  );
}

/// 牌パレットで手牌と各家の河を編集する画面です。
class SituationInputPage extends StatefulWidget {
  /// 局面入力画面を生成します。
  const SituationInputPage({
    super.key,
    this.imageSourceGateway,
    this.tileRecognizer,
  });

  /// カメラ・画像選択の差し替え可能な窓口です。
  final ImageSourceGateway? imageSourceGateway;

  /// 静止画認識の差し替え可能な窓口です。
  final MahjongTileRecognizer? tileRecognizer;

  @override
  State<SituationInputPage> createState() => _SituationInputPageState();
}

/// 画面の選択先と局面編集状態を保持します。
class _SituationInputPageState extends State<SituationInputPage> {
  InputTarget _target = InputTarget.hand;
  late final SituationEditor _editor;
  late final MatchInputFlow _flow;
  late final ImageSourceGateway _imageSourceGateway;
  late final MahjongTileRecognizer _tileRecognizer;
  late final bool _ownsTileRecognizer;
  final HandDangerPresenter _handDangerPresenter = const HandDangerPresenter();

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
    _imageSourceGateway =
        widget.imageSourceGateway ?? ImagePickerSourceGateway();
    _ownsTileRecognizer = widget.tileRecognizer == null;
    _tileRecognizer = widget.tileRecognizer ?? OnnxMahjongTileRecognizer();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreLostImage());
  }

  @override
  void dispose() {
    if (_ownsTileRecognizer) _tileRecognizer.dispose();
    super.dispose();
  }

  /// Androidで画像選択中に破棄されたActivityの結果を復元します。
  Future<void> _restoreLostImage() async {
    final result = await _imageSourceGateway.retrieveLostImage();
    if (!mounted || result == null) return;
    if (result.isSuccess) {
      await _reviewRecognition(result.path!);
    } else if (result.failure != ImageAcquisitionFailure.cancelled) {
      _showImageAcquisitionFailure(result.failure!);
    }
  }

  /// カメラまたは端末内画像を選ぶシートを表示します。
  Future<void> _showStaticImageInput() async {
    final source = await showModalBottomSheet<StillImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('静止画から局面を入力'),
              subtitle: Text('認識結果は確認・訂正してから反映されます。'),
            ),
            ListTile(
              key: const Key('recognitionCameraSource'),
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('カメラで撮影'),
              onTap: () => Navigator.pop(context, StillImageSource.camera),
            ),
            ListTile(
              key: const Key('recognitionGallerySource'),
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('端末の画像を選択'),
              onTap: () => Navigator.pop(context, StillImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (!mounted || source == null) return;
    final result = await _imageSourceGateway.acquire(source);
    if (!mounted) return;
    if (!result.isSuccess) {
      if (result.failure != ImageAcquisitionFailure.cancelled) {
        _showImageAcquisitionFailure(result.failure!);
      }
      return;
    }
    await _reviewRecognition(
      result.path!,
      deleteAfterReview: source == StillImageSource.camera,
    );
  }

  /// 認識候補の確認画面を開き、確定時だけ現在局へ一括反映します。
  Future<void> _reviewRecognition(
    String imagePath, {
    bool deleteAfterReview = false,
  }) async {
    RecognitionDraft? draft;
    try {
      draft = await Navigator.of(context).push<RecognitionDraft>(
        MaterialPageRoute(
          builder: (context) => StaticImageRecognitionPage(
            imagePath: imagePath,
            recognizer: _tileRecognizer,
          ),
        ),
      );
    } finally {
      if (deleteAfterReview) await _deleteTemporaryImage(imagePath);
    }
    if (!mounted || draft == null) return;
    final applied = const ApplyRecognitionDraftUseCase().call(
      draft: draft,
      target: _editor.situation,
      handLimit: _currentHandLimit,
    );
    if (!applied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('局面へ反映できませんでした。候補をもう一度確認してください。')),
      );
      return;
    }
    setState(() {
      _editor.clearHistory();
      _target = InputTarget.hand;
      if (_flow.started) _flow.reseedFromSituation();
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('確認済みの認識結果を局面へ反映しました。')));
  }

  /// 画像取得失敗の理由を個人情報を含まない案内へ変換して表示します。
  void _showImageAcquisitionFailure(ImageAcquisitionFailure failure) {
    final message = switch (failure) {
      ImageAcquisitionFailure.cancelled => '画像の選択を中止しました。',
      ImageAcquisitionFailure.permissionDenied =>
        'カメラまたは写真へのアクセスが許可されていません。端末設定を確認してください。',
      ImageAcquisitionFailure.unavailable => 'この端末では画像取得を利用できません。',
      ImageAcquisitionFailure.unknown => '画像を取得できませんでした。もう一度お試しください。',
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// 選択中の編集先へ牌を追加し、上限時には理由を表示します。
  void _add(
    Tile tile, {
    DiscardSource source = DiscardSource.unknown,
    bool declaresRiichi = false,
  }) {
    final target = _isOwnDiscardTurn ? InputTarget.hand : _visibleTarget;
    if (_flow.started && _flow.kanDoraPending) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('先にカンドラ表示牌を選択してください。')));
      return;
    }
    if (!_flow.started &&
        target == InputTarget.doraIndicators &&
        _editor.situation.doraIndicators.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('開始前のドラ表示牌は1枚です。選び直す場合は表示牌をタップしてください。')),
      );
      return;
    }
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
          roundAdvanced = _flow.recordDiscard(
            target,
            tile,
            source: source,
            declaresRiichi: declaresRiichi,
          );
        }
      });
      if (roundAdvanced) _finishRoundInput();
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('同じ牌は4枚までです。')));
  }

  /// 相手の打牌を手出し・ツモ切り・リーチ属性付きで追加します。
  Future<void> _addDiscardWithMetadata(Tile tile) async {
    if (!_flow.started ||
        !_isRiverTarget(_visibleTarget) ||
        _visibleTarget == InputTarget.ownRiver) {
      return;
    }
    final selection = await showDialog<DiscardMetadataSelection>(
      context: context,
      builder: (context) => DiscardMetadataEditor(tile: tile),
    );
    if (!mounted || selection == null) return;
    _add(
      tile,
      source: selection.source,
      declaresRiichi: selection.declaresRiichi,
    );
  }

  /// カメラ撮影で作られた一時画像だけを確認終了後に破棄します。
  Future<void> _deleteTemporaryImage(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 一時ファイルの削除失敗は局面反映を妨げない。
    }
  }

  /// 指定領域の指定位置にある牌を削除します。
  void _remove(InputTarget target, int index) {
    if (_flow.started && _isRiverTarget(target)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('対局中の河訂正は「取り消し」または打牌履歴の編集を使ってください。')),
      );
      return;
    }
    setState(() => _editor.removeAt(target, index));
  }

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
    final result = _flow.lastRoundResult;
    final resultMessage = result == null
        ? '局を終了しました'
        : _roundResultMessage(result);
    final message = progress.matchFinished
        ? '$resultMessage。南4局が終了しました。'
        : '$resultMessage。${_roundWindLabel(progress.roundWind)}${progress.kyoku}局へ進みました。'
              '手牌とドラを入力してください。';
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
    var accepted = false;
    setState(() {
      accepted = _flow.acceptCall(
        selection.type,
        selection.callerRiver,
        meld: meld,
      );
    });
    if (accepted && selection.type == MeldType.kan) {
      await _showDoraIndicatorPicker(requiredByKan: true);
    }
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
    setState(() => _flow.requireKanDoraIndicator());
    await _showDoraIndicatorPicker(requiredByKan: true);
  }

  /// 追加ドラを選び、カン後の場合は嶺上牌より先に入力を確定します。
  Future<void> _showDoraIndicatorPicker({bool requiredByKan = false}) async {
    final tile = await showModalBottomSheet<Tile>(
      context: context,
      isScrollControlled: true,
      isDismissible: !requiredByKan,
      enableDrag: !requiredByKan,
      builder: (context) => PopScope(
        canPop: !requiredByKan,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    requiredByKan ? 'カンドラ表示牌を選択' : '追加するドラ表示牌',
                    key: requiredByKan ? const Key('kanDoraPickerTitle') : null,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (requiredByKan) ...[
                    const SizedBox(height: 4),
                    const Text('嶺上牌を入力する前に、新しい表示牌を1枚選んでください。'),
                  ],
                  const SizedBox(height: 8),
                  _TilePalette(
                    onTap: (tile) => Navigator.pop(context, tile),
                    remainingCopies: _editor.remainingCopies,
                    compact: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (!mounted || tile == null) return;
    if (!_editor.add(InputTarget.doraIndicators, tile)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('同じ牌は4枚までです。')));
      return;
    }
    setState(() {
      if (requiredByKan) _flow.confirmKanDoraIndicator();
    });
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
    var accepted = false;
    setState(() {
      accepted = _flow.acceptSelfKan(meld: meld);
    });
    if (accepted) {
      await _showDoraIndicatorPicker(requiredByKan: true);
    }
  }

  /// 副露を取り消して、鳴かれた打牌と通常の手番を復元します。
  void _removeMeld(Meld meld) {
    if (meld.origin == MeldOrigin.selfKan && !_flow.ownDrawRequired) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('嶺上牌を入力した後はカンを取り消せません。')));
      return;
    }
    setState(() {
      if (!_editor.removeMeld(meld)) return;
      if (meld.type == MeldType.kan &&
          _editor.situation.doraIndicators.length > 1) {
        _editor.removeAt(
          InputTarget.doraIndicators,
          _editor.situation.doraIndicators.length - 1,
        );
      }
      switch (meld.origin) {
        case MeldOrigin.call:
          final fromRiver = meld.fromRiver;
          if (fromRiver != null) {
            _flow.restoreCallOpportunity(
              fromRiver,
              meld.calledTile,
              meld: meld,
            );
          }
          break;
        case MeldOrigin.setup:
          break;
        case MeldOrigin.selfKan:
          _flow.cancelSelfKan(meld: meld);
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

  /// 半荘終了後の局面と履歴を破棄し、東1局の準備へ戻します。
  void _startNewMatch() => setState(() {
    _flow.resetForNewMatch();
    _editor.clearHistory();
    _target = InputTarget.hand;
  });

  /// 入力済みの牌を保持したまま準備画面へ戻ります。
  void _returnToSetup() => setState(() {
    _flow.returnToSetup();
    _target = InputTarget.hand;
  });

  /// 現在の入力局面を使う相手分析画面を開きます。
  void _openDangerAnalysis() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => DangerAnalysisPage(
          situation: _editor.situation,
          roundWind: _flow.progress.roundWind,
          dealer: _flow.dealer,
          turn: _flow.progress.turn,
          actionHistory: _flow.actionHistory,
        ),
      ),
    );
  }

  /// 長押しした手牌について3人分の危険情報を表示します。
  void _showHandDangerDetails(HandDangerSummary summary) {
    showDialog<void>(
      context: context,
      builder: (context) => HandDangerDetailDialog(summary: summary),
    );
  }

  /// ツモまたはロンの内容を選び、現在局を終了します。
  Future<void> _showRoundEndDialog() async {
    final discard = _flow.lastDiscard;
    final selection = await showDialog<RoundEndSelection>(
      context: context,
      builder: (context) => RoundEndDialog(
        discarder: discard == null
            ? null
            : MatchInputFlow.seatForRiver(discard.river),
      ),
    );
    if (!mounted || selection == null) return;
    var completed = false;
    setState(() {
      completed = _flow.completeWin(
        reason: selection.reason,
        winner: selection.winner,
      );
      if (completed) _editor.clearHistory();
    });
    if (completed) {
      _finishRoundInput();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('直前の打牌がないため、ロンでは局を終了できません。')),
      );
    }
  }

  /// 開始前に手牌と最初のドラを同時表示する簡略入力画面です。
  Widget _buildSetupBody() {
    if (_flow.progress.matchFinished) {
      return Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('半荘終了です。'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const Key('newMatchButton'),
                  onPressed: _startNewMatch,
                  icon: const Icon(Icons.refresh),
                  label: const Text('新しい対局'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final validation = _flow.setupValidation;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '${_roundWindLabel(_flow.progress.roundWind)}${_flow.progress.kyoku}局・'
          '${_flow.progress.turn}巡目',
          key: const Key('setupRoundStatus'),
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _DealerSelector(
          dealer: _flow.dealer,
          enabled: true,
          onChanged: _selectDealer,
        ),
        const SizedBox(height: 8),
        _SetupTargetCard(
          key: const Key('setupTarget-hand'),
          label: '自分の手牌',
          selected: _target == InputTarget.hand,
          countLabel: '${_editor.situation.hand.length}/${_flow.handLimit}枚',
          onTap: () => setState(() => _target = InputTarget.hand),
          child: _SetupTileStrip(
            key: const Key('targetArea-hand'),
            tiles: _editor.situation.hand,
            tileKeyPrefix: 'handTile',
            onRemove: (index) => _remove(InputTarget.hand, index),
          ),
        ),
        _SetupTargetCard(
          key: const Key('setupTarget-doraIndicators'),
          label: '最初のドラ表示牌',
          selected: _target == InputTarget.doraIndicators,
          countLabel: '${_editor.situation.doraIndicators.length}/1枚',
          onTap: () => setState(() => _target = InputTarget.doraIndicators),
          child: _SetupTileStrip(
            key: const Key('targetArea-doraIndicators'),
            tiles: _editor.situation.doraIndicators,
            tileKeyPrefix: 'setupDoraTile',
            onRemove: (index) => _remove(InputTarget.doraIndicators, index),
          ),
        ),
        _buildSetupActions(),
        if (!validation.canStart)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _setupIssueMessage(validation.issues.first),
              key: const Key('setupValidationMessage'),
            ),
          ),
        const SizedBox(height: 20),
        const Text(
          '牌を選ぶ',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _TilePalette(onTap: _add, remainingCopies: _editor.remainingCopies),
      ],
    );
  }

  /// 開始後の卓を固定し、牌パレットだけを内部スクロール可能にします。
  Widget _buildStartedBody() => LayoutBuilder(
    builder: (context, constraints) {
      final tableHeight = (constraints.maxHeight * 0.43)
          .clamp(245.0, 300.0)
          .toDouble();
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
        child: Column(
          children: [
            SizedBox(
              height: tableHeight,
              child: StartedTableLayout(
                situation: _editor.situation,
                progress: _flow.progress,
                dealer: _flow.dealer,
                activeRiver: _isOwnDiscardTurn && _flow.ownDrawRequired
                    ? null
                    : _flow.currentRiver,
                onRemoveTile: _remove,
                onRemoveMeld: _removeMeld,
                onRemoveDora: (index) =>
                    _remove(InputTarget.doraIndicators, index),
              ),
            ),
            const SizedBox(height: 4),
            _buildMatchInputStatus(),
            const SizedBox(height: 4),
            MatchActionBar(
              canUndo: _editor.canUndo,
              showCall: _flow.lastDiscard != null,
              showSelfKan:
                  _isOwnDiscardTurn &&
                  _flow.canOwnDiscard &&
                  _editor.selfKanOptions.isNotEmpty,
              onUndo: _undo,
              onCall: _showCallDialog,
              onSelfKan: _showSelfKanDialog,
              onRoundEnd: _showRoundEndDialog,
              onCorrectSituation: _showSetupKanDialog,
              onAddDora: _showDoraIndicatorPicker,
              onOpenAnalysis: _openDangerAnalysis,
              onReturnToSetup: _returnToSetup,
              onImportImage: _showStaticImageInput,
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Container(
                key: const Key('tilePalettePanel'),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
                child: SingleChildScrollView(
                  key: const Key('startedPaletteScroll'),
                  primary: false,
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '牌を選ぶ',
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      _TilePalette(
                        onTap: _add,
                        onLongPress:
                            _isRiverTarget(_visibleTarget) &&
                                _visibleTarget != InputTarget.ownRiver
                            ? _addDiscardWithMetadata
                            : null,
                        remainingCopies: _editor.remainingCopies,
                        compact: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  /// 現在求めているツモまたは打牌を小さな帯で表示します。
  Widget _buildMatchInputStatus() => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      _flow.kanDoraPending
          ? '対局入力中：カンドラ表示牌を選択'
          : _isOwnDiscardTurn
          ? _flow.ownDrawRequired
                ? '対局入力中：ツモ牌を選択'
                : '対局入力中：手牌から自分の打牌を選択'
          : '対局入力中：${_targetLabel(_flow.currentRiver)}を選択',
      key: const Key('matchInputStatus'),
      style: Theme.of(context).textTheme.labelMedium
          ?.copyWith(fontWeight: FontWeight.bold),
    ),
  );

  /// 開始前の開始操作と現在の手牌枚数を表示します。
  Widget _buildSetupActions() => Wrap(
    spacing: 8,
    runSpacing: 6,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      FilledButton.icon(
        key: const Key('startButton'),
        onPressed: _flow.canStart ? _start : null,
        icon: const Icon(Icons.play_arrow),
        label: const Text('開始'),
      ),
      OutlinedButton.icon(
        key: const Key('staticImageInputButton'),
        onPressed: _showStaticImageInput,
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('画像から入力'),
      ),
      Text(
        '手牌 ${_editor.situation.hand.length}/${_flow.handLimit}枚',
        key: const Key('inputGuide'),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Maohjong 局面入力')),
    bottomNavigationBar: _flow.started
        ? _PersistentHand(
            tiles: _editor.situation.hand,
            limit: _currentHandLimit,
            started: _flow.started,
            isOwnDiscardTurn: _isOwnDiscardTurn,
            ownDrawRequired: _flow.ownDrawRequired,
            melds: const [],
            dangerSummaries: _flow.started
                ? {
                    for (final summary in _handDangerPresenter.summarize(
                      _editor.situation,
                    ))
                      summary.tile: summary,
                  }
                : const {},
            onTileTap: _flow.started
                ? (_isOwnDiscardTurn ? _discardFromHand : null)
                : (index) => _remove(InputTarget.hand, index),
            onMeldTap: _removeMeld,
            onDangerLongPress: _flow.started ? _showHandDangerDetails : null,
          )
        : null,
    body: SafeArea(
      child: _flow.started ? _buildStartedBody() : _buildSetupBody(),
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
    required this.dangerSummaries,
    required this.onTileTap,
    required this.onMeldTap,
    required this.onDangerLongPress,
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

  /// 牌種ごとの最大危険率と相手別評価です。開始前は空です。
  final Map<Tile, HandDangerSummary> dangerSummaries;

  /// 手牌タップ時の処理です。相手の番は null です。
  final ValueChanged<int>? onTileTap;

  /// 副露をタップして訂正するときの処理です。
  final ValueChanged<Meld> onMeldTap;

  /// 手牌長押し時に危険情報を表示する処理です。開始前は null です。
  final ValueChanged<HandDangerSummary>? onDangerLongPress;

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
                Expanded(
                  child: Text(
                    '自分の手牌 ${tiles.length}/$limit枚',
                    maxLines: 2,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    isOwnDiscardTurn
                        ? ownDrawRequired
                              ? '先にツモ牌を選択'
                              : 'タップして打牌'
                        : started
                        ? '相手の打牌を入力中'
                        : 'タップして削除',
                    maxLines: 2,
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
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
                                dangerScore: dangerSummaries[tiles[index]]
                                    ?.maximumAssessment
                                    .score,
                                dangerScoreKey: Key('handDangerScore-$index'),
                                onTap: onTileTap == null
                                    ? null
                                    : () => onTileTap!(index),
                                onLongPress:
                                    onDangerLongPress == null ||
                                        dangerSummaries[tiles[index]] == null
                                    ? null
                                    : () => onDangerLongPress!(
                                        dangerSummaries[tiles[index]]!,
                                      ),
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
                            child: MahjongTileFace(
                              tile: tile,
                              width: compact ? 18 : 24,
                              height: compact ? 24 : 32,
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

  /// 画面上に並ぶ候補から鳴いた人を直接選択します。
  void _selectCaller(InputTarget river) => setState(() {
    _callerRiver = river;
  });

  @override
  Widget build(BuildContext context) {
    final callers = widget.flow.callersFor(_type);
    final sequences = widget.flow.chiSequences(widget.discard.tile);
    final chiEnabled = sequences.isNotEmpty;
    return AlertDialog(
      title: Row(
        children: [
          MahjongTileFace(tile: widget.discard.tile, width: 28, height: 38),
          const SizedBox(width: 8),
          Text('${tileLabel(widget.discard.tile)}を鳴く'),
        ],
      ),
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
            const SizedBox(height: 4),
            Wrap(
              key: const Key('callPlayerSelector'),
              spacing: 6,
              runSpacing: 6,
              children: callers
                  .map(
                    (river) => ChoiceChip(
                      key: Key('callPlayer-${river.name}'),
                      label: Text(_riverOwnerLabel(river)),
                      selected: _callerRiver == river,
                      onSelected: (_) => _selectCaller(river),
                    ),
                  )
                  .toList(),
            ),
            if (_type == MeldType.chi) ...[
              const SizedBox(height: 8),
              const Text('順子'),
              Wrap(
                spacing: 6,
                children: sequences
                    .map(
                      (sequence) => Semantics(
                        label: sequence.map(tileLabel).join('、'),
                        child: ChoiceChip(
                          key: Key(
                            'chi-${sequence.map((tile) => tile.name).join('-')}',
                          ),
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: sequence
                                .map(
                                  (tile) => Padding(
                                    padding: const EdgeInsets.only(right: 2),
                                    child: MahjongTileFace(
                                      tile: tile,
                                      width: 22,
                                      height: 30,
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                          selected: _sameTiles(_sequence, sequence),
                          onSelected: (_) =>
                              setState(() => _sequence = sequence),
                        ),
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

/// 開始前の手牌または最初のドラを、入力対象として選べるカードです。
class _SetupTargetCard extends StatelessWidget {
  /// 入力領域と選択状態を受け取ってカードを生成します。
  const _SetupTargetCard({
    super.key,
    required this.label,
    required this.selected,
    required this.countLabel,
    required this.onTap,
    required this.child,
  });

  /// 入力領域の名称です。
  final String label;

  /// 現在牌パレットの入力先かどうかです。
  final bool selected;

  /// 現在枚数と上限の表示です。
  final String countLabel;

  /// 入力対象へ切り替える処理です。
  final VoidCallback onTap;

  /// カード内に表示する牌一覧です。
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (selected)
                  Text(
                    '入力中',
                    key: Key(
                      'setupActive-${label == '自分の手牌' ? 'hand' : 'doraIndicators'}',
                    ),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                const SizedBox(width: 8),
                Text(countLabel),
              ],
            ),
            const SizedBox(height: 4),
            child,
          ],
        ),
      ),
    ),
  );
}

/// 開始前カード内で入力済みの牌を直接訂正できる一覧です。
class _SetupTileStrip extends StatelessWidget {
  /// 表示する牌と削除処理を受け取って一覧を生成します。
  const _SetupTileStrip({
    super.key,
    required this.tiles,
    required this.tileKeyPrefix,
    required this.onRemove,
  });

  /// 表示する入力済みの牌です。
  final List<Tile> tiles;

  /// 牌を一意に識別するキーの接頭辞です。
  final String tileKeyPrefix;

  /// タップした牌を削除する処理です。
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 4,
    runSpacing: 4,
    children: tiles.isEmpty
        ? const [Text('牌をタップして追加')]
        : List.generate(
            tiles.length,
            (index) => _TileButton(
              key: Key('$tileKeyPrefix-$index'),
              tile: tiles[index],
              onTap: () => onRemove(index),
            ),
          ),
  );
}

/// 34種類の牌をタップ可能なパレットとして表示します。
class _TilePalette extends StatelessWidget {
  /// 牌パレットを生成します。
  const _TilePalette({
    required this.onTap,
    required this.remainingCopies,
    this.onLongPress,
    this.compact = false,
  });

  final ValueChanged<Tile> onTap;

  /// 詳細属性を付けて入力するための長押し処理です。
  final ValueChanged<Tile>? onLongPress;

  /// 見えている牌を差し引いた、各牌の未確認枚数を返します。
  final int Function(Tile) remainingCopies;

  /// 対局開始後の限られた高さへ収める表示かどうかです。
  final bool compact;

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
    padding: EdgeInsets.only(bottom: compact ? 3 : 6),
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
            fitHeight: compact ? 38 : null,
            remainingCopies: remaining,
            onTap: remaining == 0 ? null : () => onTap(tile),
            onLongPress: remaining == 0 || onLongPress == null
                ? null
                : () => onLongPress!(tile),
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
    this.onLongPress,
    this.dangerScore,
    this.dangerScoreKey,
    this.remainingCopies,
    this.paletteWidth,
    this.fitWidth,
    this.fitHeight,
  });

  final Tile tile;

  /// タップ時の処理です。残数0のパレット牌では null になります。
  final VoidCallback? onTap;

  /// 長押し時の処理です。開始後の固定手牌だけで使用します。
  final VoidCallback? onLongPress;

  /// 3人の相手について最大となる危険スコアです。
  final int? dangerScore;

  /// 固定手牌上の危険率表示を識別するキーです。
  final Key? dangerScoreKey;

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
    final isEnabled = onTap != null || onLongPress != null;
    return Semantics(
      button: true,
      enabled: isEnabled,
      excludeSemantics: true,
      label: isPaletteTile
          ? '${tileLabel(tile)}、残り$remainingCopies枚'
          : dangerScore == null
          ? tileLabel(tile)
          : '${tileLabel(tile)}、危険率$dangerScoreパーセント',
      child: InkWell(
        key: isPaletteTile ? Key('palette-${tile.name}') : null,
        onTap: onTap,
        onLongPress: onLongPress,
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
          child: Padding(
            padding: const EdgeInsets.all(1),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: Opacity(
                    opacity: isEnabled ? 1 : 0.42,
                    child: MahjongTileFace(
                      tile: tile,
                      width: fitWidth ?? (isPaletteTile ? paletteWidth : 38),
                      height: fitHeight ?? (isPaletteTile ? 56 : 52),
                    ),
                  ),
                ),
                if (isPaletteTile)
                  Positioned(
                    right: 1,
                    bottom: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Text(
                          '残$remainingCopies',
                          maxLines: 1,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: Colors.white, fontSize: 9),
                        ),
                      ),
                    ),
                  ),
                if (dangerScore != null)
                  Positioned(
                    right: 1,
                    top: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Text(
                          '$dangerScore%',
                          key: dangerScoreKey,
                          maxLines: 1,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
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

/// 開始を妨げている理由コードを画面表示用の日本語へ変換します。
String _setupIssueMessage(SetupValidationIssue issue) => switch (issue) {
  SetupValidationIssue.handEmpty => '自分の手牌を入力してください。',
  SetupValidationIssue.doraMissing => '最初のドラ表示牌を1枚選んでください。',
  SetupValidationIssue.tooManyInitialDora => '開始前のドラ表示牌は1枚にしてください。',
  SetupValidationIssue.handLimitExceeded => '親・子に応じた手牌の最大枚数を超えています。',
  SetupValidationIssue.matchFinished => '新しい対局を開始してください。',
  SetupValidationIssue.invalidVisibleTileCount => '同じ牌は局面全体で4枚までです。',
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

/// 直近局の終了理由、和了者、放銃者を通知用の文へ変換します。
String _roundResultMessage(RoundResult result) => switch (result.reason) {
  RoundEndReason.tsumo => 'ツモ：${roundSeatLabel(result.winner!)}が和了',
  RoundEndReason.ron =>
    'ロン：${roundSeatLabel(result.winner!)}が和了'
        '（放銃：${roundSeatLabel(result.loser!)}）',
  RoundEndReason.exhaustiveDraw => '流局',
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
