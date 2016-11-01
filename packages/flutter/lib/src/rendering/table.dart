// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:collection';
import 'dart:math' as math;

import 'box.dart';
import 'object.dart';

/// Parent data used by [RenderTable] for its children.
class TableCellParentData extends BoxParentData {
  /// Where this cell should be placed vertically.
  TableCellVerticalAlignment verticalAlignment;

  /// The column that the child was in the last time it was laid out.
  int x;

  /// The row that the child was in the last time it was laid out.
  int y;

  @override
  String toString() => '${super.toString()}; ${verticalAlignment == null ? "default vertical alignment" : "$verticalAlignment"}';
}

/// Base class to describe how wide a column in a [RenderTable] should be.
///
/// To size a column to a specific number of pixels, use a [FixedColumnWidth].
/// This is the cheapest way to size a column.
///
/// Other algorithms that are relatively cheap include [FlexColumnWidth], which
/// distributes the space equally among the flexible columns,
/// [FractionColumnWidth], which sizes a column based on the size of the
/// table's container.
abstract class TableColumnWidth {
  /// Abstract const constructor. This constructor enables subclasses to provide
  /// const constructors so that they can be used in const expressions.
  const TableColumnWidth();

  /// The smallest width that the column can have.
  ///
  /// The `cells` argument is an iterable that provides all the cells
  /// in the table for this column. Walking the cells is by definition
  /// O(N), so algorithms that do that should be considered expensive.
  ///
  /// The `containerWidth` argument is the `maxWidth` of the incoming
  /// constraints for the table, and might be infinite.
  double minIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth);

  /// The ideal width that the column should have. This must be equal
  /// to or greater than the [minIntrinsicWidth]. The column might be
  /// bigger than this width, e.g. if the column is flexible or if the
  /// table's width ends up being forced to be bigger than the sum of
  /// all the maxIntrinsicWidth values.
  ///
  /// The `cells` argument is an iterable that provides all the cells
  /// in the table for this column. Walking the cells is by definition
  /// O(N), so algorithms that do that should be considered expensive.
  ///
  /// The `containerWidth` argument is the `maxWidth` of the incoming
  /// constraints for the table, and might be infinite.
  double maxIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth);

  /// The flex factor to apply to the cell if there is any room left
  /// over when laying out the table. The remaining space is
  /// distributed to any columns with flex in proportion to their flex
  /// value (higher values get more space).
  ///
  /// The `cells` argument is an iterable that provides all the cells
  /// in the table for this column. Walking the cells is by definition
  /// O(N), so algorithms that do that should be considered expensive.
  double flex(Iterable<RenderBox> cells) => null;

  @override
  String toString() => '$runtimeType';
}

/// Sizes the column according to the intrinsic dimensions of all the
/// cells in that column.
///
/// This is a very expensive way to size a column.
///
/// A flex value can be provided. If specified (and non-null), the
/// column will participate in the distribution of remaining space
/// once all the non-flexible columns have been sized.
class IntrinsicColumnWidth extends TableColumnWidth {
  /// Creates a column width based on intrinsic sizing.
  ///
  /// This sizing algorithm is very expensive.
  const IntrinsicColumnWidth({ double flex }) : _flex = flex;

  @override
  double minIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) {
    double result = 0.0;
    for (RenderBox cell in cells)
      result = math.max(result, cell.getMinIntrinsicWidth(double.INFINITY));
    return result;
  }

  @override
  double maxIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) {
    double result = 0.0;
    for (RenderBox cell in cells)
      result = math.max(result, cell.getMaxIntrinsicWidth(double.INFINITY));
    return result;
  }

  final double _flex;

  @override
  double flex(Iterable<RenderBox> cells) => _flex;
}

/// Sizes the column to a specific number of pixels.
///
/// This is the cheapest way to size a column.
class FixedColumnWidth extends TableColumnWidth {
  /// Creates a column width based on a fixed number of logical pixels.
  ///
  /// The [value] argument must not be null.
  const FixedColumnWidth(this.value);

  /// The width the column should occupy in logical pixels.
  final double value;

  @override
  double minIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) {
    return value;
  }

  @override
  double maxIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) {
    return value;
  }

  @override
  String toString() => '$runtimeType($value)';
}

/// Sizes the column to a fraction of the table's constraints' maxWidth.
///
/// This is a cheap way to size a column.
class FractionColumnWidth extends TableColumnWidth {
  /// Creates a column width based on a fraction of the table's constraints'
  /// maxWidth.
  ///
  /// The [value] argument must not be null.
  const FractionColumnWidth(this.value);

  /// The fraction of the table's constraints' maxWidth that this column should
  /// occupy.
  final double value;

  @override
  double minIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) {
    if (!containerWidth.isFinite)
      return 0.0;
    return value * containerWidth;
  }

  @override
  double maxIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) {
    if (!containerWidth.isFinite)
      return 0.0;
    return value * containerWidth;
  }

  @override
  String toString() => '$runtimeType($value)';
}

/// Sizes the column by taking a part of the remaining space once all
/// the other columns have been laid out.
///
/// For example, if two columns have a [FlexColumnWidth], then half the
/// space will go to one and half the space will go to the other.
///
/// This is a cheap way to size a column.
class FlexColumnWidth extends TableColumnWidth {
  /// Creates a column width based on a fraction of the remaining space once all
  /// the other columns have been laid out.
  ///
  /// The [value] argument must not be null.
  const FlexColumnWidth([this.value = 1.0]);

  /// The reaction of the of the remaining space once all the other columns have
  /// been laid out that this column should occupy.
  final double value;

