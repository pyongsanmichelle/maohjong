import 'package:flutter_test/flutter_test.dart';
import 'package:maohjong/domain/game_situation.dart';
import 'package:maohjong/domain/match_input_flow.dart';
import 'package:maohjong/domain/round_progress.dart';
import 'package:maohjong/domain/tile.dart';

void main() {
  test('通常進行では4人分の打牌で巡目を進めツモ回数を減らす', () {
    final situation = GameSituation()
      ..hand.addAll(List.filled(14, Tile.m1))
      ..doraIndicators.add(Tile.p1);
    final progress = RoundProgress();
    final flow = MatchInputFlow(situation, progress: progress);

    expect(flow.start(), isTrue);
    expect(progress.remainingDraws, 69);
    expect(flow.recordDiscard(InputTarget.ownRiver, Tile.m1), isFalse);
    expect(progress.remainingDraws, 69);
    expect(flow.recordDiscard(InputTarget.lowerRiver, Tile.m2), isFalse);
    expect(progress.remainingDraws, 68);
    expect(flow.recordDiscard(InputTarget.acrossRiver, Tile.m3), isFalse);
    expect(flow.recordDiscard(InputTarget.upperRiver, Tile.m4), isFalse);

    expect(progress.turn, 2);
    expect(progress.remainingDraws, 66);
    expect(flow.ownDrawRequired, isTrue);
    expect(flow.markOwnDrawn(), isTrue);
    expect(progress.remainingDraws, 65);
  });

  test('残りツモが尽きた最後の打牌後に次局へ進み局面を初期化する', () {
    final situation = GameSituation()
      ..hand.addAll(List.filled(14, Tile.m1))
      ..doraIndicators.add(Tile.p1);
    final progress = RoundProgress(turn: 18);
    final flow = MatchInputFlow(situation, progress: progress);

    expect(progress.remainingDraws, 1);
    expect(flow.start(), isTrue);
    expect(flow.recordDiscard(InputTarget.ownRiver, Tile.m1), isFalse);
    expect(flow.recordDiscard(InputTarget.lowerRiver, Tile.m2), isTrue);

    expect(progress.roundWind, RoundWind.east);
    expect(progress.kyoku, 2);
    expect(progress.turn, 1);
    expect(progress.remainingDraws, 69);
    expect(flow.dealer, SeatPosition.lower);
    expect(flow.started, isFalse);
    expect(situation.hand, isEmpty);
    expect(situation.doraIndicators, isEmpty);
    expect(flow.lastRoundResult?.reason, RoundEndReason.exhaustiveDraw);
    expect(flow.lastRoundResult?.winner, isNull);
  });

  test('開始巡目を変更すると残りツモ回数を概算し直す', () {
    final progress = RoundProgress();

    progress.selectTurn(6);

    expect(progress.turn, 6);
    expect(progress.remainingDraws, 49);
  });

  test('相手の打牌を取り消すとツモ回数と巡目進行も元へ戻す', () {
    final situation = GameSituation()
      ..hand.add(Tile.m1)
      ..doraIndicators.add(Tile.p1);
    final progress = RoundProgress();
    final flow = MatchInputFlow(situation, progress: progress);
    expect(flow.selectDealer(SeatPosition.lower), isTrue);
    expect(flow.start(), isTrue);

    expect(flow.recordDiscard(InputTarget.lowerRiver, Tile.m2), isFalse);
    expect(flow.recordDiscard(InputTarget.acrossRiver, Tile.m3), isFalse);
    expect(progress.remainingDraws, 68);

    flow.rewindTo(InputTarget.acrossRiver);

    expect(progress.remainingDraws, 69);
    expect(progress.turn, 1);
    expect(flow.currentRiver, InputTarget.acrossRiver);
  });
}
