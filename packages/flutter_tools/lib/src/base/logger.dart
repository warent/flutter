// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert' show ASCII;
import 'dart:io';

import 'package:stack_trace/stack_trace.dart';

final AnsiTerminal terminal = new AnsiTerminal();

abstract class Logger {
  bool get isVerbose => false;

  bool quiet = false;

  bool get supportsColor => terminal.supportsColor;
  set supportsColor(bool value) {
    terminal.supportsColor = value;
  }

  /// Display an error level message to the user. Commands should use this if they
  /// fail in some way.
  void printError(String message, [StackTrace stackTrace]);

  /// Display normal output of the command. This should be used for things like
  /// progress messages, success messages, or just normal command output.
  void printStatus(String message, { bool emphasis: false, bool newline: true });

  /// Use this for verbose tracing output. Users can turn this output on in order
  /// to help diagnose issues with the toolchain or with their setup.
  void printTrace(String message);

  /// Start an indeterminate progress display.
  Status startProgress(String message);
}

class Status {
  void stop({ bool showElapsedTime: false }) { }
  void cancel() { }
}

class StdoutLogger extends Logger {
  Status _status;

  @override
  bool get isVerbose => false;

  @override
  void printError(String message, [StackTrace stackTrace]) {
    _status?.cancel();
    _status = null;

    stderr.writeln(message);
    if (stackTrace != null)
      stderr.writeln(new Chain.forTrace(stackTrace).terse.toString());
  }

  @override
  void printStatus(String message, { bool emphasis: false, bool newline: true }) {
    _status?.cancel();
    _status = null;

    if (newline)
      stdout.writeln(emphasis ? terminal.writeBold(message) : message);
    else
      stdout.write(emphasis ? terminal.writeBold(message) : message);
  }

  @override
  void printTrace(String message) { }

  @override
  Status startProgress(String message) {
    _status?.cancel();
    _status = null;

    if (supportsColor) {
      _status = new _AnsiStatus(message);
      return _status;
    } else {
      printStatus(message);
      return new Status();
    }
  }
}

class BufferLogger extends Logger {
  @override
  bool get isVerbose => false;

  StringBuffer _error = new StringBuffer();
  StringBuffer _status = new StringBuffer();
  StringBuffer _trace = new StringBuffer();

  String get errorText => _error.toString();
  String get statusText => _status.toString();
  String get traceText => _trace.toString();

  @override
  void printError(String message, [StackTrace stackTrace]) => _error.writeln(message);

  @override
  void printStatus(String message, { bool emphasis: false, bool newline: true }) {
    if (newline)
      _status.writeln(message);
    else
      _status.write(message);
  }

  @override
  void printTrace(String message) => _trace.writeln(message);

  @override
  Status startProgress(String message) {
    printStatus(message);
    return new Status();
  }
}

class VerboseLogger extends Logger {
  Stopwatch stopwatch = new Stopwatch();

  VerboseLogger() {
    stopwatch.start();
  }

  @override
  bool get isVerbose => true;

  @override
  void printError(String message, [StackTrace stackTrace]) {
    _emit(_LogType.error, message, stackTrace);
  }

  @override
  void printStatus(String message, { bool emphasis: false, bool newline: true }) {
    _emit(_LogType.status, message);
  }

  @override
  void printTrace(String message) {
    _emit(_LogType.trace, message);
  }

  @override
  Status startProgress(String message) {
    printStatus(message);
    return new Status();
  }

  void _emit(_LogType type, String message, [StackTrace stackTrace]) {
    if (message.trim().isEmpty)
      return;

    int millis = stopwatch.elapsedMilliseconds;
    stopwatch.reset();

    String prefix;
    const int prefixWidth = 8;
    if (millis == 0) {
      prefix = ''.padLeft(prefixWidth);
    } else {
      prefix = '+$millis ms'.padLeft(prefixWidth);
      if (millis >= 100)
        prefix = terminal.writeBold(prefix);
    }
    prefix = '[$prefix] ';

    String indent = ''.padLeft(prefix.length);
    String indentMessage = message.replaceAll('\n', '\n$indent');

    if (type == _LogType.error) {
      stderr.writeln(prefix + terminal.writeBold(indentMessage));
      if (stackTrace != null)
        stderr.writeln(indent + stackTrace.toString().replaceAll('\n', '\n$indent'));
    } else if (type == _LogType.status) {
      print(prefix + terminal.writeBold(indentMessage));
    } else {
      print(prefix + indentMessage);
    }
  }
}

enum _LogType {
  error,
  status,
  trace
}

class AnsiTerminal {
  AnsiTerminal() {
    // TODO(devoncarew): This detection does not work for Windows.
    String term = Platform.environment['TERM'];
    supportsColor = term != null && term != 'dumb';
  }

  static const String KEY_F1  = '\u001BOP';
  static const String KEY_F5  = '\u001B[15~';
  static const String KEY_F10 = '\u001B[21~';

  static const String _bold  = '\u001B[1m';
  static const String _reset = '\u001B[0m';
  static const String _clear = '\u001B[2J\u001B[H';

  bool supportsColor;

  String writeBold(String str) => supportsColor ? '$_bold$str$_reset' : str;

  String clearScreen() => supportsColor ? _clear : '\n\n';

  set singleCharMode(bool value) {
    stdin.lineMode = !value;
  }

  /// Return keystrokes from the console.
  ///
  /// Useful when the console is in [singleCharMode].
  Stream<String> get onCharInput => stdin.transform(ASCII.decoder);
}

class _AnsiStatus extends Status {
  _AnsiStatus(this.message) {
    stopwatch = new Stopwatch()..start();

    stdout.write('${message.padRight(51)}     ');
    stdout.write('${_progress[0]}');

    timer = new Timer.periodic(new Duration(milliseconds: 100), _callback);
  }

  static final List<String> _progress = <String>['-', r'\', '|', r'/', '-', r'\', '|', '/'];

  final String message;
  Stopwatch stopwatch;
  Timer timer;
  int index = 1;
  bool live = true;

  void _callback(Timer timer) {
    stdout.write('\b${_progress[index]}');
    index = ++index % _progress.length;
  }

  @override
  void stop({ bool showElapsedTime: false }) {
    if (!live)
      return;
    live = false;

    if (showElapsedTime) {
      print('\b\b\b\b${stopwatch.elapsedMilliseconds.toString()}ms');
    } else {
      print('\b ');
    }

    timer.cancel();
  }

  @override
  void cancel() {
    if (!live)
      return;
    live = false;

    print('\b ');
    timer.cancel();
  }
}