  @override
  double minIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) {
    return 0.0;
  }

  @override
  double maxIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) {
    return 0.0;
  }

  @override
  double flex(Iterable<RenderBox> cells) {
    return value;
  }

  @override
  String toString() => '$runtimeType($value)';
}

/// Sizes the column such that it is the size that is the maximum of
/// two column width specifications.
///
/// For example, to have a column be 10% of the container width or
/// 100px, whichever is bigger, you could use:
///
///     const MaxColumnWidth(const FixedColumnWidth(100.0), FractionColumnWidth(0.1))
///
/// Both specifications are evaluated, so if either specification is
/// expensive, so is this.
class MaxColumnWidth extends TableColumnWidth {
  /// Creates a column width that is the maximum of two other column widths.
  const MaxColumnWidth(this.a, this.b);

  /// A lower bound for the width of this column.
  final TableColumnWidth a;

  /// Another lower bound for the width of this column.
  final TableColumnWidth b;

  @override
  double minIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) {
    return math.max(
      a.minIntrinsicWidth(cells, containerWidth),
      b.minIntrinsicWidth(cells, containerWidth)
    );
  }

  @override
  double maxIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) {
    return math.max(
      a.maxIntrinsicWidth(cells, containerWidth),
      b.maxIntrinsicWidth(cells, containerWidth)
    );
  }

  @override
  double flex(Iterable<RenderBox> cells) {
    final double aFlex = a.flex(cells);
    if (aFlex == null)
      return b.flex(cells);
    final double bFlex = b.flex(cells);
    if (bFlex == null)
      return null;
    return math.max(aFlex, bFlex);
  }

  @override
  String toString() => '$runtimeType($a, $b)';
}

/// Sizes the column such that it is the size that is the minimum of
/// two column width specifications.
///
/// For example, to have a column be 10% of the container width but
/// never bigger than 100px, you could use:
///
///     const MinColumnWidth(const FixedColumnWidth(100.0), FractionColumnWidth(0.1))
///
/// Both specifications are evaluated, so if either specification is
/// expensive, so is this.
class MinColumnWidth extends TableColumnWidth {
  /// Creates a column width that is the minimum of two other column widths.
  const MinColumnWidth(this.a, this.b);

  /// An upper bound for the width of this column.
  final TableColumnWidth a;

  /// Another upper bound for the width of this column.
  final TableColumnWidth b;

  @override
  double minIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) {
    return math.min(
      a.minIntrinsicWidth(cells, containerWidth),
      b.minIntrinsicWidth(cells, containerWidth)
    );
  }

  @override
  double maxIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) {
    return math.min(
      a.maxIntrinsicWidth(cells, containerWidth),
      b.maxIntrinsicWidth(cells, containerWidth)
    );
  }

  @override
  double flex(Iterable<RenderBox> cells) {
    double aFlex = a.flex(cells);
    if (aFlex == null)
      return b.flex(cells);
    double bFlex = b.flex(cells);
    if (bFlex == null)
      return null;
    return math.min(aFlex, bFlex);
  }

  @override
  String toString() => '$runtimeType($a, $b)';
}

/// Border specification for [RenderTable].
///
/// This is like [Border], with the addition of two sides: the inner
/// horizontal borders and the inner vertical borders.
class TableBorder extends Border {
  /// Creates a border for a table.
  ///
  /// All the sides of the border default to [BorderSide.none].
  const TableBorder({
    BorderSide top: BorderSide.none,
    BorderSide right: BorderSide.none,
    BorderSide bottom: BorderSide.none,
    BorderSide left: BorderSide.none,
    this.horizontalInside: BorderSide.none,
    this.verticalInside: BorderSide.none
  }) : super(
    top: top,
    right: right,
    bottom: bottom,
    left: left
  );

  /// A uniform border with all sides the same color and width.
  factory TableBorder.all({
    Color color: const Color(0xFF000000),
    double width: 1.0
  }) {
    final BorderSide side = new BorderSide(color: color, width: width);
    return new TableBorder(top: side, right: side, bottom: side, left: side, horizontalInside: side, verticalInside: side);
  }

  /// Creates a border for a table where all the interior sides use the same
  /// styling and all the exterior sides use the same styling.
  factory TableBorder.symmetric({
    BorderSide inside: BorderSide.none,
    BorderSide outside: BorderSide.none
  }) {
    return new TableBorder(
      top: outside,
      right: outside,
      bottom: outside,
      left: outside,
      horizontalInside: inside,
      verticalInside: inside
    );
  }

  /// The horizontal interior sides of this border.
  final BorderSide horizontalInside;

  /// The vertical interior sides of this border.
  final BorderSide verticalInside;

  @override
  bool get isUniform {
    assert(horizontalInside != null);
    assert(verticalInside != null);
    if (!super.isUniform)
      return false;

    final Color topColor = top.color;
    if (horizontalInside.color != topColor ||
        verticalInside.color != topColor)
      return false;

    final double topWidth = top.width;
    if (horizontalInside.width != topWidth ||
        verticalInside.width != topWidth)
      return false;

    final BorderStyle topStyle = top.style;
    if (horizontalInside.style != topStyle ||
        verticalInside.style != topStyle)
      return false;

    return true;
  }

  @override
  TableBorder scale(double t) {
    return new TableBorder(
      top: top.copyWith(width: t * top.width),
      right: right.copyWith(width: t * right.width),
      bottom: bottom.copyWith(width: t * bottom.width),
      left: left.copyWith(width: t * left.width),
      horizontalInside: horizontalInside.copyWith(width: t * horizontalInside.width),
      verticalInside: verticalInside.copyWith(width: t * verticalInside.width)
    );
  }

