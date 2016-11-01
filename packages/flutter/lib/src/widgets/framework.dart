// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:collection';
import 'dart:developer';

import 'debug.dart';

import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';

export 'dart:ui' show hashValues, hashList;
export 'package:flutter/rendering.dart' show RenderObject, RenderBox, debugPrint;
export 'package:flutter/foundation.dart' show FlutterError;

// KEYS

/// A [Key] is an identifier for [Widget]s and [Element]s.
///
/// A new widget will only be used to update an existing element if its key is
/// the same as the key of the current widget associted with the element.
///
/// Keys must be unique amongst the [Element]s with the same parent.
///
/// Subclasses of [Key] should either subclass [LocalKey] or [GlobalKey].
abstract class Key {
  /// Construct a [ValueKey<String>] with the given [String].
  ///
  /// This is the simplest way to create keys.
  factory Key(String value) => new ValueKey<String>(value);

  /// Default constructor, used by subclasses.
  ///
  /// Useful so that subclasses can call us, because the Key() factory
  /// constructor shadows the implicit constructor.
  const Key._();
}

/// A key that is not a [GlobalKey].
///
/// Keys must be unique amongst the [Element]s with the same parent. By
/// contrast, [GlobalKey]s must be unique across the entire app.
abstract class LocalKey extends Key {
  /// Default constructor, used by subclasses.
  const LocalKey() : super._();
}

/// A key that uses a value of a particular type to identify itself.
///
/// A [ValueKey<T>] is equal to another [ValueKey<T>] if, and only if, their
/// values are [operator==].
class ValueKey<T> extends LocalKey {
  /// Creates a key that delgates its [operator==] to the given value.
  const ValueKey(this.value);

  /// The value to which this key delegates its [operator==]
  final T value;

  @override
  bool operator ==(dynamic other) {
    if (other is! ValueKey<T>)
      return false;
    final ValueKey<T> typedOther = other;
    return value == typedOther.value;
  }

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => '[\'$value\']';
}

/// A key that is only equal to itself.
class UniqueKey extends LocalKey {
  /// Creates a key that is equal only to itself.
  UniqueKey();

  @override
  String toString() => '[$hashCode]';
}

/// A key that takes its identity from the object used as its value.
///
/// Used to tie the identity of a widget to the identity of an object used to
/// generate that widget.
class ObjectKey extends LocalKey {
  /// Creates a key that uses [identical] on [value] for its [operator==].
  const ObjectKey(this.value);

  /// The object whose identity is used by this key's [operator==].
  final Object value;

  @override
  bool operator ==(dynamic other) {
    if (other is! ObjectKey)
      return false;
    final ObjectKey typedOther = other;
    return identical(value, typedOther.value);
  }

  @override
  int get hashCode => identityHashCode(value);

  @override
  String toString() => '[${value.runtimeType}(${value.hashCode})]';
}

/// Signature for a callback when a global key is removed from the tree.
typedef void GlobalKeyRemoveListener(GlobalKey key);

/// A key that is unique across the entire app.
///
/// Global keys uniquely indentify elements. Global keys provide access to other
/// objects that are associated with elements, such as the a [BuildContext] and,
/// for [StatefulWidget]s, a [State].
///
/// Widgets that have global keys reparent their subtrees when they are moved
/// from one location in the tree to another location in the tree. In order to
/// reparent its subtree, a widget must arrive at its new location in the tree
/// in the same animation frame in which it was removed from its old location in
/// the tree.
///
/// Global keys are relatively expensive. If you don't need any of the features
/// listed above, consider using a [Key], [ValueKey], [ObjectKey], or
/// [UniqueKey] instead.
@optionalTypeArgs
abstract class GlobalKey<T extends State<StatefulWidget>> extends Key {
  /// Creates a [LabeledGlobalKey], which is a [GlobalKey] with a label used for debugging.
  ///
  /// The label is purely for debugging and not used for comparing the identity
  /// of the key.
  factory GlobalKey({ String debugLabel }) => new LabeledGlobalKey<T>(debugLabel); // the label is purely for debugging purposes and is otherwise ignored

  /// Creates a global key without a label.
  ///
  /// Used by subclasss because the factory constructor shadows the implicit
  /// constructor.
  const GlobalKey.constructor() : super._();

  static final Map<GlobalKey, Element> _registry = new Map<GlobalKey, Element>();
  static final Map<GlobalKey, int> _debugDuplicates = new Map<GlobalKey, int>();
  static final Map<GlobalKey, Set<GlobalKeyRemoveListener>> _removeListeners = new Map<GlobalKey, Set<GlobalKeyRemoveListener>>();
  static final Set<GlobalKey> _removedKeys = new HashSet<GlobalKey>();

  void _register(Element element) {
    assert(() {
      if (_registry.containsKey(this)) {
        int oldCount = _debugDuplicates.putIfAbsent(this, () => 1);
        assert(oldCount >= 1);
        _debugDuplicates[this] = oldCount + 1;
      }
      return true;
    });
    _registry[this] = element;
  }

  void _unregister(Element element) {
    assert(() {
      if (_registry.containsKey(this) && _debugDuplicates.containsKey(this)) {
        int oldCount = _debugDuplicates[this];
        assert(oldCount >= 2);
        if (oldCount == 2) {
          _debugDuplicates.remove(this);
        } else {
          _debugDuplicates[this] = oldCount - 1;
        }
      }
      return true;
    });
    if (_registry[this] == element) {
      _registry.remove(this);
      _removedKeys.add(this);
    }
  }

  Element get _currentElement => _registry[this];

  /// The build context in which the widget with this key builds.
  ///
  /// The current context is null if there is no widget in the tree that matches
  /// this global key.
  BuildContext get currentContext => _currentElement;

  /// The widget in the tree that currently has this global key.
  ///
  /// The current widget is null if there is no widget in the tree that matches
  /// this global key.
  Widget get currentWidget => _currentElement?.widget;

  /// The [State] for the widget in the tree that currently has this global key.
  ///
  /// The current state is null if (1) there is no widget in the tree that
  /// matches this global key, (2) that widget is not a [StatefulWidget], or the
  /// assoicated [State] object is not a subtype of `T`.
  T get currentState {
    Element element = _currentElement;
    if (element is StatefulElement) {
      StatefulElement statefulElement = element;
      State state = statefulElement.state;
      if (state is T)
        return state;
    }
    return null;
  }

  /// Calls `listener` whenever a widget with the given global key is removed
  /// from the tree.
  ///
  /// Listeners can be removed with [unregisterRemoveListener].
  static void registerRemoveListener(GlobalKey key, GlobalKeyRemoveListener listener) {
    assert(key != null);
    Set<GlobalKeyRemoveListener> listeners =
        _removeListeners.putIfAbsent(key, () => new HashSet<GlobalKeyRemoveListener>());
    bool added = listeners.add(listener);
    assert(added);
  }

  /// Stop calling `listener` whenever a widget with the given global key is
  /// removed from the tree.
  ///
  /// Listeners can be added with [addListener].
  static void unregisterRemoveListener(GlobalKey key, GlobalKeyRemoveListener listener) {
    assert(key != null);
    assert(_removeListeners.containsKey(key));
    assert(_removeListeners[key].contains(listener));
    bool removed = _removeListeners[key].remove(listener);
    if (_removeListeners[key].isEmpty)
      _removeListeners.remove(key);
    assert(removed);
  }

  static bool _debugCheckForDuplicates() {
    String message = '';
    for (GlobalKey key in _debugDuplicates.keys) {
      message += 'The following GlobalKey was found multiple times among mounted elements: $key (${_debugDuplicates[key]} instances)\n';
      message += 'The most recently registered instance is: ${_registry[key]}\n';
    }
    if (_debugDuplicates.isNotEmpty) {
      throw new FlutterError(
        'Incorrect GlobalKey usage.\n'
        '$message'
      );
    }
    return true;
  }

  static void _notifyListeners() {
    if (_removedKeys.isEmpty)
      return;
    try {
      for (GlobalKey key in _removedKeys) {
        if (!_registry.containsKey(key) && _removeListeners.containsKey(key)) {
          Set<GlobalKeyRemoveListener> localListeners = new HashSet<GlobalKeyRemoveListener>.from(_removeListeners[key]);
          for (GlobalKeyRemoveListener listener in localListeners)
            listener(key);
        }
      }
    } catch (e, stack) {
      _debugReportException('while notifying GlobalKey listeners', e, stack);
    } finally {
      _removedKeys.clear();
    }
  }

}

/// A global key with a debugging label.
///
/// The debug label is useful for documentation and for debugging. The label
/// does not affect the key's identity.
@optionalTypeArgs
class LabeledGlobalKey<T extends State<StatefulWidget>> extends GlobalKey<T> {
  /// Creates a global key with a debugging label.
  ///
  /// The label does not affect the key's identity.
  const LabeledGlobalKey(this._debugLabel) : super.constructor();

  final String _debugLabel;

  @override
  String toString() => '[GlobalKey ${_debugLabel != null ? _debugLabel : hashCode}]';
}

/// A global key that takes its identity from the object used as its value.
///
/// Used to tie the identity of a widget to the identity of an object used to
/// generate that widget.
@optionalTypeArgs
class GlobalObjectKey<T extends State<StatefulWidget>> extends GlobalKey<T> {
  /// Creates a global key that uses [identical] on [value] for its [operator==].
  const GlobalObjectKey(this.value) : super.constructor();

  /// The object whose identity is used by this key's [operator==].
  final Object value;

  @override
  bool operator ==(dynamic other) {
    if (other is! GlobalObjectKey<T>)
      return false;
    final GlobalObjectKey<T> typedOther = other;
    return identical(value, typedOther.value);
  }

  @override
  int get hashCode => identityHashCode(value);

  @override
  String toString() => '[$runtimeType ${value.runtimeType}(${value.hashCode})]';
}

/// This class is a work-around for the "is" operator not accepting a variable value as its right operand
@optionalTypeArgs
class TypeMatcher<T> {
  /// Creates a type matcher for the given type parameter.
  const TypeMatcher();

  /// Returns `true` if the given object is of type `T`.
  bool check(dynamic object) => object is T;
}

/// Describes the configuration for an [Element].
///
/// Widgets are the central class hierarchy in the Flutter framework. A widget
/// is an immutable description of part of a user interface. Widgets can be
/// inflated into elements, which manage the underlying render tree.
///
/// Widgets themselves have no mutable state (all their fields must be final).
/// If you wish to associate mutable state with a widget, consider using a
/// [StatefulWidget], which creates a [State] object (via
/// [StatefulWidget.createState]) whenever it is inflated into an element and
/// incorporated into the tree.
///
/// A given widget can be included in the tree zero or more times. In particular
/// a given widget can be placed in the tree multiple times. Each time a widget
/// is placed in the tree, it is inflated into an [Element], which means a
/// widget that is incorporated into the tree multiple times will be inflated
/// multiple times.
///
/// The [key] property controls how one widget replaces another widget in the
/// tree. If the [runtimeType] and [key] properties of the two widgets are
/// [operator==], respectively, then the new widget replaces the old widget by
/// updating the underlying element (i.e., by calling [Element.update] with the
/// new widget). Otherwise, the old element is removed from the tree, the new
/// widget is inflated into an element, and the new element is inserted into the
/// tree.
///
/// See also:
///
///  * [StatefulWidget] and [State], for widgets that can build differently
///    several times over their lifetime.
///  * [InheritedWidget], for widgets that introduce ambient state that can
///    be read by descendant widgets.
///  * [StatelessWidget], for widgets that always build the same way given a
///    particular configuration and ambient state.
abstract class Widget {
  /// Initializes [key] for subclasses.
  const Widget({ this.key });

  /// Controls how one widget replaces another widget in the tree.
  ///
  /// If the [runtimeType] and [key] properties of the two widgets are
  /// [operator==], respectively, then the new widget replaces the old widget by
  /// updating the underlying element (i.e., by calling [Element.update] with the
  /// new widget). Otherwise, the old element is removed from the tree, the new
  /// widget is inflated into an element, and the new element is inserted into the
  /// tree.
  final Key key;

  /// Inflates this configuration to a concrete instance.
  ///
  /// A given widget can be included in the tree zero or more times. In particular
  /// a given widget can be placed in the tree multiple times. Each time a widget
  /// is placed in the tree, it is inflated into an [Element], which means a
  /// widget that is incorporated into the tree multiple times will be inflated
  /// multiple times.
  @protected
  Element createElement();

  /// A short, textual description of this widget.
  String toStringShort() {
    return key == null ? '$runtimeType' : '$runtimeType-$key';
  }

  @override
  String toString() {
    final String name = toStringShort();
    final List<String> data = <String>[];
    debugFillDescription(data);
    if (data.isEmpty)
      return '$name';
    return '$name(${data.join("; ")})';
  }

  /// Add additional information to the given description for use by [toString].
  ///
  /// This method makes it easier for subclasses to coordinate to provide a
  /// high-quality [toString] implementation. The [toString] implementation on
  /// the [State] base class calls [debugFillDescription] to collect useful
  /// information from subclasses to incorporate into its return value.
  ///
  /// If you override this, make sure to start your method with a call to
  /// `super.debugFillDescription(description)`.
  @protected
  @mustCallSuper
  void debugFillDescription(List<String> description) { }

  /// Whether the `newWidget` can be used to update an [Element] that currently
  /// has the `oldWidget` as its configuration.
  ///
  /// An element that uses a given widget as its configuration can be updated to
  /// use another widget as its configuration if, and only if, the two widgets
  /// have [runtimeType] and [key] properties that are [operator==].
  static bool canUpdate(Widget oldWidget, Widget newWidget) {
    return oldWidget.runtimeType == newWidget.runtimeType
        && oldWidget.key == newWidget.key;
  }
}

/// A widget that does not require mutable state.
///
/// A stateless widget is a widget that describes part of the user interface by
/// building a constellation of other widgets that describe the user interface
/// more concretely. The building process continues recursively until the
/// description of the user interface is fully concrete (e.g., consists
/// entirely of [RenderObjectWidget]s, which describe concrete [RenderObject]s).
///
/// Stateless widget are useful when the part of the user interface you are
/// describing does not depend on anything other than the configuration
/// information in the object itself and the [BuildContext] in which the widget
/// is inflated. For compositions that can change dynamically, e.g. due to
/// having an internal clock-driven state, or depending on some system state,
/// consider using [StatefulWidget].
///
/// See also:
///
///  * [StatefulWidget] and [State], for widgets that can build differently
///    several times over their lifetime.
///  * [InheritedWidget], for widgets that introduce ambient state that can
///    be read by descendant widgets.
abstract class StatelessWidget extends Widget {
  /// Initializes [key] for subclasses.
  const StatelessWidget({ Key key }) : super(key: key);

  /// Creates a [StatelessElement] to manage this widget's location in the tree.
  ///
  /// It is uncommon for subclasses to override this method.
  @override
  StatelessElement createElement() => new StatelessElement(this);

  /// Describes the part of the user interface represented by this widget.
  ///
  /// The framework calls this method when this widget is inserted into the
  /// tree in a given [BuildContext] and when the dependencies of this widget
  /// change (e.g., an [InheritedWidget] referenced by this widget changes).
  ///
  /// The framework replaces the subtree below this widget with the widget
  /// returned by this method, either by updating the existing subtree or by
  /// removing the subtree and inflating a new subtree, depending on whether the
  /// widget returned by this method can update the root of the existing
  /// subtree, as determined by calling [Widget.canUpdate].
  ///
  /// Typically implementations return a newly created constellation of widgets
  /// that are configured with information from this widget's constructor and
  /// from the given [BuildContext].
  ///
  /// The given [BuildContext] contains information about the location in the
  /// tree at which this widget is being built. For example, the context
  /// provides the set of inherited widgets for this location in the tree. A
  /// given widget might be with multiple different [BuildContext] arguments
  /// over time if the widget is moved around the tree or if the widget is
  /// inserted into the tree in multiple places at once.
  ///
  /// The implementation of this method must only depend on:
  ///
  /// * the fields of the widget, which themselves must not change over time,
  ///   and
  /// * any ambient state obtained from the `context` using
  ///   [BuildContext.inheritFromWidgetOfExactType].
  ///
  /// If a widget's [build] method is to depend on anything else, use a
  /// [StatefulWidget] instead.
  @protected
  Widget build(BuildContext context);
}

