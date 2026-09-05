import 'package:flutter_test/flutter_test.dart';
import 'package:maohjong/domain/game_situation.dart';
import 'package:maohjong/domain/match_input_flow.dart';
import 'package:maohjong/domain/meld.dart';
import 'package:maohjong/domain/round_progress.dart';
import 'package:maohjong/domain/tile.dart';

void main() {
  test('親の河から打牌順に入力先を切り替える', () {
    final situation = GameSituation()
      ..hand.add(Tile.m1)
      ..doraIndicators.add(Tile.p1);
    final flow = MatchInputFlow(situation);

    expect(flow.selectDealer(SeatPosition.lower), isTrue);
    expect(flow.handLimit, 13);
    expect(flow.start(), isTrue);
    expect(flow.currentRiver, InputTarget.lowerRiver);

    flow.advanceRiver();
    expect(flow.currentRiver, InputTarget.acrossRiver);
    flow.advanceRiver();
    expect(flow.currentRiver, InputTarget.upperRiver);
    flow.advanceRiver();
    expect(flow.currentRiver, InputTarget.ownRiver);
    expect(flow.ownDrawRequired, isTrue);
    expect(flow.canOwnDiscard, isFalse);
    expect(flow.markOwnDrawn(), isTrue);
    expect(flow.canOwnDiscard, isTrue);
  });

  test('自分が親なら14枚、子なら13枚を手牌上限にする', () {
    final situation = GameSituation()..hand.addAll(List.filled(14, Tile.m1));
    final flow = MatchInputFlow(situation);

    expect(flow.handLimit, 14);
    expect(flow.selectDealer(SeatPosition.across), isFalse);
    expect(flow.dealer, SeatPosition.self);
    expect(flow.handLimit, 14);
  });

  test('ポンとカンは鳴いた人へ移り、チーは次の人だけ選べる', () {
    final flow = MatchInputFlow(GameSituation());

    flow.recordDiscard(InputTarget.ownRiver, Tile.m3);
    expect(flow.currentRiver, InputTarget.lowerRiver);
    expect(flow.callersFor(MeldType.chi), [InputTarget.lowerRiver]);
    expect(flow.acceptCall(MeldType.chi, InputTarget.acrossRiver), isFalse);
    expect(flow.acceptCall(MeldType.pon, InputTarget.acrossRiver), isTrue);
    expect(flow.currentRiver, InputTarget.acrossRiver);
  });

  test('数牌の打牌から成立するチー候補を列挙する', () {
    final flow = MatchInputFlow(GameSituation());

    expect(flow.chiSequences(Tile.m3), [
      [Tile.m1, Tile.m2, Tile.m3],
      [Tile.m2, Tile.m3, Tile.m4],
      [Tile.m3, Tile.m4, Tile.m5],
    ]);
    expect(flow.chiSequences(Tile.east), isEmpty);
  });

  test('14枚で開始した親は初回だけツモ入力なしで打牌できる', () {
    final situation = GameSituation()
      ..hand.addAll(List.filled(14, Tile.m1))
      ..doraIndicators.add(Tile.p1);
    final flow = MatchInputFlow(situation);

    expect(flow.start(), isTrue);
    expect(flow.currentRiver, InputTarget.ownRiver);
    expect(flow.ownDrawRequired, isFalse);
    expect(flow.canOwnDiscard, isTrue);
  });

  test('自分のポン後は打牌でき、大明槓後は嶺上牌の入力を待つ', () {
    final situation = GameSituation()
      ..hand.add(Tile.m1)
      ..doraIndicators.add(Tile.p1);
    final flow = MatchInputFlow(situation);
    expect(flow.selectDealer(SeatPosition.lower), isTrue);
    expect(flow.start(), isTrue);

    flow.recordDiscard(InputTarget.upperRiver, Tile.p5);
    expect(flow.acceptCall(MeldType.pon, InputTarget.ownRiver), isTrue);
    expect(flow.canOwnDiscard, isTrue);

    flow.recordDiscard(InputTarget.upperRiver, Tile.p5);
    expect(flow.acceptCall(MeldType.kan, InputTarget.ownRiver), isTrue);
    expect(flow.ownDrawRequired, isTrue);
    expect(flow.canOwnDiscard, isFalse);
  });

  test('自分の副露数に応じて開始前と開始後の手牌上限を減らす', () {
    final situation = GameSituation()
      ..hand.addAll(List.filled(11, Tile.m1))
      ..doraIndicators.add(Tile.p1)
      ..melds.add(
        Meld(
          type: MeldType.kan,
          ownerRiver: InputTarget.ownRiver,
          tiles: List.filled(4, Tile.s1),
          calledTile: Tile.s1,
          fromRiver: null,
          kanType: KanType.concealed,
          origin: MeldOrigin.setup,
        ),
      );
    final flow = MatchInputFlow(situation);

    expect(flow.handLimit, 11);
    expect(flow.activeHandLimit, 11);
    expect(flow.start(), isTrue);
    expect(flow.canOwnDiscard, isTrue);
    expect(flow.ownDrawRequired, isFalse);
  });

  test('自分の暗槓・加槓後は嶺上牌を入力するまで打牌できない', () {
    final situation = GameSituation()
      ..hand.addAll(List.filled(14, Tile.m1))
      ..doraIndicators.add(Tile.p1);
    final flow = MatchInputFlow(situation);

    expect(flow.start(), isTrue);
    expect(flow.canOwnDiscard, isTrue);
    expect(flow.acceptSelfKan(), isTrue);
    expect(flow.ownDrawRequired, isTrue);
    expect(flow.canOwnDiscard, isFalse);
    expect(flow.cancelSelfKan(), isTrue);
    expect(flow.canOwnDiscard, isTrue);
  });

  test('ツモ上がりで結果を保持して次局へ進み局面を初期化する', () {
    final situation = GameSituation()
      ..hand.add(Tile.m1)
      ..ownRiver.add(Tile.m2)
      ..doraIndicators.add(Tile.p1);
    final flow = MatchInputFlow(situation);
    expect(flow.start(), isTrue);

    expect(
      flow.completeWin(
        reason: RoundEndReason.tsumo,
        winner: SeatPosition.across,
      ),
      isTrue,
    );

    expect(flow.started, isFalse);
    expect(flow.progress.roundWind, RoundWind.east);
    expect(flow.progress.kyoku, 2);
    expect(flow.dealer, SeatPosition.lower);
    expect(situation.hand, isEmpty);
    expect(situation.ownRiver, isEmpty);
    expect(situation.doraIndicators, isEmpty);
    expect(flow.lastRoundResult?.reason, RoundEndReason.tsumo);
    expect(flow.lastRoundResult?.winner, SeatPosition.across);
    expect(flow.lastRoundResult?.loser, isNull);
  });

  test('ロンは直前打牌を必須とし放銃者を河から自動判定する', () {
    final situation = GameSituation()
      ..hand.add(Tile.m1)
      ..doraIndicators.add(Tile.p1);
    final flow = MatchInputFlow(situation);
    expect(flow.selectDealer(SeatPosition.lower), isTrue);
    expect(flow.start(), isTrue);

    expect(
      flow.completeWin(reason: RoundEndReason.ron, winner: SeatPosition.across),
      isFalse,
    );
    expect(flow.started, isTrue);

    flow.recordDiscard(InputTarget.lowerRiver, Tile.s3);
    expect(
      flow.completeWin(reason: RoundEndReason.ron, winner: SeatPosition.across),
      isTrue,
    );
    expect(flow.lastRoundResult?.reason, RoundEndReason.ron);
    expect(flow.lastRoundResult?.winner, SeatPosition.across);
    expect(flow.lastRoundResult?.loser, SeatPosition.lower);
  });

  test('南4局のツモ上がりで半荘終了状態にする', () {
    final situation = GameSituation()
      ..hand.add(Tile.m1)
      ..doraIndicators.add(Tile.p1);
    final progress = RoundProgress(roundWind: RoundWind.south, kyoku: 4);
    final flow = MatchInputFlow(situation, progress: progress);
    expect(flow.start(), isTrue);

    expect(
      flow.completeWin(reason: RoundEndReason.tsumo, winner: SeatPosition.self),
      isTrue,
    );

    expect(progress.matchFinished, isTrue);
    expect(flow.started, isFalse);
    expect(flow.lastRoundResult?.roundWind, RoundWind.south);
    expect(flow.lastRoundResult?.kyoku, 4);
  });
}