  /// Linearly interpolate between two table borders.
  static TableBorder lerp(TableBorder a, TableBorder b, double t) {
    if (a == null && b == null)
      return null;
    if (a == null)
      return b.scale(t);
    if (b == null)
      return a.scale(1.0 - t);
    return new TableBorder(
      top: BorderSide.lerp(a.top, b.top, t),
      right: BorderSide.lerp(a.right, b.right, t),
      bottom: BorderSide.lerp(a.bottom, b.bottom, t),
      left: BorderSide.lerp(a.left, b.left, t),
      horizontalInside: BorderSide.lerp(a.horizontalInside, b.horizontalInside, t),
      verticalInside: BorderSide.lerp(a.verticalInside, b.verticalInside, t)
    );
  }

  @override
  bool operator ==(dynamic other) {
    if (super != other)
      return false;
    final TableBorder typedOther = other;
    return horizontalInside == typedOther.horizontalInside &&
           verticalInside == typedOther.verticalInside;
  }

  @override
  int get hashCode => hashValues(super.hashCode, horizontalInside, verticalInside);

  @override
  String toString() => 'TableBorder($top, $right, $bottom, $left, $horizontalInside, $verticalInside)';
}

/// Vertical alignment options for cells in [RenderTable] objects.
///
/// This is specified using [TableCellParentData] objects on the
/// [RenderObject.parentData] of the children of the [RenderTable].
enum TableCellVerticalAlignment {
  /// Cells with this alignment are placed with their top at the top of the row.
  top,

  /// Cells with this alignment are vertically centered in the row.
  middle,

  /// Cells with this alignment are placed with their bottom at the bottom of the row.
  bottom,

  /// Cells with this alignment are aligned such that they all share the same
  /// baseline. Cells with no baseline are top-aligned instead. The baseline
  /// used is specified by [RenderTable.baseline]. It is not valid to use the
  /// baseline value if [RenderTable.baseline] is not specified.
  ///
  /// This vertial alignment is relatively expensive because it causes the table
  /// to compute the baseline for each cell in the row.
  baseline,

  /// Cells with this alignment are sized to be as tall as the row, then made to fit the row.
  /// If all the cells have this alignment, then the row will have zero height.
  fill
}

/// A table where the columns and rows are sized to fit the contents of the cells.
class RenderTable extends RenderBox {
  /// Creates a table render object.
  ///
  ///  * `columns` must either be null or non-negative. If `columns` is null,
  ///    the number of columns will be inferred from length of the first sublist
  ///    of `children`.
  ///  * `rows` must either be null or non-negative. If `rows` is null, the
  ///    number of rows will be inferred from the `children`. If `rows` is not
  ///    null, then `children` must be null.
  ///  * `children` must either be null or contain lists of all the same length.
  ///    if `children` is not null, then `rows` must be null.
  ///  * [defaultColumnWidth] must not be null.
  ///  * [configuration] must not be null (but has a default value).
  RenderTable({
    int columns,
    int rows,
    Map<int, TableColumnWidth> columnWidths,
    TableColumnWidth defaultColumnWidth: const FlexColumnWidth(1.0),
    TableBorder border,
    List<Decoration> rowDecorations,
    ImageConfiguration configuration: ImageConfiguration.empty,
    Decoration defaultRowDecoration,
    TableCellVerticalAlignment defaultVerticalAlignment: TableCellVerticalAlignment.top,
    TextBaseline textBaseline,
    List<List<RenderBox>> children
  }) {
    assert(columns == null || columns >= 0);
    assert(rows == null || rows >= 0);
    assert(rows == null || children == null);
    assert(defaultColumnWidth != null);
    assert(configuration != null);
    _columns = columns ?? (children != null && children.length > 0 ? children.first.length : 0);
    _rows = rows ?? 0;
    _children = new List<RenderBox>()..length = _columns * _rows;
    _columnWidths = columnWidths ?? new HashMap<int, TableColumnWidth>();
    _defaultColumnWidth = defaultColumnWidth;
    _border = border;
    this.rowDecorations = rowDecorations; // must use setter to initialize box painters array
    _configuration = configuration;
    _defaultVerticalAlignment = defaultVerticalAlignment;
    _textBaseline = textBaseline;
    if (children != null) {
      for (List<RenderBox> row in children)
        addRow(row);
    }
  }

  // Children are stored in row-major order.
  // _children.length must be rows * columns
  List<RenderBox> _children = const <RenderBox>[];

  /// The number of vertical alignment lines in this table.
  ///
  /// Changing the number of columns will remove any children that no longer fit
  /// in the table.
  ///
  /// Changing the number of columns is an expensive operation because the table
  /// needs to rearranage its internal representation.
  int get columns => _columns;
  int _columns;
  set columns(int value) {
    assert(value != null);
    assert(value >= 0);
    if (value == columns)
      return;
    int oldColumns = columns;
    List<RenderBox> oldChildren = _children;
    _columns = value;
    _children = new List<RenderBox>()..length = columns * rows;
    int columnsToCopy = math.min(columns, oldColumns);
    for (int y = 0; y < rows; y += 1) {
      for (int x = 0; x < columnsToCopy; x += 1)
        _children[x + y * columns] = oldChildren[x + y * oldColumns];
    }
    if (oldColumns > columns) {
      for (int y = 0; y < rows; y += 1) {
        for (int x = columns; x < oldColumns; x += 1) {
          int xy = x + y * oldColumns;
          if (oldChildren[xy] != null)
            dropChild(oldChildren[xy]);
        }
      }
    }
    markNeedsLayout();
  }

