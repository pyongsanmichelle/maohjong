import 'package:flutter_test/flutter_test.dart';
import 'package:maohjong/domain/game_situation.dart';
import 'package:maohjong/domain/match_input_flow.dart';
import 'package:maohjong/domain/meld.dart';
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
}
