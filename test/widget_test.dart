import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maohjong/main.dart';

void main() {
  testWidgets('局と巡目は初期値を表示し変更できる', (tester) async {
    await tester.pumpWidget(const MaohjongApp());

    expect(find.text('東1局・1巡目'), findsOneWidget);
    expect(find.text('残りツモ 69回'), findsOneWidget);

    await tester.tap(find.text('南場'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('kyokuSelector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('4局').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('turnSelector')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('18巡目'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('18巡目').last);
    await tester.pumpAndSettle();

    expect(find.text('南4局・18巡目'), findsOneWidget);
    expect(find.text('残りツモ 1回'), findsOneWidget);
  });

  testWidgets('牌をタップすると初期選択の手牌へ追加できる', (tester) async {
    await tester.pumpWidget(const MaohjongApp());
    await _showTilePalette(tester);

    await tester.tap(find.byKey(const Key('palette-m1')));
    await tester.pump();
    await _showInputAreas(tester);

    expect(
      find.descendant(
        of: find.byKey(const Key('targetArea-hand')),
        matching: find.text('1萬'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('タブ切替時は選択中の牌領域だけを表示する', (tester) async {
    await tester.pumpWidget(const MaohjongApp());

    expect(find.text('牌パレットから手牌を追加'), findsOneWidget);
    expect(find.text('自分の河'), findsNothing);

    await tester.tap(find.byKey(const Key('targetTab-ownRiver')));
    await tester.pump();

    expect(find.text('自分の河'), findsOneWidget);
    expect(find.text('上家の河'), findsNothing);
    expect(find.text('牌をタップして追加'), findsOneWidget);
  });

  testWidgets('開始後は親の河から自動切替し取り消しで戻る', (tester) async {
    await tester.pumpWidget(const MaohjongApp());

    await tester.tap(find.byKey(const Key('dealer-lower')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('targetTab-doraIndicators')));
    await tester.pump();
    await _showTilePalette(tester);
    await tester.tap(find.byKey(const Key('palette-p9')));
    await tester.pump();
    await _showInputAreas(tester);
    await tester.tap(find.byKey(const Key('targetTab-hand')));
    await tester.pump();
    await _showTilePalette(tester);
    await tester.tap(find.byKey(const Key('palette-m1')));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const Key('targetArea-hand')),
        matching: find.text('1萬'),
      ),
      findsOneWidget,
    );
    final startButton = find.byKey(const Key('startButton'));
    await tester.ensureVisible(startButton);
    expect(tester.widget<FilledButton>(startButton).onPressed, isNotNull);
    await tester.tap(startButton);
    await tester.pump();
    await _showInputAreas(tester);

    expect(find.text('対局入力中：下家の河を選択'), findsOneWidget);
    await _showTilePalette(tester);
    await tester.tap(find.byKey(const Key('palette-p1')));
    await tester.pump();
    await _showInputAreas(tester);
    expect(find.text('対局入力中：対面の河を選択'), findsOneWidget);

    await tester.tap(find.text('取り消し'));
    await tester.pump();
    expect(find.text('対局入力中：下家の河を選択'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('targetArea-lowerRiver')),
        matching: find.text('1筒'),
      ),
      findsNothing,
    );
  });

  testWidgets('自分の番は固定表示の手牌から打牌し取り消しで戻せる', (tester) async {
    await tester.pumpWidget(const MaohjongApp());

    await tester.tap(find.byKey(const Key('targetTab-doraIndicators')));
    await tester.pump();
    await _showTilePalette(tester);
    await tester.tap(find.byKey(const Key('palette-p9')));
    await tester.pump();
    await _showInputAreas(tester);
    await tester.tap(find.byKey(const Key('targetTab-hand')));
    await tester.pump();
    await _showTilePalette(tester);
    await tester.tap(find.byKey(const Key('palette-m1')));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const Key('targetArea-hand')),
        matching: find.text('1萬'),
      ),
      findsOneWidget,
    );
    final ownTurnStartButton = find.byKey(const Key('startButton'));
    await tester.ensureVisible(ownTurnStartButton);
    expect(
      tester.widget<FilledButton>(ownTurnStartButton).onPressed,
      isNotNull,
    );
    expect(
      tester.getBottomRight(ownTurnStartButton).dy,
      lessThanOrEqualTo(
        tester.getTopLeft(find.byKey(const Key('persistentHand'))).dy,
      ),
      reason: '開始ボタンが固定手牌に隠れないこと',
    );
    await tester.tap(ownTurnStartButton);
    await tester.pump();
    await _showInputAreas(tester);

    final matchInputStatus = find.byKey(const Key('matchInputStatus'));
    expect(matchInputStatus, findsOneWidget);
    expect(tester.widget<Text>(matchInputStatus).data, '対局入力中：ツモ牌を選択');
    expect(find.text('残りツモ 69回'), findsOneWidget);
    final handTile = find.descendant(
      of: find.byKey(const Key('targetArea-hand')),
      matching: find.text('1萬'),
    );
    expect(handTile, findsOneWidget);
    await tester.tap(handTile);
    await tester.pump();
    expect(find.text('先にツモ牌を選択してください。'), findsOneWidget);
    expect(handTile, findsOneWidget);

    await _showTilePalette(tester);
    await tester.tap(find.byKey(const Key('palette-p1')));
    await tester.pump();
    await _showInputAreas(tester);
    expect(find.text('対局入力中：手牌から自分の打牌を選択'), findsOneWidget);
    expect(find.text('残りツモ 68回'), findsOneWidget);
    await tester.tap(handTile);
    await tester.pump();

    expect(find.text('対局入力中：下家の河を選択'), findsOneWidget);
    expect(handTile, findsNothing);
    await tester.ensureVisible(find.text('取り消し'));
    await tester.tap(find.text('取り消し'));
    await tester.pump();
    await _showInputAreas(tester);

    expect(find.text('対局入力中：手牌から自分の打牌を選択'), findsOneWidget);
    expect(handTile, findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('targetArea-ownRiver')),
        matching: find.text('1萬'),
      ),
      findsNothing,
    );
  });

  testWidgets('ポンした人へ手番を移し河とは別の副露へ配置する', (tester) async {
    await tester.pumpWidget(const MaohjongApp());

    await tester.tap(find.byKey(const Key('targetTab-doraIndicators')));
    await tester.pump();
    await _showTilePalette(tester);
    await tester.tap(find.byKey(const Key('palette-p9')));
    await tester.pump();
    await _showInputAreas(tester);
    await tester.tap(find.byKey(const Key('targetTab-hand')));
    await tester.pump();
    await _showTilePalette(tester);
    await tester.tap(find.byKey(const Key('palette-m1')));
    await tester.pump();
    final startButton = find.byKey(const Key('startButton'));
    await tester.ensureVisible(startButton);
    await tester.tap(startButton);
    await tester.pump();
    await _showInputAreas(tester);
    await _showTilePalette(tester);
    await tester.tap(find.byKey(const Key('palette-p1')));
    await tester.pump();
    await _showInputAreas(tester);
    await tester.tap(find.byKey(const Key('handTile-0')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('callButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('callType-pon')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('callPlayerSelector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('対面').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmCallButton')));
    await tester.pumpAndSettle();

    expect(find.text('対局入力中：対面の河を選択'), findsOneWidget);
    expect(find.byKey(const Key('meld-acrossRiver-0')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('targetArea-acrossRiver')),
        matching: find.text('1萬'),
      ),
      findsNothing,
    );
  });

  testWidgets('自分が親のとき手牌を14枚までに制限する', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaohjongApp());
    await _showTilePalette(tester);

    for (final tileName in [
      'm1',
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
      'p3',
      'p4',
      'p5',
    ]) {
      await tester.tap(find.byKey(Key('palette-$tileName')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('palette-p6')));
    await tester.pump();

    expect(find.text('手牌は最大14枚です。'), findsOneWidget);
    expect(find.text('手牌 14/14枚'), findsOneWidget);
    final first = tester.getTopLeft(find.byKey(const Key('handTile-0')));
    final last = tester.getTopRight(find.byKey(const Key('handTile-13')));
    expect(last.dy, first.dy);
    expect(last.dx, lessThanOrEqualTo(348.1));
  });

  testWidgets('自分が子のとき手牌を13枚までに制限する', (tester) async {
    await tester.pumpWidget(const MaohjongApp());

    await tester.tap(find.byKey(const Key('dealer-upper')));
    await tester.pump();
    await _showTilePalette(tester);
    for (final tileName in [
      'm1',
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
      'p3',
      'p4',
    ]) {
      await tester.tap(find.byKey(Key('palette-$tileName')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('palette-p5')));
    await tester.pump();

    expect(find.text('手牌は最大13枚です。'), findsOneWidget);
    expect(find.text('手牌 13/13枚'), findsOneWidget);
  });

  testWidgets('複数のドラ表示牌を選び牌の残数を確認できる', (tester) async {
    await tester.pumpWidget(const MaohjongApp());

    await tester.tap(find.byKey(const Key('targetTab-doraIndicators')));
    await tester.pump();
    await _showTilePalette(tester);
    await tester.tap(find.byKey(const Key('palette-m1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('palette-m1')));
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const Key('palette-m1')),
        matching: find.text('残2'),
      ),
      findsOneWidget,
    );
    await _showInputAreas(tester);
    expect(
      find.descendant(
        of: find.byKey(const Key('targetArea-doraIndicators')),
        matching: find.text('1萬'),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('自分の河を選択して牌を追加できる', (tester) async {
    await tester.pumpWidget(const MaohjongApp());

    await tester.tap(find.byKey(const Key('targetTab-ownRiver')));
    await tester.pump();
    await _showTilePalette(tester);
    await tester.tap(find.byKey(const Key('palette-p1')));
    await tester.pump();
    await _showInputAreas(tester);

    expect(
      find.descendant(
        of: find.byKey(const Key('targetArea-ownRiver')),
        matching: find.text('1筒'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('入力先を切り替えて河の牌を削除できる', (tester) async {
    await tester.pumpWidget(const MaohjongApp());

    await tester.tap(find.byKey(const Key('targetTab-upperRiver')));
    await tester.pump();
    await _showTilePalette(tester);
    await tester.tap(find.text('東').last);
    await tester.pump();
    await _showInputAreas(tester);
    final riverEast = find.descendant(
      of: find.byKey(const Key('targetArea-upperRiver')),
      matching: find.text('東'),
    );
    expect(riverEast, findsOneWidget);

    await tester.tap(riverEast);
    await tester.pump();
    expect(riverEast, findsNothing);
  });

  testWidgets('最後の追加を取り消せる', (tester) async {
    await tester.pumpWidget(const MaohjongApp());
    await _showTilePalette(tester);

    await tester.tap(find.byKey(const Key('palette-m1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('palette-m2')));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('取り消し'),
      -300,
      scrollable: _verticalScrollable(),
    );
    await tester.tap(find.text('取り消し'));
    await tester.pump();
    await _showInputAreas(tester);

    final handArea = find.byKey(const Key('targetArea-hand'));
    expect(
      find.descendant(of: handArea, matching: find.text('1萬')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: handArea, matching: find.text('2萬')),
      findsNothing,
    );
  });

  testWidgets('残数0の牌はパレットで選択できない', (tester) async {
    await tester.pumpWidget(const MaohjongApp());
    await tester.tap(find.byKey(const Key('targetTab-upperRiver')));
    await tester.pump();
    await _showTilePalette(tester);

    for (var index = 0; index < 4; index++) {
      await tester.tap(find.byKey(const Key('palette-white')));
      await tester.pump();
    }

    expect(
      find.descendant(
        of: find.byKey(const Key('palette-white')),
        matching: find.text('残0'),
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<InkWell>(find.byKey(const Key('palette-white'))).onTap,
      isNull,
    );
  });

  testWidgets('数牌のパレットは横一列に9枚表示する', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaohjongApp());
    await _showTilePalette(tester);

    final first = tester.getTopLeft(find.byKey(const Key('palette-m1')));
    final last = tester.getTopRight(find.byKey(const Key('palette-m9')));

    expect(last.dy, first.dy);
    expect(last.dx, lessThanOrEqualTo(344));
  });
}

/// 画面下部の牌パレットまでスクロールします。
Future<void> _showTilePalette(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const Key('palette-red')),
    300,
    scrollable: _verticalScrollable(),
  );
  await tester.pumpAndSettle();
}

/// 入力済みの手牌と河が表示される画面上部までスクロールします。
Future<void> _showInputAreas(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('東1局・1巡目'),
    -300,
    scrollable: _verticalScrollable(),
  );
  await tester.pumpAndSettle();
}

/// 画面本体のListViewが使用する縦スクロール要素を返します。
Finder _verticalScrollable() => find.byWidgetPredicate(
  (widget) =>
      widget is Scrollable && widget.axisDirection == AxisDirection.down,
);