/// A widget that has mutable state.
///
/// State is information that (1) can be read synchronously when the widget is
/// built and (2) might change during the lifetime of the widget. It is the
/// responsibility of the widget implementer to ensure that the [State] is
/// promptly notified when such state changes, using [State.setState].
///
/// A stateful widget is a widget that describes part of the user interface by
/// building a constellation of other widgets that describe the user interface
/// more concretely. The building process continues recursively until the
/// description of the user interface is fully concrete (e.g., consists
/// entirely of [RenderObjectWidget]s, which describe concrete [RenderObject]s).
///
/// Stateless widget are useful when the part of the user interface you are
/// describing can change dynamically, e.g. due to having an internal
/// clock-driven state, or depending on some system state. For compositions that
/// depend only on the configuration information in the object itself and the
/// [BuildContext] in which the widget is inflated, consider using
/// [StatelessWidget].
///
/// [StatefulWidget] instances themselves are immutable and store their mutable
/// state either in separate [State] objects that are created by the
/// [createState] method, or in objects to which that [State] subscribes, for
/// example [Stream] or [ChangeNotifier] objects, to which references are stored
/// in final fields on the [StatefulWidget] itself.
///
/// The framework calls [createState] whenever it inflates a
/// [StatefulWidget], which means that multiple [State] objects might be
/// associated with the same [StatefulWidget] if that widget has been inserted
/// into the tree in multiple places. Similarly, if a [StatefulWidget] is
/// removed from the tree and later inserted in to the tree again, the framework
/// will call [createState] again to create a fresh [State] object, simplifying
/// the lifecycle of [State] objects.
///
/// A [StatefulWidget] keeps the same [State] object when moving from one
/// location in the tree to another if its creator used a [GlobalKey] for its
/// [key]. Because a widget with a [GlobalKey] can be used in at most one
/// location in the tree, a widget that uses a [GlobalKey] has at most one
/// associated element. The framework takes advantage of this property when
/// moving a widget with a global key from one location in the tree to another
/// by grafting the (unique) subtree associated with that widget from the old
/// location to the new location (instead of recreating the subtree at the new
/// location). The [State] objects associated with [StatefulWidget] are grafted
/// along with the rest of the subtree, which means the [State] object is reused
/// (instead of being recreated) in the new location. However, in order to be
/// eligible for grafting, the widget might be inserted into the new location in
/// the same animation frame in which it was removed from the old location.
///
/// See also:
///
///  * [State], where the logic behind a [StatefulWidget] is hosted.
///  * [StatelessWidget], for widgets that always build the same way given a
///    particular configuration and ambient state.
///  * [InheritedWidget], for widgets that introduce ambient state that can
///    be read by descendant widgets.
abstract class StatefulWidget extends Widget {
  /// Initializes [key] for subclasses.
  const StatefulWidget({ Key key }) : super(key: key);

  /// Creates a [StatefulElement] to manage this widget's location in the tree.
  ///
  /// It is uncommon for subclasses to override this method.
  @override
  StatefulElement createElement() => new StatefulElement(this);

  /// Creates the mutable state for this widget at a given location in the tree.
  ///
  /// Subclasses should override this method to return a newly created
  /// instance of their associated [State] subclass:
  ///
  /// ```dart
  /// @override
  /// _MyState createState() => new _MyState();
  /// ```
  ///
  /// The framework can call this method multiple times over the lifetime of
  /// a [StatefulWidget]. For example, if the widget is inserted into the tree
  /// in multiple locations, the framework will create a separate [State] object
  /// for each location. Similarly, if the widget is removed from the tree and
  /// later inserted into the tree again, the framework will call [createState]
  /// again to create a fresh [State] object, simplifying the lifecycle of
  /// [State] objects.
  @protected
  State createState();
}

/// Tracks the lifecycle of [State] objects when asserts are enabled.
enum _StateLifecycle {
  /// The [State] object has been created. [State.initState] is called at this
  /// time.
  created,

  /// The [State.initState] method has been called but the [State] object is
  /// not yet ready to build. [State.dependenciesChanged] is called at this time.
  initialized,

  /// The [State] object is ready to build and [State.dispose] has not yet been
  /// called.
  ready,

  /// The [State.dispose] method has been called and the [State] object is
  /// no longer able to build.
  defunct,
}

/// The signature of [State.setState] functions.
typedef void StateSetter(VoidCallback fn);

/// The logic and internal state for a [StatefulWidget].
///
/// State is information that (1) can be read synchronously when the widget is
/// built and (2) might change during the lifetime of the widget. It is the
/// responsibility of the widget implementer to ensure that the [State] is
/// promptly notified when such state changes, using [State.setState].
///
/// [State] objects are created by the framework by calling the
/// [StatefulWidget.createState] method when inflating a [StatefulWidget] to
/// insert it into the tree. Because a given [StatefulWidget] instance can be
/// inflated multiple times (e.g., the widget is incorporated into the tree in
/// multiple places at once), there might be more than one [State] object
/// associated with a given [StatefulWidget] instance. Similarly, if a
/// [StatefulWidget] is removed from the tree and later inserted in to the tree
/// again, the framework will call [StatefulWidget.createState] again to create
/// a fresh [State] object, simplifying the lifecycle of [State] objects.
///
/// [State] objects have the following lifecycle:
///
///  * The framework creates a [State] object by calling
///    [StatefulWidget.createState].
///  * The newly created [State] object is associated with a [BuildContext].
///    This association is permanent: the [State] object will never change its
///    [BuildContext]. However, the [BuildContext] itself can be moved around
///    the tree along with its subtree. At this point, the [State] object is
///    considered [mounted].
///  * The framework calls [initState]. Subclasses of [State] should override
///    [initState] to perform one-time initialization that depends on the
///    [BuildContext] or the widget, which are available as the [context] and
///    [config] properties, respectively, when the [initState] method is
///    called.
///  * The framework calls [dependenciesChanged]. Subclasses of [State] should
///    override [dependenciesChanged] to perform initialization involving
///    [InheritedWidget]s. If [BuildContext.inheritFromWidgetOfExactType] is
///    called, the [dependenciesChanged] method will be called again if the
///    inherited widgets subsequently change or if the widget moves in the tree.
///  * At this point, the [State] object is fully initialized and the framework
///    might call its [build] method any number of times to obtain a
///    description of the user interface for this subtree. [State] objects can
///    spontanteously request to rebuild their subtree by callings their
///    [setState] method, which indicates that some of their internal state
///    has changed in a way that might impact the user interface in this
///    subtree.
///  * During this time, a parent widget might rebuild and request that this
///    location in the tree update to display a new widget with the same
///    [runtimeType] and [key]. When this happens, the framework will update the
///    [config] property to refer to the new widget and then call the
///    [didUpdateConfig] method with the previous widget as an argument.
///    [State] objects should override [didUpdateConfig] to respond to changes
///    in their associated wiget (e.g., to start implicit animations).
///    The framework always calls [build] after calling [didUpdateConfig], which
///    means any calls to [setState] in [didUpdateConfig] are redundant.
///  * If the subtree containing the [State] object is removed from the tree
///    (e.g., because the parent built a widget with a different [runtimeType]
///    or [key]), the framework calls the [deactivate] method. Subclasses
///    should override this method to clean up any links between this object
///    and other elements in the tree (e.g. if you have provided an ancestor
///    with a pointer to a descendant's [RenderObject]).
///  * At this point, the framework might reinsert this subtree into another
///    part of the tree. If that happens, the framework will ensure that it
///    calls [build] to give the [State] object a chance to adapt to its new
///    location in the tree. If the framework does reinsert this subtree, it
///    will do so before the end of the animation frame in which the subtree was
///    removed from the tree. For this reason, [State] objects can defer
///    releasing most resources until the framework calls their [dispose]
///    method.
///  * If the framework does not reinsert this subtree by the end of the current
///    animation frame, the framework will call [dispose], which indiciates that
///    this [State] object will never build again. Subclasses should override
///    this method to release any resources retained by this object (e.g.,
///    stop any active animations).
///  * After the framework calls [dispose], the [State] object is considered
///    unmounted and the [mounted] property is false. It is an error to call
///    [setState] at this point. This stage of the lifecycle is terminal: there
///    is no way to remount a [State] object that has been disposed.
///
/// See also:
///
///  * [StatefulWidget], where the current configuration of a [State] is hosted
///    (see [config]).
///  * [StatelessWidget], for widgets that always build the same way given a
///    particular configuration and ambient state.
///  * [InheritedWidget], for widgets that introduce ambient state that can
///    be read by descendant widgets.
@optionalTypeArgs
abstract class State<T extends StatefulWidget> {
  /// The current configuration.
  ///
  /// A [State] object's configuration is the corresponding [StatefulWidget]
  /// instance. This property is initialized by the framework before calling
  /// [initState]. If the parent updates this location in the tree to a new
  /// widget with the same [runtimeType] and [key] as the current configuration,
  /// the framework will update this property to refer to the new widget and
  /// then call [didUpdateConfig], passing the old configuration as an argument.
  T get config => _config;
  T _config;

  /// The current stage in the lifecycle for this state object.
  ///
  /// This field is used by the framework when asserts are enabled to verify
  /// that [State] objects move through their lifecycle in an orderly fashion.
  _StateLifecycle _debugLifecycleState = _StateLifecycle.created;

  /// Verifies that the [State] that was created is one that expects to be
  /// created for that particular [Widget].
  bool _debugTypesAreRight(Widget widget) => widget is T;

  /// The location in the tree where this widget builds.
  ///
  /// The framework associates [State] objects with a [BuildContext] after
  /// creating them with [StatefulWidget.createState] and before calling
  /// [initState]. The association is permanent: the [State] object will never
  /// change its [BuildContext]. However, the [BuildContext] itself can be moved
  /// around the tree.
  ///
  /// After calling [dispose], the framework severs the [State] object's
  /// connection with the [BuildContext].
  BuildContext get context => _element;
  StatefulElement _element;

  /// Whether this [State] object is currently in a tree.
  ///
  /// After creating a [State] object and before calling [initState], the
  /// framework "mounts" the [State] object by associating it with a
  /// [BuildContext]. The [State] object remains mounted until the framework
  /// calls [dispose], after which time the framework will never ask the [State]
  /// object to [build] again.
  ///
  /// It is an error to call [setState] unless [mounted] is true.
  bool get mounted => _element != null;

  /// Called when this object is inserted into the tree.
  ///
  /// The framework will call this method exactly once for each [State] object
  /// it creates.
  ///
  /// Override this method to perform initialization that depends on the
  /// location at which this object was inserted into the tree (i.e., [context])
  /// or on the widget used to configure this object (i.e., [config]).
  ///
  /// If a [State]'s [build] method depends on an object that can itself change
  /// state, for example a [ChangeNotifier] or [Stream], or some other object to
  /// which one can subscribe to receive notifications, then the [State] should
  /// subscribe to that object during [initState], unsubscribe from the old
  /// object and subscribe to the new object when it changes in
  /// [didUpdateConfig], and then unsubscribe from the object in [dispose].
  ///
  /// You cannot use [BuildContext.inheritFromWidgetOfExactType] from this
  /// method. However, [dependenciesChanged] will be called immediately
  /// following this method, and [BuildContext.inheritFromWidgetOfExactType] can
  /// be used there.
  ///
  /// If you override this, make sure your method starts with a call to
  /// super.initState().
  @protected
  @mustCallSuper
  void initState() {
    assert(_debugLifecycleState == _StateLifecycle.created);
  }

  /// Called whenever the configuration changes.
  ///
  /// If the parent widget rebuilds and request that this location in the tree
  /// update to display a new widget with the same [runtimeType] and [key], the
  /// framework will update the [config] property of this [State] object to
  /// refer to the new widget and then call the this method with the previous
  /// widget as an argument.
  ///
  /// Override this method to respond to changes in the [config] widget (e.g.,
  /// to start implicit animations).
  ///
  /// The framework always calls [build] after calling [didUpdateConfig], which
  /// means any calls to [setState] in [didUpdateConfig] are redundant.
  ///
  /// If a [State]'s [build] method depends on an object that can itself change
  /// state, for example a [ChangeNotifier] or [Stream], or some other object to
  /// which one can subscribe to receive notifications, then the [State] should
  /// subscribe to that object during [initState], unsubscribe from the old
  /// object and subscribe to the new object when it changes in
  /// [didUpdateConfig], and then unsubscribe from the object in [dispose].
  ///
  /// If you override this, make sure your method starts with a call to
  /// super.didUpdateConfig(oldConfig).
  // TODO(abarth): Add @mustCallSuper.
  @protected
  void didUpdateConfig(@checked T oldConfig) { }

  /// Called whenever the application is reassembled during debugging.
  ///
  /// This method should rerun any initialization logic that depends on global
  /// state, for example, image loading from asset bundles (since the asset
  /// bundle may have changed).
  ///
  /// In addition to this method being invoked, it is guaranteed that the
  /// [build] method will be invoked when a reassemble is signalled. Most
  /// widgets therefore do not need to do anything in the [reassemble] method.
  ///
  /// This function will only be called during development. In release builds,
  /// the `ext.flutter.reassemble` hook is not available, and so this code will
  /// never execute.
  ///
  /// See also:
  ///
  /// * [BindingBase.reassembleApplication].
  /// * [Image], which uses this to reload images.
  @protected
  @mustCallSuper
  void reassemble() { }

  /// Notify the framework that the internal state of this object has changed.
  ///
  /// Whenever you change the internal state of a [State] object, make the
  /// change in a function that you pass to [setState]:
  ///
  /// ```dart
  /// setState(() { _myState = newValue });
  /// ```
  ///
  /// The provided callback is immediately called synchronously. It must not
  /// return a future (the callback cannot be `async`), since then it would be
  /// unclear when the state was actually being set.
  ///
  /// Calling [setState] notifies the framework that the internal state of this
  /// object has changed in a way that might impact the user interface in this
  /// subtree, which causes the framework to schedule a [build] for this [State]
  /// object.
  ///
  /// If you just change the state directly without calling [setState], the
  /// framework might not schedule a [build] and the user interface for this
  /// subtree might not be updated to reflect the new state.
  ///
  /// Generally it is recommended that the `setState` method only be used to
  /// wrap the actual changes to the state, not any computation that might be
  /// associated with the change. For example, here a value used by the [build]
  /// function is incremented, and then the change is written to disk, but only
  /// the increment is wrapped in the `setState`:
  ///
  /// ```dart
  /// Future<Null> _incrementCounter() async {
  ///   setState(() {
  ///     _counter++;
  ///   });
  ///   final String dir = await PathProvider.getApplicationDocumentsDirectory();
  ///   await new File('$dir/counter.txt').writeAsString('$_counter');
  ///   return null;
  /// }
  /// ```
  ///
  /// It is an error to call this method after the framework calls [dispose].
  /// You can determine whether it is legal to call this method by checking
  /// whether the [mounted] property is true.
  @protected
  void setState(VoidCallback fn) {
    assert(fn != null);
    assert(() {
      if (_debugLifecycleState == _StateLifecycle.defunct) {
        throw new FlutterError(
          'setState() called after dispose(): $this\n'
          'This error happens if you call setState() on a State object for a widget that '
          'no longer appears in the widget tree (e.g., whose parent widget no longer '
          'includes the widget in its build). This error can occur when code calls '
          'setState() from a timer or an animation callback. The preferred solution is '
          'to cancel the timer or stop listening to the animation in the dispose() '
          'callback. Another solution is to check the "mounted" property of this '
          'object before calling setState() to ensure the object is still in the '
          'tree.\n'
          'This error might indicate a memory leak if setState() is being called '
          'because another object is retaining a reference to this State object '
          'after it has been removed from the tree. To avoid memory leaks, '
          'consider breaking the reference to this object during dispose().'
        );
      }
      return true;
    });
    dynamic result = fn() as dynamic;
    assert(() {
      if (result is Future) {
        throw new FlutterError(
          'setState() callback argument returned a Future.\n'
          'The setState() method on $this was called with a closure or method that '
          'returned a Future. Maybe it is marked as "async".\n'
          'Instead of performing asynchronous work inside a call to setState(), first '
          'execute the work (without updating the widget state), and then synchronously '
          'update the state inside a call to setState().'
        );
      }
      // We ignore other types of return values so that you can do things like:
      //   setState(() => x = 3);
      return true;
    });
    _element.markNeedsBuild();
  }