  /// The number of horizontal alignment lines in this table.
  ///
  /// Changing the number of rows will remove any children that no longer fit
  /// in the table.
  int get rows => _rows;
  int _rows;
  set rows(int value) {
    assert(value != null);
    assert(value >= 0);
    if (value == rows)
      return;
    if (_rows > value) {
      for (int xy = columns * value; xy < _children.length; xy += 1) {
        if (_children[xy] != null)
          dropChild(_children[xy]);
      }
    }
    _rows = value;
    _children.length = columns * rows;
    markNeedsLayout();
  }

  /// How the horizontal extents of the columns of this table should be determined.
  ///
  /// If the [Map] has a null entry for a given column, the table uses the
  /// [defaultColumnWidth] instead.
  ///
  /// The layout performance of the table depends critically on which column
  /// sizing algorithms are used here. In particular, [IntrinsicColumnWidth] is
  /// quite expensive because it needs to measure each cell in the column to
  /// determine the intrinsic size of the column.
  Map<int, TableColumnWidth> get columnWidths => new Map<int, TableColumnWidth>.unmodifiable(_columnWidths);
  Map<int, TableColumnWidth> _columnWidths;
  set columnWidths(Map<int, TableColumnWidth> value) {
    value ??= new HashMap<int, TableColumnWidth>();
    if (_columnWidths == value)
      return;
    _columnWidths = value;
    markNeedsLayout();
  }

  /// Determines how the width of column with the given index is determined.
  void setColumnWidth(int column, TableColumnWidth value) {
    if (_columnWidths[column] == value)
      return;
    _columnWidths[column] = value;
    markNeedsLayout();
  }

  /// How to determine with widths of columns that don't have an explicit sizing algorithm.
  ///
  /// Specifically, the [defaultColumnWidth] is used for column `i` if
  /// `columnWidths[i]` is null.
  TableColumnWidth get defaultColumnWidth => _defaultColumnWidth;
  TableColumnWidth _defaultColumnWidth;
  set defaultColumnWidth(TableColumnWidth value) {
    assert(value != null);
    if (defaultColumnWidth == value)
      return;
    _defaultColumnWidth = value;
    markNeedsLayout();
  }

  /// The style to use when painting the boundary and interior divisions of the table.
  TableBorder get border => _border;
  TableBorder _border;
  set border(TableBorder value) {
    if (border == value)
      return;
    _border = value;
    markNeedsPaint();
  }

  /// The decorations to use for each row of the table.
  ///
  /// Row decorations fill the horizontal and vertical extent of each row in
  /// the table, unlike decorations for individual cells, which might not fill
  /// either.
  List<Decoration> get rowDecorations => new List<Decoration>.unmodifiable(_rowDecorations ?? const <Decoration>[]);
  List<Decoration> _rowDecorations;
  List<BoxPainter> _rowDecorationPainters;
  set rowDecorations(List<Decoration> value) {
    if (_rowDecorations == value)
      return;
    _rowDecorations = value;
    if (_rowDecorationPainters != null) {
      for (BoxPainter painter in _rowDecorationPainters)
        painter?.dispose();
    }
    _rowDecorationPainters = _rowDecorations != null ? new List<BoxPainter>(_rowDecorations.length) : null;
  }

  /// The settings to pass to the [rowDecorations] when painting, so that they
  /// can resolve images appropriately. See [ImageProvider.resolve] and
  /// [BoxPainter.paint].
  ImageConfiguration get configuration => _configuration;
  ImageConfiguration _configuration;
  set configuration (ImageConfiguration value) {
    assert(value != null);
    if (value == _configuration)
      return;
    _configuration = value;
    markNeedsPaint();
  }

  /// How cells that do not explicitly specify a vertical alignment are aligned vertically.
  TableCellVerticalAlignment get defaultVerticalAlignment => _defaultVerticalAlignment;
  TableCellVerticalAlignment _defaultVerticalAlignment;
  set defaultVerticalAlignment (TableCellVerticalAlignment value) {
    if (_defaultVerticalAlignment == value)
      return;
    _defaultVerticalAlignment = value;
    markNeedsLayout();
  }

