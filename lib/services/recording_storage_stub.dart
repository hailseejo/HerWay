const bool isSupported = false;

Future<String> recordingsDirectoryPath() async => throw UnsupportedError(
      'Local recording storage is not supported on this platform.',
    );

Future<String> recordingFilePath(String name) async => throw UnsupportedError(
      'Local recording storage is not supported on this platform.',
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