  /// Called when this object is removed from the tree.
  ///
  /// The framework calls this method whenever it removes this [State] object
  /// from the tree. In some cases, the framework will reinsert the [State]
  /// object into another part of the tree (e.g., if the subtree containing this
  /// [State] object is grafted from one location in the tree to another). If
  /// that happens, the framework will ensure that it calls [build] to give the
  /// [State] object a chance to adapt to its new location in the tree. If
  /// the framework does reinsert this subtree, it will do so before the end of
  /// the animation frame in which the subtree was removed from the tree. For
  /// this reason, [State] objects can defer releasing most resources until the
  /// framework calls their [dispose] method.
  ///
  /// Subclasses should override this method to clean up any links between
  /// this object and other elements in the tree (e.g. if you have provided an
  /// ancestor with a pointer to a descendant's [RenderObject]).
  ///
  /// If you override this, make sure to end your method with a call to
  /// super.deactivate().
  ///
  /// See also [dispose], which is called after [deactivate] if the widget is
  /// removed from the tree permanently.
  @protected
  @mustCallSuper
  void deactivate() { }

  /// Called when this object is removed from the tree permanently.
  ///
  /// The framework calls this method when this [State] object will never
  /// build again. After the framework calls [dispose], the [State] object is
  /// considered unmounted and the [mounted] property is false. It is an error
  /// to call [setState] at this point. This stage of the lifecycle is terminal:
  /// there is no way to remount a [State] object that has been disposed.
  ///
  /// Subclasses should override this method to release any resources retained
  /// by this object (e.g., stop any active animations).
  ///
  /// If a [State]'s [build] method depends on an object that can itself change
  /// state, for example a [ChangeNotifier] or [Stream], or some other object to
  /// which one can subscribe to receive notifications, then the [State] should
  /// subscribe to that object during [initState], unsubscribe from the old
  /// object and subscribe to the new object when it changes in
  /// [didUpdateConfig], and then unsubscribe from the object in [dispose].
  ///
  /// If you override this, make sure to end your method with a call to
  /// super.dispose().
  ///
  /// See also [deactivate], which is called prior to [dispose].
  @protected
  @mustCallSuper
  void dispose() {
    assert(_debugLifecycleState == _StateLifecycle.ready);
    assert(() { _debugLifecycleState = _StateLifecycle.defunct; return true; });
  }

  /// Describes the part of the user interface represented by this widget.
  ///
  /// The framework calls this method in a number of different situations:
  ///
  ///  * After calling [initState].
  ///  * After calling [didUpdateConfig].
  ///  * After receiving a call to [setState].
  ///  * After a dependency of this [State] object changes (e.g., an
  ///    [InheritedWidget] referenced by the previous [build] changes).
  ///  * After calling [deactivate] and then reinserting the [State] object into
  ///    the tree at another location.
  ///
  /// The framework replaces the subtree below this widget with the widget
  /// returned by this method, either by updating the existing subtree or by
  /// removing the subtree and inflating a new subtree, depending on whether the
  /// widget returned by this method can update the root of the existing
  /// subtree, as determined by calling [Widget.canUpdate].
  ///
  /// Typically implementations return a newly created constellation of widgets
  /// that are configured with information from this widget's constructor, the
  /// given [BuildContext], and the internal state of this [State] object.
  ///
  /// The given [BuildContext] contains information about the location in the
  /// tree at which this widget is being built. For example, the context
  /// provides the set of inherited widgets for this location in the tree. The
  /// [BuildContext] argument is always the same as the [context] property of
  /// this [State] object and will remain the same for the lifetime of this
  /// object. The [BuildContext] argument is provided redundantly here so that
  /// this method matches the signature for a [WidgetBuilder].
  @protected
  Widget build(BuildContext context);

  /// Called when a dependency of this [State] object changes.
  ///
  /// For example, if the previous call to [build] referenced an
  /// [InheritedWidget] that later changed, the framework would call this
  /// method to notify this object about the change.
  ///
  /// This method is also called immediately after [initState]. It is safe to
  /// call [BuildContext.inheritFromWidgetOfExactType] from this method.
  ///
  /// Subclasses rarely override this method because the framework always
  /// calls [build] after a dependency changes. Some subclasses do override
  /// this method because they need to do some expensive work (e.g., network
  /// fetches) when their dependencies change, and that work would be too
  /// expensive to do for every build.
  @protected
  @mustCallSuper
  void dependenciesChanged() { }

  @override
  String toString() {
    final List<String> data = <String>[];
    debugFillDescription(data);
    return '$runtimeType(${data.join("; ")})';
  }

  /// Add additional information to the given description for use by [toString].
  ///
  /// This method makes it easier for subclasses to coordinate to provide a
  /// high-quality [toString] implementation. The [toString] implementation on
  /// the [State] base class calls [debugFillDescription] to collect useful
  /// information from subclasses to incorporate into its return value.
  ///
  /// If you override this, make sure to start your method with a call to
  /// `super.debugFillDescription(description)`.
  @protected
  @mustCallSuper
  void debugFillDescription(List<String> description) {
    description.add('$hashCode');
    assert(() {
      if (_debugLifecycleState != _StateLifecycle.ready)
        description.add('$_debugLifecycleState');
      return true;
    });
    if (_config == null)
      description.add('no config');
    if (_element == null)
      description.add('not mounted');
  }
}

/// A widget that has exactly one child widget.
///
/// Useful as a base class for other widgets, such as [InheritedWidget] and
/// [ParentDataWidget].
abstract class ProxyWidget extends Widget {
  /// Creates a widget that has exactly one child widget.
  const ProxyWidget({ Key key, this.child }) : super(key: key);

  /// The widget below this widget in the tree.
  final Widget child;
}

/// Base class for widgets that hook [ParentData] information to children of
/// [RenderObjectWidget]s.
///
/// This can be used to provide per-child configuration for
/// [RenderObjectWidget]s with more than one child. For example, [Stack] uses
/// the [Positioned] parent data widget to position each child.
///
/// A [ParentDataWidget] is specific to a particular kind of [RenderObject], and
/// thus also to a particular [RenderObjectWidget] class. That class is `T`, the
/// [ParentDataWidget] type argument.
abstract class ParentDataWidget<T extends RenderObjectWidget> extends ProxyWidget {
  /// Abstract const constructor. This constructor enables subclasses to provide
  /// const constructors so that they can be used in const expressions.
  const ParentDataWidget({ Key key, Widget child })
    : super(key: key, child: child);

  @override
  ParentDataElement<T> createElement() => new ParentDataElement<T>(this);

  /// Subclasses should override this method to return true if the given
  /// ancestor is a RenderObjectWidget that wraps a RenderObject that can handle
  /// the kind of ParentData widget that the ParentDataWidget subclass handles.
  ///
  /// The default implementation uses the type argument.
  bool debugIsValidAncestor(RenderObjectWidget ancestor) {
    assert(T != dynamic);
    assert(T != RenderObjectWidget);
    return ancestor is T;
  }

  /// Subclasses should override this to describe the requirements for using the
  /// ParentDataWidget subclass. It is called when debugIsValidAncestor()
  /// returned false for an ancestor, or when there are extraneous
  /// [ParentDataWidget]s in the ancestor chain.
  String debugDescribeInvalidAncestorChain({ String description, String ownershipChain, bool foundValidAncestor, Iterable<Widget> badAncestors }) {
    assert(T != dynamic);
    assert(T != RenderObjectWidget);
    String result;
    if (!foundValidAncestor) {
      result = '$runtimeType widgets must be placed inside $T widgets.\n'
               '$description has no $T ancestor at all.\n';
    } else {
      assert(badAncestors.isNotEmpty);
      result = '$runtimeType widgets must be placed directly inside $T widgets.\n'
               '$description has a $T ancestor, but there are other widgets between them:\n';
      for (Widget ancestor in badAncestors) {
        if (ancestor.runtimeType == runtimeType) {
          result += '  $ancestor (this is a different $runtimeType than the one with the problem)\n';
        } else {
          result += '  $ancestor\n';
        }
      }
      result += 'These widgets cannot come between a $runtimeType and its $T.\n';
    }
    result += 'The ownership chain for the parent of the offending $runtimeType was:\n  $ownershipChain';
    return result;
  }

  /// Write the data from this widget into the given render object's parent data.
  ///
  /// The framework calls this function whenever it detects that the
  /// [RenderObject] associated with the [child] has outdated
  /// [RenderObject.parentData]. For example, if the render object was recently
  /// inserted into the render tree, the render object's parent data might not
  /// match the data in this widget.
  ///
  /// Subclasses are expected to override this function to copy data from their
  /// fields into the [RenderObject.parentData] field of the given render
  /// object. The render object's parent is guaranteed to have been created by a
  /// widget of type `T`, which usually means that this function can assume that
  /// the render object's parent data object inherits from a particular class.
  ///
  /// If this function modifies data that can change the parent's layout or
  /// painting, this function is responsible for calling
  /// [RenderObject.markNeedsLayout] or [RenderObject.markNeedsPaint] on the
  /// parent, as appropriate.
  @protected
  void applyParentData(RenderObject renderObject);
}

/// Base class for widgets that efficiently propagate information down the tree.
///
/// To obtain the nearest instance of a particular type of inherited widget from
/// a build context, use [BuildContext.inheritFromWidgetOfExactType].
///
/// Inherited widgets, when referenced in this way, will cause the consumer to
/// rebuild when the inherited widget itself changes state.
abstract class InheritedWidget extends ProxyWidget {
  /// Abstract const constructor. This constructor enables subclasses to provide
  /// const constructors so that they can be used in const expressions.
  const InheritedWidget({ Key key, Widget child })
    : super(key: key, child: child);

  @override
  InheritedElement createElement() => new InheritedElement(this);

  /// Whether the framework should notify widgets that inherit from this widget.
  ///
  /// When this widget is rebuilt, sometimes we need to rebuild the widgets that
  /// inherit from this widget but sometimes we do not. For example, if the data
  /// held by this widget is the same as the data held by `oldWidget`, then then
  /// we do not need to rebuild the widgets that inherited the data held by
  /// `oldWidget`.
  ///
  /// The framework distinguishes these cases by calling this function with the
  /// widget that previously occupied this location in the tree as an argument.
  /// The given widget is guaranteed to have the same [runtimeType] as this
  /// object.
  @protected
  bool updateShouldNotify(@checked InheritedWidget oldWidget);
}

/// RenderObjectWidgets provide the configuration for [RenderObjectElement]s,
/// which wrap [RenderObject]s, which provide the actual rendering of the
/// application.
abstract class RenderObjectWidget extends Widget {
  /// Abstract const constructor. This constructor enables subclasses to provide
  /// const constructors so that they can be used in const expressions.
  const RenderObjectWidget({ Key key }) : super(key: key);

  /// RenderObjectWidgets always inflate to a [RenderObjectElement] subclass.
  @override
  RenderObjectElement createElement();

  /// Creates an instance of the [RenderObject] class that this
  /// [RenderObjectWidget] represents, using the configuration described by this
  /// [RenderObjectWidget].
  @protected
  RenderObject createRenderObject(BuildContext context);

  /// Copies the configuration described by this [RenderObjectWidget] to the
  /// given [RenderObject], which will be of the same type as returned by this
  /// object's [createRenderObject].
  @protected
  void updateRenderObject(BuildContext context, @checked RenderObject renderObject) { }

  /// A render object previously associated with this widget has been removed
  /// from the tree. The given [RenderObject] will be of the same type as
  /// returned by this object's [createRenderObject].
  @protected
  void didUnmountRenderObject(@checked RenderObject renderObject) { }
}

/// A superclass for RenderObjectWidgets that configure RenderObject subclasses
/// that have no children.
abstract class LeafRenderObjectWidget extends RenderObjectWidget {
  /// Abstract const constructor. This constructor enables subclasses to provide
  /// const constructors so that they can be used in const expressions.
  const LeafRenderObjectWidget({ Key key }) : super(key: key);

  @override
  LeafRenderObjectElement createElement() => new LeafRenderObjectElement(this);
}

/// A superclass for RenderObjectWidgets that configure RenderObject subclasses
/// that have a single child slot. (This superclass only provides the storage
/// for that child, it doesn't actually provide the updating logic.)
abstract class SingleChildRenderObjectWidget extends RenderObjectWidget {
  /// Abstract const constructor. This constructor enables subclasses to provide
  /// const constructors so that they can be used in const expressions.
  const SingleChildRenderObjectWidget({ Key key, this.child }) : super(key: key);

  /// The widget below this widget in the tree.
  final Widget child;

  @override
  SingleChildRenderObjectElement createElement() => new SingleChildRenderObjectElement(this);
}

/// A superclass for RenderObjectWidgets that configure RenderObject subclasses
/// that have a single list of children. (This superclass only provides the
/// storage for that child list, it doesn't actually provide the updating
/// logic.)
abstract class MultiChildRenderObjectWidget extends RenderObjectWidget {
  /// Initializes fields for subclasses.
  ///
  /// The [children] argument must not be null and must not contain any null
  /// objects.
  MultiChildRenderObjectWidget({ Key key, this.children: const <Widget>[] })
    : super(key: key) {
    assert(children != null);
    assert(!children.any((Widget child) => child == null));
  }

  /// The widgets below this widget in the tree.
  ///
  /// If this list is going to be mutated, it is usually wise to put [Key]s on
  /// the widgets, so that the framework can match old configurations to new
  /// configurations and maintain the underlying render objects.
  final List<Widget> children;

  @override
  MultiChildRenderObjectElement createElement() => new MultiChildRenderObjectElement(this);
}


// ELEMENTS

enum _ElementLifecycle {
  initial,
  active,
  inactive,
  defunct,
}

class _InactiveElements {
  bool _locked = false;
  final Set<Element> _elements = new HashSet<Element>();

  void _unmount(Element element) {
    assert(element._debugLifecycleState == _ElementLifecycle.inactive);
    assert(() {
      if (debugPrintGlobalKeyedWidgetLifecycle) {
        if (element.widget.key is GlobalKey)
          debugPrint('Discarding $element from inactive elements list.');
      }
      return true;
    });
    element.visitChildren((Element child) {
      assert(child._parent == element);
      _unmount(child);
    });
    element.unmount();
    assert(element._debugLifecycleState == _ElementLifecycle.defunct);
  }

  void _unmountAll() {
    _locked = true;
    final List<Element> elements = _elements.toList()..sort(Element._sort);
    _elements.clear();
    try {
      for (Element element in elements.reversed)
        _unmount(element);
    } finally {
      assert(_elements.isEmpty);
      _locked = false;
    }
  }

  void _deactivateRecursively(Element element) {
    assert(element._debugLifecycleState == _ElementLifecycle.active);
    element.deactivate();
    assert(element._debugLifecycleState == _ElementLifecycle.inactive);
    element.visitChildren(_deactivateRecursively);
    assert(() { element.debugDeactivated(); return true; });
  }

  void add(Element element) {
    assert(!_locked);
    assert(!_elements.contains(element));
    assert(element._parent == null);
    if (element._active)
      _deactivateRecursively(element);
    _elements.add(element);
  }

  void remove(Element element) {
    assert(!_locked);
    assert(_elements.contains(element));
    assert(element._parent == null);
    _elements.remove(element);
    assert(!element._active);
  }
}

/// Signature for the callback to [BuildContext.visitChildElements].
///
/// The argument is the child being visited.
///
/// It is safe to call `element.visitChildElements` reentrantly within
/// this callback.
typedef void ElementVisitor(Element element);

