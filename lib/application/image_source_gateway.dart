/// 静止画を取得する方法です。
enum StillImageSource { camera, gallery }

/// 画像取得が完了しなかった理由です。
enum ImageAcquisitionFailure {
  cancelled,
  permissionDenied,
  unavailable,
  unknown,
}

/// カメラまたは端末内画像から得た一時画像参照です。
class ImageAcquisitionResult {
  /// 画像取得に成功した結果を生成します。
  const ImageAcquisitionResult.success(this.path) : failure = null;

  /// 画像取得に失敗またはキャンセルした結果を生成します。
  const ImageAcquisitionResult.failure(this.failure) : path = null;

  /// 取得した端末内画像パスです。
  final String? path;

  /// 取得できなかった理由です。
  final ImageAcquisitionFailure? failure;

  /// 画像取得に成功したかどうかです。
  bool get isSuccess => path != null;
}

/// UIから画像取得実装を差し替えるための窓口です。
abstract interface class ImageSourceGateway {
  /// 指定方法で静止画を取得します。
  Future<ImageAcquisitionResult> acquire(StillImageSource source);

  /// Androidで失われた画像取得結果があれば復元します。
  Future<ImageAcquisitionResult?> retrieveLostImage();
}
