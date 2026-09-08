import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maohjong/main.dart';

void main() {
  testWidgets('開始後は小型縦画面に卓全体を固定配置する', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaohjongApp());

    await tester.tap(find.byKey(const Key('dealer-upper')));
    await tester.pump();
    await _selectTargetAndAdd(tester, 'doraIndicators', 'p9');
    await _selectTargetAndAdd(tester, 'hand', 'm2');

    final startButton = find.byKey(const Key('startButton'));
    await tester.ensureVisible(startButton);
    await tester.tap(startButton);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('startedTableLayout')), findsOneWidget);
    expect(find.byKey(const Key('compactRoundStatus')), findsOneWidget);
    expect(find.text('東1局・1巡目'), findsOneWidget);
    expect(find.text('親: 上家'), findsOneWidget);
    expect(find.text('残りツモ 69回'), findsOneWidget);

    for (final target in [
      'hand',
      'ownRiver',
      'upperRiver',
      'acrossRiver',
      'lowerRiver',
      'doraIndicators',
    ]) {
      expect(find.byKey(Key('targetTab-$target')), findsNothing);
    }
    for (final target in [
      'ownRiver',
      'upperRiver',
      'acrossRiver',
      'lowerRiver',
      'doraIndicators',
    ]) {
      expect(find.byKey(Key('targetArea-$target')), findsOneWidget);
    }
    expect(find.byKey(const Key('persistentHand')), findsOneWidget);
    expect(find.byKey(const Key('activeInput-upperRiver')), findsOneWidget);

    final board = tester.getRect(find.byKey(const Key('tableBoard')));
    final upper = tester.getRect(
      find.byKey(const Key('playerZone-upperRiver')),
    );
    final across = tester.getRect(
      find.byKey(const Key('playerZone-acrossRiver')),
    );
    final lower = tester.getRect(
      find.byKey(const Key('playerZone-lowerRiver')),
    );
    final own = tester.getRect(find.byKey(const Key('playerZone-ownRiver')));
    final dora = tester.getRect(find.byKey(const Key('doraZone')));

    expect(across.top, closeTo(board.top + 4, 3));
    expect(upper.left, lessThan(dora.left));
    expect(dora.right, lessThan(lower.right));
    expect(own.top, greaterThan(upper.top));
    expect(own.center.dx, closeTo(board.center.dx, 2));

    final tableTileWidth = tester
        .getSize(find.byKey(const Key('tableTile-doraIndicators-0')))
        .width;
    final paletteTileWidth = tester
        .getSize(find.byKey(const Key('palette-m1')))
        .width;
    expect(tableTileWidth, lessThanOrEqualTo(paletteTileWidth * 0.55));
  });
}

/// 開始前の手牌またはドラ領域を選び、指定した牌を1枚追加します。
Future<void> _selectTargetAndAdd(
  WidgetTester tester,
  String targetName,
  String tileName,
) async {
  await tester.drag(_verticalScrollable(), const Offset(0, 1000));
  await tester.pumpAndSettle();
  final target = find.byKey(Key('setupTarget-$targetName'));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pump();
  await tester.scrollUntilVisible(
    find.byKey(const Key('palette-red')),
    240,
    scrollable: _verticalScrollable(),
  );
  final tile = find.byKey(Key('palette-$tileName'));
  await tester.ensureVisible(tile);
  await tester.tap(tile);
  await tester.pump();
}

/// 開始前の画面全体を動かす縦スクロール要素を返します。
Finder _verticalScrollable() => find.byWidgetPredicate(
  (widget) =>
      widget is Scrollable && widget.axisDirection == AxisDirection.down,
);