/// A handle to the location of a widget in the widget tree.
///
/// This class presents a set of methods that can be used from
/// [StatelessWidget.build] methods and from methods on [State] objects.
///
/// [BuildContext] objects are passed to [WidgetBuilder] functions (such as
/// [StatelessWidget.build]), and are available from the [State.context] member.
/// Some static functions (e.g. [showDialog], [Theme.of], and so forth) also
/// take build contexts so that they can act on behalf of the calling widget, or
/// obtain data specifically for the given context.
///
/// Each widget has its own [BuildContext], which becomes the parent of the
/// widget returned by the [StatelessWidget.build] or [State.build] function.
/// (And similarly, the parent of any children for [RenderObjectWidget]s.)
///
/// In particular, this means that within a build method, the build context of
/// the widget of the build method is not the same as the build context of the
/// widgets returned by that build method. This can lead to some tricky cases.
/// For example, [Theme.of(context)] looks for the nearest enclosing [Theme] of
/// the given build context. If a build method for a widget Q includes a [Theme]
/// within its returned widget tree, and attempts to use [Theme.of] passing its
/// own context, the build method for Q will not find that [Theme] object. It
/// will instead find whatever [Theme] was an ancestor to the widget Q. If the
/// build context for a subpart of the returned tree is needed, a [Builder]
/// widget can be used: the build context passed to the [Builder.builder]
/// callback will be that of the [Builder] itself.
///
/// For example, in the following snippet, the [ScaffoldState.showSnackBar]
/// method is called on the [Scaffold] widget that the build method itself
/// creates. If a [Builder] had not been used, and instead the `context`
/// argument of the build method itself had been used, no [Scaffold] would have
/// been found, and the [Scaffold.of] function would have returned null.
///
/// ```dart
///   @override
///   Widget build(BuildContext context) {
///     // here, Scaffold.of(context) returns null
///     return new Scaffold(
///       appBar: new AppBar(title: new Text('Demo')),
///       body: new Builder(
///         builder: (BuildContext context) {
///           return new FlatButton(
///             child: new Text('BUTTON'),
///             onPressed: () {
///               // here, Scaffold.of(context) returns the locally created Scaffold
///               Scaffold.of(context).showSnackBar(new SnackBar(
///                 content: new Text('Hello.')
///               ));
///             }
///           );
///         }
///       )
///     );
///   }
/// ```
///
/// The [BuildContext] for a particular widget can change location over time as
/// the widget is moved around the tree. Because of this, values returned from
/// the methods on this class should not be cached beyond the execution of a
/// single synchronous function.
///
/// [BuildContext] objects are actually [Element] objects. The [BuildContext]
/// interface is used to discourage direct manipulation of [Element] objects.
abstract class BuildContext {
  /// The current configuration of the [Element] that is this [BuildContext].
  Widget get widget;

  /// The current [RenderObject] for the widget. If the widget is a
  /// [RenderObjectWidget], this is the render object that the widget created
  /// for itself. Otherwise, it is the render object of the first descendant
  /// [RenderObjectWidget].
  ///
  /// This method will only return a valid result after the build phase is
  /// complete. It is therefore not valid to call this from the [build] function
  /// itself. It should only be called from interaction event handlers (e.g.
  /// gesture callbacks) or layout or paint callbacks.
  ///
  /// If the render object is a [RenderBox], which is the common case, then the
  /// size of the render object can be obtained from the [size] getter. This is
  /// only valid after the layout phase, and should therefore only be examined
  /// from paint callbacks or interaction event handlers (e.g. gesture
  /// callbacks).
  ///
  /// For details on the different phases of a frame, see
  /// [WidgetsBinding.beginFrame].
  ///
  /// Calling this method is theoretically relatively expensive (O(N) in the
  /// depth of the tree), but in practice is usually cheap because the tree
  /// usually has many render objects and therefore the distance to the nearest
  /// render object is usually short.
  RenderObject findRenderObject();

  /// The size of the [RenderBox] returned by [findRenderObject].
  ///
  /// This getter will only return a valid result after the layout phase is
  /// complete. It is therefore not valid to call this from the [build] function
  /// itself. It should only be called from paint callbacks or interaction event
  /// handlers (e.g. gesture callbacks).
  ///
  /// For details on the different phases of a frame, see
  /// [WidgetsBinding.beginFrame].
  ///
  /// This getter will only return a valid result if [findRenderObject] actually
  /// returns a [RenderBox]. If [findRenderObject] returns a render object that
  /// is not a subtype of [RenderBox] (e.g., [RenderView], this getter will
  /// throw an exception in checked mode and will return null in release mode.
  ///
  /// Calling this getter is theoretically relatively expensive (O(N) in the
  /// depth of the tree), but in practice is usually cheap because the tree
  /// usually has many render objects and therefore the distance to the nearest
  /// render object is usually short.
  Size get size;

  /// Obtains the nearest widget of the given type, which must be the type of a
  /// concrete [InheritedWidget] subclass, and registers this build context with
  /// that widget such that when that widget changes (or a new widget of that
  /// type is introduced, or the widget goes away), this build context is
  /// rebuilt so that it can obtain new values from that widget.
  ///
  /// This is typically called implicitly from `of()` static methods, e.g.
  /// [Theme.of].
  ///
  /// This should not be called from widget constructors or from
  /// [State.initState] methods, because those methods would not get called
  /// again if the inherited value were to change. To ensure that the widget
  /// correctly updates itself when the inherited value changes, only call this
  /// (directly or indirectly) from build methods, layout and paint callbacks, or
  /// from [State.dependenciesChanged].
  ///
  /// It is also possible to call this from interaction event handlers (e.g.
  /// gesture callbacks) or timers, to obtain a value once, if that value is not
  /// going to be cached and reused later.
  ///
  /// Calling this method is O(1) with a small constant factor, but will lead to
  /// the widget being rebuilt more often.
  ///
  /// Once a widget registers a dependency on a particular type by calling this
  /// method, it will be rebuilt, and [State.dependenciesChanged] will be
  /// called, whenever changes occur relating to that widget until the next time
  /// the widget or one of its ancestors is moved (for example, because an
  /// ancestor is added or removed).
  InheritedWidget inheritFromWidgetOfExactType(Type targetType);

  /// Returns the nearest ancestor widget of the given type, which must be the
  /// type of a concrete [Widget] subclass.
  ///
  /// This should not be used from build methods, because the build context will
  /// not be rebuilt if the value that would be returned by this method changes.
  /// In general, [inheritFromWidgetOfExactType] is more useful. This method is
  /// appropriate when used in interaction event handlers (e.g. gesture
  /// callbacks), or for performing one-off tasks.
  ///
  /// Calling this method is relatively expensive (O(N) in the depth of the
  /// tree). Only call this method if the distance from this widget to the
  /// desired ancestor is known to be small and bounded.
  Widget ancestorWidgetOfExactType(Type targetType);

  /// Returns the [State] object of the nearest ancestor [StatefulWidget] widget
  /// that matches the given [TypeMatcher].
  ///
  /// This should not be used from build methods, because the build context will
  /// not be rebuilt if the value that would be returned by this method changes.
  /// In general, [inheritFromWidgetOfExactType] is more appropriate for such
  /// cases. This method is useful to change the state of an ancestor widget in
  /// a one-off manner, for example, to cause an ancestor scrolling list to
  /// scroll this build context's widget into view, or to move the focus in
  /// response to user interaction.
  ///
  /// In general, though, consider using a callback that triggers a stateful
  /// change in the ancestor rather than using the imperative style implied by
  /// this method. This will usually lead to more maintainable and reusable code
  /// since it decouples widgets from each other.
  ///
  /// Calling this method is relatively expensive (O(N) in the depth of the
  /// tree). Only call this method if the distance from this widget to the
  /// desired ancestor is known to be small and bounded.
  State ancestorStateOfType(TypeMatcher matcher);

  /// Returns the [RenderObject] object of the nearest ancestor [RenderObjectWidget] widget
  /// that matches the given [TypeMatcher].
  ///
  /// This should not be used from build methods, because the build context will
  /// not be rebuilt if the value that would be returned by this method changes.
  /// In general, [inheritFromWidgetOfExactType] is more appropriate for such
  /// cases. This method is useful only in esoteric cases where a widget needs
  /// to cause an ancestor to change its layout or paint behavior. For example,
  /// it is used by [Material] so that [InkWell] widgets can trigger the ink
  /// splash on the [Material]'s actual render object.
  ///
  /// Calling this method is relatively expensive (O(N) in the depth of the
  /// tree). Only call this method if the distance from this widget to the
  /// desired ancestor is known to be small and bounded.
  RenderObject ancestorRenderObjectOfType(TypeMatcher matcher);

  /// Walks the ancestor chain, starting with the parent of this build context's
  /// widget, invoking the argument for each ancestor. The callback is given a
  /// reference to the ancestor widget's corresponding [Element] object. The
  /// walk stops when it reaches the root widget or when the callback returns
  /// false. The callback must not return null.
  ///
  /// This is useful for inspecting the widget tree.
  ///
  /// Calling this method is relatively expensive (O(N) in the depth of the tree).
  void visitAncestorElements(bool visitor(Element element));

  /// Walks the children of this widget.
  ///
  /// This is useful for applying changes to children after they are built
  /// without waiting for the next frame, especially if the children are known,
  /// and especially if there is exactly one child (as is always the case for
  /// [StatefulWidget]s or [StatelessWidget]s).
  ///
  /// Calling this method is very cheap for build contexts that correspond to
  /// [StatefulWidget]s or [StatelessWidget]s (O(1), since there's only one
  /// child).
  ///
  /// Calling this method is potentially expensive for build contexts that
  /// correspond to [RenderObjectWidget]s (O(N) in the number of children).
  ///
  /// Calling this method recursively is extremely expensive (O(N) in the number
  /// of descendants), and should be avoided if possible. Generally it is
  /// significantly cheaper to use an [InheritedWidget] and have the descendants
  /// pull data down, than it is to use [visitChildElements] recursively to push
  /// data down to them.
  void visitChildElements(ElementVisitor visitor);
}

/// Manager class for the widgets framework.
///
/// This class tracks which widgets need rebuilding, and handles other tasks
/// that apply to widget trees as a whole, such as managing the inactive element
/// list for the tree and triggering the "reassemble" command when necessary
/// during debugging.
///
/// The main build owner is typically owned by the [WidgetsBinding], and is
/// driven from the operating system along with the rest of the
/// build/layout/paint pipeline.
///
/// Additional build owners can be built to manage off-screen widget trees.
///
/// To assign a build owner to a tree, use the
/// [RootRenderObjectElement.assignOwner] method on the root element of the
/// widget tree.
class BuildOwner {
  /// Creates an object that manages widgets.
  BuildOwner({ this.onBuildScheduled });

  /// Called on each build pass when the first buildable element is marked
  /// dirty.
  VoidCallback onBuildScheduled;

  final _InactiveElements _inactiveElements = new _InactiveElements();

  final List<BuildableElement> _dirtyElements = <BuildableElement>[];
  bool _scheduledFlushDirtyElements = false;
  bool _dirtyElementsNeedsResorting; // null means we're not in a buildScope

  /// Flags the dirty elements list as needing resorting.
  ///
  /// This should only be called while a [buildScope] is actively rebuilding the
  /// widget tree.
  void markNeedsToResortDirtyElements() {
    assert(() {
      if (debugPrintScheduleBuildForStacks)
        debugPrintStack(label: 'markNeedsToResortDirtyElements() called; _dirtyElementsNeedsResorting was $_dirtyElementsNeedsResorting (now true); dirty list is: $_dirtyElements');
      if (_dirtyElementsNeedsResorting == null) {
        throw new FlutterError(
          'markNeedsToResortDirtyElements() called inappropriately.\n'
          'The markNeedsToResortDirtyElements() method should only be called while the '
          'buildScope() method is actively rebuilding the widget tree.'
        );
      }
      return true;
    });
    _dirtyElementsNeedsResorting = true;
  }

  /// Adds an element to the dirty elements list so that it will be rebuilt
  /// when [WidgetsBinding.beginFrame] calls [buildScope].
  void scheduleBuildFor(BuildableElement element) {
    assert(element != null);
    assert(element.owner == this);
    assert(element._inDirtyList == _dirtyElements.contains(element));
    assert(() {
      if (debugPrintScheduleBuildForStacks)
        debugPrintStack(label: 'scheduleBuildFor() called for $element${_dirtyElements.contains(element) ? " (ALREADY IN LIST)" : ""}');
      if (element._inDirtyList) {
        throw new FlutterError(
          'scheduleBuildFor() called for a widget for which a build was already scheduled.\n'
          'The method was called for the following element:\n'
          '  $element\n'
          'The current dirty list consists of:\n'
          '  $_dirtyElements\n'
          'This usually indicates that a widget was rebuilt outside the build phase (thus '
          'marking the element as clean even though it is still in the dirty list). '
          'This should not be possible and is probably caused by a bug in the widgets framework. '
          'Please report it: https://github.com/flutter/flutter/issues/new\n'
          'To debug this issue, consider setting the debugPrintScheduleBuildForStacks and '
          'debugPrintBuildDirtyElements flags to true and looking for a call to scheduleBuildFor '
          'for a widget that is labeled "ALREADY IN LIST".'
        );
      }
      if (!element.dirty) {
        throw new FlutterError(
          'scheduleBuildFor() called for a widget that is not marked as dirty.\n'
          'The method was called for the following element:\n'
          '  $element\n'
          'This element is not current marked as dirty. Make sure to set the dirty flag before '
          'calling scheduleBuildFor().\n'
          'If you did not attempt to call scheduleBuildFor() yourself, then this probably '
          'indicates a bug in the widgets framework. Please report it: '
          'https://github.com/flutter/flutter/issues/new'
        );
      }
      return true;
    });
    if (!_scheduledFlushDirtyElements && onBuildScheduled != null) {
      _scheduledFlushDirtyElements = true;
      onBuildScheduled();
    }
    _dirtyElements.add(element);
    element._inDirtyList = true;
    assert(() {
      if (debugPrintScheduleBuildForStacks)
        debugPrint('...dirty list is now: $_dirtyElements');
      return true;
    });
  }

  int _debugStateLockLevel = 0;
  bool get _debugStateLocked => _debugStateLockLevel > 0;
  bool _debugBuilding = false;
  BuildableElement _debugCurrentBuildTarget;

  /// Establishes a scope in which calls to [State.setState] are forbidden, and
  /// calls the given `callback`.
  ///
  /// This mechanism is used to ensure that, for instance, [State.dispose] does
  /// not call [State.setState].
  void lockState(void callback()) {
    assert(callback != null);
    assert(_debugStateLockLevel >= 0);
    assert(() {
      _debugStateLockLevel += 1;
      return true;
    });
    try {
      callback();
    } finally {
      assert(() {
        _debugStateLockLevel -= 1;
        return true;
      });
    }
    assert(_debugStateLockLevel >= 0);
  }

  /// Establishes a scope for updating the widget tree, and calls the given
  /// `callback`, if any. Then, builds all the elements that were marked as
  /// dirty using [scheduleBuildFor], in depth order.
  ///
  /// This mechanism prevents build functions from transitively requiring other
  /// build functions to run, potentially causing infinite loops.
  ///
  /// The dirty list is processed after `callback` returns, building all the
  /// elements that were marked as dirty using [scheduleBuildFor], in depth
  /// order. If elements are marked as dirty while this method is running, they
  /// must be deeper than the `context` node, and deeper than any
  /// previously-built node in this pass.
  ///
  /// To flush the current dirty list without performing any other work, this
  /// function can be called with no callback. This is what the framework does
  /// each frame, in [WidgetsBinding.beginFrame].
  ///
  /// Only one [buildScope] can be active at a time.
  ///
  /// A [buildScope] implies a [lockState] scope as well.
  void buildScope(BuildableElement context, [VoidCallback callback]) {
    if (callback == null && _dirtyElements.isEmpty)
      return;
    assert(context != null);
    assert(_debugStateLockLevel >= 0);
    assert(!_debugBuilding);
    assert(() {
      if (debugPrintBuildScope)
        debugPrint('buildScope called with context $context; dirty list is: $_dirtyElements');
      _debugStateLockLevel += 1;
      _debugBuilding = true;
      return true;
    });
    Timeline.startSync('Build');
    try {
      _scheduledFlushDirtyElements = true;
      if (callback != null) {
        assert(context is BuildableElement);
        assert(_debugStateLocked);
        BuildableElement debugPreviousBuildTarget;
        assert(() {
          context._debugSetAllowIgnoredCallsToMarkNeedsBuild(true);
          debugPreviousBuildTarget = _debugCurrentBuildTarget;
          _debugCurrentBuildTarget = context;
         return true;
        });
        _dirtyElementsNeedsResorting = false;
        try {
          callback();
        } finally {
          assert(() {
            context._debugSetAllowIgnoredCallsToMarkNeedsBuild(false);
            assert(_debugCurrentBuildTarget == context);
            _debugCurrentBuildTarget = debugPreviousBuildTarget;
            return true;
          });
        }
      }
      _dirtyElements.sort(Element._sort);
      _dirtyElementsNeedsResorting = false;
      int dirtyCount = _dirtyElements.length;
      int index = 0;
      while (index < dirtyCount) {
        assert(_dirtyElements[index] != null);
        assert(_dirtyElements[index]._inDirtyList);
        assert(!_dirtyElements[index]._active || _dirtyElements[index]._debugIsInScope(context));
        try {
          _dirtyElements[index].rebuild();
        } catch (e, stack) {
          _debugReportException(
            'while rebuilding dirty elements', e, stack,
            informationCollector: (StringBuffer information) {
              information.writeln('The element being rebuilt at the time was index $index of $dirtyCount:');
              information.write('  ${_dirtyElements[index]}');
            }
          );
        }
        index += 1;
        if (dirtyCount < _dirtyElements.length || _dirtyElementsNeedsResorting) {
          _dirtyElements.sort(Element._sort);
          _dirtyElementsNeedsResorting = false;
          dirtyCount = _dirtyElements.length;
          while (index > 0 && _dirtyElements[index - 1].dirty) {
            // It is possible for previously dirty but inactive widgets to move right in the list.
            // We therefore have to move the index left in the list to account for this.
            // We don't know how many could have moved. However, we do know that the only possible
            // change to the list is that nodes that were previously to the left of the index have
            // now moved to be to the right of the right-most cleaned node, and we do know that
            // all the clean nodes were to the left of the index. So we move the index left
            // until just after the right-most clean node.
            index -= 1;
          }
        }
      }
      assert(() {
        if (_dirtyElements.any((BuildableElement element) => element._active && element.dirty)) {
          throw new FlutterError(
            'buildScope missed some dirty elements.\n'
            'This probably indicates that the dirty list should have been resorted but was not.\n'
            'The list of dirty elements at the end of the buildScope call was:\n'
            '  $_dirtyElements'
          );
        }
        return true;
      });
    } finally {
      for (BuildableElement element in _dirtyElements) {
        assert(element._inDirtyList);
        element._inDirtyList = false;
      }
      _dirtyElements.clear();
      _scheduledFlushDirtyElements = false;
      _dirtyElementsNeedsResorting = null;
      Timeline.finishSync();
      assert(_debugBuilding);
      assert(() {
        _debugBuilding = false;
        _debugStateLockLevel -= 1;
        if (debugPrintBuildScope)
          debugPrint('buildScope finished');
        return true;
      });
    }
    assert(_debugStateLockLevel >= 0);
  }

