// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'android/android_device.dart';
import 'application_package.dart';
import 'base/common.dart';
import 'base/os.dart';
import 'base/utils.dart';
import 'build_info.dart';
import 'globals.dart';
import 'vmservice.dart';
import 'ios/devices.dart';
import 'ios/simulators.dart';

/// A class to get all available devices.
class DeviceManager {
  /// Constructing DeviceManagers is cheap; they only do expensive work if some
  /// of their methods are called.
  DeviceManager() {
    // Register the known discoverers.
    _deviceDiscoverers.add(new AndroidDevices());
    _deviceDiscoverers.add(new IOSDevices());
    _deviceDiscoverers.add(new IOSSimulators());
  }

  List<DeviceDiscovery> _deviceDiscoverers = <DeviceDiscovery>[];

  /// A user-specified device ID.
  String specifiedDeviceId;

  bool get hasSpecifiedDeviceId => specifiedDeviceId != null;

  /// Return the devices with a name or id matching [deviceId].
  /// This does a case insentitive compare with [deviceId].
  Future<List<Device>> getDevicesById(String deviceId) async {
    deviceId = deviceId.toLowerCase();
    List<Device> devices = await getAllConnectedDevices();
    Device device = devices.firstWhere(
        (Device device) =>
            device.id.toLowerCase() == deviceId ||
            device.name.toLowerCase() == deviceId,
        orElse: () => null);

    if (device != null)
      return <Device>[device];

    // Match on a id or name starting with [deviceId].
    return devices.where((Device device) {
      return (device.id.toLowerCase().startsWith(deviceId) ||
        device.name.toLowerCase().startsWith(deviceId));
    }).toList();
  }

  /// Return the list of connected devices, filtered by any user-specified device id.
  Future<List<Device>> getDevices() async {
    if (specifiedDeviceId == null) {
      return getAllConnectedDevices();
    } else {
      return getDevicesById(specifiedDeviceId);
    }
  }

  /// Return the list of all connected devices.
  Future<List<Device>> getAllConnectedDevices() async {
    return _deviceDiscoverers
      .where((DeviceDiscovery discoverer) => discoverer.supportsPlatform)
      .expand((DeviceDiscovery discoverer) => discoverer.devices)
      .toList();
  }
}

/// An abstract class to discover and enumerate a specific type of devices.
abstract class DeviceDiscovery {
  bool get supportsPlatform;
  List<Device> get devices;
}

/// A [DeviceDiscovery] implementation that uses polling to discover device adds
/// and removals.
abstract class PollingDeviceDiscovery extends DeviceDiscovery {
  PollingDeviceDiscovery(this.name);

  static const Duration _pollingDuration = const Duration(seconds: 4);

  final String name;
  ItemListNotifier<Device> _items;
  Timer _timer;

  List<Device> pollingGetDevices();

  void startPolling() {
    if (_timer == null) {
      if (_items == null)
        _items = new ItemListNotifier<Device>();
      _timer = new Timer.periodic(_pollingDuration, (Timer timer) {
        _items.updateWithNewList(pollingGetDevices());
      });
    }
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  List<Device> get devices {
    if (_items == null)
      _items = new ItemListNotifier<Device>.from(pollingGetDevices());
    return _items.items;
  }

  Stream<Device> get onAdded {
    if (_items == null)
      _items = new ItemListNotifier<Device>();
    return _items.onAdded;
  }

  Stream<Device> get onRemoved {
    if (_items == null)
      _items = new ItemListNotifier<Device>();
    return _items.onRemoved;
  }

  void dispose() => stopPolling();

  @override
  String toString() => '$name device discovery';
}

abstract class Device {
  Device(this.id);

  final String id;

  String get name;

  bool get supportsStartPaused => true;

  /// Whether it is an emulated device running on localhost.
  bool get isLocalEmulator;

  /// Check if a version of the given app is already installed
  bool isAppInstalled(ApplicationPackage app);

  /// Install an app package on the current device
  bool installApp(ApplicationPackage app);

  /// Uninstall an app package from the current device
  bool uninstallApp(ApplicationPackage app);

  /// Check if the device is supported by Flutter
  bool isSupported();

  // String meant to be displayed to the user indicating if the device is
  // supported by Flutter, and, if not, why.
  String supportMessage() => isSupported() ? "Supported" : "Unsupported";

  TargetPlatform get platform;

  String get sdkNameAndVersion;

  /// Get the log reader for this device.
  DeviceLogReader get logReader;

  /// Get the port forwarder for this device.
  DevicePortForwarder get portForwarder;

  /// Clear the device's logs.
  void clearLogs();

  /// Start an app package on the current device.
  ///
  /// [platformArgs] allows callers to pass platform-specific arguments to the
  /// start call. The build mode is not used by all platforms.
  Future<LaunchResult> startApp(
    ApplicationPackage package,
    BuildMode mode, {
    String mainPath,
    String route,
    DebuggingOptions debuggingOptions,
    Map<String, dynamic> platformArgs,
    bool prebuiltApplication: false
  });

  /// Does this device implement support for hot reloading / restarting?
  bool get supportsHotMode => false;

  /// Run from a file. Necessary for hot mode.
  Future<bool> runFromFile(ApplicationPackage package,
                           String scriptUri,
                           String packagesUri) {
    throw 'runFromFile unsupported';
  }

  bool get supportsRestart => false;

  bool get restartSendsFrameworkInitEvent => true;

