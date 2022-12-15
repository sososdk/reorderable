import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'reorderable_animated_container.dart';
import 'reorderable_drag_target.dart';

// ignore_for_file: lines_longer_than_80_chars

mixin ReorderableData on RenderSliverMultiBoxAdaptor {
  int? dragIndex;
  int? insertIndex;

  void reorder(ReorderCallback onReorder) {
    if (dragIndex != null && insertIndex != null) {
      onReorder(insertIndex!, dragIndex!);
    }
    dragIndex = null;
    insertIndex = null;
  }
}

mixin ReorderableParentData on SliverMultiBoxAdaptorParentData {
  // ItemData? itemData;
  // int itemIndex = -1;
  // int? renderObjectIndex = -1;
  Offset currentOffset = const Offset(-1.0, -1.0);
  bool isMergeTarget = false;

  double? get crossAxisOffset;

  void setRenderObjectIndex(int? index) {
    // renderObjectIndex = index;
  }

  void toggleMergeTarget() {
    isMergeTarget = !isMergeTarget;
  }

  void resetState() {
    isMergeTarget = false;
  }
}

/// An element that lazily builds children for a [ReorderableSliverMultiBoxAdaptorElement].
///
/// Implements [RenderSliverBoxChildManager], which lets this element manage
/// the children of subclasses of [RenderSliverMultiBoxAdaptor].
abstract class ReorderableSliverMultiBoxAdaptorElement
    extends RenderObjectElement implements RenderSliverBoxChildManager {
  /// Creates an element that lazily builds children for the given widget.
  ///
  /// If `replaceMovedChildren` is set to true, a new child is proactively
  /// inflate for the index that was previously occupied by a child that moved
  /// to a new index. The layout offset of the moved child is copied over to the
  /// new child. RenderObjects, that depend on the layout offset of existing
  /// children during [RenderObject.performLayout] should set this to true
  /// (example: [RenderSliverList]). For RenderObjects that figure out the
  /// layout offset of their children without looking at the layout offset of
  /// existing children this should be set to false (example:
  /// [RenderSliverFixedExtentList]) to avoid inflating unnecessary children.
  ReorderableSliverMultiBoxAdaptorElement(
      ReorderableSliverMultiBoxAdaptorWidget super.widget,
      {bool replaceMovedChildren = false})
      : _replaceMovedChildren = replaceMovedChildren;

  final bool _replaceMovedChildren;

  @override
  RenderSliverMultiBoxAdaptor get renderObject =>
      super.renderObject as RenderSliverMultiBoxAdaptor;

  @override
  void update(covariant ReorderableSliverMultiBoxAdaptorWidget newWidget) {
    final oldWidget = widget as ReorderableSliverMultiBoxAdaptorWidget;
    super.update(newWidget);
    final newDelegate = newWidget.delegate;
    final oldDelegate = oldWidget.delegate;
    if (newDelegate != oldDelegate &&
        (newDelegate.runtimeType != oldDelegate.runtimeType ||
            newDelegate.shouldRebuild(oldDelegate))) {
      performRebuild();
    }
  }

  final _childElements = SplayTreeMap<int, Element?>();
  RenderBox? _currentBeforeChild;

  @override
  void performRebuild() {
    super.performRebuild();
    _currentBeforeChild = null;
    var childrenUpdated = false;
    assert(_currentlyUpdatingChildIndex == null);
    try {
      final newChildren = SplayTreeMap<int, Element?>();
      final Map<int, double> indexToLayoutOffset = HashMap<int, double>();
      final adaptorWidget = widget as ReorderableSliverMultiBoxAdaptorWidget;
      void processElement(int index) {
        _currentlyUpdatingChildIndex = index;
        if (_childElements[index] != null &&
            _childElements[index] != newChildren[index]) {
          // This index has an old child that isn't used anywhere and should be deactivated.
          _childElements[index] =
              updateChild(_childElements[index], null, index);
          childrenUpdated = true;
        }
        final newChild = updateChild(
            newChildren[index], _build(index, adaptorWidget), index);
        if (newChild != null) {
          childrenUpdated =
              childrenUpdated || _childElements[index] != newChild;
          _childElements[index] = newChild;
          final parentData = newChild.renderObject!.parentData!
              as SliverMultiBoxAdaptorParentData;
          if (index == 0) {
            parentData.layoutOffset = 0.0;
          } else if (indexToLayoutOffset.containsKey(index)) {
            parentData.layoutOffset = indexToLayoutOffset[index];
          }
          if (!parentData.keptAlive) {
            _currentBeforeChild = newChild.renderObject as RenderBox?;
          }
        } else {
          childrenUpdated = true;
          _childElements.remove(index);
        }
      }

      for (final index in _childElements.keys.toList()) {
        final key = _childElements[index]!.widget.key;
        final newIndex =
            key == null ? null : adaptorWidget.delegate.findIndexByKey(key);
        final childParentData = _childElements[index]!.renderObject?.parentData
            as SliverMultiBoxAdaptorParentData?;

        if (childParentData != null && childParentData.layoutOffset != null) {
          indexToLayoutOffset[index] = childParentData.layoutOffset!;
        }

        if (newIndex != null && newIndex != index) {
          // The layout offset of the child being moved is no longer accurate.
          if (childParentData != null) {
            childParentData.layoutOffset = null;
          }

          newChildren[newIndex] = _childElements[index];
          if (_replaceMovedChildren) {
            // We need to make sure the original index gets processed.
            newChildren.putIfAbsent(index, () => null);
          }
          // We do not want the remapped child to get deactivated during processElement.
          _childElements.remove(index);
        } else {
          newChildren.putIfAbsent(index, () => _childElements[index]);
        }
      }

      renderObject.debugChildIntegrityEnabled =
          false; // Moving children will temporary violate the integrity.
      newChildren.keys.forEach(processElement);
      // An element rebuild only updates existing children. The underflow check
      // is here to make sure we look ahead one more child if we were at the end
      // of the child list before the update. By doing so, we can update the max
      // scroll offset during the layout phase. Otherwise, the layout phase may
      // be skipped, and the scroll view may be stuck at the previous max
      // scroll offset.
      //
      // This logic is not needed if any existing children has been updated,
      // because we will not skip the layout phase if that happens.
      if (!childrenUpdated && _didUnderflow) {
        final lastKey = _childElements.lastKey() ?? -1;
        final rightBoundary = lastKey + 1;
        newChildren[rightBoundary] = _childElements[rightBoundary];
        processElement(rightBoundary);
      }
    } finally {
      _currentlyUpdatingChildIndex = null;
      renderObject.debugChildIntegrityEnabled = true;
    }
  }

  Widget? _build(int index, ReorderableSliverMultiBoxAdaptorWidget widget) {
    final child = widget.delegate.build(this, index);
    if (child == null) return null;

    return buildChild(index, child);
  }

  Widget buildChild(int index, Widget child);

  @override
  void createChild(int index, {required RenderBox? after}) {
    assert(_currentlyUpdatingChildIndex == null);
    owner!.buildScope(this, () {
      final insertFirst = after == null;
      assert(insertFirst || _childElements[index - 1] != null);
      _currentBeforeChild = insertFirst
          ? null
          : (_childElements[index - 1]!.renderObject as RenderBox?);
      Element? newChild;
      try {
        final adaptorWidget = widget as ReorderableSliverMultiBoxAdaptorWidget;
        _currentlyUpdatingChildIndex = index;
        newChild = updateChild(
            _childElements[index], _build(index, adaptorWidget), index);
      } finally {
        _currentlyUpdatingChildIndex = null;
      }
      if (newChild != null) {
        _childElements[index] = newChild;
      } else {
        _childElements.remove(index);
      }
    });
  }

  @override
  Element? updateChild(Element? child, Widget? newWidget, Object? newSlot) {
    final oldParentData =
        child?.renderObject?.parentData as SliverMultiBoxAdaptorParentData?;
    final newChild = super.updateChild(child, newWidget, newSlot);
    final newParentData =
        newChild?.renderObject?.parentData as SliverMultiBoxAdaptorParentData?;

    // Preserve the old layoutOffset if the renderObject was swapped out.
    if (oldParentData != newParentData &&
        oldParentData != null &&
        newParentData != null) {
      newParentData.layoutOffset = oldParentData.layoutOffset;
    }
    return newChild;
  }

  @override
  void forgetChild(Element child) {
    assert(child.slot != null);
    assert(_childElements.containsKey(child.slot));
    _childElements.remove(child.slot);
    super.forgetChild(child);
  }

  @override
  void removeChild(RenderBox child) {
    final index = renderObject.indexOf(child);
    assert(_currentlyUpdatingChildIndex == null);
    assert(index >= 0);
    owner!.buildScope(this, () {
      assert(_childElements.containsKey(index));
      try {
        _currentlyUpdatingChildIndex = index;
        final result = updateChild(_childElements[index], null, index);
        assert(result == null);
      } finally {
        _currentlyUpdatingChildIndex = null;
      }
      _childElements.remove(index);
      assert(!_childElements.containsKey(index));
    });
  }

  static double _extrapolateMaxScrollOffset(
    int firstIndex,
    int lastIndex,
    double leadingScrollOffset,
    double trailingScrollOffset,
    int childCount,
  ) {
    if (lastIndex == childCount - 1) {
      return trailingScrollOffset;
    }
    final reifiedCount = lastIndex - firstIndex + 1;
    final averageExtent =
        (trailingScrollOffset - leadingScrollOffset) / reifiedCount;
    final remainingCount = childCount - lastIndex - 1;
    return trailingScrollOffset + averageExtent * remainingCount;
  }

  @override
  double estimateMaxScrollOffset(
    SliverConstraints? constraints, {
    int? firstIndex,
    int? lastIndex,
    double? leadingScrollOffset,
    double? trailingScrollOffset,
  }) {
    final childCount = estimatedChildCount;
    if (childCount == null) {
      return double.infinity;
    }
    return (widget as ReorderableSliverMultiBoxAdaptorWidget)
            .estimateMaxScrollOffset(
          constraints,
          firstIndex!,
          lastIndex!,
          leadingScrollOffset!,
          trailingScrollOffset!,
        ) ??
        _extrapolateMaxScrollOffset(
          firstIndex,
          lastIndex,
          leadingScrollOffset,
          trailingScrollOffset,
          childCount,
        );
  }

  /// The best available estimate of [childCount], or null if no estimate is available.
  ///
  /// This differs from [childCount] in that [childCount] never returns null (and must
  /// not be accessed if the child count is not yet available, meaning the [createChild]
  /// method has not been provided an index that does not create a child).
  ///
  /// See also:
  ///
  ///  * [SliverChildDelegate.estimatedChildCount], to which this getter defers.
  int? get estimatedChildCount =>
      (widget as ReorderableSliverMultiBoxAdaptorWidget)
          .delegate
          .estimatedChildCount;

  @override
  int get childCount {
    var result = estimatedChildCount;
    if (result == null) {
      // Since childCount was called, we know that we reached the end of
      // the list (as in, _build return null once), so we know that the
      // list is finite.
      // Let's do an open-ended binary search to find the end of the list
      // manually.
      var lo = 0;
      var hi = 1;
      final adaptorWidget = widget as ReorderableSliverMultiBoxAdaptorWidget;
      const max = kIsWeb
          ? 9007199254740992 // max safe integer on JS (from 0 to this number x != x+1)
          : ((1 << 63) - 1);
      while (_build(hi - 1, adaptorWidget) != null) {
        lo = hi - 1;
        if (hi < max ~/ 2) {
          hi *= 2;
        } else if (hi < max) {
          hi = max;
        } else {
          throw FlutterError(
            'Could not find the number of children in ${adaptorWidget.delegate}.\n'
            "The childCount getter was called (implying that the delegate's builder returned null "
            'for a positive index), but even building the child with index $hi (the maximum '
            'possible integer) did not return null. Consider implementing childCount to avoid '
            'the cost of searching for the final child.',
          );
        }
      }
      while (hi - lo > 1) {
        final mid = (hi - lo) ~/ 2 + lo;
        if (_build(mid - 1, adaptorWidget) == null) {
          hi = mid;
        } else {
          lo = mid;
        }
      }
      result = lo;
    }
    return result;
  }

  @override
  void didStartLayout() {
    assert(debugAssertChildListLocked());
  }

  @override
  void didFinishLayout() {
    assert(debugAssertChildListLocked());
    final firstIndex = _childElements.firstKey() ?? 0;
    final lastIndex = _childElements.lastKey() ?? 0;
    (widget as ReorderableSliverMultiBoxAdaptorWidget)
        .delegate
        .didFinishLayout(firstIndex, lastIndex);

    onFinishLayout();
  }

  void onFinishLayout();

  int? _currentlyUpdatingChildIndex;
  int? _currentlyInsertChildIndex;
  int? _currentlyInsertTargetChildIndex;

  @override
  bool debugAssertChildListLocked() {
    assert(_currentlyUpdatingChildIndex == null);
    return true;
  }

  @override
  void didAdoptChild(RenderBox child) {
    assert(_currentlyUpdatingChildIndex != null);
    final childParentData =
        child.parentData! as SliverMultiBoxAdaptorParentData;
    childParentData.index = _currentlyUpdatingChildIndex;

    if (_currentlyInsertChildIndex != null &&
        _currentlyInsertTargetChildIndex != null) {
      if (_currentlyInsertChildIndex! < _currentlyInsertTargetChildIndex!) {
        final reorderIndex = _currentlyInsertChildIndex! + 1;
        final reorderElement = _childElements[reorderIndex];
        var reorderStartIndex = _currentlyUpdatingChildIndex! + 1;
        if (reorderElement != null) {
          var reorderChild = reorderElement.renderObject as RenderBox?;
          while (reorderChild != null) {
            final parentData = reorderChild.parentData;
            if (parentData is SliverMultiBoxAdaptorParentData) {
              parentData.index = reorderStartIndex;
              reorderStartIndex++;
            }

            reorderChild = renderObject.childAfter(reorderChild);
          }
        }
      } else {
        final reorderIndex = _currentlyInsertChildIndex! - 1;
        final reorderElement = _childElements[reorderIndex];
        var reorderStartIndex = _currentlyUpdatingChildIndex! - 1;
        if (reorderElement != null) {
          var reorderChild = reorderElement.renderObject as RenderBox?;
          while (reorderChild != null) {
            final parentData = reorderChild.parentData;
            if (parentData is SliverMultiBoxAdaptorParentData) {
              parentData.index = reorderStartIndex;
              reorderStartIndex--;
            }

            reorderChild = renderObject.childBefore(reorderChild);
          }
        }
      }
    }
  }

  bool _didUnderflow = false;

  @override
  void setDidUnderflow(bool value) {
    _didUnderflow = value;
  }

  @override
  void insertRenderObjectChild(covariant RenderObject child, int slot) {
    assert(_currentlyUpdatingChildIndex == slot);
    assert(renderObject.debugValidateChild(child));
    renderObject.insert(child as RenderBox, after: _currentBeforeChild);
    assert(() {
      final childParentData =
          child.parentData! as SliverMultiBoxAdaptorParentData;
      assert(slot == childParentData.index);
      return true;
    }());
  }

  @override
  void moveRenderObjectChild(
      covariant RenderObject child, int oldSlot, int newSlot) {
    assert(_currentlyUpdatingChildIndex == newSlot);
    renderObject.move(child as RenderBox, after: _currentBeforeChild);
  }

  @override
  void removeRenderObjectChild(covariant RenderObject child, int slot) {
    assert(_currentlyUpdatingChildIndex != null);
    renderObject.remove(child as RenderBox);
  }

  @override
  void visitChildren(ElementVisitor visitor) {
    // The toList() is to make a copy so that the underlying list can be modified by
    // the visitor:
    assert(!_childElements.values.any((child) => child == null));
    _childElements.values.cast<Element>().toList().forEach(visitor);
  }

  @override
  void debugVisitOnstageChildren(ElementVisitor visitor) {
    _childElements.values.cast<Element>().where((child) {
      final parentData =
          child.renderObject!.parentData! as SliverMultiBoxAdaptorParentData;
      final double itemExtent;
      switch (renderObject.constraints.axis) {
        case Axis.horizontal:
          itemExtent = child.renderObject!.paintBounds.width;
          break;
        case Axis.vertical:
          itemExtent = child.renderObject!.paintBounds.height;
          break;
      }

      return parentData.layoutOffset != null &&
          parentData.layoutOffset! <
              renderObject.constraints.scrollOffset +
                  renderObject.constraints.remainingPaintExtent &&
          parentData.layoutOffset! + itemExtent >
              renderObject.constraints.scrollOffset;
    }).forEach(visitor);
  }

  void reorderRenderObjectChild(int toIndex, int fromIndex) {
    if (renderObject.debugNeedsLayout) return;

    final fromRenderObject = _childElements[fromIndex]?.renderObject;
    final toRenderObject = _childElements[toIndex]?.renderObject;

    final parentDatas = <int, dynamic>{};
    for (var index in _childElements.keys.toList()) {
      final childParentData = _childElements[index]!.renderObject?.parentData
          as SliverMultiBoxAdaptorParentData;
      parentDatas[index] = convertChildParentData(childParentData);
    }

    if (fromRenderObject != null) {
      final fromItem = _childElements[fromIndex];

      _currentlyUpdatingChildIndex =
          (toRenderObject?.parentData! as SliverMultiBoxAdaptorParentData)
              .index;

      // Adjust the element order.
      if (toIndex < fromIndex) {
        for (var index = fromIndex; index > toIndex; index--) {
          final preItem =
              index - 1 < toIndex ? fromItem : _childElements[index - 1];
          _childElements[index] = preItem;
        }
      } else {
        for (var index = fromIndex; index < toIndex; index++) {
          final nextItem =
              index + 1 > toIndex ? fromItem : _childElements[index + 1];
          _childElements[index] = nextItem;
        }
      }
      _childElements[toIndex] = fromItem;
      _currentlyInsertChildIndex = toIndex;
      _currentlyInsertTargetChildIndex = fromIndex;

      final afterBox = _childElements[toIndex - 1]?.renderObject as RenderBox?;
      renderObject.move(fromRenderObject as RenderBox, after: afterBox);

      // Update child position.
      for (var index in _childElements.keys.toList()) {
        final childElement = _childElements[index]!;
        final childData = parentDatas[index];
        updateChildParentData(childElement, childData);
      }

      _currentlyUpdatingChildIndex = null;
      _currentlyInsertChildIndex = null;
      _currentlyInsertTargetChildIndex = null;
    }
  }

  dynamic convertChildParentData(SliverMultiBoxAdaptorParentData parentData);

  void updateChildParentData(Element element, data);
}