  /// Complete the element build pass by unmounting any elements that are no
  /// longer active.
  ///
  /// This is called by [WidgetsBinding.beginFrame].
  ///
  /// In checked mode, this also verifies that each global key is used at most
  /// once.
  ///
  /// After the current call stack unwinds, a microtask that notifies listeners
  /// about changes to global keys will run.
  void finalizeTree() {
    Timeline.startSync('Finalize tree');
    try {
      lockState(() {
        _inactiveElements._unmountAll();
      });
      assert(GlobalKey._debugCheckForDuplicates);
      scheduleMicrotask(GlobalKey._notifyListeners);
    } catch (e, stack) {
      _debugReportException('while finalizing the widget tree', e, stack);
    } finally {
      Timeline.finishSync();
    }
  }

  /// Cause the entire subtree rooted at the given [Element] to be entirely
  /// rebuilt. This is used by development tools when the application code has
  /// changed, to cause the widget tree to pick up any changed implementations.
  ///
  /// This is expensive and should not be called except during development.
  void reassemble(Element root) {
    assert(root._parent == null);
    assert(root.owner == this);
    root._reassemble();
  }
}

/// An instantiation of a [Widget] at a particular location in the tree.
///
/// Widgets describe how to configure a subtree but the same widget can be used
/// to configure multiple subtrees simultaneously because widgets are immutable.
/// An [Element] represents the use of a widget to configure a specific location
/// in the tree. Over time, the widget associated with a given element can
/// change, for example, if the parent widget rebuilds and creates a new widget
/// for this location.
///
/// Elements form a tree. Most elements have a unique child, but some widgets
/// (e.g., subclasses of [RenderObjectElement]) can have multiple children.
///
/// Elements have the following lifecycle:
///
///  * The framework creates an element by calling [Widget.createElement] on the
///    widget that will be used as the element's initial configuration.
///  * The framework calls [mount] to add the newly created element to the tree
///    at a given slot in a given parent. The [mount] method is responsible for
///    inflating any child widgets and calling [attachRenderObject] as
///    necessary to attach any associated render objects to the render tree.
///  * At this point, the element is considered "active" and might appear on
///    screen.
///  * At some point, the parent might decide to change the widget used to
///    configure this element, for example because the parent rebuilt with new
///    state. When this happens, the framework will call [update] with the new
///    widget. The new widget will always have the same [runtimeType] and key as
///    old widget. If the parent wishes to change the [runtimeType] or key of
///    the widget at this location in the tree, can do so by unmounting this
///    element and inflating the new widget at this location.
///  * At some point, an ancestor might decide to remove this element (or an
///    intermediate ancestor) from the tree, which the ancestor does by calling
///    [deactivateChild] on itself. Deactivating the intermediate ancestor will
///    remove that element's render object from the render tree and add this
///    element to the [owner]'s list of inactive elements, causing the framework
///    to call [deactivate] on this element.
///  * At this point, the element is considered "inactive" and will not appear
///    on screen. An element can remain in the inactive state only only until
///    the end of the current animation frame. At the end of the animation
///    frame, any elements that are still inactive will be unmounted.
///  * If the element gets reincorporated into the tree (e.g., because it or one
///    of its ancestors has a global key that is reused), the framework will
///    remove the element from the [owner]'s list of inactive elements, call
///    [activate] on the element, and reattach the element's render object to
///    the render tree. (At this point, the element is again considered "active"
///    and might appear on screen.)
///  * If the element does not get reincorporated into the tree by the end of
///    the current animation frame, the framework will call [unmount] on the
///    element.
///  * At this point, the element is considered "defunct" and will not be
///    incorporated into the tree in the future.
abstract class Element implements BuildContext {
  /// Creates an element that uses the given widget as its configuration.
  ///
  /// Typically called by an override of [Widget.createElement].
  Element(Widget widget) : _widget = widget {
    assert(widget != null);
  }

  Element _parent;

  /// Information set by parent to define where this child fits in its parent's
  /// child list.
  ///
  /// Subclasses of Element that only have one child should use null for
  /// the slot for that child.
  dynamic get slot => _slot;
  dynamic _slot;

  /// An integer that is guaranteed to be greater than the parent's, if any.
  /// The element at the root of the tree must have a depth greater than 0.
  int get depth => _depth;
  int _depth;

  static int _sort(BuildableElement a, BuildableElement b) {
    if (a.depth < b.depth)
      return -1;
    if (b.depth < a.depth)
      return 1;
    if (b.dirty && !a.dirty)
      return -1;
    if (a.dirty && !b.dirty)
      return 1;
    return 0;
  }

  /// The configuration for this element.
  @override
  Widget get widget => _widget;
  Widget _widget;

  /// The object that manages the lifecycle of this element.
  BuildOwner get owner => _owner;
  BuildOwner _owner;

  bool _active = false;

  void _reassemble() {
    assert(_active);
    visitChildren((Element child) {
      child._reassemble();
    });
  }

  bool _debugIsInScope(Element target) {
    assert(target != null);
    if (target == this)
      return true;
    if (_parent != null)
      return _parent._debugIsInScope(target);
    return false;
  }

  /// The render object at (or below) this location in the tree.
  ///
  /// If this object is a [RenderObjectElement], the render object is the one at
  /// this location in the tree. Otherwise, this getter will walk down the tree
  /// until it finds a [RenderObjectElement].
  RenderObject get renderObject {
    RenderObject result;
    void visit(Element element) {
      assert(result == null); // this verifies that there's only one child
      if (element is RenderObjectElement)
        result = element.renderObject;
      else
        element.visitChildren(visit);
    }
    visit(this);
    return result;
  }

  // This is used to verify that Element objects move through life in an
  // orderly fashion.
  _ElementLifecycle _debugLifecycleState = _ElementLifecycle.initial;

  /// Calls the argument for each child. Must be overridden by subclasses that
  /// support having children.
  void visitChildren(ElementVisitor visitor) { }

  /// Calls the argument for each child that is relevant for semantics. By
  /// default, defers to [visitChildren]. Classes like [Offstage] override this
  /// to hide their children.
  void visitChildrenForSemantics(ElementVisitor visitor) => visitChildren(visitor);

  /// Wrapper around visitChildren for BuildContext.
  @override
  void visitChildElements(ElementVisitor visitor) {
    // don't allow visitChildElements() during build, since children aren't necessarily built yet
    assert(owner == null || !owner._debugStateLocked);
    visitChildren(visitor);
  }

  /// Remove the given child.
  ///
  /// This updates the child model such that [visitChildren] does not walk that
  /// child anymore.
  ///
  /// The element must have already been deactivated when this is called,
  /// meaning that its parent should be null.
  @protected
  void detachChild(Element child);

  /// This method is the core of the system.
  ///
  /// It is called each time we are to add, update, or remove a child based on
  /// an updated configuration.
  ///
  /// If the child is null, and the newWidget is not null, then we have a new
  /// child for which we need to create an Element, configured with newWidget.
  ///
  /// If the newWidget is null, and the child is not null, then we need to
  /// remove it because it no longer has a configuration.
  ///
  /// If neither are null, then we need to update the child's configuration to
  /// be the new configuration given by newWidget. If newWidget can be given to
  /// the existing child, then it is so given. Otherwise, the old child needs
  /// to be disposed and a new child created for the new configuration.
  ///
  /// If both are null, then we don't have a child and won't have a child, so
  /// we do nothing.
  ///
  /// The updateChild() method returns the new child, if it had to create one,
  /// or the child that was passed in, if it just had to update the child, or
  /// null, if it removed the child and did not replace it.
  @protected
  Element updateChild(Element child, Widget newWidget, dynamic newSlot) {
    if (newWidget == null) {
      if (child != null)
        deactivateChild(child);
      return null;
    }
    if (child != null) {
      if (child.widget == newWidget) {
        if (child.slot != newSlot)
          updateSlotForChild(child, newSlot);
        return child;
      }
      if (Widget.canUpdate(child.widget, newWidget)) {
        if (child.slot != newSlot)
          updateSlotForChild(child, newSlot);
        child.update(newWidget);
        assert(child.widget == newWidget);
        return child;
      }
      deactivateChild(child);
      assert(child._parent == null);
    }
    return inflateWidget(newWidget, newSlot);
  }

  /// Add this element to the tree in the given slot of the given parent.
  ///
  /// The framework calls this function when a newly created element is added to
  /// the tree for the first time. Use this method to initialize state that
  /// depends on having a parent. State that is independent of the parent can
  /// more easily be initialized in the constructor.
  ///
  /// This method transitions the element from the "initial" lifecycle state to
  /// the "active" lifecycle state.
  @mustCallSuper
  void mount(Element parent, dynamic newSlot) {
    assert(_debugLifecycleState == _ElementLifecycle.initial);
    assert(widget != null);
    assert(_parent == null);
    assert(parent == null || parent._debugLifecycleState == _ElementLifecycle.active);
    assert(slot == null);
    assert(depth == null);
    assert(!_active);
    _parent = parent;
    _slot = newSlot;
    _depth = _parent != null ? _parent.depth + 1 : 1;
    _active = true;
    if (parent != null) // Only assign ownership if the parent is non-null
      _owner = parent.owner;
    if (widget.key is GlobalKey) {
      final GlobalKey key = widget.key;
      key._register(this);
    }
    _updateInheritance();
    assert(() { _debugLifecycleState = _ElementLifecycle.active; return true; });
  }

  /// Change the widget used to configure this element.
  ///
  /// The framework calls this function when the parent wishes to use a
  /// different widget to configure this element. The new widget is guaranteed
  /// to have the same [runtimeType] as the old widget.
  ///
  /// This function is called only during the "active" lifecycle state.
  @mustCallSuper
  void update(@checked Widget newWidget) {
    assert(_debugLifecycleState == _ElementLifecycle.active);
    assert(widget != null);
    assert(newWidget != null);
    assert(newWidget != widget);
    assert(depth != null);
    assert(_active);
    assert(Widget.canUpdate(widget, newWidget));
    _widget = newWidget;
  }

  /// Change the slot that the given child occupies in its parent.
  ///
  /// Called by [MultiChildRenderObjectElement], and other [RenderObjectElement]
  /// subclasses that have multiple children, when child moves from one position
  /// to another in this element's child list.
  @protected
  void updateSlotForChild(Element child, dynamic newSlot) {
    assert(_debugLifecycleState == _ElementLifecycle.active);
    assert(child != null);
    assert(child._parent == this);
    void visit(Element element) {
      element._updateSlot(newSlot);
      if (element is! RenderObjectElement)
        element.visitChildren(visit);
    }
    visit(child);
  }

  void _updateSlot(dynamic newSlot) {
    assert(_debugLifecycleState == _ElementLifecycle.active);
    assert(widget != null);
    assert(_parent != null);
    assert(_parent._debugLifecycleState == _ElementLifecycle.active);
    assert(depth != null);
    _slot = newSlot;
  }

  void _updateDepth(int parentDepth) {
    int expectedDepth = parentDepth + 1;
    if (_depth < expectedDepth) {
      _depth = expectedDepth;
      visitChildren((Element child) {
        child._updateDepth(expectedDepth);
      });
    }
  }

  /// Remove [renderObject] from the render tree.
  ///
  /// The default implementation of this function simply calls
  /// [detachRenderObject] recursively on its children. The
  /// [RenderObjectElement.detachRenderObject] override does the actual work of
  /// removing [renderObject] from the render tree.
  void detachRenderObject() {
    visitChildren((Element child) {
      child.detachRenderObject();
    });
    _slot = null;
  }

  /// Add [renderObject] to the render tree at the location specified by [slot].
  ///
  /// The default implementation of this function simply calls
  /// [attachRenderObject] recursively on its children. The
  /// [RenderObjectElement.attachRenderObject] override does the actual work of
  /// adding [renderObject] to the render tree.
  void attachRenderObject(dynamic newSlot) {
    assert(_slot == null);
    visitChildren((Element child) {
      child.attachRenderObject(newSlot);
    });
    _slot = newSlot;
  }

  Element _retakeInactiveElement(GlobalKey key, Widget newWidget) {
    Element element = key._currentElement;
    if (element == null)
      return null;
    if (!Widget.canUpdate(element.widget, newWidget))
      return null;
    assert(() {
      if (debugPrintGlobalKeyedWidgetLifecycle)
        debugPrint('Attempting to take $element from ${element._parent ?? "inactive elements list"} to put in $this.');
      return true;
    });
    final Element parent = element._parent;
    if (parent != null) {
      parent.deactivateChild(element);
      parent.detachChild(element);
    }
    assert(element._parent == null);
    owner._inactiveElements.remove(element);
    return element;
  }

  /// Create an element for the given widget and add it as a child of this element in the given slot.
  ///
  /// This method is typically called by [updateChild] but can be called
  /// directly by subclasses that need finer-grained control over creating
  /// elements.
  ///
  /// If the given widget has a global key and an element already exists that
  /// has a widget with that global key, this function will reuse that element
  /// (potentially grafting it from another location in the tree or reactivating
  /// it from the list of inactive elements) rather than creating a new element.
  ///
  /// The element returned by this function will already have been mounted and
  /// will be in the "active" lifecycle state.
  @protected
  Element inflateWidget(Widget newWidget, dynamic newSlot) {
    assert(newWidget != null);
    Key key = newWidget.key;
    if (key is GlobalKey) {
      Element newChild = _retakeInactiveElement(key, newWidget);
      if (newChild != null) {
        assert(newChild._parent == null);
        assert(() { _debugCheckForCycles(newChild); return true; });
        newChild._activateWithParent(this, newSlot);
        Element updatedChild = updateChild(newChild, newWidget, newSlot);
        assert(newChild == updatedChild);
        return updatedChild;
      }
    }
    Element newChild = newWidget.createElement();
    assert(() { _debugCheckForCycles(newChild); return true; });
    newChild.mount(this, newSlot);
    assert(newChild._debugLifecycleState == _ElementLifecycle.active);
    return newChild;
  }

  void _debugCheckForCycles(Element newChild) {
    assert(newChild._parent == null);
    assert(() {
      Element node = this;
      while (node._parent != null)
        node = node._parent;
      assert(node != newChild); // indicates we are about to create a cycle
      return true;
    });
  }

  /// Move the given element to the list of inactive elements.
  ///
  /// This method stops the given element from being a child of this element by
  /// detaching its render object from the render tree and moving the element to
  /// the list of inactive elements.
  ///
  /// The caller is responsible from removing the child from its child model.
  @protected
  void deactivateChild(Element child) {
    assert(child != null);
    assert(child._parent == this);
    child._parent = null;
    child.detachRenderObject();
    owner._inactiveElements.add(child); // this eventually calls child.deactivate()
    assert(() {
      if (debugPrintGlobalKeyedWidgetLifecycle) {
        if (child.widget.key is GlobalKey)
          debugPrint('Deactivated $child (keyed child of $this)');
      }
      return true;
    });
  }

