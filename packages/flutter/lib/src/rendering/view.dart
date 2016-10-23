// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:developer';
import 'dart:ui' as ui show Scene, SceneBuilder, window;

import 'package:vector_math/vector_math_64.dart';

import 'box.dart';
import 'debug.dart';
import 'layer.dart';
import 'object.dart';
import 'binding.dart';

/// The layout constraints for the root render object.
class ViewConfiguration {
  /// Creates a view configuration.
  ///
  /// By default, the view has zero [size] and a [devicePixelRatio] of 1.0.
  const ViewConfiguration({
    this.size: Size.zero,
    this.devicePixelRatio: 1.0,
    this.orientation
  });

  /// The size of the output surface.
  final Size size;

  /// The pixel density of the output surface.
  final double devicePixelRatio;

  /// The orientation of the output surface (aspirational).
  final int orientation;

  /// Creates a transformation matrix that applies the [devicePixelRatio].
  Matrix4 toMatrix() {
    return new Matrix4.diagonal3Values(devicePixelRatio, devicePixelRatio, 1.0);
  }

  @override
  String toString() => '$size at ${devicePixelRatio}x';
}

/// The root of the render tree.
///
/// The view represents the total output surface of the render tree and handles
/// bootstrapping the rendering pipeline. The view has a unique child
/// [RenderBox], which is required to fill the entire output surface.
class RenderView extends RenderObject with RenderObjectWithChildMixin<RenderBox> {
  /// Creates the root of the render tree.
  ///
  /// Typically created by the binding (e.g., [RendererBinding]).
  RenderView({
    RenderBox child,
    this.timeForRotation: const Duration(microseconds: 83333),
    ViewConfiguration configuration
  }) : _configuration = configuration {
    this.child = child;
  }

  /// The amount of time the screen rotation animation should last (aspirational).
  Duration timeForRotation;

  /// The current layout size of the view.
  Size get size => _size;
  Size _size = Size.zero;

  /// The current orientation of the view (aspirational).
  int get orientation => _orientation;
  int _orientation; // 0..3

  /// The constraints used for the root layout.
  ViewConfiguration get configuration => _configuration;
  ViewConfiguration _configuration;
  set configuration(ViewConfiguration value) {
    if (configuration == value)
      return;
    _configuration = value;
    replaceRootLayer(new TransformLayer(transform: configuration.toMatrix()));
    markNeedsLayout();
  }

  /// Bootstrap the rendering pipeline by scheduling the first frame.
  void scheduleInitialFrame() {
    assert(owner != null);
    scheduleInitialLayout();
    scheduleInitialPaint(new TransformLayer(transform: configuration.toMatrix()));
    owner.requestVisualUpdate();
  }

  // We never call layout() on this class, so this should never get
  // checked. (This class is laid out using scheduleInitialLayout().)
  @override
  void debugAssertDoesMeetConstraints() { assert(false); }

  @override
  void performResize() {
    assert(false);
  }

  @override
  void performLayout() {
    if (configuration.orientation != _orientation) {
      if (_orientation != null && child != null)
        child.rotate(oldAngle: _orientation, newAngle: configuration.orientation, time: timeForRotation);
      _orientation = configuration.orientation;
    }
    _size = configuration.size;
    assert(_size.isFinite);

    if (child != null)
      child.layout(new BoxConstraints.tight(_size));
  }

  @override
  void rotate({ int oldAngle, int newAngle, Duration time }) {
    assert(false); // nobody tells the screen to rotate, the whole rotate() dance is started from our performResize()
  }

  /// Determines the set of render objects located at the given position.
  ///
  /// Returns true if the given point is contained in this render object or one
  /// of its descendants. Adds any render objects that contain the point to the
  /// given hit test result.
  ///
  /// The [position] argument is in the coordinate system of the render view.
  bool hitTest(HitTestResult result, { Point position }) {
    if (child != null)
      child.hitTest(result, position: position);
    result.add(new HitTestEntry(this));
    return true;
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child != null)
      context.paintChild(child, offset);
  }

  /// Uploads the composited layer tree to the engine.
  ///
  /// Actually causes the output of the rendering pipeline to appear on screen.
  void compositeFrame() {
    Timeline.startSync('Compositing');
    try {
      ui.SceneBuilder builder = new ui.SceneBuilder();
      layer.addToScene(builder, Offset.zero);
      ui.Scene scene = builder.build();
      ui.window.render(scene);
      scene.dispose();
      assert(() {
        if (debugRepaintRainbowEnabled)
          debugCurrentRepaintColor = debugCurrentRepaintColor.withHue(debugCurrentRepaintColor.hue + debugRepaintRainbowHueIncrement);
        return true;
      });
    } finally {
      Timeline.finishSync();
    }
  }

  @override
  Rect get paintBounds => Point.origin & size;

  @override
  Rect get semanticBounds => Point.origin & size;

  @override
  void debugFillDescription(List<String> description) {
    // call to ${super.debugFillDescription(prefix)} is omitted because the root superclasses don't include any interesting information for this class
    description.add('window size: ${ui.window.physicalSize} (in physical pixels)');
    description.add('device pixel ratio: ${ui.window.devicePixelRatio} (physical pixels per logical pixel)');
    description.add('configuration: $configuration (in logical pixels)');
  }
}
