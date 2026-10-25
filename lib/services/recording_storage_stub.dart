import 'package:video_player/video_player.dart';

const bool isSupported = false;

Future<String> recordingsDirectoryPath() async => throw UnsupportedError(
      'Local recording storage is not supported on this platform.',
    );

Future<String> recordingFilePath(String name) async => throw UnsupportedError(
      'Local recording storage is not supported on this platform.',
    );

VideoPlayerController videoPlayerForFile(String path) => throw UnsupportedError(
      'Local video playback is not supported on this platform.',
    );

Future<void> ensureRecordingsDirectory() async => throw UnsupportedError(
      'Local recording storage is not supported on this platform.',
    );

Future<void> saveRecordingFile(String sourcePath, String name) async =>
    throw UnsupportedError(
      'Local recording storage is not supported on this platform.',
    );

Future<List<String>> listRecordings() async => throw UnsupportedError(
      'Local recording storage is not supported on this platform.',
    );