  void _activateWithParent(Element parent, dynamic newSlot) {
    assert(_debugLifecycleState == _ElementLifecycle.inactive);
    _parent = parent;
    assert(() {
      if (debugPrintGlobalKeyedWidgetLifecycle)
        debugPrint('Reactivating $this (now child of $_parent).');
      return true;
    });
    _updateDepth(_parent.depth);
    _activateRecursively(this);
    attachRenderObject(newSlot);
    assert(_debugLifecycleState == _ElementLifecycle.active);
  }

  static void _activateRecursively(Element element) {
    assert(element._debugLifecycleState == _ElementLifecycle.inactive);
    element.activate();
    assert(element._debugLifecycleState == _ElementLifecycle.active);
    element.visitChildren(_activateRecursively);
  }

  /// Transition from the "inactive" to the "active" lifecycle state.
  ///
  /// The framework calls this method when a previously deactivated element has
  /// been reincorporated into the tree. The framework does not call this method
  /// the first time an element becomes active (i.e., from the "initial"
  /// lifecycle state). Instead, the framework calls [mount] in that situation.
  ///
  /// See the lifecycle documentation for [Element] for additional information.
  @mustCallSuper
  void activate() {
    assert(_debugLifecycleState == _ElementLifecycle.inactive);
    assert(widget != null);
    assert(owner != null);
    assert(depth != null);
    assert(!_active);
    _active = true;
    // We unregistered our dependencies in deactivate, but never cleared the list.
    // Since we're going to be reused, let's clear our list now.
    _dependencies?.clear();
    _hadUnsatisfiedDependencies = false;
    _updateInheritance();
    assert(() { _debugLifecycleState = _ElementLifecycle.active; return true; });
  }

  /// Transition from the "active" to the "inactive" lifecycle state.
  ///
  /// The framework calls this method when a previously active element is moved
  /// to the list of inactive elements. While in the inactive state, the element
  /// will not appear on screen. The element can remain in the inactive state
  /// only until the end of the current animation frame. At the end of the
  /// animation frame, if the element has not be reactivated, the framework will
  /// unmount the element.
  ///
  /// See the lifecycle documentation for [Element] for additional information.
  @mustCallSuper
  void deactivate() {
    assert(_debugLifecycleState == _ElementLifecycle.active);
    assert(widget != null);
    assert(depth != null);
    assert(_active);
    if (_dependencies != null && _dependencies.length > 0) {
      for (InheritedElement dependency in _dependencies)
        dependency._dependents.remove(this);
      // For expediency, we don't actually clear the list here, even though it's
      // no longer representative of what we are registered with. If we never
      // get re-used, it doesn't matter. If we do, then we'll clear the list in
      // activate(). The benefit of this is that it allows BuildableElement's
      // activate() implementation to decide whether to rebuild based on whether
      // we had dependencies here.
    }
    _inheritedWidgets = null;
    _active = false;
    assert(() { _debugLifecycleState = _ElementLifecycle.inactive; return true; });
  }

  /// Called after children have been deactivated (see [deactivate]).
  @mustCallSuper
  void debugDeactivated() {
    assert(_debugLifecycleState == _ElementLifecycle.inactive);
  }

  /// Transition from the "inactive" to the "defunct" lifecycle state.
  ///
  /// Called when the framework determines that an inactive element will never
  /// be reactivated. At the end of each animation frame, the framework calls
  /// [unmount] on any remaining inactive elements, preventing inactive elements
  /// from remaining inactive for longer than a single animation frame.
  ///
  /// After this function is called, the element will not be incorporated into
  /// the tree again.
  ///
  /// See the lifecycle documentation for [Element] for additional information.
  @mustCallSuper
  void unmount() {
    assert(_debugLifecycleState == _ElementLifecycle.inactive);
    assert(widget != null);
    assert(depth != null);
    assert(!_active);
    if (widget.key is GlobalKey) {
      final GlobalKey key = widget.key;
      key._unregister(this);
    }
    assert(() { _debugLifecycleState = _ElementLifecycle.defunct; return true; });
  }

  @override
  RenderObject findRenderObject() => renderObject;

  @override
  Size get size {
    assert(() {
      if (_debugLifecycleState != _ElementLifecycle.active) {
        throw new FlutterError(
          'Cannot get size of inactive element.\n'
          'In order for an element to have a valid size, the element must be '
          'active, which means it is part of the tree. Instead, this element '
          'is in the $_debugLifecycleState state.\n'
          'The size getter was called for the following element:\n'
          '  $this\n'
        );
      }
      if (owner._debugBuilding) {
        throw new FlutterError(
          'Cannot get size during build.\n'
          'The size of this render object has not yet been determined because '
          'the framework is still in the process of building widgets, which '
          'means the render tree for this frame has not youet been determined. '
          'The size getter should only be called from paint callbacks or '
          'interaction event handlers (e.g. gesture callbacks).\n'
          '\n'
          'If you need some sizing information during build to decide which '
          'widgets to build, consider using a LayoutBuilder widget, which can '
          'tell you the layout constraints at a given location in the tree. See '
          '<https://docs.flutter.io/flutter/widgets/LayoutBuilder-class.html> '
          'for more details.\n'
          '\n'
          'The size getter was called for the following element:\n'
          '  $this\n'
        );
      }
      return true;
    });
    final RenderObject renderObject = findRenderObject();
    assert(() {
      if (renderObject == null) {
        throw new FlutterError(
          'Cannot get size without a render object.\n'
          'In order for an element to have a valid size, the element must have '
          'an assoicated render object. This element does not have an assoicated '
          'render object, which typically means that the size getter was called '
          'too early in the pipeline (e.g., during the build phase) before the '
          'framework has created the render tree.\n'
          'The size getter was called for the following element:\n'
          '  $this\n'
        );
      }
      if (renderObject is! RenderBox) {
        throw new FlutterError(
          'Cannot get size from a render object that is not a RenderBox.\n'
          'Instead of being a subtype of RenderBox, the render object associated '
          'with this element is a ${renderObject.runtimeType}. If this type of '
          'render object does have a size, consider calling findRenderObject '
          'and extracting its size manually.\n'
          'The size getter was called for the following element:\n'
          '  $this\n'
        );
      }
      final RenderBox box = renderObject;
      if (!box.hasSize || box.needsLayout) {
        throw new FlutterError(
          'Cannot get size from a render object that has not been through layout.\n'
          'The size of this render object has not yet been determined because '
          'this render object has not yet been through layout, which typically '
          'means that the size getter was called too early in the pipeline '
          '(e.g., during the build pahse) before the framework has determined '
          'the size and position of the render objects during layout.\n'
          'The size getter was called for the following element:\n'
          '  $this\n'
        );
      }
      return true;
    });
    if (renderObject is RenderBox)
      return renderObject.size;
    return null;
  }

  Map<Type, InheritedElement> _inheritedWidgets;
  Set<InheritedElement> _dependencies;
  bool _hadUnsatisfiedDependencies = false;

  @override
  InheritedWidget inheritFromWidgetOfExactType(Type targetType) {
    InheritedElement ancestor = _inheritedWidgets == null ? null : _inheritedWidgets[targetType];
    if (ancestor != null) {
      assert(ancestor is InheritedElement);
      _dependencies ??= new HashSet<InheritedElement>();
      _dependencies.add(ancestor);
      ancestor._dependents.add(this);
      return ancestor.widget;
    }
    _hadUnsatisfiedDependencies = true;
    return null;
  }

  void _updateInheritance() {
    assert(_active);
    _inheritedWidgets = _parent?._inheritedWidgets;
  }

  @override
  Widget ancestorWidgetOfExactType(Type targetType) {
    Element ancestor = _parent;
    while (ancestor != null && ancestor.widget.runtimeType != targetType)
      ancestor = ancestor._parent;
    return ancestor?.widget;
  }

  @override
  State ancestorStateOfType(TypeMatcher matcher) {
    Element ancestor = _parent;
    while (ancestor != null) {
      if (ancestor is StatefulElement && matcher.check(ancestor.state))
        break;
      ancestor = ancestor._parent;
    }
    StatefulElement statefulAncestor = ancestor;
    return statefulAncestor?.state;
  }

  @override
  RenderObject ancestorRenderObjectOfType(TypeMatcher matcher) {
    Element ancestor = _parent;
    while (ancestor != null) {
      if (ancestor is RenderObjectElement && matcher.check(ancestor.renderObject))
        break;
      ancestor = ancestor._parent;
    }
    RenderObjectElement renderObjectAncestor = ancestor;
    return renderObjectAncestor?.renderObject;
  }

  @override
  void visitAncestorElements(bool visitor(Element element)) {
    Element ancestor = _parent;
    while (ancestor != null && visitor(ancestor))
      ancestor = ancestor._parent;
  }

  /// Called when a dependency of this element changes.
  ///
  /// The [inheritFromWidgetOfExactType] registers this element as depending on
  /// inherited information of the given type. When the information of that type
  /// changes at this location in the tree (e.g., because the [InheritedElement]
  /// updated to a new [InheritedWidget] and
  /// [InheritedWidget.updateShouldNotify] returned true), the framework calls
  /// this function to notify this element of the change.
  @mustCallSuper
  void dependenciesChanged() { }

  /// Returns a description of what caused this element to be created.
  ///
  /// Useful for debugging the source of an element.
  String debugGetCreatorChain(int limit) {
    List<String> chain = <String>[];
    Element node = this;
    while (chain.length < limit && node != null) {
      chain.add(node.toStringShort());
      node = node._parent;
    }
    if (node != null)
      chain.add('\u22EF');
    return chain.join(' \u2190 ');
  }

  /// A short, textual description of this element.
  String toStringShort() {
    return widget != null ? '${widget.toStringShort()}' : '[$runtimeType]';
  }

  @override
  String toString() {
    final List<String> data = <String>[];
    debugFillDescription(data);
    final String name = widget != null ? '${widget.runtimeType}' : '[$runtimeType]';
    return '$name(${data.join("; ")})';
  }

  /// Add additional information to the given description for use by [toString].
  ///
  /// This method makes it easier for subclasses to coordinate to provide a
  /// high-quality [toString] implementation. The [toString] implementation on
  /// the [State] base class calls [debugFillDescription] to collect useful
  /// information from subclasses to incorporate into its return value.
  ///
  /// If you override this, make sure to start your method with a call to
  /// `super.debugFillDescription(description)`.
  @protected
  @mustCallSuper
  void debugFillDescription(List<String> description) {
    if (depth == null)
      description.add('no depth');
    if (widget == null) {
      description.add('no widget');
    } else {
      if (widget.key != null)
        description.add('${widget.key}');
      widget.debugFillDescription(description);
    }
  }

  /// A detailed, textual description of this element, includings its children.
  String toStringDeep([String prefixLineOne = '', String prefixOtherLines = '']) {
    String result = '$prefixLineOne$this\n';
    List<Element> children = <Element>[];
    visitChildren(children.add);
    if (children.length > 0) {
      Element last = children.removeLast();
      for (Element child in children)
        result += '${child.toStringDeep("$prefixOtherLines \u251C", "$prefixOtherLines \u2502")}';
      result += '${last.toStringDeep("$prefixOtherLines \u2514", "$prefixOtherLines  ")}';
    }
    return result;
  }
}

/// A widget that renders an exception's message.
///
/// This widget is used when a build function fails, to help with determining
/// where the problem lies. Exceptions are also logged to the console, which you
/// can read using `flutter logs`. The console will also include additional
/// information such as the stack trace for the exception.
class ErrorWidget extends LeafRenderObjectWidget {
  /// Creates a widget that displays the given error message.
  ErrorWidget(Object exception) : message = _stringify(exception),
      super(key: new UniqueKey());

  /// The message to display.
  final String message;

  static String _stringify(Object exception) {
    try {
      return exception.toString();
    } catch (e) { }
    return 'Error';
  }

  @override
  RenderBox createRenderObject(BuildContext context) => new RenderErrorBox(message);

  @override
  void debugFillDescription(List<String> description) {
    super.debugFillDescription(description);
    description.add('message: ' + _stringify(message));
  }
}

/// An [Element] that can be marked dirty and rebuilt.
///
/// In practice, all subclasses of [Element] in the Flutter framework are
/// subclasses of [BuildableElement]. The distinction exists primarily to
/// segregate unrelated code.
abstract class BuildableElement extends Element {
  /// Creates an element that uses the given widget as its configuration.
  BuildableElement(Widget widget) : super(widget);

  /// Returns true if the element has been marked as needing rebuilding.
  bool get dirty => _dirty;
  bool _dirty = true;

  // Whether this is in owner._dirtyElements. This is used to know whether we
  // should be adding the element back into the list when it's reactivated.
  bool _inDirtyList = false;

  // Whether we've already built or not. Set in [rebuild].
  bool _debugBuiltOnce = false;

  // We let widget authors call setState from initState, didUpdateConfig, and
  // build even when state is locked because its convenient and a no-op anyway.
  // This flag ensures that this convenience is only allowed on the element
  // currently undergoing initState, didUpdateConfig, or build.
  bool _debugAllowIgnoredCallsToMarkNeedsBuild = false;
  bool _debugSetAllowIgnoredCallsToMarkNeedsBuild(bool value) {
    assert(_debugAllowIgnoredCallsToMarkNeedsBuild == !value);
    _debugAllowIgnoredCallsToMarkNeedsBuild = value;
    return true;
  }

  /// Marks the element as dirty and adds it to the global list of widgets to
  /// rebuild in the next frame.
  ///
  /// Since it is inefficient to build an element twice in one frame,
  /// applications and widgets should be structured so as to only mark
  /// widgets dirty during event handlers before the frame begins, not during
  /// the build itself.
  void markNeedsBuild() {
    assert(_debugLifecycleState != _ElementLifecycle.defunct);
    if (!_active)
      return;
    assert(owner != null);
    assert(_debugLifecycleState == _ElementLifecycle.active);
    assert(() {
      if (owner._debugBuilding) {
        assert(owner._debugCurrentBuildTarget != null);
        assert(owner._debugStateLocked);
        if (_debugIsInScope(owner._debugCurrentBuildTarget))
          return true;
        if (!_debugAllowIgnoredCallsToMarkNeedsBuild) {
          throw new FlutterError(
            'setState() or markNeedsBuild() called during build.\n'
            'This ${widget.runtimeType} widget cannot be marked as needing to build because the framework '
            'is already in the process of building widgets. A widget can be marked as '
            'needing to be built during the build phase only if one of its ancestors '
            'is currently building. This exception is allowed because the framework '
            'builds parent widgets before children, which means a dirty descendant '
            'will always be built. Otherwise, the framework might not visit this '
            'widget during this build phase.\n'
            'The widget on which setState() or markNeedsBuild() was called was:\n'
            '  $this\n'
            '${owner._debugCurrentBuildTarget == null ? "" : "The widget which was currently being built when the offending call was made was:\n  ${owner._debugCurrentBuildTarget}"}'
          );
        }
        assert(dirty); // can only get here if we're not in scope, but ignored calls are allowed, and our call would somehow be ignored (since we're already dirty)
      } else if (owner._debugStateLocked) {
        assert(!_debugAllowIgnoredCallsToMarkNeedsBuild);
        throw new FlutterError(
          'setState() or markNeedsBuild() called when widget tree was locked.\n'
          'This ${widget.runtimeType} widget cannot be marked as needing to build '
          'because the framework is locked.\n'
          'The widget on which setState() or markNeedsBuild() was called was:\n'
          '  $this\n'
        );
      }
      return true;
    });
    if (dirty)
      return;
    _dirty = true;
    owner.scheduleBuildFor(this);
  }

  /// Called by the binding when [BuildOwner.scheduleBuildFor] has been called
  /// to mark this element dirty, and, in components, by [mount] when the
  /// element is first built and by [update] when the widget has changed.
  void rebuild() {
    assert(_debugLifecycleState != _ElementLifecycle.initial);
    if (!_active || !_dirty)
      return;
    assert(() {
      if (debugPrintRebuildDirtyWidgets) {
        if (!_debugBuiltOnce) {
          debugPrint('Building $this');
          _debugBuiltOnce = true;
        } else {
          debugPrint('Rebuilding $this');
        }
      }
      return true;
    });
    assert(_debugLifecycleState == _ElementLifecycle.active);
    assert(owner._debugStateLocked);
    BuildableElement debugPreviousBuildTarget;
    assert(() {
      debugPreviousBuildTarget = owner._debugCurrentBuildTarget;
      owner._debugCurrentBuildTarget = this;
     return true;
    });
    performRebuild();
    assert(() {
      assert(owner._debugCurrentBuildTarget == this);
      owner._debugCurrentBuildTarget = debugPreviousBuildTarget;
      return true;
    });
    assert(!_dirty);
  }

