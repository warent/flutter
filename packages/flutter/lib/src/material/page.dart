// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/widgets.dart';
import 'material.dart';
import 'theme.dart';

const double _kMinFlingVelocity = 1.0;  // screen width per second

// Used for Android and Fuchsia.
class _MountainViewPageTransition extends AnimatedWidget {
  static final FractionalOffsetTween _kTween = new FractionalOffsetTween(
    begin: FractionalOffset.bottomLeft,
    end: FractionalOffset.topLeft
  );

  _MountainViewPageTransition({
    Key key,
    Animation<double> animation,
    this.child
  }) : super(
    key: key,
    animation: _kTween.animate(new CurvedAnimation(
      parent: animation, // The route's linear 0.0 - 1.0 animation.
      curve: Curves.fastOutSlowIn
    )
  ));

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // TODO(ianh): tell the transform to be un-transformed for hit testing
    return new SlideTransition(
      position: animation,
      child: child
    );
  }
}

// Used for iOS.
class _CupertinoPageTransition extends AnimatedWidget {
  static final FractionalOffsetTween _kTween = new FractionalOffsetTween(
    begin: FractionalOffset.topRight,
    end: -FractionalOffset.topRight
  );

  _CupertinoPageTransition({
    Key key,
    Animation<double> animation,
    this.child
  }) : super(
    key: key,
    animation: _kTween.animate(new CurvedAnimation(
      parent: animation,
      curve: new _CupertinoTransitionCurve(null)
    )
  ));

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // TODO(ianh): tell the transform to be un-transformed for hit testing
    // but not while being controlled by a gesture.
    return new SlideTransition(
      position: animation,
      child: new Material(
        elevation: 6,
        child: child
      )
    );
  }
}

// Custom curve for iOS page transitions.
class _CupertinoTransitionCurve extends Curve {
  _CupertinoTransitionCurve(this.curve);

  Curve curve;

  @override
  double transform(double t) {
    // The input [t] is the average of the current and next route's animation.
    // This means t=0.5 represents when the route is fully onscreen. At
    // t > 0.5, it is partially offscreen to the left (which happens when there
    // is another route on top). At t < 0.5, the route is to the right.
    // We divide the range into two halves, each with a different transition,
    // and scale each half to the range [0.0, 1.0] before applying curves so that
    // each half goes through the full range of the curve.
    if (t > 0.5) {
      // Route is to the left of center.
      t = (t - 0.5) * 2.0;
      if (curve != null)
        t = curve.transform(t);
      t = t / 3.0;
      t = t / 2.0 + 0.5;
    } else {
      // Route is to the right of center.
      if (curve != null)
        t = curve.transform(t * 2.0) / 2.0;
    }
    return t;
  }
}

// This class responds to drag gestures to control the route's transition
// animation progress. Used for iOS back gesture.
class _CupertinoBackGestureController extends NavigationGestureController {
  _CupertinoBackGestureController({
    NavigatorState navigator,
    this.controller,
    this.onDisposed,
  }) : super(navigator);

  AnimationController controller;
  VoidCallback onDisposed;

  @override
  void dispose() {
    super.dispose();
    onDisposed();
    controller.removeStatusListener(handleStatusChanged);
    controller = null;
  }

  @override
  void dragUpdate(double delta) {
    controller.value -= delta;
  }

  @override
  bool dragEnd(double velocity) {
    if (velocity.abs() >= _kMinFlingVelocity) {
      controller.fling(velocity: -velocity);
    } else if (controller.value <= 0.5) {
      controller.fling(velocity: -1.0);
    } else {
      controller.fling(velocity: 1.0);
    }

    // Don't end the gesture until the transition completes.
    final AnimationStatus status = controller.status;
    handleStatusChanged(controller.status);
    controller?.addStatusListener(handleStatusChanged);

    return (status == AnimationStatus.reverse || status == AnimationStatus.dismissed);
  }

  void handleStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.dismissed)
      navigator.pop();
    if (status == AnimationStatus.dismissed || status == AnimationStatus.completed)
      dispose();
  }
}

/// A modal route that replaces the entire screen with a material design transition.
///
/// The entrance transition for the page slides the page upwards and fades it
/// in. The exit transition is the same, but in reverse.
///
/// By default, when a modal route is replaced by another, the previous route
/// remains in memory. To free all the resources when this is not necessary, set
/// [maintainState] to false.
class MaterialPageRoute<T> extends PageRoute<T> {
  /// Creates a page route for use in a material design app.
  MaterialPageRoute({
    this.builder,
    RouteSettings settings: const RouteSettings(),
    this.maintainState: true,
  }) : super(settings: settings) {
    assert(builder != null);
    assert(opaque);
  }

  /// Builds the primary contents of the route.
  final WidgetBuilder builder;

  @override
  final bool maintainState;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Color get barrierColor => null;

  @override
  bool canTransitionFrom(TransitionRoute<dynamic> nextRoute) {
    return nextRoute is MaterialPageRoute<dynamic>;
  }

  @override
  void dispose() {
    _backGestureController?.dispose();
    super.dispose();
  }

  _CupertinoBackGestureController _backGestureController;

  @override
  NavigationGestureController startPopGesture(NavigatorState navigator) {
    if (controller.status != AnimationStatus.completed)
      return null;
    assert(_backGestureController == null);
    _backGestureController = new _CupertinoBackGestureController(
      navigator: navigator,
      controller: controller,
      onDisposed: () { _backGestureController = null; }
    );
    return _backGestureController;
  }

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> forwardAnimation) {
    Widget result = builder(context);
    assert(() {
      if (result == null) {
        throw new FlutterError(
          'The builder for route "${settings.name}" returned null.\n'
          'Route builders must never return null.'
        );
      }
      return true;
    });
    return result;
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> forwardAnimation, Widget child) {
    if (Theme.of(context).platform == TargetPlatform.iOS &&
        Navigator.of(context).userGestureInProgress) {
      return new _CupertinoPageTransition(
        animation: new AnimationMean(left: animation, right: forwardAnimation),
        child: child
      );
    } else {
      return new _MountainViewPageTransition(
        animation: animation,
        child: child
      );
    }
  }

  @override
  String get debugLabel => '${super.debugLabel}(${settings.name})';
}
