import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart' hide ReorderCallback;

import 'reorderable_sliver.dart';

class ReorderableSliverGridMultiBoxAdaptorElement
    extends ReorderableSliverMultiBoxAdaptorElement {
  ReorderableSliverGridMultiBoxAdaptorElement(
    super.widget, {
    super.replaceMovedChildren = false,
  });

  @override
  void onFinishLayout() {
    visitChildElements((element) {
      final parentData =
          element.renderObject?.parentData as ReorderableParentData;
      if (parentData.index != null) {
        final newItemOffset =
            Offset(parentData.crossAxisOffset!, parentData.layoutOffset!);
        parentData.currentOffset = newItemOffset;
      }
    });
  }

  @override
  Widget buildChild(int index, Widget child) {
    return child;
    // return ReorderableItemInheritedWidget(
    //   itemData: ItemData()
    //     ..itemIndex = index
    //     ..renderObjectIndex = index,
    //   child: child,
    // );
  }

  @override
  Offset convertChildParentData(SliverMultiBoxAdaptorParentData parentData) {
    final data = parentData as SliverGridParentData;
    return Offset(data.crossAxisOffset!, data.layoutOffset!);
  }

  @override
  void updateChildParentData(Element element, data) {
    final childParentData =
        element.renderObject?.parentData as ReorderableParentData;
    final offset = data as Offset;
    (childParentData as SliverGridParentData).crossAxisOffset = offset.dx;
    childParentData.layoutOffset = offset.dy;
    childParentData.setRenderObjectIndex(childParentData.index);
  }
}

/// A sliver that places multiple box children in a two dimensional arrangement.
///
/// [SliverGrid] places its children in arbitrary positions determined by
/// [gridDelegate]. Each child is forced to have the size specified by the
/// [gridDelegate].
///
/// The main axis direction of a grid is the direction in which it scrolls; the
/// cross axis direction is the orthogonal direction.
///
/// {@youtube 560 315 https://www.youtube.com/watch?v=ORiTTaVY6mM}
///
/// {@tool snippet}
///
/// This example, which would be inserted into a [CustomScrollView.slivers]
/// list, shows twenty boxes in a pretty teal grid:
///
/// ```dart
/// SliverGrid(
///   gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
///     maxCrossAxisExtent: 200.0,
///     mainAxisSpacing: 10.0,
///     crossAxisSpacing: 10.0,
///     childAspectRatio: 4.0,
///   ),
///   delegate: SliverChildBuilderDelegate(
///     (BuildContext context, int index) {
///       return Container(
///         alignment: Alignment.center,
///         color: Colors.teal[100 * (index % 9)],
///         child: Text('grid item $index'),
///       );
///     },
///     childCount: 20,
///   ),
/// )
/// ```
/// {@end-tool}
///
/// {@macro flutter.widgets.SliverChildDelegate.lifecycle}
///
/// See also:
///
///  * [SliverList], which places its children in a linear array.
///  * [SliverFixedExtentList], which places its children in a linear
///    array with a fixed extent in the main axis.
///  * [SliverPrototypeExtentList], which is similar to [SliverFixedExtentList]
///    except that it uses a prototype list item instead of a pixel value to
///    define the main axis extent of each item.
class ReorderableSliverGrid extends ReorderableSliverMultiBoxAdaptorWidget {
  /// Creates a sliver that places multiple box children in a two dimensional
  /// arrangement.
  const ReorderableSliverGrid({
    Key? key,
    required ReorderableSliverChildDelegate delegate,
    required this.gridDelegate,
  }) : super(key: key, delegate: delegate);

  /// Creates a sliver that places multiple box children in a two dimensional
  /// arrangement with a fixed number of tiles in the cross axis.
  ///
  /// Uses a [SliverGridDelegateWithFixedCrossAxisCount] as the [gridDelegate],
  /// and a [SliverChildListDelegate] as the [delegate].
  ///
  /// See also:
  ///
  ///  * [GridView.count], the equivalent constructor for [GridView] widgets.
  ReorderableSliverGrid.count({
    Key? key,
    required int crossAxisCount,
    double mainAxisSpacing = 0.0,
    double crossAxisSpacing = 0.0,
    double childAspectRatio = 1.0,
    List<Widget> children = const <Widget>[],
    required ReorderCallback onReorder,
    ReorderableIndexContextCallback? onDrag,
    ReorderableIndexContextCallback? onMerge,
  })  : gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: mainAxisSpacing,
          crossAxisSpacing: crossAxisSpacing,
          childAspectRatio: childAspectRatio,
        ),
        super(
          key: key,
          delegate: ReorderableSliverChildListDelegate(children,
              onReorder: onReorder, onDrag: onDrag, onMerge: onMerge),
        );

  /// Creates a sliver that places multiple box children in a two dimensional
  /// arrangement with tiles that each have a maximum cross-axis extent.
  ///
  /// Uses a [SliverGridDelegateWithMaxCrossAxisExtent] as the [gridDelegate],
  /// and a [SliverChildListDelegate] as the [delegate].
  ///
  /// See also:
  ///
  ///  * [GridView.extent], the equivalent constructor for [GridView] widgets.
  ReorderableSliverGrid.extent({
    Key? key,
    required double maxCrossAxisExtent,
    double mainAxisSpacing = 0.0,
    double crossAxisSpacing = 0.0,
    double childAspectRatio = 1.0,
    List<Widget> children = const <Widget>[],
    required ReorderCallback onReorder,
    ReorderableIndexContextCallback? onDrag,
    ReorderableIndexContextCallback? onMerge,
  })  : gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: maxCrossAxisExtent,
          mainAxisSpacing: mainAxisSpacing,
          crossAxisSpacing: crossAxisSpacing,
          childAspectRatio: childAspectRatio,
        ),
        super(
          key: key,
          delegate: ReorderableSliverChildListDelegate(children,
              onReorder: onReorder, onDrag: onDrag, onMerge: onMerge),
        );

  /// The delegate that controls the size and position of the children.
  final SliverGridDelegate gridDelegate;

  @override
  ReorderableSliverMultiBoxAdaptorElement createElement() {
    return ReorderableSliverGridMultiBoxAdaptorElement(this);
  }

  @override
  ReorderableRenderSliverGrid createRenderObject(BuildContext context) {
    final element = context as ReorderableSliverMultiBoxAdaptorElement;
    return ReorderableRenderSliverGrid(
        childManager: element, gridDelegate: gridDelegate);
  }

  @override
  void updateRenderObject(
      BuildContext context, ReorderableRenderSliverGrid renderObject) {
    renderObject.gridDelegate = gridDelegate;
  }

  @override
  double estimateMaxScrollOffset(
    SliverConstraints? constraints,
    int firstIndex,
    int lastIndex,
    double leadingScrollOffset,
    double trailingScrollOffset,
  ) {
    return super.estimateMaxScrollOffset(
          constraints,
          firstIndex,
          lastIndex,
          leadingScrollOffset,
          trailingScrollOffset,
        ) ??
        gridDelegate
            .getLayout(constraints!)
            .computeMaxScrollOffset(delegate.estimatedChildCount!);
  }
}

class ReorderableRenderSliverGrid extends RenderSliverGrid
    with ReorderableData {
  ReorderableRenderSliverGrid({
    required super.childManager,
    required super.gridDelegate,
  });

  @override
  void setupParentData(covariant RenderObject child) {
    if (child.parentData is! ReorderableSliverGridParentData) {
      child.parentData = ReorderableSliverGridParentData();
    }
  }
}

class ReorderableSliverGridParentData extends SliverGridParentData
    with ReorderableParentData {}