  /// Called by rebuild() after the appropriate checks have been made.
  @protected
  void performRebuild();

  @override
  void dependenciesChanged() {
    super.dependenciesChanged();
    assert(_active); // otherwise markNeedsBuild is a no-op
    markNeedsBuild();
  }

  @override
  void activate() {
    final bool hadDependencies = ((_dependencies != null && _dependencies.length > 0) || _hadUnsatisfiedDependencies);
    super.activate(); // clears _dependencies, and sets active to true
    if (_dirty) {
      if (_inDirtyList) {
        owner.markNeedsToResortDirtyElements();
      } else {
        owner.scheduleBuildFor(this);
      }
    }
    if (hadDependencies)
      dependenciesChanged();
  }

  @override
  void _reassemble() {
    assert(_active); // otherwise markNeedsBuild is a no-op
    markNeedsBuild();
    super._reassemble();
  }

  @override
  void debugFillDescription(List<String> description) {
    super.debugFillDescription(description);
    if (dirty)
      description.add('dirty');
  }
}

/// Signature for a function that creates a widget.
typedef Widget WidgetBuilder(BuildContext context);

/// Signature for a function that creates a widget for a given index, e.g., in a list.
typedef Widget IndexedWidgetBuilder(BuildContext context, int index);

// See ComponentElement._builder.
Widget _buildNothing(BuildContext context) => null;

/// An [Element] that composes other [Element]s.
///
/// Rather than creating a [RenderObject] directly, a [ComponentElement] creates
/// [RenderObject]s indirectly by creating other [Element]s.
///
/// Contrast with [RenderObjectElement].
abstract class ComponentElement extends BuildableElement {
  /// Creates an element that uses the given widget as its configuration.
  ComponentElement(Widget widget) : super(widget);

  // Initializing this field with _buildNothing helps the compiler prove that
  // this field always holds a closure.
  WidgetBuilder _builder = _buildNothing;

  Element _child;

  @override
  void mount(Element parent, dynamic newSlot) {
    super.mount(parent, newSlot);
    assert(_child == null);
    assert(_active);
    _firstBuild();
    assert(_child != null);
  }

  void _firstBuild() {
    rebuild();
  }

  /// Calls the `build` method of the [StatelessWidget] object (for
  /// stateless widgets) or the [State] object (for stateful widgets) and
  /// then updates the widget tree.
  ///
  /// Called automatically during [mount] to generate the first build, and by
  /// [rebuild] when the element needs updating.
  @override
  void performRebuild() {
    assert(_debugSetAllowIgnoredCallsToMarkNeedsBuild(true));
    Widget built;
    try {
      built = _builder(this);
      debugWidgetBuilderValue(widget, built);
    } catch (e, stack) {
      _debugReportException('building $this', e, stack);
      built = new ErrorWidget(e);
    } finally {
      // We delay marking the element as clean until after calling _builder so
      // that attempts to markNeedsBuild() during build() will be ignored.
      _dirty = false;
      assert(_debugSetAllowIgnoredCallsToMarkNeedsBuild(false));
    }
    try {
      _child = updateChild(_child, built, slot);
      assert(_child != null);
    } catch (e, stack) {
      _debugReportException('building $this', e, stack);
      built = new ErrorWidget(e);
      _child = updateChild(null, built, slot);
    }
  }

  @override
  void visitChildren(ElementVisitor visitor) {
    if (_child != null)
      visitor(_child);
  }

  @override
  void detachChild(Element child) {
    assert(child == _child);
    _child = null;
  }
}

/// An element that uses a [StatelessWidget] as its configuration.
class StatelessElement extends ComponentElement {
  /// Creates an element that uses the given widget as its configuration.
  StatelessElement(StatelessWidget widget) : super(widget) {
    _builder = widget.build;
  }

  @override
  StatelessWidget get widget => super.widget;

  @override
  void update(StatelessWidget newWidget) {
    super.update(newWidget);
    assert(widget == newWidget);
    _builder = widget.build;
    _dirty = true;
    rebuild();
  }

  @override
  void _reassemble() {
    _builder = widget.build;
    super._reassemble();
  }
}

/// An element that uses a [StatefulWidget] as its configuration.
class StatefulElement extends ComponentElement {
  /// Creates an element that uses the given widget as its configuration.
  StatefulElement(StatefulWidget widget)
    : _state = widget.createState(), super(widget) {
    assert(() {
      if (!_state._debugTypesAreRight(widget)) {
        throw new FlutterError(
          'StatefulWidget.createState must return a subtype of State<${widget.runtimeType}>\n'
          'The createState function for ${widget.runtimeType} returned a state '
          'of type ${_state.runtimeType}, which is not a subtype of '
          'State<${widget.runtimeType}>, violating the contract for createState.'
        );
      }
      return true;
    });
    assert(_state._element == null);
    _state._element = this;
    assert(_builder == _buildNothing);
    _builder = _state.build;
    assert(_state._config == null);
    _state._config = widget;
    assert(_state._debugLifecycleState == _StateLifecycle.created);
  }

  /// The [State] instance associated with this location in the tree.
  ///
  /// There is a one-to-one relationship between [State] objects and the
  /// [StatefulElement] objects that hold them. The [State] objects are created
  /// by [StatefulElement] in [mount].
  State<StatefulWidget> get state => _state;
  State<StatefulWidget> _state;

  @override
  void _reassemble() {
    _builder = state.build;
    state.reassemble();
    super._reassemble();
  }

  @override
  void _firstBuild() {
    assert(_state._debugLifecycleState == _StateLifecycle.created);
    try {
      _debugSetAllowIgnoredCallsToMarkNeedsBuild(true);
      _state.initState();
    } finally {
      _debugSetAllowIgnoredCallsToMarkNeedsBuild(false);
    }
    assert(() { _state._debugLifecycleState = _StateLifecycle.initialized; return true; });
    _state.dependenciesChanged();
    assert(() { _state._debugLifecycleState = _StateLifecycle.ready; return true; });
    super._firstBuild();
  }

  @override
  void update(StatefulWidget newWidget) {
    super.update(newWidget);
    assert(widget == newWidget);
    StatefulWidget oldConfig = _state._config;
    // Notice that we mark ourselves as dirty before calling didUpdateConfig to
    // let authors call setState from within didUpdateConfig without triggering
    // asserts.
    _dirty = true;
    _state._config = widget;
    try {
      _debugSetAllowIgnoredCallsToMarkNeedsBuild(true);
      _state.didUpdateConfig(oldConfig);
    } finally {
      _debugSetAllowIgnoredCallsToMarkNeedsBuild(false);
    }
    rebuild();
  }

  @override
  void activate() {
    super.activate();
    // Since the State could have observed the deactivate() and thus disposed of
    // resources allocated in the build function, we have to rebuild the widget
    // so that its State can reallocate its resources.
    assert(_active); // otherwise markNeedsBuild is a no-op
    markNeedsBuild();
  }

  @override
  void deactivate() {
    _state.deactivate();
    super.deactivate();
  }

  @override
  void unmount() {
    super.unmount();
    _state.dispose();
    assert(() {
      if (_state._debugLifecycleState == _StateLifecycle.defunct)
        return true;
      throw new FlutterError(
        '${_state.runtimeType}.dispose failed to call super.dispose.\n'
        'dispose() implementations must always call their superclass dispose() method, to ensure '
        'that all the resources used by the widget are fully released.'
      );
    });
    _state._element = null;
    _state = null;
  }

  @override
  InheritedWidget inheritFromWidgetOfExactType(Type targetType) {
    assert(() {
      if (state._debugLifecycleState == _StateLifecycle.created) {
        throw new FlutterError(
          'inheritFromWidgetOfExactType($targetType) was called before ${_state.runtimeType}.initState() completed.\n'
          'When an inherited widget changes, for example if the value of Theme.of() changes, '
          'its dependent widgets are rebuilt. If the dependent widget\'s reference to '
          'the inherited widget is in a constructor or an initState() method, '
          'then the rebuilt dependent widget will not reflect the changes in the '
          'inherited widget.\n'
          'Typically references to to inherited widgets should occur in widget build() methods. Alternatively, '
          'initialization based on inherited widgets can be placed in the dependenciesChanged method, which '
          'is called after initState and whenever the dependencies change thereafter.'
        );
      }
      if (state._debugLifecycleState == _StateLifecycle.defunct) {
        throw new FlutterError(
          'inheritFromWidgetOfExactType($targetType) called after dispose(): $this\n'
          'This error happens if you call inheritFromWidgetOfExactType() on the '
          'BuildContext for a widget that no longer appears in the widget tree '
          '(e.g., whose parent widget no longer includes the widget in its '
          'build). This error can occur when code calls '
          'inheritFromWidgetOfExactType() from a timer or an animation callback. '
          'The preferred solution is to cancel the timer or stop listening to the '
          'animation in the dispose() callback. Another solution is to check the '
          '"mounted" property of this object before calling '
          'inheritFromWidgetOfExactType() to ensure the object is still in the '
          'tree.\n'
          'This error might indicate a memory leak if '
          'inheritFromWidgetOfExactType() is being called because another object '
          'is retaining a reference to this State object after it has been '
          'removed from the tree. To avoid memory leaks, consider breaking the '
          'reference to this object during dispose().'
        );
      }
      return true;
    });
    return super.inheritFromWidgetOfExactType(targetType);
  }

  @override
  void dependenciesChanged() {
    super.dependenciesChanged();
    _state.dependenciesChanged();
  }

  @override
  void debugFillDescription(List<String> description) {
    super.debugFillDescription(description);
    if (state != null)
      description.add('state: $state');
  }
}

/// An element that uses a [ProxyElement] as its configuration.
abstract class ProxyElement extends ComponentElement {
  /// Initializes fields for subclasses.
  ProxyElement(ProxyWidget widget) : super(widget) {
    _builder = _build;
  }

  @override
  ProxyWidget get widget => super.widget;

  Widget _build(BuildContext context) => widget.child;

  @override
  void _reassemble() {
    _builder = _build;
    super._reassemble();
  }

  @override
  void update(ProxyWidget newWidget) {
    ProxyWidget oldWidget = widget;
    assert(widget != null);
    assert(widget != newWidget);
    super.update(newWidget);
    assert(widget == newWidget);
    notifyClients(oldWidget);
    _dirty = true;
    rebuild();
  }

  /// Notify other objects that the wiget associated with this element has changed.
  ///
  /// Called during [update] after changing the widget associated with this
  /// element but before rebuilding this element.
  @protected
  void notifyClients(@checked ProxyWidget oldWidget);
}

/// An element that uses a [ParentDataWidget] as its configuration.
class ParentDataElement<T extends RenderObjectWidget> extends ProxyElement {
  /// Creates an element that uses the given widget as its configuration.
  ParentDataElement(ParentDataWidget<T> widget) : super(widget);

  @override
  ParentDataWidget<T> get widget => super.widget;

  @override
  void mount(Element parent, dynamic slot) {
    assert(() {
      List<Widget> badAncestors = <Widget>[];
      Element ancestor = parent;
      while (ancestor != null) {
        if (ancestor is ParentDataElement<RenderObjectWidget>) {
          badAncestors.add(ancestor.widget);
        } else if (ancestor is RenderObjectElement) {
          if (widget.debugIsValidAncestor(ancestor.widget))
            break;
          badAncestors.add(ancestor.widget);
        }
        ancestor = ancestor._parent;
      }
      if (ancestor != null && badAncestors.isEmpty)
        return true;
      throw new FlutterError(
        'Incorrect use of ParentDataWidget.\n' +
        widget.debugDescribeInvalidAncestorChain(
          description: "$this",
          ownershipChain: parent.debugGetCreatorChain(10),
          foundValidAncestor: ancestor != null,
          badAncestors: badAncestors
        )
      );
    });
    super.mount(parent, slot);
  }

  void _notifyChildren(Element child) {
    if (child is RenderObjectElement) {
      child._updateParentData(widget);
    } else {
      assert(child is! ParentDataElement<RenderObjectWidget>);
      child.visitChildren(_notifyChildren);
    }
  }

  @override
  void notifyClients(ParentDataWidget<T> oldWidget) {
    visitChildren(_notifyChildren);
  }
}

/// An element that uses a [InheritedWidget] as its configuration.
class InheritedElement extends ProxyElement {
  /// Creates an element that uses the given widget as its configuration.
  InheritedElement(InheritedWidget widget) : super(widget);

  @override
  InheritedWidget get widget => super.widget;

  final Set<Element> _dependents = new HashSet<Element>();

  @override
  void _updateInheritance() {
    assert(_active);
    final Map<Type, InheritedElement> incomingWidgets = _parent?._inheritedWidgets;
    if (incomingWidgets != null)
      _inheritedWidgets = new Map<Type, InheritedElement>.from(incomingWidgets);
    else
      _inheritedWidgets = new Map<Type, InheritedElement>();
    _inheritedWidgets[widget.runtimeType] = this;
  }

  @override
  void debugDeactivated() {
    assert(() {
      assert(_dependents.isEmpty);
      return true;
    });
    super.debugDeactivated();
  }

  @override
  void notifyClients(InheritedWidget oldWidget) {
    if (!widget.updateShouldNotify(oldWidget))
      return;
    dispatchDependenciesChanged();
  }

  /// Notifies all dependent elements that this inherited widget has changed.
  ///
  /// [InheritedElement] calls this function if [InheritedWidget.updateShouldNotify]
  /// returns true. Subclasses of [InheritedElement] might wish to call this
  /// function at other times if their inherited information changes outside of
  /// the build phase.
  @protected
  void dispatchDependenciesChanged() {
    for (Element dependent in _dependents) {
      assert(() {
        // check that it really is our descendant
        Element ancestor = dependent._parent;
        while (ancestor != this && ancestor != null)
          ancestor = ancestor._parent;
        return ancestor == this;
      });
      // check that it really deepends on us
      assert(dependent._dependencies.contains(this));
      dependent.dependenciesChanged();
    }
  }
}

/// An element that uses a [RenderObjectWidget] as its configuration.
///
/// [RenderObjectElement] objects have an associated [RenderObject] widget in
/// the render tree, which handles concrete operations like laying out,
/// painting, and hit testing.
///
/// Contrast with [ComponentElement].
abstract class RenderObjectElement extends BuildableElement {
  /// Creates an element that uses the given widget as its configuration.
  RenderObjectElement(RenderObjectWidget widget) : super(widget);

  @override
  RenderObjectWidget get widget => super.widget;

  /// The underlying [RenderObject] for this element.
  @override
  RenderObject get renderObject => _renderObject;
  RenderObject _renderObject;

  RenderObjectElement _ancestorRenderObjectElement;

  RenderObjectElement _findAncestorRenderObjectElement() {
    Element ancestor = _parent;
    while (ancestor != null && ancestor is! RenderObjectElement)
      ancestor = ancestor._parent;
    return ancestor;
  }

  ParentDataElement<RenderObjectWidget> _findAncestorParentDataElement() {
    Element ancestor = _parent;
    while (ancestor != null && ancestor is! RenderObjectElement) {
      if (ancestor is ParentDataElement<RenderObjectWidget>)
        return ancestor;
      ancestor = ancestor._parent;
    }
    return null;
  }

  @override
  void mount(Element parent, dynamic newSlot) {
    super.mount(parent, newSlot);
    _renderObject = widget.createRenderObject(this);
    assert(() { _debugUpdateRenderObjectOwner(); return true; });
    assert(_slot == newSlot);
    attachRenderObject(newSlot);
    _dirty = false;
  }

  @override
  void update(RenderObjectWidget newWidget) {
    super.update(newWidget);
    assert(widget == newWidget);
    assert(() { _debugUpdateRenderObjectOwner(); return true; });
    widget.updateRenderObject(this, renderObject);
    _dirty = false;
  }

  void _debugUpdateRenderObjectOwner() {
    _renderObject.debugCreator = debugGetCreatorChain(10);
  }

  @override
  void performRebuild() {
    widget.updateRenderObject(this, renderObject);
    _dirty = false;
  }

