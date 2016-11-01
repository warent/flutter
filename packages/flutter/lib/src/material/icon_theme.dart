// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

import 'icon_theme_data.dart';
import 'theme.dart';

/// Controls the default color, opacity, and size of icons in a widget subtree.
///
/// The icon theme is honored by [Icon] and [ImageIcon] widgets.
class IconTheme extends InheritedWidget {
  /// Creates an icon theme that controls the color, opacity, and size of
  /// descendant widgets.
  ///
  /// Both [data] and [child] arguments must not be null.
  IconTheme({
    Key key,
    @required this.data,
    @required Widget child
  }) : super(key: key, child: child) {
    assert(data != null);
    assert(child != null);
  }

  /// Creates an icon theme that controls the color, opacity, and size of
  /// descendant widgets, and merges in the current icon theme, if any.
  ///
  /// The [context], [data], and [child] arguments must not be null.
  factory IconTheme.merge({
    Key key,
    @required BuildContext context,
    @required IconThemeData data,
    @required Widget child
  }) {
    return new IconTheme(
      key: key,
      data: IconTheme.of(context).merge(data),
      child: child
    );
  }

  /// The color, opacity, and size to use for icons in this subtree.
  final IconThemeData data;

  /// The data from the closest instance of this class that encloses the given
  /// context.
  ///
  /// Defaults to the current [ThemeData.iconTheme].
  ///
  /// Typical usage is as follows:
  ///
  /// ```dart
  /// IconThemeData theme = IconTheme.of(context);
  /// ```
  static IconThemeData of(BuildContext context) {
    IconTheme result = context.inheritFromWidgetOfExactType(IconTheme);
    return result?.data ?? Theme.of(context).iconTheme;
  }

  @override
  bool updateShouldNotify(IconTheme old) => data != old.data;

  @override
  void debugFillDescription(List<String> description) {
    super.debugFillDescription(description);
    description.add('$data');
  }
}
