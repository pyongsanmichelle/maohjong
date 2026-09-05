import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maohjong/main.dart';

void main() {
  testWidgets('開始前は危険率を表示せず手牌タップで削除する', (tester) async {
    await tester.pumpWidget(const MaohjongApp());
    await _showTilePalette(tester);
    await tester.tap(find.byKey(const Key('palette-m1')));
    await tester.pump();

    expect(find.byKey(const Key('handDangerScore-0')), findsNothing);
    expect(find.byKey(const Key('handTile-0')), findsOneWidget);

    await tester.tap(find.byKey(const Key('handTile-0')));
    await tester.pump();

    expect(find.byKey(const Key('handTile-0')), findsNothing);
  });

  testWidgets('固定手牌は3人の最大危険率を表示し長押しで理由を確認して通常タップで打牌する', (tester) async {
    await tester.pumpWidget(const MaohjongApp());

    await _selectTargetAndAdd(tester, 'lowerRiver', 'm1');
    await _selectTargetAndAdd(tester, 'hand', 'm1', copies: 2);
    await _selectTargetAndAdd(tester, 'doraIndicators', 'p9');
    await _showInputAreas(tester);
    final startButton = find.byKey(const Key('startButton'));
    await tester.ensureVisible(startButton);
    await tester.tap(startButton);
    await tester.pump();

    expect(
      tester.widget<Text>(find.byKey(const Key('handDangerScore-0'))).data,
      '50%',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('handDangerScore-1'))).data,
      '50%',
    );

    await tester.longPress(find.byKey(const Key('handTile-0')));
    await tester.pumpAndSettle();

    expect(find.text('1萬の危険情報'), findsOneWidget);
    expect(find.text('代表危険率：50%（注意）'), findsOneWidget);
    expect(find.text('下家：危険率 0%（安全）'), findsOneWidget);
    expect(find.text('対面：危険率 50%（注意）'), findsOneWidget);
    expect(find.text('上家：危険率 50%（注意）'), findsOneWidget);
    expect(find.text('・対象相手の捨て牌に同じ牌がある現物です。'), findsOneWidget);
    expect(find.text('・入力済み情報から強い安全材料が見つかりません。'), findsNWidgets(2));

    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();
    await _showTilePalette(tester);
    await tester.tap(find.byKey(const Key('palette-p1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('handTile-0')));
    await tester.pump();
    await _showInputAreas(tester);

    expect(find.text('対局入力中：下家の河を選択'), findsOneWidget);
    expect(find.text('自分の手牌 2/14枚'), findsOneWidget);
  });
}

/// 指定した入力先へ牌を必要枚数追加します。
Future<void> _selectTargetAndAdd(
  WidgetTester tester,
  String targetName,
  String tileName, {
  int copies = 1,
}) async {
  await _showInputAreas(tester);
  await tester.tap(find.byKey(Key('targetTab-$targetName')));
  await tester.pump();
  await _showTilePalette(tester);
  for (var index = 0; index < copies; index++) {
    await tester.tap(find.byKey(Key('palette-$tileName')));
    await tester.pump();
  }
}

/// 牌パレットまでスクロールします。
Future<void> _showTilePalette(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const Key('palette-red')),
    300,
    scrollable: _verticalScrollable(),
  );
  await tester.pumpAndSettle();
}

/// 画面上部の入力領域までスクロールします。
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
