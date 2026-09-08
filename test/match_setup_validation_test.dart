import 'package:flutter_test/flutter_test.dart';
import 'package:maohjong/domain/game_situation.dart';
import 'package:maohjong/domain/match_setup_validation.dart';
import 'package:maohjong/domain/round_result.dart';
import 'package:maohjong/domain/tile.dart';

void main() {
  group('MatchSetupValidator', () {
    test('手牌と最初のドラ1枚があれば開始できる', () {
      final situation = GameSituation()
        ..hand.add(Tile.m1)
        ..doraIndicators.add(Tile.p9);

      final result = MatchSetupValidator.validate(
        situation: situation,
        dealer: SeatPosition.self,
        matchFinished: false,
      );

      expect(result.canStart, isTrue);
      expect(result.issues, isEmpty);
    });

    test('不足と開始前ドラ2枚を理由コードで返す', () {
      final empty = MatchSetupValidator.validate(
        situation: GameSituation(),
        dealer: SeatPosition.self,
        matchFinished: false,
      );
      expect(
        empty.issues,
        containsAll([
          SetupValidationIssue.handEmpty,
          SetupValidationIssue.doraMissing,
        ]),
      );

      final tooMany = GameSituation()
        ..hand.add(Tile.m1)
        ..doraIndicators.addAll([Tile.p8, Tile.p9]);
      final result = MatchSetupValidator.validate(
        situation: tooMany,
        dealer: SeatPosition.self,
        matchFinished: false,
      );
      expect(result.canStart, isFalse);
      expect(result.issues, contains(SetupValidationIssue.tooManyInitialDora));
    });

    test('子の14枚手牌と同種牌5枚を検出する', () {
      final situation = GameSituation()
        ..hand.addAll(List.filled(14, Tile.m1))
        ..doraIndicators.add(Tile.m1);

      final result = MatchSetupValidator.validate(
        situation: situation,
        dealer: SeatPosition.lower,
        matchFinished: false,
      );

      expect(result.issues, contains(SetupValidationIssue.handLimitExceeded));
      expect(
        result.issues,
        contains(SetupValidationIssue.invalidVisibleTileCount),
      );
    });
  });
}
