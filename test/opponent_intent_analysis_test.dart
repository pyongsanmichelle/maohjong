import 'package:flutter_test/flutter_test.dart';
import 'package:maohjong/application/analyze_opponent_intent_use_case.dart';
import 'package:maohjong/domain/game_situation.dart';
import 'package:maohjong/domain/meld.dart';
import 'package:maohjong/domain/match_input_flow.dart';
import 'package:maohjong/domain/opponent.dart';
import 'package:maohjong/domain/opponent_analysis_context.dart';
import 'package:maohjong/domain/opponent_intent.dart';
import 'package:maohjong/domain/round_action_history.dart';
import 'package:maohjong/domain/round_progress.dart';
import 'package:maohjong/domain/situation_editor.dart';
import 'package:maohjong/domain/tile.dart';

void main() {
  group('RoundActionHistory', () {
    test('同じ牌の打牌をIDで区別し、属性を訂正できる', () {
      final history = RoundActionHistory();
      final first = history.appendDiscard(
        actor: InputTarget.upperRiver,
        tile: Tile.m1,
        turn: 1,
      );
      final second = history.appendDiscard(
        actor: InputTarget.upperRiver,
        tile: Tile.m1,
        turn: 2,
      );

      expect(first.id, isNot(second.id));
      expect(
        history.updateDiscard(
          second.id,
          source: DiscardSource.fromHand,
          declaresRiichi: true,
        ),
        isTrue,
      );
      final updated = history.discardById(second.id)!;
      expect(updated.source, DiscardSource.fromHand);
      expect(updated.declaresRiichi, isTrue);
      expect(history.discardById(first.id)!.source, DiscardSource.unknown);

      final third = history.appendDiscard(
        actor: InputTarget.upperRiver,
        tile: Tile.m2,
        turn: 3,
        declaresRiichi: true,
      );
      expect(history.discardById(second.id)!.declaresRiichi, isFalse);
      expect(history.discardById(third.id)!.declaresRiichi, isTrue);
    });

    test('副露後も鳴かれた打牌を履歴に残し、取消時に表示へ戻す', () {
      final history = RoundActionHistory();
      final discard = history.appendDiscard(
        actor: InputTarget.upperRiver,
        tile: Tile.m3,
        turn: 4,
      );
      final meld = _meld(
        MeldType.chi,
        InputTarget.ownRiver,
        [Tile.m1, Tile.m2, Tile.m3],
        calledTile: Tile.m3,
        fromRiver: InputTarget.upperRiver,
      );

      history.appendMeld(meld: meld, calledDiscardId: discard.id);
      expect(history.discardById(discard.id)!.visibleInRiver, isFalse);
      expect(history.actions.whereType<MeldAction>(), hasLength(1));

      expect(history.removeMeld(meld), isTrue);
      expect(history.discardById(discard.id)!.visibleInRiver, isTrue);
      expect(history.actions.whereType<MeldAction>(), isEmpty);
    });

    test('MatchInputFlowの打牌属性と取り消しが履歴へ同期する', () {
      final situation = GameSituation();
      final flow = MatchInputFlow(situation);

      flow.recordDiscard(
        InputTarget.upperRiver,
        Tile.p5,
        source: DiscardSource.drawn,
        declaresRiichi: true,
      );
      final action = flow.actionHistory.actions.single as DiscardAction;
      expect(action.source, DiscardSource.drawn);
      expect(action.declaresRiichi, isTrue);

      flow.rewindTo(InputTarget.upperRiver);
      expect(flow.actionHistory.actions, isEmpty);
    });

    test('開始時の河と副露を互換履歴へ取り込み、次局で初期化する', () {
      final situation = GameSituation()
        ..hand.add(Tile.m1)
        ..doraIndicators.add(Tile.p1)
        ..upperRiver.add(Tile.s1)
        ..melds.add(
          _meld(MeldType.pon, InputTarget.upperRiver, [
            Tile.white,
            Tile.white,
            Tile.white,
          ], fromRiver: null),
        );
      final flow = MatchInputFlow(situation);

      expect(flow.start(), isTrue);
      expect(
        flow.actionHistory.actions.whereType<DiscardAction>(),
        hasLength(1),
      );
      expect(flow.actionHistory.actions.whereType<MeldAction>(), hasLength(1));

      expect(
        flow.completeWin(
          reason: RoundEndReason.tsumo,
          winner: SeatPosition.self,
        ),
        isTrue,
      );
      expect(flow.actionHistory.actions, isEmpty);
    });

    test('副露取消で河へ戻った牌をUndoすると進行履歴も巻き戻る', () {
      final situation = GameSituation();
      final editor = SituationEditor(situation);
      final flow = MatchInputFlow(situation);
      expect(editor.add(InputTarget.upperRiver, Tile.m3), isTrue);
      flow.recordDiscard(InputTarget.upperRiver, Tile.m3);
      final meld = editor.declareMeld(
        type: MeldType.pon,
        callerRiver: InputTarget.lowerRiver,
        fromRiver: InputTarget.upperRiver,
        calledTile: Tile.m3,
        tiles: const [Tile.m3, Tile.m3, Tile.m3],
      )!;
      expect(
        flow.acceptCall(MeldType.pon, InputTarget.lowerRiver, meld: meld),
        isTrue,
      );

      expect(editor.removeMeld(meld), isTrue);
      flow.restoreCallOpportunity(InputTarget.upperRiver, Tile.m3, meld: meld);
      expect(editor.canUndo, isTrue);

      final target = editor.undoLastAddition();
      expect(target, InputTarget.upperRiver);
      flow.rewindTo(target!);
      expect(situation.upperRiver, isEmpty);
      expect(flow.actionHistory.actions, isEmpty);
    });
  });

  group('OpponentAnalysisContextFactory', () {
    const factory = OpponentAnalysisContextFactory();

    test('河・副露・リーチがなければ情報なしにする', () {
      final context = factory.create(
        situation: GameSituation(),
        opponent: Opponent.upper,
        roundWind: RoundWind.east,
        dealer: SeatPosition.self,
        turn: 1,
      );

      expect(context.evidenceSufficiency, EvidenceSufficiency.none);
      expect(
        context.warnings,
        contains(OpponentAnalysisWarning.compatibilityHistory),
      );
    });

    test('打牌8枚から利用可能になり、見込み残数を求める', () {
      final situation = GameSituation();
      situation.upperRiver.addAll([
        Tile.m1,
        Tile.m2,
        Tile.m3,
        Tile.p1,
        Tile.p2,
        Tile.p3,
        Tile.s1,
        Tile.s2,
      ]);
      final context = factory.create(
        situation: situation,
        opponent: Opponent.upper,
        roundWind: RoundWind.east,
        dealer: SeatPosition.self,
        turn: 8,
      );

      expect(context.evidenceSufficiency, EvidenceSufficiency.usable);
      expect(context.remainingCopiesByTile[Tile.m1], 3);
      expect(context.discardHistory, hasLength(8));
    });

    test('河の順序が履歴と違う場合は現在局面へフォールバックする', () {
      final situation = GameSituation()..upperRiver.addAll([Tile.m1, Tile.m2]);
      final history = RoundActionHistory()
        ..appendDiscard(actor: InputTarget.upperRiver, tile: Tile.m2, turn: 1)
        ..appendDiscard(actor: InputTarget.upperRiver, tile: Tile.m1, turn: 1);

      final context = factory.create(
        situation: situation,
        opponent: Opponent.upper,
        roundWind: RoundWind.east,
        dealer: SeatPosition.self,
        turn: 1,
        actionHistory: history,
      );

      expect(
        context.warnings,
        contains(OpponentAnalysisWarning.inconsistentHistory),
      );
      expect(context.discardHistory.map((action) => action.tile), [
        Tile.m1,
        Tile.m2,
      ]);
    });

    test('副露が現在局面と違う場合は古い副露履歴を分析に使わない', () {
      final situation = GameSituation()..upperRiver.add(Tile.p1);
      final history = RoundActionHistory()
        ..appendDiscard(actor: InputTarget.upperRiver, tile: Tile.p1, turn: 1)
        ..appendMeld(
          meld: _meld(MeldType.pon, InputTarget.upperRiver, [
            Tile.white,
            Tile.white,
            Tile.white,
          ]),
        );

      final context = factory.create(
        situation: situation,
        opponent: Opponent.upper,
        roundWind: RoundWind.east,
        dealer: SeatPosition.self,
        turn: 1,
        actionHistory: history,
      );

      expect(
        context.warnings,
        contains(OpponentAnalysisWarning.inconsistentHistory),
      );
      expect(context.melds, isEmpty);
    });
  });

  group('AnalyzeOpponentIntentUseCase', () {
    const useCase = AnalyzeOpponentIntentUseCase();

    test('公開された役風刻子を成立確認の役牌として返す', () {
      final situation = GameSituation();
      situation.melds.add(
        _meld(
          MeldType.pon,
          InputTarget.upperRiver,
          [Tile.north, Tile.north, Tile.north],
          calledTile: Tile.north,
          fromRiver: InputTarget.acrossRiver,
        ),
      );

      final analysis = useCase(
        situation: situation,
        opponent: Opponent.upper,
        roundWind: RoundWind.east,
        dealer: SeatPosition.self,
        turn: 5,
      );
      final yakuhai = analysis.yakuHypotheses.firstWhere(
        (candidate) => candidate.yaku == YakuKind.yakuhai,
      );

      expect(yakuhai.score, 95);
      expect(yakuhai.level, IntentConfidenceLevel.confirmedByOpenInformation);
      expect(yakuhai.relatedTiles, [Tile.north]);
    });

    test('同色副露と他色の河から混一色候補を返す', () {
      final situation = GameSituation();
      situation.melds.addAll([
        _meld(MeldType.chi, InputTarget.upperRiver, [
          Tile.m1,
          Tile.m2,
          Tile.m3,
        ]),
        _meld(MeldType.chi, InputTarget.upperRiver, [
          Tile.m4,
          Tile.m5,
          Tile.m6,
        ]),
      ]);
      situation.upperRiver.addAll([Tile.p1, Tile.p2, Tile.s1, Tile.s2]);

      final analysis = useCase(
        situation: situation,
        opponent: Opponent.upper,
        roundWind: RoundWind.east,
        dealer: SeatPosition.self,
        turn: 6,
      );

      expect(analysis.yakuHypotheses, isNotEmpty);
      expect(analysis.yakuHypotheses.first.yaku, YakuKind.honitsu);
      expect(
        analysis.yakuHypotheses.first.positiveReasons.map(
          (reason) => reason.code,
        ),
        contains(IntentReasonCode.sameSuitMelds),
      );
    });

    test('待ち候補は残数0を除外し最大3件を決定的に返す', () {
      final situation = GameSituation();
      situation.hand.addAll([Tile.m9, Tile.m9, Tile.m9, Tile.m9]);
      situation.melds.addAll([
        _meld(MeldType.chi, InputTarget.upperRiver, [
          Tile.m1,
          Tile.m2,
          Tile.m3,
        ]),
        _meld(MeldType.chi, InputTarget.upperRiver, [
          Tile.m4,
          Tile.m5,
          Tile.m6,
        ]),
      ]);
      situation.upperRiver.addAll([Tile.p1, Tile.p2, Tile.s1, Tile.s2]);

      final first = useCase(
        situation: situation,
        opponent: Opponent.upper,
        roundWind: RoundWind.east,
        dealer: SeatPosition.self,
        turn: 8,
      );
      final second = useCase(
        situation: situation,
        opponent: Opponent.upper,
        roundWind: RoundWind.east,
        dealer: SeatPosition.self,
        turn: 8,
      );

      expect(first.waitCandidates.length, lessThanOrEqualTo(3));
      expect(
        first.waitCandidates.map((candidate) => candidate.tile),
        isNot(contains(Tile.m9)),
      );
      expect(
        second.waitCandidates.map((candidate) => candidate.tile).toList(),
        first.waitCandidates.map((candidate) => candidate.tile).toList(),
      );
      expect(
        first.waitCandidates.every(
          (candidate) => candidate.remainingCopies > 0,
        ),
        isTrue,
      );
      expect(
        first.waitCandidates.every(
          (candidate) =>
              candidate.possibleShapes.length == 1 &&
              candidate.possibleShapes.single == WaitShape.unknown,
        ),
        isTrue,
      );
    });

    test('一気通貫候補は根拠となった色だけを関連牌にする', () {
      final situation = GameSituation()
        ..melds.addAll([
          _meld(MeldType.chi, InputTarget.upperRiver, [
            Tile.m1,
            Tile.m2,
            Tile.m3,
          ]),
          _meld(MeldType.chi, InputTarget.upperRiver, [
            Tile.m4,
            Tile.m5,
            Tile.m6,
          ]),
        ]);

      final analysis = useCase(
        situation: situation,
        opponent: Opponent.upper,
        roundWind: RoundWind.east,
        dealer: SeatPosition.self,
        turn: 3,
      );
      final ittsuu = analysis.yakuHypotheses.firstWhere(
        (candidate) => candidate.yaku == YakuKind.ittsuu,
      );

      expect(ittsuu.relatedTiles, containsAll([Tile.m1, Tile.m9]));
      expect(ittsuu.relatedTiles, isNot(contains(Tile.p1)));
      expect(ittsuu.relatedTiles, isNot(contains(Tile.s1)));
    });

    test('三色同順候補は根拠となった数字範囲だけを関連牌にする', () {
      final situation = GameSituation()
        ..melds.addAll([
          _meld(MeldType.chi, InputTarget.upperRiver, [
            Tile.m1,
            Tile.m2,
            Tile.m3,
          ]),
          _meld(MeldType.chi, InputTarget.upperRiver, [
            Tile.p1,
            Tile.p2,
            Tile.p3,
          ]),
        ]);

      final analysis = useCase(
        situation: situation,
        opponent: Opponent.upper,
        roundWind: RoundWind.east,
        dealer: SeatPosition.self,
        turn: 4,
      );
      final sanshoku = analysis.yakuHypotheses.firstWhere(
        (candidate) => candidate.yaku == YakuKind.sanshokuDoujun,
      );

      expect(sanshoku.relatedTiles, containsAll([Tile.m1, Tile.p2, Tile.s3]));
      expect(sanshoku.relatedTiles, isNot(contains(Tile.m4)));
      expect(sanshoku.relatedTiles, isNot(contains(Tile.east)));
    });

    test('情報が少ない場合は待ち候補を返さない', () {
      final situation = GameSituation()..upperRiver.add(Tile.m1);
      final analysis = useCase(
        situation: situation,
        opponent: Opponent.upper,
        roundWind: RoundWind.east,
        dealer: SeatPosition.self,
        turn: 1,
      );

      expect(analysis.evidenceSufficiency, EvidenceSufficiency.low);
      expect(analysis.waitCandidates, isEmpty);
    });
  });
}

/// テスト用の公開副露を生成します。
Meld _meld(
  MeldType type,
  InputTarget owner,
  List<Tile> tiles, {
  Tile? calledTile,
  InputTarget? fromRiver,
}) => Meld(
  type: type,
  ownerRiver: owner,
  tiles: List.unmodifiable(tiles),
  calledTile: calledTile ?? tiles.last,
  fromRiver: fromRiver,
);
