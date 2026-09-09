import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maohjong/main.dart';
import 'package:maohjong/presentation/match_action_bar.dart';

void main() {
  testWidgets('主要操作と文脈操作を固定高さの1行に表示する', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: MatchActionBar(
            canUndo: true,
            showCall: true,
            showSelfKan: true,
            onUndo: () {},
            onCall: () {},
            onSelfKan: () {},
            onRoundEnd: () {},
            onCorrectSituation: () {},
            onAddDora: () {},
            onOpenAnalysis: () {},
            onReturnToSetup: () {},
          ),
        ),
      ),
    );

    final bar = tester.getRect(find.byKey(const Key('matchActionBar')));
    expect(bar.height, MatchActionBar.height);
    expect(find.byTooltip('取り消し'), findsOneWidget);
    expect(find.byTooltip('チー・ポン・カン'), findsOneWidget);
    expect(find.byTooltip('自分のカン'), findsOneWidget);
    expect(find.byTooltip('局終了'), findsOneWidget);
    expect(find.bySemanticsLabel('取り消し'), findsOneWidget);
    expect(find.bySemanticsLabel('その他の対局操作'), findsOneWidget);
    for (final key in [
      'undoButton',
      'callButton',
      'selfKanButton',
      'roundEndButton',
      'matchMoreMenuButton',
    ]) {
      final button = tester.getRect(find.byKey(Key(key)));
      expect(button.width, greaterThanOrEqualTo(48));
      expect(button.height, greaterThanOrEqualTo(48));
      expect(button.top, bar.top);
      expect(button.bottom, bar.bottom);
      expect(button.left, greaterThanOrEqualTo(bar.left));
      expect(button.right, lessThanOrEqualTo(bar.right));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('その他メニューから全ての補助操作を選択できる', (tester) async {
    var selected = '';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatchActionBar(
            canUndo: false,
            showCall: false,
            showSelfKan: false,
            onUndo: () => selected = 'undo',
            onCall: () => selected = 'call',
            onSelfKan: () => selected = 'selfKan',
            onRoundEnd: () => selected = 'roundEnd',
            onCorrectSituation: () => selected = 'correction',
            onAddDora: () => selected = 'dora',
            onOpenAnalysis: () => selected = 'analysis',
            onReturnToSetup: () => selected = 'setup',
            onImportImage: () => selected = 'image',
          ),
        ),
      ),
    );

    for (final entry in {
      'kanCorrectionButton': 'correction',
      'addDoraButton': 'dora',
      'staticImageInputMenuButton': 'image',
      'dangerAnalysisButton': 'analysis',
      'returnToSetupButton': 'setup',
    }.entries) {
      await tester.tap(find.byKey(const Key('matchMoreMenuButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key(entry.key)));
      await tester.pumpAndSettle();
      expect(selected, entry.value);
    }
  });

  testWidgets('小型縦画面の文字倍率1.5でも開始後にoverflowしない', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await tester.pumpWidget(const MaohjongApp());

    await tester.tap(find.byKey(const Key('dealer-upper')));
    await tester.pump();
    await _selectTargetAndAdd(tester, 'hand', 'm1');
    await _selectTargetAndAdd(tester, 'doraIndicators', 'p9');
    final start = find.byKey(const Key('startButton'));
    await tester.ensureVisible(start);
    await tester.tap(start);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('matchActionBar')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('matchActionBar'))).height,
      MatchActionBar.height,
    );
    expect(find.byKey(const Key('startedTableLayout')), findsOneWidget);
    expect(find.byKey(const Key('tilePalettePanel')), findsOneWidget);
    expect(find.byKey(const Key('persistentHand')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('小型縦画面で鳴きボタンからポンを確定できる', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaohjongApp());

    await tester.tap(find.byKey(const Key('dealer-upper')));
    await tester.pump();
    await _selectTargetAndAdd(tester, 'hand', 'm1');
    await _selectTargetAndAdd(tester, 'doraIndicators', 'p9');

    final start = find.byKey(const Key('startButton'));
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('palette-east')),
      120,
      scrollable: _startedPaletteScrollable(),
    );
    await tester.tap(find.byKey(const Key('palette-east')));
    await tester.pump();

    final callButton = find.byKey(const Key('callButton'));
    expect(callButton, findsOneWidget);
    expect(callButton.hitTestable(), findsOneWidget);
    await tester.tap(callButton);
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButton), findsNothing);
    final lowerCaller = find.byKey(const Key('callPlayer-lowerRiver'));
    expect(lowerCaller, findsOneWidget);
    await tester.tap(lowerCaller);
    await tester.pump();
    expect(tester.widget<ChoiceChip>(lowerCaller).selected, isTrue);
    await tester.tap(find.byKey(const Key('confirmCallButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('meld-lowerRiver-0')), findsOneWidget);
    expect(find.byKey(const Key('activeInput-lowerRiver')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('大明槓ではカンドラを選んでから嶺上牌入力へ進む', (tester) async {
    await tester.pumpWidget(const MaohjongApp());

    await tester.tap(find.byKey(const Key('dealer-upper')));
    await tester.pump();
    await _selectTargetAndAdd(tester, 'hand', 'm1');
    await _selectTargetAndAdd(tester, 'doraIndicators', 'p9');
    final start = find.byKey(const Key('startButton'));
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('palette-east')),
      120,
      scrollable: _startedPaletteScrollable(),
    );
    await tester.tap(find.byKey(const Key('palette-east')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('callButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('callType-kan')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('callPlayer-lowerRiver')));
    await tester.tap(find.byKey(const Key('confirmCallButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('kanDoraPickerTitle')), findsOneWidget);
    expect(find.textContaining('嶺上牌を入力する前'), findsOneWidget);
    await _selectKanDora(tester, 's9');

    expect(find.byKey(const Key('meld-lowerRiver-0')), findsOneWidget);
    expect(find.byKey(const Key('tableTile-doraIndicators-1')), findsOneWidget);
    expect(find.byKey(const Key('activeInput-lowerRiver')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// 開始前の入力領域を選択して指定牌を1枚追加します。
Future<void> _selectTargetAndAdd(
  WidgetTester tester,
  String targetName,
  String tileName,
) async {
  await tester.drag(_setupScrollable(), const Offset(0, 1000));
  await tester.pumpAndSettle();
  final target = find.byKey(Key('setupTarget-$targetName'));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pump();
  await tester.scrollUntilVisible(
    find.byKey(Key('palette-$tileName')),
    240,
    scrollable: _setupScrollable(),
  );
  await tester.tap(find.byKey(Key('palette-$tileName')));
  await tester.pump();
}

/// 開始前画面の縦スクロール要素を返します。
Finder _setupScrollable() => find.byWidgetPredicate(
  (widget) =>
      widget is Scrollable && widget.axisDirection == AxisDirection.down,
);

/// 対局開始後の牌パレット専用スクロール要素を返します。
Finder _startedPaletteScrollable() => find.descendant(
  of: find.byKey(const Key('tilePalettePanel')),
  matching: find.byType(Scrollable),
);

/// カン直後の必須ドラ選択シートから表示牌を1枚選びます。
Future<void> _selectKanDora(WidgetTester tester, String tileName) async {
  final tile = find.descendant(
    of: find.byType(BottomSheet),
    matching: find.byKey(Key('palette-$tileName')),
  );
  await tester.ensureVisible(tile);
  await tester.tap(tile);
  await tester.pumpAndSettle();
}