  /// Updates the children of this element to use new widgets.
  ///
  /// Attempts to update the given old children list using the given new
  /// widgets, removing obsolete elements and introducing new ones as necessary,
  /// and then returns the new child list.
  ///
  /// During this function the `oldChildren` list must not be modified. If the
  /// caller wishes to remove elements from `oldChildren` re-entrantly while
  /// this function is on the stack, the caller can supply a `detachedChildren`
  /// argument, which can be modified while this function is on the stack.
  /// Whenever this function reads from `oldChildren`, this function first
  /// checks whether the child is in `detachedChildren`. If it is, the function
  /// acts as if the child was not in `oldChildren`.
  ///
  /// This function is a convienence wrapper around [updateChild], which updates
  /// each individual child. When calling [updateChild], this function uses the
  /// previous element as the `newSlot` argument.
  @protected
  List<Element> updateChildren(List<Element> oldChildren, List<Widget> newWidgets, { Set<Element> detachedChildren }) {
    assert(oldChildren != null);
    assert(newWidgets != null);

    Element replaceWithNullIfDetached(Element child) {
      return detachedChildren != null && detachedChildren.contains(child) ? null : child;
    }

    // This attempts to diff the new child list (this.children) with
    // the old child list (old.children), and update our renderObject
    // accordingly.

    // The cases it tries to optimise for are:
    //  - the old list is empty
    //  - the lists are identical
    //  - there is an insertion or removal of one or more widgets in
    //    only one place in the list
    // If a widget with a key is in both lists, it will be synced.
    // Widgets without keys might be synced but there is no guarantee.

    // The general approach is to sync the entire new list backwards, as follows:
    // 1. Walk the lists from the top, syncing nodes, until you no longer have
    //    matching nodes.
    // 2. Walk the lists from the bottom, without syncing nodes, until you no
    //    longer have matching nodes. We'll sync these nodes at the end. We
    //    don't sync them now because we want to sync all the nodes in order
    //    from beginning ot end.
    // At this point we narrowed the old and new lists to the point
    // where the nodes no longer match.
    // 3. Walk the narrowed part of the old list to get the list of
    //    keys and sync null with non-keyed items.
    // 4. Walk the narrowed part of the new list forwards:
    //     * Sync unkeyed items with null
    //     * Sync keyed items with the source if it exists, else with null.
    // 5. Walk the bottom of the list again, syncing the nodes.
    // 6. Sync null with any items in the list of keys that are still
    //    mounted.

    int newChildrenTop = 0;
    int oldChildrenTop = 0;
    int newChildrenBottom = newWidgets.length - 1;
    int oldChildrenBottom = oldChildren.length - 1;

    List<Element> newChildren = oldChildren.length == newWidgets.length ?
        oldChildren : new List<Element>(newWidgets.length);

    Element previousChild;

    // Update the top of the list.
    while ((oldChildrenTop <= oldChildrenBottom) && (newChildrenTop <= newChildrenBottom)) {
      Element oldChild = replaceWithNullIfDetached(oldChildren[oldChildrenTop]);
      Widget newWidget = newWidgets[newChildrenTop];
      assert(oldChild == null || oldChild._debugLifecycleState == _ElementLifecycle.active);
      if (oldChild == null || !Widget.canUpdate(oldChild.widget, newWidget))
        break;
      Element newChild = updateChild(oldChild, newWidget, previousChild);
      assert(newChild._debugLifecycleState == _ElementLifecycle.active);
      newChildren[newChildrenTop] = newChild;
      previousChild = newChild;
      newChildrenTop += 1;
      oldChildrenTop += 1;
    }

    // Scan the bottom of the list.
    while ((oldChildrenTop <= oldChildrenBottom) && (newChildrenTop <= newChildrenBottom)) {
      Element oldChild = replaceWithNullIfDetached(oldChildren[oldChildrenBottom]);
      Widget newWidget = newWidgets[newChildrenBottom];
      assert(oldChild == null || oldChild._debugLifecycleState == _ElementLifecycle.active);
      if (oldChild == null || !Widget.canUpdate(oldChild.widget, newWidget))
        break;
      oldChildrenBottom -= 1;
      newChildrenBottom -= 1;
    }

    // Scan the old children in the middle of the list.
    bool haveOldChildren = oldChildrenTop <= oldChildrenBottom;
    Map<Key, Element> oldKeyedChildren;
    if (haveOldChildren) {
      oldKeyedChildren = new Map<Key, Element>();
      while (oldChildrenTop <= oldChildrenBottom) {
        Element oldChild = replaceWithNullIfDetached(oldChildren[oldChildrenTop]);
        assert(oldChild == null || oldChild._debugLifecycleState == _ElementLifecycle.active);
        if (oldChild != null) {
          if (oldChild.widget.key != null)
            oldKeyedChildren[oldChild.widget.key] = oldChild;
          else
            deactivateChild(oldChild);
        }
        oldChildrenTop += 1;
      }
    }

    // Update the middle of the list.
    while (newChildrenTop <= newChildrenBottom) {
      Element oldChild;
      Widget newWidget = newWidgets[newChildrenTop];
      if (haveOldChildren) {
        Key key = newWidget.key;
        if (key != null) {
          oldChild = oldKeyedChildren[newWidget.key];
          if (oldChild != null) {
            if (Widget.canUpdate(oldChild.widget, newWidget)) {
              // we found a match!
              // remove it from oldKeyedChildren so we don't unsync it later
              oldKeyedChildren.remove(key);
            } else {
              // Not a match, let's pretend we didn't see it for now.
              oldChild = null;
            }
          }
        }
      }
      assert(oldChild == null || Widget.canUpdate(oldChild.widget, newWidget));
      Element newChild = updateChild(oldChild, newWidget, previousChild);
      assert(newChild._debugLifecycleState == _ElementLifecycle.active);
      assert(oldChild == newChild || oldChild == null || oldChild._debugLifecycleState != _ElementLifecycle.active);
      newChildren[newChildrenTop] = newChild;
      previousChild = newChild;
      newChildrenTop += 1;
    }

    // We've scaned the whole list.
    assert(oldChildrenTop == oldChildrenBottom + 1);
    assert(newChildrenTop == newChildrenBottom + 1);
    assert(newWidgets.length - newChildrenTop == oldChildren.length - oldChildrenTop);
    newChildrenBottom = newWidgets.length - 1;
    oldChildrenBottom = oldChildren.length - 1;

    // Update the bottom of the list.
    while ((oldChildrenTop <= oldChildrenBottom) && (newChildrenTop <= newChildrenBottom)) {
      Element oldChild = oldChildren[oldChildrenTop];
      assert(replaceWithNullIfDetached(oldChild) != null);
      assert(oldChild._debugLifecycleState == _ElementLifecycle.active);
      Widget newWidget = newWidgets[newChildrenTop];
      assert(Widget.canUpdate(oldChild.widget, newWidget));
      Element newChild = updateChild(oldChild, newWidget, previousChild);
      assert(newChild._debugLifecycleState == _ElementLifecycle.active);
      assert(oldChild == newChild || oldChild == null || oldChild._debugLifecycleState != _ElementLifecycle.active);
      newChildren[newChildrenTop] = newChild;
      previousChild = newChild;
      newChildrenTop += 1;
      oldChildrenTop += 1;
    }

    // clean up any of the remaining middle nodes from the old list
    if (haveOldChildren && oldKeyedChildren.isNotEmpty) {
      for (Element oldChild in oldKeyedChildren.values) {
        if (detachedChildren == null || !detachedChildren.contains(oldChild))
          deactivateChild(oldChild);
      }
    }

    return newChildren;
  }

  @override
  void deactivate() {
    super.deactivate();
    assert(!renderObject.attached);
  }

  @override
  void unmount() {
    super.unmount();
    assert(!renderObject.attached);
    widget.didUnmountRenderObject(renderObject);
  }

  void _updateParentData(ParentDataWidget<RenderObjectWidget> parentData) {
    parentData.applyParentData(renderObject);
  }

  @override
  void _updateSlot(dynamic newSlot) {
    assert(slot != newSlot);
    super._updateSlot(newSlot);
    assert(slot == newSlot);
    _ancestorRenderObjectElement.moveChildRenderObject(renderObject, slot);
  }

  @override
  void attachRenderObject(dynamic newSlot) {
    assert(_ancestorRenderObjectElement == null);
    _slot = newSlot;
    _ancestorRenderObjectElement = _findAncestorRenderObjectElement();
    _ancestorRenderObjectElement?.insertChildRenderObject(renderObject, newSlot);
    ParentDataElement<RenderObjectWidget> parentDataElement = _findAncestorParentDataElement();
    if (parentDataElement != null)
      _updateParentData(parentDataElement.widget);
  }

  @override
  void detachRenderObject() {
    if (_ancestorRenderObjectElement != null) {
      _ancestorRenderObjectElement.removeChildRenderObject(renderObject);
      _ancestorRenderObjectElement = null;
    }
    _slot = null;
  }

  /// Insert the given child into [renderObject] at the given slot.
  ///
  /// The semantics of `slot` are determined by this element. For example, if
  /// this element has a single child, the slot should always be null. If this
  /// element has a list of children, the previous sibling is a convenient value
  /// for the slot.
  @protected
  void insertChildRenderObject(@checked RenderObject child, @checked dynamic slot);

  /// Move the given child to the given slot.
  ///
  /// The given child is guaranteed to have [renderObject] as its parent.
  ///
  /// The semantics of `slot` are determined by this element. For example, if
  /// this element has a single child, the slot should always be null. If this
  /// element has a list of children, the previous sibling is a convenient value
  /// for the slot.
  @protected
  void moveChildRenderObject(@checked RenderObject child, @checked dynamic slot);

  /// Remove the given child from [renderObject].
  ///
  /// The given child is guaranteed to have [renderObject] as its parent.
  @protected
  void removeChildRenderObject(@checked RenderObject child);

  @override
  void debugFillDescription(List<String> description) {
    super.debugFillDescription(description);
    if (renderObject != null)
      description.add('renderObject: $renderObject');
  }
}

/// The element at the root of the tree.
///
/// Only root elements may have their owner set explicitly. All other
/// elements inherit their owner from their parent.
abstract class RootRenderObjectElement extends RenderObjectElement {
  /// Initializes fields for subclasses.
  RootRenderObjectElement(RenderObjectWidget widget): super(widget);

  /// Set the owner of the element. The owner will be propagated to all the
  /// descendants of this element.
  ///
  /// The owner manages the dirty elements list.
  ///
  /// The [WidgetsBinding] introduces the primary owner,
  /// [WidgetsBinding.buildOwner], and assigns it to the widget tree in the call
  /// to [runApp]. The binding is responsible for driving the build pipeline by
  /// calling the build owner's [BuildOwner.buildScope] method. See
  /// [WidgetsBinding.beginFrame].
  void assignOwner(BuildOwner owner) {
    _owner = owner;
  }

  @override
  void mount(Element parent, dynamic newSlot) {
    // Root elements should never have parents.
    assert(parent == null);
    assert(newSlot == null);
    super.mount(parent, newSlot);
  }
}

/// An element that uses a [LeafRenderObjectWidget] as its configuration.
class LeafRenderObjectElement extends RenderObjectElement {
  /// Creates an element that uses the given widget as its configuration.
  LeafRenderObjectElement(LeafRenderObjectWidget widget): super(widget);

  @override
  void detachChild(Element child) {
    assert(false);
  }

  @override
  void insertChildRenderObject(RenderObject child, dynamic slot) {
    assert(false);
  }

  @override
  void moveChildRenderObject(RenderObject child, dynamic slot) {
    assert(false);
  }

  @override
  void removeChildRenderObject(RenderObject child) {
    assert(false);
  }
}

/// An element that uses a [SingleChildRenderObjectWidget] as its configuration.
///
/// The child is optional.
///
/// This element subclass can be used for RenderObjectWidgets whose
/// RenderObjects use the [RenderObjectWithChildMixin] mixin. Such widgets are
/// expected to inherit from [SingleChildRenderObjectWidget].
class SingleChildRenderObjectElement extends RenderObjectElement {
  /// Creates an element that uses the given widget as its configuration.
  SingleChildRenderObjectElement(SingleChildRenderObjectWidget widget) : super(widget);

  @override
  SingleChildRenderObjectWidget get widget => super.widget;

  Element _child;

  @override
  void visitChildren(ElementVisitor visitor) {
    if (_child != null)
      visitor(_child);
  }

  @override
  void detachChild(Element child) {
    assert(child == _child);
    _child = null;
  }

  @override
  void mount(Element parent, dynamic newSlot) {
    super.mount(parent, newSlot);
    _child = updateChild(_child, widget.child, null);
  }

  @override
  void update(SingleChildRenderObjectWidget newWidget) {
    super.update(newWidget);
    assert(widget == newWidget);
    _child = updateChild(_child, widget.child, null);
  }

  @override
  void insertChildRenderObject(RenderObject child, dynamic slot) {
    final RenderObjectWithChildMixin<RenderObject> renderObject = this.renderObject;
    assert(slot == null);
    renderObject.child = child;
    assert(renderObject == this.renderObject);
  }

  @override
  void moveChildRenderObject(RenderObject child, dynamic slot) {
    assert(false);
  }

  @override
  void removeChildRenderObject(RenderObject child) {
    final RenderObjectWithChildMixin<RenderObject> renderObject = this.renderObject;
    assert(renderObject.child == child);
    renderObject.child = null;
    assert(renderObject == this.renderObject);
  }
}

/// An element that uses a [MultiChildRenderObjectWidget] as its configuration.
///
/// This element subclass can be used for RenderObjectWidgets whose
/// RenderObjects use the [ContainerRenderObjectMixin] mixin with a parent data
/// type that implements [ContainerParentDataMixin<RenderObject>]. Such widgets
/// are expected to inherit from [MultiChildRenderObjectWidget].
class MultiChildRenderObjectElement extends RenderObjectElement {
  /// Creates an element that uses the given widget as its configuration.
  MultiChildRenderObjectElement(MultiChildRenderObjectWidget widget) : super(widget) {
    assert(!debugChildrenHaveDuplicateKeys(widget, widget.children));
  }

  @override
  MultiChildRenderObjectWidget get widget => super.widget;

  List<Element> _children;
  // We keep a set of detached children to avoid O(n^2) work walking _children
  // repeatedly to remove children.
  final Set<Element> _detachedChildren = new HashSet<Element>();

  @override
  void insertChildRenderObject(RenderObject child, Element slot) {
    final ContainerRenderObjectMixin<RenderObject, ContainerParentDataMixin<RenderObject>> renderObject = this.renderObject;
    renderObject.insert(child, after: slot?.renderObject);
    assert(renderObject == this.renderObject);
  }

  @override
  void moveChildRenderObject(RenderObject child, dynamic slot) {
    final ContainerRenderObjectMixin<RenderObject, ContainerParentDataMixin<RenderObject>> renderObject = this.renderObject;
    assert(child.parent == renderObject);
    renderObject.move(child, after: slot?.renderObject);
    assert(renderObject == this.renderObject);
  }

  @override
  void removeChildRenderObject(RenderObject child) {
    final ContainerRenderObjectMixin<RenderObject, ContainerParentDataMixin<RenderObject>> renderObject = this.renderObject;
    assert(child.parent == renderObject);
    renderObject.remove(child);
    assert(renderObject == this.renderObject);
  }

  @override
  void visitChildren(ElementVisitor visitor) {
    for (Element child in _children) {
      if (!_detachedChildren.contains(child))
        visitor(child);
    }
  }

  @override
  void detachChild(Element child) {
    assert(_children.contains(child));
    assert(!_detachedChildren.contains(child));
    _detachedChildren.add(child);
  }

  @override
  void mount(Element parent, dynamic newSlot) {
    super.mount(parent, newSlot);
    _children = new List<Element>(widget.children.length);
    Element previousChild;
    for (int i = 0; i < _children.length; i += 1) {
      final Element newChild = inflateWidget(widget.children[i], previousChild);
      _children[i] = newChild;
      previousChild = newChild;
    }
  }

  @override
  void update(MultiChildRenderObjectWidget newWidget) {
    super.update(newWidget);
    assert(widget == newWidget);
    _children = updateChildren(_children, widget.children, detachedChildren: _detachedChildren);
    _detachedChildren.clear();
  }
}

void _debugReportException(String context, dynamic exception, StackTrace stack, {
  InformationCollector informationCollector
}) {
  FlutterError.reportError(new FlutterErrorDetails(
    exception: exception,
    stack: stack,
    library: 'widgets library',
    context: context,
    informationCollector: informationCollector,
  ));
}
