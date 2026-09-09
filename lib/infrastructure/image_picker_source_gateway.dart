import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../application/image_source_gateway.dart';

/// Flutter公式の画像選択プラグインで静止画を取得します。
class ImagePickerSourceGateway implements ImageSourceGateway {
  /// 利用する画像選択器を受け取ります。
  ImagePickerSourceGateway({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  /// AndroidとiOSの画像選択を行うプラグインです。
  final ImagePicker _picker;

  @override
  Future<ImageAcquisitionResult> acquire(StillImageSource source) async {
    try {
      final image = await _picker.pickImage(
        source: source == StillImageSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        requestFullMetadata: false,
        imageQuality: 92,
      );
      if (image == null) {
        return const ImageAcquisitionResult.failure(
          ImageAcquisitionFailure.cancelled,
        );
      }
      return ImageAcquisitionResult.success(image.path);
    } on UnsupportedError {
      return const ImageAcquisitionResult.failure(
        ImageAcquisitionFailure.unavailable,
      );
    } on PlatformException catch (error) {
      if (error.code == 'camera_access_denied' ||
          error.code == 'photo_access_denied') {
        return const ImageAcquisitionResult.failure(
          ImageAcquisitionFailure.permissionDenied,
        );
      }
      return const ImageAcquisitionResult.failure(
        ImageAcquisitionFailure.unknown,
      );
    } catch (_) {
      return const ImageAcquisitionResult.failure(
        ImageAcquisitionFailure.unknown,
      );
    }
  }

  @override
  Future<ImageAcquisitionResult?> retrieveLostImage() async {
    try {
      final response = await _picker.retrieveLostData();
      if (response.isEmpty) return null;
      final files = response.files;
      if (files != null && files.isNotEmpty) {
        return ImageAcquisitionResult.success(files.first.path);
      }
      return const ImageAcquisitionResult.failure(
        ImageAcquisitionFailure.unknown,
      );
    } catch (_) {
      return const ImageAcquisitionResult.failure(
        ImageAcquisitionFailure.unknown,
      );
    }
  }
}
