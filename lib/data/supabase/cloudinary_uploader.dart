import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_exception.dart';
import '../../models/uploaded_image.dart';
import '../../repositories/repositories.dart';
import 'error_mapper.dart';

/// Uploads to Cloudinary using a SERVER-SIGNED ticket.
class CloudinaryUploader implements ImageUploader {
  CloudinaryUploader(this._client, {http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final SupabaseClient _client;
  final http.Client _http;

  static const int maxBytes = 5 * 1024 * 1024;

  @override
  Future<UploadedImage> uploadProductImage(XFile image) =>
      _upload(image, 'product');

  @override
  Future<UploadedImage> uploadAvatar(XFile image) =>
      _upload(image, 'avatar');

  Future<UploadedImage> _upload(XFile image, String scope) async {
    try {
      final size = await image.length();

      if (size > maxBytes) {
        throw AppException(
          'Image is too large. Please choose one under 5 MB.',
        );
      }

      final bytes = await image.readAsBytes();

      final res = await _client.functions.invoke(
        'cloudinary-sign',
        body: {'scope': scope},
      );

      final t = res.data;

      if (t is! Map) {
        throw AppException(
          'Could not prepare the upload. Please try again.',
        );
      }

      final overwrite = t['overwrite'] == true;

      final request = http.MultipartRequest(
        'POST',
        Uri.parse(t['uploadUrl'] as String),
      )
        ..fields.addAll({
          'api_key': '${t['apiKey']}',
          'timestamp': '${t['timestamp']}',
          'signature': '${t['signature']}',
          'public_id': '${t['publicId']}',
          'allowed_formats': '${t['allowedFormats']}',
          'overwrite': '$overwrite',
          if (overwrite) 'invalidate': 'true',
        })
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            bytes,
            filename: image.name,
          ),
        );

      final streamed = await _http
          .send(request)
          .timeout(const Duration(seconds: 60));

      final response = await http.Response.fromStream(streamed);
      final body = jsonDecode(response.body);

      if (response.statusCode != 200 ||
          body is! Map ||
          body['secure_url'] is! String) {
        throw AppException('Image upload failed. Please try again.');
      }

      if (body['public_id'] != t['publicId']) {
        throw AppException('Image upload failed. Please try again.');
      }

      return UploadedImage(
        url: body['secure_url'] as String,
        publicId: body['public_id'] as String,
      );
    } catch (e) {
      throw appExceptionFrom(e);
    }
  }
}