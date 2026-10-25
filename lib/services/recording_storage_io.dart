import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

const bool isSupported = true;

Future<Directory> _recordingsDirectory() async {
  final documents = await getApplicationDocumentsDirectory();
  return Directory(
      '${documents.path}${Platform.pathSeparator}HerWayRecordings');
}

Future<String> recordingsDirectoryPath() async =>
    (await _recordingsDirectory()).path;

Future<String> recordingFilePath(String name) async {
  final directory = await _recordingsDirectory();
  await directory.create(recursive: true);
  return '${directory.path}${Platform.pathSeparator}$name';
}

VideoPlayerController videoPlayerForFile(String path) =>
    VideoPlayerController.file(File(path));

Future<void> ensureRecordingsDirectory() async {
  await (await _recordingsDirectory()).create(recursive: true);
}

Future<void> saveRecordingFile(String sourcePath, String name) async {
  final directory = await _recordingsDirectory();
  await directory.create(recursive: true);
  final source = File(sourcePath);
  final destination = File('${directory.path}${Platform.pathSeparator}$name');
  await source.copy(destination.path);
  await source.delete();
}

Future<List<String>> listRecordings() async {
  final directory = await _recordingsDirectory();
  if (!await directory.exists()) return [];
  final files = await directory
      .list()
      .where((entity) => entity is File)
      .cast<File>()
      .toList();
  files.sort(
    (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
  );
  return files.map((file) => file.uri.pathSegments.last).toList();
}
