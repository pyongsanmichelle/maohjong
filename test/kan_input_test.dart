import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maohjong/main.dart';

void main() {
  testWidgets('開始前に既存のカンを登録して訂正できる', (tester) async {
    await tester.pumpWidget(const MaohjongApp());

    final setupKanButton = find.byKey(const Key('setupKanButton'));
    await tester.scrollUntilVisible(
      setupKanButton,
      300,
      scrollable: _verticalScrollable(),
    );
    await tester.tap(setupKanButton);
    await tester.pumpAndSettle();

    expect(find.text('開始時点のカンを登録'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmSetupKanButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('meld-ownRiver-0')), findsOneWidget);
    expect(find.textContaining('暗槓'), findsOneWidget);
    expect(find.text('手牌 0/11枚'), findsOneWidget);

    await tester.tap(find.byKey(const Key('meld-ownRiver-0')));
    await tester.pump();
    expect(find.byKey(const Key('meld-ownRiver-0')), findsNothing);
    expect(find.text('手牌 0/14枚'), findsOneWidget);
  });

  testWidgets('自分の番に暗槓すると嶺上牌入力まで打牌できない', (tester) async {
    await tester.pumpWidget(const MaohjongApp());

    await _addTile(tester, 'm1', copies: 4);
    for (final tile in [
      'm2',
      'm3',
      'm4',
      'm5',
      'm6',
      'm7',
      'm8',
      'm9',
      'p1',
      'p2',
    ]) {
      await _addTile(tester, tile);
    }
    await _showInputAreas(tester);
    await tester.tap(find.byKey(const Key('targetTab-doraIndicators')));
    await tester.pump();
    await _addTile(tester, 'p9');

    final startButton = find.byKey(const Key('startButton'));
    await tester.scrollUntilVisible(
      startButton,
      -300,
      scrollable: _verticalScrollable(),
    );
    await tester.tap(startButton);
    await tester.pump();

    final selfKanButton = find.byKey(const Key('selfKanButton'));
    await tester.ensureVisible(selfKanButton);
    expect(selfKanButton, findsOneWidget);
    await tester.tap(selfKanButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('selfKan-concealed-m1')));
    await tester.pumpAndSettle();

    expect(find.textContaining('暗槓'), findsOneWidget);
    expect(find.text('対局入力中：ツモ牌を選択'), findsOneWidget);
    expect(find.text('自分の手牌 10/11枚'), findsOneWidget);

    final handTile = find.byKey(const Key('handTile-0'));
    await tester.tap(handTile);
    await tester.pump();
    expect(find.text('先にツモ牌を選択してください。'), findsOneWidget);

    await _addTile(tester, 's1');
    expect(find.text('自分の手牌 11/11枚'), findsOneWidget);
    await _showInputAreas(tester);
    expect(
      tester.widget<Text>(find.byKey(const Key('matchInputStatus'))).data,
      '対局入力中：手牌から自分の打牌を選択',
    );
  });
}

/// 牌パレットを表示して指定牌を必要枚数追加します。
Future<void> _addTile(
  WidgetTester tester,
  String tileName, {
  int copies = 1,
}) async {
  await tester.scrollUntilVisible(
    find.byKey(const Key('palette-red')),
    300,
    scrollable: _verticalScrollable(),
  );
  await tester.pumpAndSettle();
  final tile = find.byKey(Key('palette-$tileName'));
  for (var index = 0; index < copies; index++) {
    await tester.tap(tile);
    await tester.pump();
  }
}

/// 画面上部の入力領域まで戻します。
Future<void> _showInputAreas(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('東1局・1巡目'),
    -300,
    scrollable: _verticalScrollable(),
  );
  await tester.pumpAndSettle();
}

/// 画面本体の縦スクロール要素を返します。
Finder _verticalScrollable() => find.byWidgetPredicate(
  (widget) =>
      widget is Scrollable && widget.axisDirection == AxisDirection.down,
);
