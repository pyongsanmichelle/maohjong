/// YOLOの検出出力を、チャンネル優先の読み取り方法へ正規化します。
///
/// ONNXのエクスポート方法によって `[1, channels, anchors]` と
/// `[1, anchors, channels]` の両方があり得るため、配列を複製せずに
/// 同じインターフェースで参照できるようにします。
class YoloOutputTensor {
  /// 検証済みの出力テンソルを生成します。
  const YoloOutputTensor._({
    required List rows,
    required this.channelCount,
    required this.anchorCount,
    required bool channelsFirst,
    required this.shapeDescription,
  }) : _rows = rows,
       _channelsFirst = channelsFirst;

  /// ONNX Runtimeから得た値を検証し、対応する配置へ正規化します。
  factory YoloOutputTensor.parse(Object? value, {required int channelCount}) {
    final shape = describeShape(value);
    if (value is! List || value.isEmpty || value.first is! List) {
      throw FormatException('invalid_output_shape:$shape');
    }
    final rows = value.length == 1 && value.first is List
        ? value.first as List
        : value;
    if (rows.isEmpty || rows.first is! List) {
      throw FormatException('invalid_output_shape:$shape');
    }
    final firstRow = rows.first as List;
    if (firstRow.isEmpty) {
      throw FormatException('invalid_output_shape:$shape');
    }

    final channelsFirst = rows.length == channelCount;
    final anchorsFirst = firstRow.length == channelCount;
    if (!channelsFirst && !anchorsFirst) {
      throw FormatException('invalid_channel_count:$shape');
    }
    final expectedRowLength = channelsFirst ? firstRow.length : channelCount;
    for (final row in rows) {
      if (row is! List || row.length != expectedRowLength) {
        throw FormatException('ragged_output:$shape');
      }
      if (row.any((element) => element is! num)) {
        throw FormatException('non_numeric_output:$shape');
      }
    }

    return YoloOutputTensor._(
      rows: rows,
      channelCount: channelCount,
      anchorCount: channelsFirst ? firstRow.length : rows.length,
      channelsFirst: channelsFirst,
      shapeDescription: shape,
    );
  }

  /// 座標4個とクラススコアを合わせたチャンネル数です。
  final int channelCount;

  /// モデルが返した検出候補数です。
  final int anchorCount;

  /// 個人情報や推論値を含まない配列形状です。
  final String shapeDescription;

  /// ONNX Runtimeから取得した二次元配列です。
  final List _rows;

  /// `true` の場合、配列は `[channels, anchors]` の順です。
  final bool _channelsFirst;

  /// 指定したチャンネルと検出候補の数値を返します。
  double valueAt(int channel, int anchor) {
    final value = _channelsFirst
        ? (_rows[channel] as List)[anchor]
        : (_rows[anchor] as List)[channel];
    return (value as num).toDouble();
  }

  /// 値を含めず、入れ子配列の長さだけを診断文字列へ変換します。
  static String describeShape(Object? value) {
    final dimensions = <int>[];
    Object? current = value;
    while (current is List) {
      dimensions.add(current.length);
      if (current.isEmpty) break;
      current = current.first;
    }
    final type = value.runtimeType.toString();
    return dimensions.isEmpty ? 'type=$type' : dimensions.join('x');
  }
}