  /// The text baseline to use when aligning rows using [TableCellVerticalAlignment.baseline].
  TextBaseline get textBaseline => _textBaseline;
  TextBaseline _textBaseline;
  set textBaseline (TextBaseline value) {
    if (_textBaseline == value)
      return;
    _textBaseline = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! TableCellParentData)
      child.parentData = new TableCellParentData();
  }

  /// Replaces the children of this table with the given cells.
  ///
  /// The cells are divided into the specified number of columns before
  /// replacing the existing children.
  ///
  /// If the new cells contain any existing children of the table, those
  /// children are simply moved to their new location in the table rather than
  /// removed from the table and re-added.
  void setFlatChildren(int columns, List<RenderBox> cells) {
    if (cells == _children && columns == _columns)
      return;
    assert(columns >= 0);
    // consider the case of a newly empty table
    if (columns == 0 || cells.length == 0) {
      assert(cells == null || cells.length == 0);
      _columns = columns;
      if (_children.length == 0) {
        assert(_rows == 0);
        return;
      }
      for (RenderBox oldChild in _children) {
        if (oldChild != null)
          dropChild(oldChild);
      }
      _rows = 0;
      _children.clear();
      markNeedsLayout();
      return;
    }
    assert(cells != null);
    assert(cells.length % columns == 0);
    // fill a set with the cells that are moving (it's important not
    // to dropChild a child that's remaining with us, because that
    // would clear their parentData field)
    final Set<RenderBox> lostChildren = new HashSet<RenderBox>();
    for (int y = 0; y < _rows; y += 1) {
      for (int x = 0; x < _columns; x += 1) {
        int xyOld = x + y * _columns;
        int xyNew = x + y * columns;
        if (_children[xyOld] != null && (x >= columns || xyNew >= cells.length || _children[xyOld] != cells[xyNew]))
          lostChildren.add(_children[xyOld]);
      }
    }
    // adopt cells that are arriving, and cross cells that are just moving off our list of lostChildren
    int y = 0;
    while (y * columns < cells.length) {
      for (int x = 0; x < columns; x += 1) {
        int xyNew = x + y * columns;
        int xyOld = x + y * _columns;
        if (cells[xyNew] != null && (x >= _columns || y >= _rows || _children[xyOld] != cells[xyNew])) {
          if (!lostChildren.remove(cells[xyNew]))
            adoptChild(cells[xyNew]);
        }
      }
      y += 1;
    }
    // drop all the lost children
    for (RenderBox oldChild in lostChildren)
      dropChild(oldChild);
    // update our internal values
    _columns = columns;
    _rows = cells.length ~/ columns;
    _children = cells.toList();
    assert(_children.length == rows * columns);
    markNeedsLayout();
  }

  /// Replaces the children of this table with the given cells.
  void setChildren(List<List<RenderBox>> cells) {
    // TODO(ianh): Make this smarter, like setFlatChildren
    if (cells == null) {
      setFlatChildren(0, null);
      return;
    }
    for (RenderBox oldChild in _children) {
      if (oldChild != null)
        dropChild(oldChild);
    }
    _children.clear();
    _columns = cells.length > 0 ? cells.first.length : 0;
    _rows = 0;
    for (List<RenderBox> row in cells)
      addRow(row);
    assert(_children.length == rows * columns);
  }

  /// Adds a row to the end of the table.
  ///
  /// The newly added children must not already have parents.
  void addRow(List<RenderBox> cells) {
    assert(cells.length == columns);
    assert(_children.length == rows * columns);
    _rows += 1;
    _children.addAll(cells);
    for (RenderBox cell in cells) {
      if (cell != null)
        adoptChild(cell);
    }
    markNeedsLayout();
  }

  /// Replaces the child at the given position with the given child.
  ///
  /// If the given child is already located at the given position, this function
  /// does not modify the table. Otherwise, the given child must not already
  /// have a parent.
  void setChild(int x, int y, RenderBox value) {
    assert(x != null);
    assert(y != null);
    assert(x >= 0 && x < columns && y >= 0 && y < rows);
    assert(_children.length == rows * columns);
    final int xy = x + y * columns;
    RenderBox oldChild = _children[xy];
    if (oldChild == value)
      return;
    if (oldChild != null)
      dropChild(oldChild);
    _children[xy] = value;
    if (value != null)
      adoptChild(value);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    for (RenderBox child in _children)
      child?.attach(owner);
  }

  @override
  void detach() {
    if (_rowDecorationPainters != null) {
      for (BoxPainter painter in _rowDecorationPainters)
        painter?.dispose();
      _rowDecorationPainters = null;
    }
    for (RenderBox child in _children)
      child?.detach();
    super.detach();
  }

  @override
  void visitChildren(RenderObjectVisitor visitor) {
    assert(_children.length == rows * columns);
    for (RenderBox child in _children) {
      if (child != null)
        visitor(child);
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    assert(_children.length == rows * columns);
    double totalMinWidth = 0.0;
    for (int x = 0; x < columns; x += 1) {
      TableColumnWidth columnWidth = _columnWidths[x] ?? defaultColumnWidth;
      Iterable<RenderBox> columnCells = column(x);
      totalMinWidth += columnWidth.minIntrinsicWidth(columnCells, double.INFINITY);
    }
    return totalMinWidth;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    assert(_children.length == rows * columns);
    double totalMaxWidth = 0.0;
    for (int x = 0; x < columns; x += 1) {
      TableColumnWidth columnWidth = _columnWidths[x] ?? defaultColumnWidth;
      Iterable<RenderBox> columnCells = column(x);
      totalMaxWidth += columnWidth.maxIntrinsicWidth(columnCells, double.INFINITY);
    }
    return totalMaxWidth;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    // winner of the 2016 world's most expensive intrinsic dimension function award
    // honorable mention, most likely to improve if taught about memoization award
    assert(_children.length == rows * columns);
    final List<double> widths = _computeColumnWidths(new BoxConstraints.tightForFinite(width: width));
    double rowTop = 0.0;
    for (int y = 0; y < rows; y += 1) {
      double rowHeight = 0.0;
      for (int x = 0; x < columns; x += 1) {
        final int xy = x + y * columns;
        RenderBox child = _children[xy];
        if (child != null)
          rowHeight = math.max(rowHeight, child.getMaxIntrinsicHeight(widths[x]));
      }
      rowTop += rowHeight;
    }
    return rowTop;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    return computeMinIntrinsicHeight(width);
  }

  double _baselineDistance;
  @override
  double computeDistanceToActualBaseline(TextBaseline baseline) {
    // returns the baseline of the first cell that has a baseline in the first row
    assert(!needsLayout);
    return _baselineDistance;
  }

  /// Returns the list of [RenderBox] objects that are in the given
  /// column, in row order, starting from the first row.
  ///
  /// This is a lazily-evaluated iterable.
  Iterable<RenderBox> column(int x) sync* {
    for (int y = 0; y < rows; y += 1) {
      final int xy = x + y * columns;
      RenderBox child = _children[xy];
      if (child != null)
        yield child;
    }
  }

  /// Returns the list of [RenderBox] objects that are on the given
  /// row, in column order, starting with the first column.
  ///
  /// This is a lazily-evaluated iterable.
  Iterable<RenderBox> row(int y) sync* {
    final int start = y * columns;
    final int end = (y + 1) * columns;
    for (int xy = start; xy < end; xy += 1) {
      RenderBox child = _children[xy];
      if (child != null)
        yield child;
    }
  }

  List<double> _computeColumnWidths(BoxConstraints constraints) {
    assert(constraints != null);
    assert(_children.length == rows * columns);
    // We apply the constraints to the column widths in the order of
    // least important to most important:
    // 1. apply the ideal widths (maxIntrinsicWidth)
    // 2. grow the flex columns so that the table has the maxWidth (if
    //    finite) or the minWidth (if not)
    // 3. if there were no flex columns, then grow the table to the
    //    minWidth.
    // 4. apply the maximum width of the table, shrinking columns as
    //    necessary, applying minimum column widths as we go

    // 1. apply ideal widths, and collect information we'll need later
    final List<double> widths = new List<double>(columns);
    final List<double> minWidths = new List<double>(columns);
    final List<double> flexes = new List<double>(columns);
    double tableWidth = 0.0; // running tally of the sum of widths[x] for all x
    double unflexedTableWidth = 0.0; // sum of the maxIntrinsicWidths of any column that has null flex
    double totalFlex = 0.0;
    for (int x = 0; x < columns; x += 1) {
      TableColumnWidth columnWidth = _columnWidths[x] ?? defaultColumnWidth;
      Iterable<RenderBox> columnCells = column(x);
      // apply ideal width (maxIntrinsicWidth)
      final double maxIntrinsicWidth = columnWidth.maxIntrinsicWidth(columnCells, constraints.maxWidth);
      assert(maxIntrinsicWidth.isFinite);
      assert(maxIntrinsicWidth >= 0.0);
      widths[x] = maxIntrinsicWidth;
      tableWidth += maxIntrinsicWidth;
      // collect min width information while we're at it
      final double minIntrinsicWidth = columnWidth.minIntrinsicWidth(columnCells, constraints.maxWidth);
      assert(minIntrinsicWidth.isFinite);
      assert(minIntrinsicWidth >= 0.0);
      minWidths[x] = minIntrinsicWidth;
      assert(maxIntrinsicWidth >= minIntrinsicWidth);
      // collect flex information while we're at it
      double flex = columnWidth.flex(columnCells);
      if (flex != null) {
        assert(flex.isFinite);
        assert(flex > 0.0);
        flexes[x] = flex;
        totalFlex += flex;
      } else {
        unflexedTableWidth += maxIntrinsicWidth;
      }
    }
    assert(!widths.any((double value) => value == null));
    final double maxWidthConstraint = constraints.maxWidth;
    final double minWidthConstraint = constraints.minWidth;

    // 2. grow the flex columns so that the table has the maxWidth (if
    //    finite) or the minWidth (if not)
    if (totalFlex > 0.0) {
      // this can only grow the table, but it _will_ grow the table at
      // least as big as the target width.
      double targetWidth;
      if (maxWidthConstraint.isFinite) {
        targetWidth = maxWidthConstraint;
      } else {
        targetWidth = minWidthConstraint;
      }
      if (tableWidth < targetWidth) {
        final double remainingWidth = targetWidth - unflexedTableWidth;
        assert(remainingWidth.isFinite);
        assert(remainingWidth >= 0.0);
        for (int x = 0; x < columns; x += 1) {
          if (flexes[x] != null) {
            final double flexedWidth = remainingWidth * flexes[x] / totalFlex;
            assert(flexedWidth.isFinite);
            assert(flexedWidth >= 0.0);
            if (widths[x] < flexedWidth) {
              final double delta = flexedWidth - widths[x];
              tableWidth += delta;
              widths[x] = flexedWidth;
            }
          }
        }
        assert(tableWidth >= targetWidth);
      }
    } else // step 2 and 3 are mutually exclusive

    // 3. if there were no flex columns, then grow the table to the
    //    minWidth.
    if (tableWidth < minWidthConstraint) {
      final double delta = (minWidthConstraint - tableWidth) / columns;
      for (int x = 0; x < columns; x += 1)
        widths[x] += delta;
      tableWidth = minWidthConstraint;
    }

    // beyond this point, unflexedTableWidth is no longer valid
    assert(() { unflexedTableWidth = null; return true; });

    // 4. apply the maximum width of the table, shrinking columns as
    //    necessary, applying minimum column widths as we go
    if (tableWidth > maxWidthConstraint) {
      double deficit = tableWidth - maxWidthConstraint;
      // Some columns may have low flex but have all the free space.
      // (Consider a case with a 1px wide column of flex 1000.0 and
      // a 1000px wide column of flex 1.0; the sizes coming from the
      // maxIntrinsicWidths. If the maximum table width is 2px, then
      // just applying the flexes to the deficit would result in a
      // table with one column at -998px and one column at 990px,
      // which is wildly unhelpful.)
      // Similarly, some columns may be flexible, but not actually
      // be shrinkable due to a large minimum width. (Consider a
      // case with two columns, one is flex and one isn't, both have
      // 1000px maxIntrinsicWidths, but the flex one has 1000px
      // minIntrinsicWidth also. The whole deficit will have to come
      // from the non-flex column.)
      // So what we do is we repeatedly iterate through the flexible
      // columns shrinking them proportionally until we have no
      // available columns, then do the same to the non-flexible ones.
      int availableColumns = columns;
      while (deficit > 0.0 && totalFlex > 0.0) {
        double newTotalFlex = 0.0;
        for (int x = 0; x < columns; x += 1) {
          if (flexes[x] != null) {
            final double newWidth = widths[x] - deficit * flexes[x] / totalFlex;
            assert(newWidth.isFinite);
            if (newWidth <= minWidths[x]) {
              // shrank to minimum
              deficit -= widths[x] - minWidths[x];
              widths[x] = minWidths[x];
              flexes[x] = null;
              availableColumns -= 1;
            } else {
              deficit -= widths[x] - newWidth;
              widths[x] = newWidth;
              newTotalFlex += flexes[x];
            }
            assert(widths[x] >= 0.0);
          }
        }
        totalFlex = newTotalFlex;
      }
      if (deficit > 0.0) {
        // Now we have to take out the remaining space from the
        // columns that aren't minimum sized.
        // To make this fair, we repeatedly remove equal amounts from
        // each column, clamped to the minimum width, until we run out
        // of columns that aren't at their minWidth.
        do {
          final double delta = deficit / availableColumns;
          int newAvailableColumns = 0;
          for (int x = 0; x < columns; x += 1) {
            double availableDelta = widths[x] - minWidths[x];
            if (availableDelta > 0.0) {
              if (availableDelta <= delta) {
                // shrank to minimum
                deficit -= widths[x] - minWidths[x];
                widths[x] = minWidths[x];
              } else {
                deficit -= availableDelta;
                widths[x] -= availableDelta;
                newAvailableColumns += 1;
              }
            }
          }
          availableColumns = newAvailableColumns;
        } while (deficit > 0.0 && availableColumns > 0);
      }
    }
    return widths;
  }

  // cache the table geometry for painting purposes
  List<double> _rowTops = <double>[];
  List<double> _columnLefts;

  /// Returns the position and dimensions of the box that the given
  /// row covers, in this render object's coordinate space (so the
  /// left coordinate is always 0.0).
  ///
  /// The row being queried must exist.
  ///
  /// This is only valid after layout.
  Rect getRowBox(int row) {
    assert(row >= 0);
    assert(row < rows);
    assert(!needsLayout);
    return new Rect.fromLTRB(0.0, _rowTops[row], size.width, _rowTops[row + 1]);
  }

  @override
  void performLayout() {
    assert(_children.length == rows * columns);
    if (rows * columns == 0) {
      // TODO(ianh): if columns is zero, this should be zero width
      // TODO(ianh): if columns is not zero, this should be based on the column width specifications
      size = constraints.constrain(const Size(0.0, 0.0));
      return;
    }
    final List<double> widths = _computeColumnWidths(constraints);
    final List<double> positions = new List<double>(columns);
    _rowTops.clear();
    positions[0] = 0.0;
    for (int x = 1; x < columns; x += 1)
      positions[x] = positions[x-1] + widths[x-1];
    _columnLefts = positions;
    assert(!positions.any((double value) => value == null));
    _baselineDistance = null;
    // then, lay out each row
    double rowTop = 0.0;
    for (int y = 0; y < rows; y += 1) {
      _rowTops.add(rowTop);
      double rowHeight = 0.0;
      bool haveBaseline = false;
      double beforeBaselineDistance = 0.0;
      double afterBaselineDistance = 0.0;
      List<double> baselines = new List<double>(columns);
      for (int x = 0; x < columns; x += 1) {
        final int xy = x + y * columns;
        RenderBox child = _children[xy];
        if (child != null) {
          TableCellParentData childParentData = child.parentData;
          assert(childParentData != null);
          childParentData.x = x;
          childParentData.y = y;
          switch (childParentData.verticalAlignment ?? defaultVerticalAlignment) {
            case TableCellVerticalAlignment.baseline:
              assert(textBaseline != null);
              child.layout(new BoxConstraints.tightFor(width: widths[x]), parentUsesSize: true);
              double childBaseline = child.getDistanceToBaseline(textBaseline, onlyReal: true);
              if (childBaseline != null) {
                beforeBaselineDistance = math.max(beforeBaselineDistance, childBaseline);
                afterBaselineDistance = math.max(afterBaselineDistance, child.size.height - childBaseline);
                baselines[x] = childBaseline;
                haveBaseline = true;
              } else {
                rowHeight = math.max(rowHeight, child.size.height);
                childParentData.offset = new Offset(positions[x], rowTop);
              }
              break;
            case TableCellVerticalAlignment.top:
            case TableCellVerticalAlignment.middle:
            case TableCellVerticalAlignment.bottom:
              child.layout(new BoxConstraints.tightFor(width: widths[x]), parentUsesSize: true);
              rowHeight = math.max(rowHeight, child.size.height);
              break;
            case TableCellVerticalAlignment.fill:
              break;
          }
        }
      }
      if (haveBaseline) {
        if (y == 0)
          _baselineDistance = beforeBaselineDistance;
        rowHeight = math.max(rowHeight, beforeBaselineDistance + afterBaselineDistance);
      }
      for (int x = 0; x < columns; x += 1) {
        final int xy = x + y * columns;
        RenderBox child = _children[xy];
        if (child != null) {
          final TableCellParentData childParentData = child.parentData;
          switch (childParentData.verticalAlignment ?? defaultVerticalAlignment) {
            case TableCellVerticalAlignment.baseline:
              if (baselines[x] != null)
                childParentData.offset = new Offset(positions[x], rowTop + beforeBaselineDistance - baselines[x]);
              break;
            case TableCellVerticalAlignment.top:
              childParentData.offset = new Offset(positions[x], rowTop);
              break;
            case TableCellVerticalAlignment.middle:
              childParentData.offset = new Offset(positions[x], rowTop + (rowHeight - child.size.height) / 2.0);
              break;
            case TableCellVerticalAlignment.bottom:
              childParentData.offset = new Offset(positions[x], rowTop + rowHeight - child.size.height);
              break;
            case TableCellVerticalAlignment.fill:
              child.layout(new BoxConstraints.tightFor(width: widths[x], height: rowHeight));
              childParentData.offset = new Offset(positions[x], rowTop);
              break;
          }
        }
      }
      rowTop += rowHeight;
    }
    _rowTops.add(rowTop);
    size = constraints.constrain(new Size(positions.last + widths.last, rowTop));
    assert(_rowTops.length == rows + 1);
  }

  @override
  bool hitTestChildren(HitTestResult result, { Point position }) {
    assert(_children.length == rows * columns);
    for (int index = _children.length - 1; index >= 0; index -= 1) {
      RenderBox child = _children[index];
      if (child != null) {
        final BoxParentData childParentData = child.parentData;
        Point transformed = new Point(position.x - childParentData.offset.dx,
                                      position.y - childParentData.offset.dy);
        if (child.hitTest(result, position: transformed))
          return true;
      }
    }
    return false;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    Canvas canvas;
    assert(_children.length == rows * columns);
    if (rows * columns == 0)
      return;
    assert(_rowTops.length == rows + 1);
    canvas = context.canvas;
    if (_rowDecorations != null) {
      for (int y = 0; y < rows; y += 1) {
        if (_rowDecorations.length <= y)
          break;
        if (_rowDecorations[y] != null) {
          _rowDecorationPainters[y] ??= _rowDecorations[y].createBoxPainter(markNeedsPaint);
          _rowDecorationPainters[y].paint(
            canvas,
            new Offset(offset.dx, offset.dy + _rowTops[y]),
            configuration.copyWith(size: new Size(size.width, _rowTops[y+1] - _rowTops[y]))
          );
        }
      }
    }
    for (int index = 0; index < _children.length; index += 1) {
      RenderBox child = _children[index];
      if (child != null) {
        final BoxParentData childParentData = child.parentData;
        context.paintChild(child, childParentData.offset + offset);
      }
    }
    canvas = context.canvas;
    Rect bounds = offset & size;
    if (border != null) {
      switch (border.verticalInside.style) {
        case BorderStyle.solid:
          Paint paint = new Paint()
            ..color = border.verticalInside.color
            ..strokeWidth = border.verticalInside.width
            ..style = PaintingStyle.stroke;
          Path path = new Path();
          for (int x = 1; x < columns; x += 1) {
            path.moveTo(bounds.left + _columnLefts[x], bounds.top);
            path.lineTo(bounds.left + _columnLefts[x], bounds.bottom);
          }
          canvas.drawPath(path, paint);
          break;
        case BorderStyle.none: break;
      }
      switch (border.horizontalInside.style) {
        case BorderStyle.solid:
          Paint paint = new Paint()
            ..color = border.horizontalInside.color
            ..strokeWidth = border.horizontalInside.width
            ..style = PaintingStyle.stroke;
          Path path = new Path();
          for (int y = 1; y < rows; y += 1) {
            path.moveTo(bounds.left, bounds.top + _rowTops[y]);
            path.lineTo(bounds.right, bounds.top + _rowTops[y]);
          }
          canvas.drawPath(path, paint);
          break;
        case BorderStyle.none: break;
      }
      border.paint(canvas, bounds);
    }
  }

  @override
  void debugFillDescription(List<String> description) {
    super.debugFillDescription(description);
    if (border != null)
      description.add('border: $border');
    if (_columnWidths.length > 0)
      description.add('specified column widths: $_columnWidths');
    description.add('default column width: $defaultColumnWidth');
    description.add('table size: $columns\u00D7$rows');
    if (!needsLayout) {
      description.add('column offsets: ${ _columnLefts ?? "unknown" }');
      description.add('row offsets: ${ _rowTops ?? "unknown" }');
    }
  }

  @override
  String debugDescribeChildren(String prefix) {
    StringBuffer result = new StringBuffer();
    result.writeln('$prefix \u2502');
    int lastIndex = _children.length - 1;
    if (lastIndex < 0) {
      result.writeln('$prefix \u2514\u2500table is empty');
    } else {
      for (int y = 0; y < rows; y += 1) {
        for (int x = 0; x < columns; x += 1) {
          final int xy = x + y * columns;
          RenderBox child = _children[xy];
          if (child != null) {
            if (xy < lastIndex) {
              result.write('${child.toStringDeep("$prefix \u251C\u2500child ($x, $y): ", "$prefix \u2502")}');
            } else {
              result.write('${child.toStringDeep("$prefix \u2514\u2500child ($x, $y): ", "$prefix  ")}');
            }
          } else {
            if (xy < lastIndex) {
              result.writeln('$prefix \u251C\u2500child ($x, $y) is null');
            } else {
              result.writeln('$prefix \u2514\u2500child ($x, $y) is null');
            }
          }
        }
      }
    }
    return result.toString();
  }
}
