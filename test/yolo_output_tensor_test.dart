import 'package:flutter_test/flutter_test.dart';
import 'package:maohjong/infrastructure/yolo_output_tensor.dart';

void main() {
  group('YoloOutputTensor', () {
    test('チャンネル優先出力をそのまま参照できる', () {
      final output = YoloOutputTensor.parse([
        [
          [1.0, 2.0, 3.0],
          [4.0, 5.0, 6.0],
        ],
      ], channelCount: 2);

      expect(output.anchorCount, 3);
      expect(output.valueAt(1, 2), 6.0);
      expect(output.shapeDescription, '1x2x3');
    });

    test('検出候補優先出力を転置せず参照できる', () {
      final output = YoloOutputTensor.parse([
        [
          [1.0, 4.0],
          [2.0, 5.0],
          [3.0, 6.0],
        ],
      ], channelCount: 2);

      expect(output.anchorCount, 3);
      expect(output.valueAt(1, 2), 6.0);
      expect(output.shapeDescription, '1x3x2');
    });

    test('バッチ次元が省略された出力も参照できる', () {
      final output = YoloOutputTensor.parse([
        [1.0, 2.0, 3.0],
        [4.0, 5.0, 6.0],
      ], channelCount: 2);

      expect(output.anchorCount, 3);
      expect(output.valueAt(1, 2), 6.0);
      expect(output.shapeDescription, '2x3');
    });

    test('実モデルの41チャンネル出力を受け付ける', () {
      final output = YoloOutputTensor.parse([
        List.generate(41, (channel) => [channel.toDouble(), 0.0, 0.0]),
      ], channelCount: 41);

      expect(output.channelCount, 41);
      expect(output.anchorCount, 3);
      expect(output.valueAt(40, 0), 40.0);
      expect(output.shapeDescription, '1x41x3');
    });

    test('対応できないチャンネル数は形状付きで拒否する', () {
      expect(
        () => YoloOutputTensor.parse([
          [
            [1.0, 2.0, 3.0],
            [4.0, 5.0, 6.0],
          ],
        ], channelCount: 4),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('1x2x3'),
          ),
        ),
      );
    });

    test('不揃いまたは数値以外の出力を拒否する', () {
      expect(
        () => YoloOutputTensor.parse([
          [
            [1.0, 2.0],
            [3.0],
          ],
        ], channelCount: 2),
        throwsFormatException,
      );
      expect(
        () => YoloOutputTensor.parse([
          [
            [1.0, 2.0],
            [3.0, 'invalid'],
          ],
        ], channelCount: 2),
        throwsFormatException,
      );
    });
  });
}