  /// Restart the given app; the application will already have been launched with
  /// [startApp].
  Future<bool> restartApp(
    ApplicationPackage package,
    LaunchResult result, {
    String mainPath,
    VMService observatory,
    bool prebuiltApplication: false
  }) async {
    throw 'unsupported';
  }

  /// Stop an app package on the current device.
  Future<bool> stopApp(ApplicationPackage app);

  bool get supportsScreenshot => false;

  Future<bool> takeScreenshot(File outputFile) => new Future<bool>.error('unimplemented');

  /// Find the apps that are currently running on this device.
  Future<List<DiscoveredApp>> discoverApps() =>
      new Future<List<DiscoveredApp>>.value(<DiscoveredApp>[]);

  @override
  int get hashCode => id.hashCode;

  @override
  bool operator ==(dynamic other) {
    if (identical(this, other))
      return true;
    if (other is! Device)
      return false;
    return id == other.id;
  }

  @override
  String toString() => name;

  static Iterable<String> descriptions(List<Device> devices) {
    if (devices.isEmpty)
      return <String>[];

    // Extract device information
    List<List<String>> table = <List<String>>[];
    for (Device device in devices) {
      String supportIndicator = device.isSupported() ? '' : ' (unsupported)';
      if (device.isLocalEmulator) {
        String type = device.platform == TargetPlatform.ios ? 'simulator' : 'emulator';
        supportIndicator += ' ($type)';
      }
      table.add(<String>[
        device.name,
        device.id,
        '${getNameForTargetPlatform(device.platform)}',
        '${device.sdkNameAndVersion}$supportIndicator',
      ]);
    }

    // Calculate column widths
    List<int> indices = new List<int>.generate(table[0].length - 1, (int i) => i);
    List<int> widths = indices.map((int i) => 0).toList();
    for (List<String> row in table) {
      widths = indices.map((int i) => math.max(widths[i], row[i].length)).toList();
    }

    // Join columns into lines of text
    return table.map((List<String> row) =>
        indices.map((int i) => row[i].padRight(widths[i])).join(' • ') +
        ' • ${row.last}');
  }

  static void printDevices(List<Device> devices) {
    descriptions(devices).forEach((String msg) => printStatus(msg));
  }
}

class DebuggingOptions {
  DebuggingOptions.enabled(this.buildMode, {
    this.startPaused: false,
    this.observatoryPort,
    this.diagnosticPort
   }) : debuggingEnabled = true;

  DebuggingOptions.disabled(this.buildMode) :
    debuggingEnabled = false,
    startPaused = false,
    observatoryPort = null,
    diagnosticPort = null;

  final bool debuggingEnabled;

  final BuildMode buildMode;
  final bool startPaused;
  final int observatoryPort;
  final int diagnosticPort;

  bool get hasObservatoryPort => observatoryPort != null;

  /// Return the user specified observatory port. If that isn't available,
  /// return [kDefaultObservatoryPort], or a port close to that one.
  Future<int> findBestObservatoryPort() {
    if (hasObservatoryPort)
      return new Future<int>.value(observatoryPort);
    return findPreferredPort(observatoryPort ?? kDefaultObservatoryPort);
  }

  bool get hasDiagnosticPort => diagnosticPort != null;

  /// Return the user specified diagnostic port. If that isn't available,
  /// return [kDefaultDiagnosticPort], or a port close to that one.
  Future<int> findBestDiagnosticPort() {
    return findPreferredPort(diagnosticPort ?? kDefaultDiagnosticPort);
  }
}

class LaunchResult {
  LaunchResult.succeeded({ this.observatoryPort, this.diagnosticPort }) : started = true;
  LaunchResult.failed() : started = false, observatoryPort = null, diagnosticPort = null;

  bool get hasObservatory => observatoryPort != null;

  final bool started;
  final int observatoryPort;
  final int diagnosticPort;

  @override
  String toString() {
    StringBuffer buf = new StringBuffer('started=$started');
    if (observatoryPort != null)
      buf.write(', observatory=$observatoryPort');
    if (diagnosticPort != null)
      buf.write(', diagnostic=$diagnosticPort');
    return buf.toString();
  }
}

class ForwardedPort {
  ForwardedPort(this.hostPort, this.devicePort) : context = null;
  ForwardedPort.withContext(this.hostPort, this.devicePort, this.context);

  final int hostPort;
  final int devicePort;
  final dynamic context;

  @override
  String toString() => 'ForwardedPort HOST:$hostPort to DEVICE:$devicePort';
}

/// Forward ports from the host machine to the device.
abstract class DevicePortForwarder {
  /// Returns a Future that completes with the current list of forwarded
  /// ports for this device.
  List<ForwardedPort> get forwardedPorts;

  /// Forward [hostPort] on the host to [devicePort] on the device.
  /// If [hostPort] is null, will auto select a host port.
  /// Returns a Future that completes with the host port.
  Future<int> forward(int devicePort, { int hostPort });

  /// Stops forwarding [forwardedPort].
  Future<Null> unforward(ForwardedPort forwardedPort);
}

/// Read the log for a particular device.
abstract class DeviceLogReader {
  String get name;

  /// A broadcast stream where each element in the string is a line of log output.
  Stream<String> get logLines;

  @override
  String toString() => name;
}

/// Describes an app running on the device.
class DiscoveredApp {
  DiscoveredApp(this.id, this.observatoryPort);
  final String id;
  final int observatoryPort;
}
