// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:flutter_tools/src/dart/pub.dart';
import 'package:flutter_tools/src/dart/summary.dart';
import 'package:path/path.dart' as path;

import 'base/context.dart';
import 'base/logger.dart';
import 'base/net.dart';
import 'base/os.dart';
import 'globals.dart';

/// A wrapper around the `bin/cache/` directory.
class Cache {
  /// [rootOverride] is configurable for testing.
  Cache({ Directory rootOverride }) {
    this._rootOverride = rootOverride;
  }

  Directory _rootOverride;

  // Initialized by FlutterCommandRunner on startup.
  static String flutterRoot;

  // Whether to cache artifacts for all platforms. Defaults to only caching
  // artifacts for the current platform.
  bool includeAllPlatforms = false;

  static RandomAccessFile _lock;
  static bool _lockEnabled = true;

  /// Turn off the [lock]/[releaseLockEarly] mechanism.
  ///
  /// This is used by the tests since they run simultaneously and all in one
  /// process and so it would be a mess if they had to use the lock.
  static void disableLocking() {
    _lockEnabled = false;
  }

  /// Lock the cache directory.
  ///
  /// This happens automatically on startup (see [FlutterCommandRunner.runCommand]).
  ///
  /// Normally the lock will be held until the process exits (this uses normal
  /// POSIX flock semantics). Long-lived commands should release the lock by
  /// calling [Cache.releaseLockEarly] once they are no longer touching the cache.
  static Future<Null> lock() async {
    if (!_lockEnabled)
      return null;
    assert(_lock == null);
    _lock = new File(path.join(flutterRoot, 'bin', 'cache', 'lockfile')).openSync(mode: FileMode.WRITE);
    bool locked = false;
    bool printed = false;
    while (!locked) {
      try {
        await _lock.lock();
        locked = true;
      } on FileSystemException {
        if (!printed) {
          printTrace('Waiting to be able to obtain lock of Flutter binary artifacts directory: ${_lock.path}');
          printStatus('Waiting for another flutter command to release the startup lock...');
          printed = true;
        }
        await new Future<Null>.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  /// Releases the lock. This is not necessary unless the process is long-lived.
  static void releaseLockEarly() {
    if (!_lockEnabled || _lock == null)
      return;
    _lock.closeSync();
    _lock = null;
  }

  static String _dartSdkVersion;

  static String get dartSdkVersion {
    if (_dartSdkVersion == null) {
      _dartSdkVersion = Platform.version;
    }
    return _dartSdkVersion;
  }

  static String _engineRevision;

  static String get engineRevision {
    if (_engineRevision == null) {
      File revisionFile = new File(path.join(flutterRoot, 'bin', 'internal', 'engine.version'));
      if (revisionFile.existsSync())
        _engineRevision = revisionFile.readAsStringSync().trim();
    }
    return _engineRevision;
  }

  static Cache get instance => context[Cache] ?? (context[Cache] = new Cache());

  /// Return the top-level directory in the cache; this is `bin/cache`.
  Directory getRoot() {
    if (_rootOverride != null)
      return new Directory(path.join(_rootOverride.path, 'bin', 'cache'));
    else
      return new Directory(path.join(flutterRoot, 'bin', 'cache'));
  }

  /// Return a directory in the cache dir. For `pkg`, this will return `bin/cache/pkg`.
  Directory getCacheDir(String name) {
    Directory dir = new Directory(path.join(getRoot().path, name));
    if (!dir.existsSync())
      dir.createSync(recursive: true);
    return dir;
  }

  /// Return the top-level mutable directory in the cache; this is `bin/cache/artifacts`.
  Directory getCacheArtifacts() => getCacheDir('artifacts');

  /// Get a named directory from with the cache's artifact directory; for example,
  /// `material_fonts` would return `bin/cache/artifacts/material_fonts`.
  Directory getArtifactDirectory(String name) {
    return new Directory(path.join(getCacheArtifacts().path, name));
  }

  String getVersionFor(String artifactName) {
    File versionFile = new File(path.join(_rootOverride?.path ?? flutterRoot, 'bin', 'internal', '$artifactName.version'));
    return versionFile.existsSync() ? versionFile.readAsStringSync().trim() : null;
  }

  String getStampFor(String artifactName) {
    File stampFile = getStampFileFor(artifactName);
    return stampFile.existsSync() ? stampFile.readAsStringSync().trim() : null;
  }

  void setStampFor(String artifactName, String version) {
    getStampFileFor(artifactName).writeAsStringSync(version);
  }

  File getStampFileFor(String artifactName) {
    return new File(path.join(getRoot().path, '$artifactName.stamp'));
  }

  bool isUpToDate() {
    MaterialFonts materialFonts = new MaterialFonts(cache);
    FlutterEngine engine = new FlutterEngine(cache);

    return materialFonts.isUpToDate() && engine.isUpToDate();
  }

  Future<String> getThirdPartyFile(String urlStr, String serviceName, {
    bool unzip: false
  }) async {
    Uri url = Uri.parse(urlStr);
    Directory thirdPartyDir = getArtifactDirectory('third_party');

    Directory serviceDir = new Directory(path.join(thirdPartyDir.path, serviceName));
    if (!serviceDir.existsSync())
      serviceDir.createSync(recursive: true);

    File cachedFile = new File(path.join(serviceDir.path, url.pathSegments.last));
    if (!cachedFile.existsSync()) {
      try {
        await _downloadFileToCache(url, cachedFile, unzip);
      } catch (e) {
        printError('Failed to fetch third-party artifact $url: $e');
        throw e;
      }
    }

    return cachedFile.path;
  }

  Future<Null> updateAll() async {
    if (!_lockEnabled)
      return null;
    MaterialFonts materialFonts = new MaterialFonts(cache);
    if (!materialFonts.isUpToDate())
      await materialFonts.download();

    FlutterEngine engine = new FlutterEngine(cache);
    if (!engine.isUpToDate())
      await engine.download();
  }

  /// Download a file from the given url and write it to the cache.
  /// If [unzip] is true, treat the url as a zip file, and unzip it to the
  /// directory given.
  static Future<Null> _downloadFileToCache(Uri url, FileSystemEntity location, bool unzip) async {
    if (!location.parent.existsSync())
      location.parent.createSync(recursive: true);

    List<int> fileBytes = await fetchUrl(url);
    if (unzip) {
      if (location is Directory && !location.existsSync())
        location.createSync(recursive: true);

      File tempFile = new File(path.join(Directory.systemTemp.path, '${url.toString().hashCode}.zip'));
      tempFile.writeAsBytesSync(fileBytes, flush: true);
      os.unzip(tempFile, location);
      tempFile.deleteSync();
    } else {
      File file = location;
      file.writeAsBytesSync(fileBytes, flush: true);
    }
  }
}

class MaterialFonts {
  MaterialFonts(this.cache);

  static const String kName = 'material_fonts';

  final Cache cache;

  bool isUpToDate() {
    if (!cache.getArtifactDirectory(kName).existsSync())
      return false;
    return cache.getVersionFor(kName) == cache.getStampFor(kName);
  }

  Future<Null> download() {
    Status status = logger.startProgress('Downloading Material fonts...');

    Directory fontsDir = cache.getArtifactDirectory(kName);
    if (fontsDir.existsSync())
      fontsDir.deleteSync(recursive: true);

    return Cache._downloadFileToCache(
      Uri.parse(cache.getVersionFor(kName)), fontsDir, true
    ).then((_) {
      cache.setStampFor(kName, cache.getVersionFor(kName));
      status.stop(showElapsedTime: true);
    }).whenComplete(() {
      status.cancel();
    });
  }
}

class FlutterEngine {

  FlutterEngine(this.cache);

  static const String kName = 'engine';
  static const String kSkyEngine = 'sky_engine';
  static const String kSdkBundle = 'sdk.ds';

  final Cache cache;

  List<String> _getPackageDirs() => const <String>[kSkyEngine];

  List<String> _getEngineDirs() {
    List<String> dirs = <String>[
      'android-arm',
      'android-arm-profile',
      'android-arm-release',
      'android-x64',
      'android-x86',
    ];

    if (cache.includeAllPlatforms)
      dirs.addAll(<String>['ios', 'ios-profile', 'ios-release', 'linux-x64']);
    else if (Platform.isMacOS)
      dirs.addAll(<String>['ios', 'ios-profile', 'ios-release']);
    else if (Platform.isLinux)
      dirs.add('linux-x64');

    return dirs;
  }

  // Return a list of (cache directory path, download URL path) tuples.
  List<List<String>> _getToolsDirs() {
    if (cache.includeAllPlatforms)
      return <List<String>>[]
        ..addAll(_osxToolsDirs)
        ..addAll(_linuxToolsDirs);
    else if (Platform.isMacOS)
      return _osxToolsDirs;
    else if (Platform.isLinux)
      return _linuxToolsDirs;
    else
      return <List<String>>[];
  }

  List<List<String>> get _osxToolsDirs => <List<String>>[
    <String>['darwin-x64', 'darwin-x64/artifacts.zip'],
    <String>['android-arm-profile/darwin-x64', 'android-arm-profile/darwin-x64.zip'],
    <String>['android-arm-release/darwin-x64', 'android-arm-release/darwin-x64.zip'],
  ];

  List<List<String>> get _linuxToolsDirs => <List<String>>[
    <String>['linux-x64', 'linux-x64/artifacts.zip'],
    <String>['android-arm-profile/linux-x64', 'android-arm-profile/linux-x64.zip'],
    <String>['android-arm-release/linux-x64', 'android-arm-release/linux-x64.zip'],
  ];

  bool isUpToDate() {
    Directory pkgDir = cache.getCacheDir('pkg');
    for (String pkgName in _getPackageDirs()) {
      String pkgPath = path.join(pkgDir.path, pkgName);
      String dotPackagesPath = path.join(pkgPath, '.packages');
      if (!new Directory(pkgPath).existsSync())
        return false;
      if (!new File(dotPackagesPath).existsSync())
        return false;
    }

    if (!new File(path.join(pkgDir.path, kSkyEngine, kSdkBundle)).existsSync())
      return false;

    Directory engineDir = cache.getArtifactDirectory(kName);
    for (String dirName in _getEngineDirs()) {
      Directory dir = new Directory(path.join(engineDir.path, dirName));
      if (!dir.existsSync())
        return false;
    }

    for (List<String> toolsDir in _getToolsDirs()) {
      Directory dir = new Directory(path.join(engineDir.path, toolsDir[0]));
      if (!dir.existsSync())
        return false;
    }

    return cache.getVersionFor(kName) == cache.getStampFor(kName);
  }

  Future<Null> download() async {
    String engineVersion = cache.getVersionFor(kName);
    String url = 'https://storage.googleapis.com/flutter_infra/flutter/$engineVersion/';

    Directory pkgDir = cache.getCacheDir('pkg');
    for (String pkgName in _getPackageDirs()) {
      String pkgPath = path.join(pkgDir.path, pkgName);
      Directory dir = new Directory(pkgPath);
      if (dir.existsSync())
        dir.deleteSync(recursive: true);
      await _downloadItem('Downloading package $pkgName...', url + pkgName + '.zip', pkgDir);
      await pubGet(directory: pkgPath);
    }

    Status summaryStatus = logger.startProgress('Building Dart SDK summary...');
    try {
      String skyEnginePath = path.join(pkgDir.path, kSkyEngine);
      buildSkyEngineSdkSummary(skyEnginePath, kSdkBundle);
    } finally {
      summaryStatus.stop(showElapsedTime: true);
    }

    Directory engineDir = cache.getArtifactDirectory(kName);
    if (engineDir.existsSync())
      engineDir.deleteSync(recursive: true);

    for (String dirName in _getEngineDirs()) {
      Directory dir = new Directory(path.join(engineDir.path, dirName));
      await _downloadItem('Downloading engine artifacts $dirName...',
        url + dirName + '/artifacts.zip', dir);
      File frameworkZip = new File(path.join(dir.path, 'Flutter.framework.zip'));
      if (frameworkZip.existsSync()) {
        Directory framework = new Directory(path.join(dir.path, 'Flutter.framework'));
        framework.createSync();
        os.unzip(frameworkZip, framework);
      }
    }

    for (List<String> toolsDir in _getToolsDirs()) {
      String cacheDir = toolsDir[0];
      String urlPath = toolsDir[1];
      Directory dir = new Directory(path.join(engineDir.path, cacheDir));
      await _downloadItem('Downloading $cacheDir tools...', url + urlPath, dir);
      _makeFilesExecutable(dir);
    }

    cache.setStampFor(kName, cache.getVersionFor(kName));
  }

  void _makeFilesExecutable(Directory dir) {
    for (FileSystemEntity entity in dir.listSync()) {
      if (entity is File) {
        String name = path.basename(entity.path);
        if (name == 'sky_snapshot' || name == 'sky_shell')
          os.makeExecutable(entity);
      }
    }
  }

  Future<Null> _downloadItem(String message, String url, Directory dest) {
    Status status = logger.startProgress(message);
    return Cache._downloadFileToCache(Uri.parse(url), dest, true).then((_) {
      status.stop(showElapsedTime: true);
    }).whenComplete(() {
      status.cancel();
    });
  }
}
