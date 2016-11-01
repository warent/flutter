// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/commands/create.dart';
import 'package:flutter_tools/src/dart/sdk.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'src/common.dart';
import 'src/context.dart';

void main() {
  group('create', () {
    Directory temp;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('flutter_tools');
    });

    tearDown(() {
      temp.deleteSync(recursive: true);
    });

    // Verify that we create a project that is well-formed.
    testUsingContext('project', () async {
      return _createAndAnalyzeProject(temp, <String>[]);
    });

    testUsingContext('project with-driver-test', () async {
      return _createAndAnalyzeProject(temp, <String>['--with-driver-test']);
    });

    // Verify content and formatting
    testUsingContext('content', () async {
      Cache.flutterRoot = '../..';

      CreateCommand command = new CreateCommand();
      CommandRunner runner = createTestCommandRunner(command);

      int code = await runner.run(<String>['create', '--no-pub', temp.path]);
      expect(code, 0);

      void expectExists(String relPath) {
        expect(FileSystemEntity.isFileSync('${temp.path}/$relPath'), true);
      }
      expectExists('lib/main.dart');
      for (FileSystemEntity file in temp.listSync(recursive: true)) {
        if (file is File && file.path.endsWith('.dart')) {
          String original= file.readAsStringSync();

          Process process = await Process.start(
              sdkBinaryName('dartfmt'),
              <String>[file.path],
              workingDirectory: temp.path,
          );
          String formatted =
            await process.stdout.transform(UTF8.decoder).join();

          expect(original, formatted, reason: file.path);
        }
      }
    });

    // Verify that we can regenerate over an existing project.
    testUsingContext('can re-gen over existing project', () async {
      Cache.flutterRoot = '../..';

      CreateCommand command = new CreateCommand();
      CommandRunner runner = createTestCommandRunner(command);

      int code = await runner.run(<String>['create', '--no-pub', temp.path]);
      expect(code, 0);

      code = await runner.run(<String>['create', '--no-pub', temp.path]);
      expect(code, 0);
    });

    // Verify that we help the user correct an option ordering issue
    testUsingContext('produces sensible error message', () async {
      Cache.flutterRoot = '../..';

      CreateCommand command = new CreateCommand();
      CommandRunner runner = createTestCommandRunner(command);

      int code = await runner.run(<String>['create', temp.path, '--pub']);
      expect(code, 2);
      expect(testLogger.errorText, contains('Try moving --pub'));
    });

    // Verify that we fail with an error code when the file exists.
    testUsingContext('fails when file exists', () async {
      Cache.flutterRoot = '../..';
      CreateCommand command = new CreateCommand();
      CommandRunner runner = createTestCommandRunner(command);
      File existingFile = new File("${temp.path.toString()}/bad");
      if (!existingFile.existsSync()) existingFile.createSync();
      int code = await runner.run(<String>['create', existingFile.path]);
      expect(code, 1);
    });
  });
}

Future<Null> _createAndAnalyzeProject(Directory dir, List<String> createArgs) async {
  Cache.flutterRoot = '../..';
  CreateCommand command = new CreateCommand();
  CommandRunner runner = createTestCommandRunner(command);
  List<String> args = <String>['create'];
  args.addAll(createArgs);
  args.add(dir.path);
  int code = await runner.run(args);
  expect(code, 0);

  String mainPath = path.join(dir.path, 'lib', 'main.dart');
  expect(new File(mainPath).existsSync(), true);
  String flutterToolsPath = path.absolute(path.join('bin', 'flutter_tools.dart'));
  ProcessResult exec = Process.runSync(
    '$dartSdkPath/bin/dart', <String>[flutterToolsPath, 'analyze'],
    workingDirectory: dir.path
  );
  if (exec.exitCode != 0) {
    print(exec.stdout);
    print(exec.stderr);
  }
  expect(exec.exitCode, 0);
}
