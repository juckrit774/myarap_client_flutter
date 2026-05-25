import 'dart:io';

class ImageModel {
  final String id;
  final String path;

  const ImageModel({required this.id, required this.path});

  File get file => File(path);
  String get fileName => path.split(Platform.pathSeparator).last;
}
