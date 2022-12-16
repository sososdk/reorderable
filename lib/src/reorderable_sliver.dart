import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'reorderable_animated_container.dart';

part 'reorderable_animated_item.dart';
part 'reorderable_child_delegate.dart';
part 'reorderable_drag_target.dart';

// ignore_for_file: lines_longer_than_80_chars

typedef ReorderCallback = Function(int toIndex, int fromIndex);
typedef ReorderIndexCallback = void Function(int index);

mixin ReorderableData on RenderSliverMultiBoxAdaptor {
  int? dragIndex;
  int? insertIndex;

  void reorder(ReorderCallback callback) {
    if (dragIndex != null && insertIndex != null) {
      callback(insertIndex!, dragIndex!);
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