/// A base class for sliver that have multiple box children.
///
/// Helps subclasses build their children lazily using a [SliverChildDelegate].
///
/// The widgets returned by the [delegate] are cached and the delegate is only
/// consulted again if it changes and the new delegate's
/// [SliverChildDelegate.shouldRebuild] method returns true.
abstract class ReorderableSliverMultiBoxAdaptorWidget
    extends SliverWithKeepAliveWidget {
  /// Initializes fields for subclasses.
  const ReorderableSliverMultiBoxAdaptorWidget({
    Key? key,
    required this.delegate,
  }) : super(key: key);

  /// {@template flutter.widgets.SliverMultiBoxAdaptorWidget.delegate}
  /// The delegate that provides the children for this widget.
  ///
  /// The children are constructed lazily using this delegate to avoid creating
  /// more children than are visible through the [Viewport].
  ///
  /// See also:
  ///
  ///  * [ReorderableSliverChildBuilderDelegate] and [ReorderableSliverChildListDelegate], which are
  ///    commonly used subclasses of [SliverChildDelegate] that use a builder
  ///    callback and an explicit child list, respectively.
  /// {@endtemplate}
  final SliverChildDelegate delegate;

  @override
  ReorderableSliverMultiBoxAdaptorElement createElement();

  @override
  RenderSliverMultiBoxAdaptor createRenderObject(BuildContext context);

  /// Returns an estimate of the max scroll extent for all the children.
  ///
  /// Subclasses should override this function if they have additional
  /// information about their max scroll extent.
  ///
  /// This is used by [SliverMultiBoxAdaptorElement] to implement part of the
  /// [RenderSliverBoxChildManager] API.
  ///
  /// The default implementation defers to [delegate] via its
  /// [SliverChildDelegate.estimateMaxScrollOffset] method.
  double? estimateMaxScrollOffset(
    SliverConstraints? constraints,
    int firstIndex,
    int lastIndex,
    double leadingScrollOffset,
    double trailingScrollOffset,
  ) {
    assert(lastIndex >= firstIndex);
    return delegate.estimateMaxScrollOffset(
      firstIndex,
      lastIndex,
      leadingScrollOffset,
      trailingScrollOffset,
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
        .add(DiagnosticsProperty<SliverChildDelegate>('delegate', delegate));
  }
}

int _kDefaultSemanticIndexCallback(Widget _, int localIndex) => localIndex;

typedef ReorderableIndexContextCallback = Function(int index, ItemData? data);

abstract class ReorderableSliverChildDelegate extends SliverChildDelegate {
  const ReorderableSliverChildDelegate(this.onReorder,
      {this.onDrag, this.onMerge});

  final ReorderCallback onReorder;
  final ReorderableIndexContextCallback? onDrag;
  final ReorderableIndexContextCallback? onMerge;

  Widget buildChild(BuildContext context, int index, Widget child) {
    final reorderableData = context.findRenderObject() as ReorderableData;
    return ReorderableAnimatedItem(
      index: index,
      onReorderCallback: (to, from) {
        (context as ReorderableSliverMultiBoxAdaptorElement)
            .reorderRenderObjectChild(to, from);
      },
      onDragFinish: () {
        reorderableData.reorder(onReorder);
        context.visitChildElements((element) {
          // final data =
          //     element.renderObject!.parentData as ReorderableParentData;
          final data = ReorderableItemInheritedWidget.of(element)?.itemData;
          data?.resetState();
        });
        context.findRenderObject()?.markNeedsLayout();
      },
      onDragCallback: (index) {
        print('onDragCallback');
        context.visitChildElements((element) {
          // final data =
          //     element.renderObject!.parentData as ReorderableParentData;
          final data =
              ReorderableItemInheritedWidget.of(element, isDependent: false)!
                  .itemData;
          if (index == data.itemIndex) {
            onDrag?.call(index, data);
            return;
          }
        });
      },
      onMergeCallback: (index) {
        context.visitChildElements((element) {
          // final data =
          //     element.renderObject!.parentData as ReorderableParentData;
          final data =
              ReorderableItemInheritedWidget.of(element, isDependent: false)!
                  .itemData;
          if (index == data.itemIndex) {
            data.toggleMergeTarget();
            onMerge?.call(index, data);
            return;
          }
        });
      },
      child: child,
    );
  }
}

class _SaltedValueKey extends ValueKey<Key> {
  const _SaltedValueKey(Key key) : super(key);
}

// Return a Widget for the given Exception
Widget _createErrorWidget(Object exception, StackTrace stackTrace) {
  final details = FlutterErrorDetails(
    exception: exception,
    stack: stackTrace,
    library: 'widgets library',
    context: ErrorDescription('building'),
  );
  FlutterError.reportError(details);
  return ErrorWidget.builder(details);
}

class ReorderableSliverChildBuilderDelegate
    extends ReorderableSliverChildDelegate {
  /// Creates a delegate that supplies children for slivers using the given
  /// builder callback.
  ///
  /// The [builder], [addAutomaticKeepAlives], [addRepaintBoundaries],
  /// [addSemanticIndexes], and [semanticIndexCallback] arguments must not be
  /// null.
  ///
  /// If the order in which [builder] returns children ever changes, consider
  /// providing a [findChildIndexCallback]. This allows the delegate to find the
  /// new index for a child that was previously located at a different index to
  /// attach the existing state to the [Widget] at its new location.
  const ReorderableSliverChildBuilderDelegate(
    this.builder, {
    required ReorderCallback onReorder,
    ReorderableIndexContextCallback? onDrag,
    ReorderableIndexContextCallback? onMerge,
    this.findChildIndexCallback,
    this.childCount,
    this.addAutomaticKeepAlives = true,
    this.addRepaintBoundaries = true,
    this.addSemanticIndexes = true,
    this.semanticIndexCallback = _kDefaultSemanticIndexCallback,
    this.semanticIndexOffset = 0,
  }) : super(onReorder, onDrag: onDrag, onMerge: onMerge);

  /// Called to build children for the sliver.
  ///
  /// Will be called only for indices greater than or equal to zero and less
  /// than [childCount] (if [childCount] is non-null).
  ///
  /// Should return null if asked to build a widget with a greater index than
  /// exists.
  ///
  /// The delegate wraps the children returned by this builder in
  /// [RepaintBoundary] widgets.
  final NullableIndexedWidgetBuilder builder;

  /// The total number of children this delegate can provide.
  ///
  /// If null, the number of children is determined by the least index for which
  /// [builder] returns null.
  final int? childCount;

  /// Whether to wrap each child in an [AutomaticKeepAlive].
  ///
  /// Typically, children in lazy list are wrapped in [AutomaticKeepAlive]
  /// widgets so that children can use [KeepAliveNotification]s to preserve
  /// their state when they would otherwise be garbage collected off-screen.
  ///
  /// This feature (and [addRepaintBoundaries]) must be disabled if the children
  /// are going to manually maintain their [KeepAlive] state. It may also be
  /// more efficient to disable this feature if it is known ahead of time that
  /// none of the children will ever try to keep themselves alive.
  ///
  /// Defaults to true.
  final bool addAutomaticKeepAlives;

  /// Whether to wrap each child in a [RepaintBoundary].
  ///
  /// Typically, children in a scrolling container are wrapped in repaint
  /// boundaries so that they do not need to be repainted as the list scrolls.
  /// If the children are easy to repaint (e.g., solid color blocks or a short
  /// snippet of text), it might be more efficient to not add a repaint boundary
  /// and simply repaint the children during scrolling.
  ///
  /// Defaults to true.
  final bool addRepaintBoundaries;

  /// Whether to wrap each child in an [IndexedSemantics].
  ///
  /// Typically, children in a scrolling container must be annotated with a
  /// semantic index in order to generate the correct accessibility
  /// announcements. This should only be set to false if the indexes have
  /// already been provided by an [IndexedSemantics] widget.
  ///
  /// Defaults to true.
  ///
  /// See also:
  ///
  ///  * [IndexedSemantics], for an explanation of how to manually
  ///    provide semantic indexes.
  final bool addSemanticIndexes;

  /// An initial offset to add to the semantic indexes generated by this widget.
  ///
  /// Defaults to zero.
  final int semanticIndexOffset;

  /// A [SemanticIndexCallback] which is used when [addSemanticIndexes] is true.
  ///
  /// Defaults to providing an index for each widget.
  final SemanticIndexCallback semanticIndexCallback;

  /// Called to find the new index of a child based on its key in case of reordering.
  ///
  /// If not provided, a child widget may not map to its existing [RenderObject]
  /// when the order in which children are returned from [builder] changes.
  /// This may result in state-loss.
  ///
  /// This callback should take an input [Key], and it should return the
  /// index of the child element with that associated key, or null if not found.
  final ChildIndexGetter? findChildIndexCallback;

  @override
  int? findIndexByKey(Key key) {
    if (findChildIndexCallback == null) return null;
    final Key childKey;
    if (key is _SaltedValueKey) {
      childKey = key.value;
    } else {
      childKey = key;
    }
    return findChildIndexCallback!(childKey);
  }

  @override
  @pragma('vm:notify-debugger-on-exception')
  Widget? build(BuildContext context, int index) {
    if (index < 0 || (childCount != null && index >= childCount!)) return null;
    Widget? child;
    try {
      child = builder(context, index);
      if (child == null) return null;

      child = buildChild(context, index, child);
    } catch (exception, stackTrace) {
      child = _createErrorWidget(exception, stackTrace);
    }
    final Key? key = child.key != null ? _SaltedValueKey(child.key!) : null;
    if (addRepaintBoundaries) child = RepaintBoundary(child: child);
    if (addSemanticIndexes) {
      final semanticIndex = semanticIndexCallback(child, index);
      if (semanticIndex != null) {
        child = IndexedSemantics(
            index: semanticIndex + semanticIndexOffset, child: child);
      }
    }
    if (addAutomaticKeepAlives) child = AutomaticKeepAlive(child: child);
    return KeyedSubtree(key: key, child: child);
  }

  @override
  int? get estimatedChildCount => childCount;

  @override
  bool shouldRebuild(
          covariant ReorderableSliverChildBuilderDelegate oldDelegate) =>
      true;
}

class ReorderableSliverChildListDelegate
    extends ReorderableSliverChildDelegate {
  /// Creates a delegate that supplies children for slivers using the given
  /// list.
  ///
  /// The [children], [addAutomaticKeepAlives], [addRepaintBoundaries],
  /// [addSemanticIndexes], and [semanticIndexCallback] arguments must not be
  /// null.
  ///
  /// If the order of children` never changes, consider using the constant
  /// [SliverChildListDelegate.fixed] constructor.
  ReorderableSliverChildListDelegate(
    this.children, {
    required ReorderCallback onReorder,
    ReorderableIndexContextCallback? onDrag,
    ReorderableIndexContextCallback? onMerge,
    this.addAutomaticKeepAlives = true,
    this.addRepaintBoundaries = true,
    this.addSemanticIndexes = true,
    this.semanticIndexCallback = _kDefaultSemanticIndexCallback,
    this.semanticIndexOffset = 0,
  })  : _keyToIndex = <Key?, int>{null: 0},
        super(onReorder, onDrag: onDrag, onMerge: onMerge);

  /// Creates a constant version of the delegate that supplies children for
  /// slivers using the given list.
  ///
  /// If the order of the children will change, consider using the regular
  /// [ReorderableSliverChildListDelegate] constructor.
  ///
  /// The [children], [addAutomaticKeepAlives], [addRepaintBoundaries],
  /// [addSemanticIndexes], and [semanticIndexCallback] arguments must not be
  /// null.
  const ReorderableSliverChildListDelegate.fixed(
    this.children, {
    required ReorderCallback onReorder,
    ReorderableIndexContextCallback? onDrag,
    ReorderableIndexContextCallback? onMerge,
    this.addAutomaticKeepAlives = true,
    this.addRepaintBoundaries = true,
    this.addSemanticIndexes = true,
    this.semanticIndexCallback = _kDefaultSemanticIndexCallback,
    this.semanticIndexOffset = 0,
  })  : _keyToIndex = null,
        super(onReorder, onDrag: onDrag, onMerge: onMerge);

  /// Whether to wrap each child in an [AutomaticKeepAlive].
  ///
  /// Typically, children in lazy list are wrapped in [AutomaticKeepAlive]
  /// widgets so that children can use [KeepAliveNotification]s to preserve
  /// their state when they would otherwise be garbage collected off-screen.
  ///
  /// This feature (and [addRepaintBoundaries]) must be disabled if the children
  /// are going to manually maintain their [KeepAlive] state. It may also be
  /// more efficient to disable this feature if it is known ahead of time that
  /// none of the children will ever try to keep themselves alive.
  ///
  /// Defaults to true.
  final bool addAutomaticKeepAlives;

  /// Whether to wrap each child in a [RepaintBoundary].
  ///
  /// Typically, children in a scrolling container are wrapped in repaint
  /// boundaries so that they do not need to be repainted as the list scrolls.
  /// If the children are easy to repaint (e.g., solid color blocks or a short
  /// snippet of text), it might be more efficient to not add a repaint boundary
  /// and simply repaint the children during scrolling.
  ///
  /// Defaults to true.
  final bool addRepaintBoundaries;

  /// Whether to wrap each child in an [IndexedSemantics].
  ///
  /// Typically, children in a scrolling container must be annotated with a
  /// semantic index in order to generate the correct accessibility
  /// announcements. This should only be set to false if the indexes have
  /// already been provided by an [IndexedSemantics] widget.
  ///
  /// Defaults to true.
  ///
  /// See also:
  ///
  ///  * [IndexedSemantics], for an explanation of how to manually
  ///    provide semantic indexes.
  final bool addSemanticIndexes;

  /// An initial offset to add to the semantic indexes generated by this widget.
  ///
  /// Defaults to zero.
  final int semanticIndexOffset;

  /// A [SemanticIndexCallback] which is used when [addSemanticIndexes] is true.
  ///
  /// Defaults to providing an index for each widget.
  final SemanticIndexCallback semanticIndexCallback;

  /// The widgets to display.
  ///
  /// If this list is going to be mutated, it is usually wise to put a [Key] on
  /// each of the child widgets, so that the framework can match old
  /// configurations to new configurations and maintain the underlying render
  /// objects.
  ///
  /// Also, a [Widget] in Flutter is immutable, so directly modifying the
  /// [children] such as `someWidget.children.add(...)` or
  /// passing a reference of the original list value to the [children] parameter
  /// will result in incorrect behaviors. Whenever the
  /// children list is modified, a new list object should be provided.
  ///
  /// The following code corrects the problem mentioned above.
  ///
  /// ```dart
  /// class SomeWidgetState extends State<SomeWidget> {
  ///   List<Widget> _children;
  ///
  ///   void initState() {
  ///     _children = [];
  ///   }
  ///
  ///   void someHandler() {
  ///     setState(() {
  ///       // The key here allows Flutter to reuse the underlying render
  ///       // objects even if the children list is recreated.
  ///       _children.add(ChildWidget(key: UniqueKey()));
  ///     });
  ///   }
  ///
  ///   Widget build(BuildContext context) {
  ///     // Always create a new list of children as a Widget is immutable.
  ///     return PageView(children: List<Widget>.of(_children));
  ///   }
  /// }
  /// ```
  final List<Widget> children;

  /// A map to cache key to index lookup for children.
  ///
  /// _keyToIndex[null] is used as current index during the lazy loading process
  /// in [_findChildIndex]. _keyToIndex should never be used for looking up null key.
  final Map<Key?, int>? _keyToIndex;

  bool get _isConstantInstance => _keyToIndex == null;

  int? _findChildIndex(Key key) {
    if (_isConstantInstance) {
      return null;
    }
    // Lazily fill the [_keyToIndex].
    if (!_keyToIndex!.containsKey(key)) {
      var index = _keyToIndex![null]!;
      while (index < children.length) {
        final child = children[index];
        if (child.key != null) {
          _keyToIndex![child.key] = index;
        }
        if (child.key == key) {
          // Record current index for next function call.
          _keyToIndex![null] = index + 1;
          return index;
        }
        index += 1;
      }
      _keyToIndex![null] = index;
    } else {
      return _keyToIndex![key];
    }
    return null;
  }

  @override
  int? findIndexByKey(Key key) {
    final Key childKey;
    if (key is _SaltedValueKey) {
      final saltedValueKey = key;
      childKey = saltedValueKey.value;
    } else {
      childKey = key;
    }
    return _findChildIndex(childKey);
  }

  @override
  Widget? build(BuildContext context, int index) {
    if (index < 0 || index >= children.length) return null;
    var child = buildChild(context, index, children[index]);
    final Key? key = child.key != null ? _SaltedValueKey(child.key!) : null;
    if (addRepaintBoundaries) child = RepaintBoundary(child: child);
    if (addSemanticIndexes) {
      final semanticIndex = semanticIndexCallback(child, index);
      if (semanticIndex != null) {
        child = IndexedSemantics(
            index: semanticIndex + semanticIndexOffset, child: child);
      }
    }
    if (addAutomaticKeepAlives) child = AutomaticKeepAlive(child: child);
    return KeyedSubtree(key: key, child: child);
  }

  @override
  int? get estimatedChildCount => children.length;

  @override
  bool shouldRebuild(covariant ReorderableSliverChildListDelegate oldDelegate) {
    return children != oldDelegate.children;
  }
}

class ReorderableItemInheritedWidget extends InheritedNotifier {
  const ReorderableItemInheritedWidget({
    Key? key,
    required this.itemData,
    required Widget child,
  }) : super(key: key, child: child, notifier: itemData);

  final ItemData itemData;

  static ReorderableItemInheritedWidget? of(BuildContext context,
      {bool isDependent = true}) {
    if (context is Element) {
      if (context.widget is ReorderableItemInheritedWidget) {
        isDependent = false;
      }
    }
    if (isDependent) {
      return context
          .dependOnInheritedWidgetOfExactType<ReorderableItemInheritedWidget>();
    } else {
      return context
          .getElementForInheritedWidgetOfExactType<
              ReorderableItemInheritedWidget>()
          ?.widget as ReorderableItemInheritedWidget?;
    }
  }
}

class ItemData extends ChangeNotifier {
  int itemIndex = -1;
  int? renderObjectIndex = -1;
  Offset currentOffset = const Offset(-1.0, -1.0);
  bool isMergeTarget = false;

  void setRenderObjectIndex(int? index) {
    renderObjectIndex = index;
    notifyListeners();
  }

  void toggleMergeTarget() {
    isMergeTarget = !isMergeTarget;
    notifyListeners();
  }

  void resetState() {
    isMergeTarget = false;
    notifyListeners();
  }

  @override
  String toString() {
    return 'itemIndex is $itemIndex , renderObjectIndex is $renderObjectIndex , currentOffset is $currentOffset , isMergeTarget is $isMergeTarget';
  }
}

typedef ReorderCallback = Function(int toIndex, int fromIndex);
typedef ReorderIndexCallback = void Function(int index);

class ReorderableAnimatedItem extends StatefulWidget {
  final int index;
  final Widget child;
  final ReorderCallback onReorderCallback;
  final ReorderIndexCallback? onDragCallback;
  final ReorderIndexCallback? onMergeCallback;
  final VoidCallback onDragFinish;

  const ReorderableAnimatedItem({
    Key? key,
    required this.index,
    required this.child,
    required this.onReorderCallback,
    required this.onDragFinish,
    this.onDragCallback,
    this.onMergeCallback,
  }) : super(key: key);

  @override
  State<ReorderableAnimatedItem> createState() =>
      _ReorderableAnimatedItemState();
}

class _ReorderableAnimatedItemState extends State<ReorderableAnimatedItem>
    with TickerProviderStateMixin {
  bool _isShouldIgnorePoint = false;
  bool _isMergeTarget = false;

  @override
  Widget build(BuildContext context) {
    final itemParentData = context
        .findAncestorRenderObjectOfType<RenderIndexedSemantics>()
        ?.parentData as ReorderableParentData;

    final itemData = ReorderableItemInheritedWidget.of(context)?.itemData;
    final reorderableData =
        context.findAncestorRenderObjectOfType<ReorderableData>();

    var transformX = 0.0;
    var transformY = 0.0;

    if (itemParentData == null ||
        itemData == null ||
        itemData.currentOffset.dx == -1 ||
        itemData.currentOffset.dy == -1) {
    } else {
      transformX =
          (itemParentData.crossAxisOffset ?? 0) - (itemData.currentOffset.dx);

      transformY =
          (itemParentData.layoutOffset ?? 0) - (itemData.currentOffset.dy);
    }

    var transformMatrix =
        Matrix4.translationValues(-transformX, -transformY, 0.0);

    if (transformX != 0 || transformY != 0) {
      _isShouldIgnorePoint = true;
    }

    _isMergeTarget = itemData?.isMergeTarget ?? false;

    return IgnorePointer(
      ignoring: _isShouldIgnorePoint,
      child: ReorderableAnimatedContainer(
        duration: const Duration(milliseconds: 200),
        transform: transformMatrix,
        decoration: BoxDecoration(
          // TODO 可配置
          border: _isMergeTarget
              ? Border.all(color: const Color(0xFFFF0000), width: 2.0)
              : Border.all(color: const Color(0x00000000), width: 2.0),
        ),
        onEnd: () {
          setState(() {
            _isShouldIgnorePoint = false;
          });
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            buildDraggable(
                widget.index, widget.child, reorderableData, itemData),
            buildReorderDragTarget(widget.index, reorderableData, itemData),
            buildItemFolderDragTarget(widget.index, reorderableData, itemData),
          ],
        ),
      ),
    );
  }

  Widget buildDraggable(int index, Widget child,
      ReorderableData? reorderableData, ItemData? itemData) {
    return LayoutBuilder(builder: (context, constraints) {
      final itemWidget = SizedBox(
        width: constraints.maxWidth,
        height: constraints.maxHeight,
        child: child,
      );
      return ReorderableLongPressDraggable(
        data: itemData,
        feedback: IgnorePointer(
          ignoring: true,
          child: itemWidget,
        ),
        onDragStarted: () {
          reorderableData?.dragIndex = index;
          widget.onDragCallback?.call(index);
        },
        onDraggableCanceled: (velocity, offset) {},
        onDragCompleted: () {},
        onDragEnd: (detail) => widget.onDragFinish.call(),
        childWhenDragging: Opacity(
          opacity: 0.5,
          child: itemWidget,
        ),
        child: MetaData(behavior: HitTestBehavior.opaque, child: itemWidget),
      );
    });
  }

  Widget buildReorderDragTarget(int currentItemIndex,
      ReorderableData? reorderableData, ItemData? itemData) {
    return ReorderableDragTarget<ItemData>(
      delayAcceptDuration: const Duration(milliseconds: 200),
      key: ValueKey(itemData?.renderObjectIndex),
      builder: (context, acceptedCandidates, rejectedCandidates) {
        return Container();
      },
      onDelayWillAccept: (toAcceptItemData) {
        if (toAcceptItemData != null) {
          if (toAcceptItemData.renderObjectIndex !=
              itemData?.renderObjectIndex) {
            reorderableData?.insertIndex = itemData?.renderObjectIndex ?? 0;

            widget.onReorderCallback.call(itemData?.renderObjectIndex ?? 0,
                toAcceptItemData.renderObjectIndex ?? 0);
          }
        }
        return toAcceptItemData != null;
      },
    );
  }

  Widget buildItemFolderDragTarget(int currentItemIndex,
      ReorderableData? reorderableData, ItemData? itemData) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: ReorderableDragTarget<ItemData>(
        delayAcceptDuration: const Duration(seconds: 1),
        builder: (context, acceptedCandidates, rejectedCandidates) {
          return Container();
        },
        onDelayWillAccept: (toAcceptItemData) {
          if (toAcceptItemData != null) {
            if (toAcceptItemData.renderObjectIndex !=
                itemData?.renderObjectIndex) {
              if (itemData?.itemIndex != null) {
                widget.onMergeCallback?.call(itemData!.itemIndex);
              }
            }
          }
          return toAcceptItemData != null;
        },
        onLeave: (leaveTargetData) {
          print('onLeave target is $leaveTargetData , current is $itemData');
          if (itemData?.isMergeTarget ?? false) {
            itemData?.toggleMergeTarget();
          }
        },
      ),
    );
  }
}
