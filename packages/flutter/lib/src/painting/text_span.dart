// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:ui' as ui show ParagraphBuilder;

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';

import 'basic_types.dart';
import 'text_editing.dart';
import 'text_style.dart';

// TODO(abarth): Should this be somewhere more general?
bool _deepEquals(List<Object> a, List<Object> b) {
  if (a == null)
    return b == null;
  if (b == null || a.length != b.length)
    return false;
  for (int i = 0; i < a.length; ++i) {
    if (a[i] != b[i])
      return false;
  }
  return true;
}

/// An immutable span of text.
///
/// A [TextSpan] object can be styled using its [style] property.
/// The style will be applied to the [text] and the [children].
///
/// A [TextSpan] object can just have plain text, or it can have
/// children [TextSpan] objects with their own styles that (possibly
/// only partially) override the [style] of this object. If a
/// [TextSpan] has both [text] and [children], then the [text] is
/// treated as if it was an unstyled [TextSpan] at the start of the
/// [children] list.
///
/// To paint a [TextSpan] on a [Canvas], use a [TextPainter]. To display a text
/// span in a widget, use a [RichText]. For text with a single style, consider
/// using the [Text] widget.
///
/// See also:
///
///  * [Text]
///  * [RichText]
///  * [TextPainter]
class TextSpan {
  /// Creates a [TextSpan] with the given values.
  ///
  /// For the object to be useful, at least one of [text] or
  /// [children] should be set.
  const TextSpan({
    this.style,
    this.text,
    this.children,
    this.recognizer
  });

  /// The style to apply to the [text] and the [children].
  final TextStyle style;

  /// The text contained in the span.
  ///
  /// If both [text] and [children] are non-null, the text will precede the
  /// children.
  final String text;

  /// Additional spans to include as children.
  ///
  /// If both [text] and [children] are non-null, the text will precede the
  /// children.
  ///
  /// Modifying the list after the [TextSpan] has been created is not
  /// supported and may have unexpected results.
  ///
  /// The list must not contain any nulls.
  final List<TextSpan> children;

  /// A gesture recognizer that will receive events that hit this text span.
  ///
  /// [TextSpan] itself does not implement hit testing or event
  /// dispatch. The owner of the [TextSpan] tree to which the object
  /// belongs is responsible for dispatching events.
  ///
  /// For an example, see [RenderParagraph] in the Flutter rendering library.
  final GestureRecognizer recognizer;

  /// Apply the [style], [text], and [children] of this object to the
  /// given [ParagraphBuilder], from which a [Paragraph] can be obtained.
  /// [Paragraph] objects can be drawn on [Canvas] objects.
  ///
  /// Rather than using this directly, it's simpler to use the
  /// [TextPainter] class to paint [TextSpan] objects onto [Canvas]
  /// objects.
  void build(ui.ParagraphBuilder builder, { double textScaleFactor: 1.0 }) {
    assert(debugAssertIsValid());
    final bool hasStyle = style != null;
    if (hasStyle)
      builder.pushStyle(style.getTextStyle(textScaleFactor: textScaleFactor));
    if (text != null)
      builder.addText(text);
    if (children != null) {
      for (TextSpan child in children) {
        assert(child != null);
        child.build(builder, textScaleFactor: textScaleFactor);
      }
    }
    if (hasStyle)
      builder.pop();
  }

  /// Walks this text span and its decendants in pre-order and calls [visitor] for each span that has text.
  bool visitTextSpan(bool visitor(TextSpan span)) {
    if (text != null) {
      if (!visitor(this))
        return false;
    }
    if (children != null) {
      for (TextSpan child in children) {
        if (!child.visitTextSpan(visitor))
          return false;
      }
    }
    return true;
  }

  /// Returns the text span that contains the given position in the text.
  TextSpan getSpanForPosition(TextPosition position) {
    assert(debugAssertIsValid());
    TextAffinity affinity = position.affinity;
    int targetOffset = position.offset;
    int offset = 0;
    TextSpan result;
    visitTextSpan((TextSpan span) {
      assert(result == null);
      int endOffset = offset + span.text.length;
      if (targetOffset == offset && affinity == TextAffinity.downstream ||
          targetOffset > offset && targetOffset < endOffset ||
          targetOffset == endOffset && affinity == TextAffinity.upstream) {
        result = span;
        return false;
      }
      offset = endOffset;
      return true;
    });
    return result;
  }

  /// Flattens the [TextSpan] tree into a single string.
  ///
  /// Styles are not honored in this process.
  String toPlainText() {
    assert(debugAssertIsValid());
    StringBuffer buffer = new StringBuffer();
    visitTextSpan((TextSpan span) {
      buffer.write(span.text);
      return true;
    });
    return buffer.toString();
  }

  @override
  String toString([String prefix = '']) {
    StringBuffer buffer = new StringBuffer();
    buffer.writeln('$prefix$runtimeType:');
    String indent = '$prefix  ';
    if (style != null)
      buffer.writeln(style.toString(indent));
    if (text != null)
      buffer.writeln('$indent"$text"');
    if (children != null) {
      for (TextSpan child in children) {
        if (child != null) {
          buffer.write(child.toString(indent));
        } else {
          buffer.writeln('$indent<null>');
        }
      }
    }
    if (style == null && text == null && children == null)
      buffer.writeln('$indent(empty)');
    return buffer.toString();
  }

  /// In checked mode, throws an exception if the object is not in a
  /// valid configuration. Otherwise, returns true.
  ///
  /// This is intended to be used as follows:
  /// ```dart
  ///   assert(myTextSpan.debugAssertIsValid());
  /// ```
  bool debugAssertIsValid() {
    assert(() {
      if (!visitTextSpan((TextSpan span) {
        if (span.children != null) {
          for (TextSpan child in span.children) {
            if (child == null)
              return false;
          }
        }
        return true;
      })) {
        throw new FlutterError(
          'TextSpan contains a null child.\n'
          'A TextSpan object with a non-null child list should not have any nulls in its child list.\n'
          'The full text in question was:\n'
          '${toString("  ")}'
        );
      }
      return true;
    });
    return true;
  }

  @override
  bool operator ==(dynamic other) {
    if (identical(this, other))
      return true;
    if (other is! TextSpan)
      return false;
    final TextSpan typedOther = other;
    return typedOther.text == text
        && typedOther.style == style
        && typedOther.recognizer == recognizer
        && _deepEquals(typedOther.children, children);
  }

  @override
  int get hashCode => hashValues(style, text, recognizer, hashList(children));
}
