import 'package:image_picker/image_picker.dart';

import '../../models/uploaded_image.dart';
import '../../repositories/repositories.dart';

/// Demo uploader: nothing leaves the device.
  class MockImageUploader implements ImageUploader {
    String _id(XFile image) => 'local/${image.name}';

    @override
    Future<UploadedImage> uploadProductImage(XFile image) async =>
        UploadedImage(url: image.path, publicId: _id(image));

    @override
    Future<UploadedImage> uploadAvatar(XFile image) async =>
        UploadedImage(url: image.path, publicId: _id(image));
  }