part of 'reorderable.dart';

class _ListDragInfo extends _DragInfo {
  _ListDragInfo({
    required super.item,
    super.initialPosition = Offset.zero,
    super.scrollDirection = Axis.vertical,
    super.onUpdate,
    super.onEnd,
    super.onCancel,
    super.onDropCompleted,
    super.proxyDecorator,
    required super.tickerProvider,
  });

  @override
  void update(DragUpdateDetails details) {
    final delta = _restrictAxis(details.delta, scrollDirection);
    dragPosition += delta;
    onUpdate?.call(this, dragPosition, details.delta);
  }
}

class _ReorderableListItem extends _ReorderableItem {
  const _ReorderableListItem({
    required super.key,
    required super.index,
    required super.child,
    required super.capturedThemes,
  });

  @override
  _ReorderableItemState<_ReorderableItem> createState() => _ReorderableListItemState();
}

class _ReorderableListItemState extends _ReorderableItemState<_ReorderableListItem> {
  @override
  Offset _calculateNewTargetOffset(int gapIndex, double gapExtent, bool reverse) {
    if (gapIndex <= index) {
      return _extentOffset(reverse ? -gapExtent : gapExtent, _reorderableState._scrollDirection);
    } else {
      return Offset.zero;
    }
  }
}

class SliverReorderableList extends SliverReorderable {
  const SliverReorderableList({
    super.key,
    required super.itemBuilder,
    super.findChildIndexCallback,
    required super.itemCount,
    required super.onReorder,
    super.onReorderStart,
    super.onReorderEnd,
    this.itemExtent,
    this.prototypeItem,
    super.proxyDecorator,
  }) : assert(
          itemExtent == null || prototypeItem == null,
          'You can only pass itemExtent or prototypeItem, not both',
        );

  /// {@macro flutter.widgets.list_view.itemExtent}
  final double? itemExtent;

  /// {@macro flutter.widgets.list_view.prototypeItem}
  final Widget? prototypeItem;

  @override
  SliverReorderableState<SliverReorderable> createState() => _SliverReorderableListState();
}

class _SliverReorderableListState extends SliverReorderableState<SliverReorderableList> {
  @override
  Widget build(BuildContext context) {
    assert(debugCheckHasOverlay(context));
    final childrenDelegate = SliverChildBuilderDelegate(
      _itemBuilder,
      // When dragging, the dragged item is still in the list but has been replaced
      // by a zero height SizedBox, so that the gap can move around. To make the
      // list extent stable we add a dummy entry to the end.
      childCount: widget.itemCount + (_dragInfo != null ? 1 : 0),
      findChildIndexCallback: widget.findChildIndexCallback,
    );
    if (widget.itemExtent != null) {
      return SliverFixedExtentList(
        delegate: childrenDelegate,
        itemExtent: widget.itemExtent!,
      );
    } else if (widget.prototypeItem != null) {
      return SliverPrototypeExtentList(
        delegate: childrenDelegate,
        prototypeItem: widget.prototypeItem!,
      );
    }
    return SliverList(delegate: childrenDelegate);
  }

  @override
  _ReorderableItem _createReorderableItem(Key key, int index, BuildContext overlayContext, Widget child) {
    return _ReorderableListItem(
      key: _ReorderableItemGlobalKey(key, index, this),
      index: index,
      capturedThemes: InheritedTheme.capture(from: context, to: overlayContext),
      child: child,
    );
  }

  @override
  _DragInfo _createDragInfo(_ReorderableItemState item, Offset position) {
    return _ListDragInfo(
      item: item,
      initialPosition: position,
      scrollDirection: _scrollDirection,
      onUpdate: _dragUpdate,
      onCancel: _dragCancel,
      onEnd: _dragEnd,
      onDropCompleted: _dropCompleted,
      proxyDecorator: widget.proxyDecorator,
      tickerProvider: this,
    );
  }

  @override
  void _dragUpdateItems() {
    assert(_dragInfo != null);
    final gapExtent = _dragInfo!.itemExtent;
    final proxyItemStart = _offsetExtent(_dragInfo!.dragPosition - _dragInfo!.dragOffset, _scrollDirection);
    // ignore: unused_local_variable
    final proxyItemEnd = proxyItemStart + gapExtent;

    // Find the new index for inserting the item being dragged.
    var newIndex = _insertIndex!;
    for (final item in _items.values) {
      if (item.index == _dragIndex! || !item.mounted) {
        continue;
      }

      var geometry = item.targetGeometry();
      if (!_dragStartTransitionComplete && _dragIndex! <= item.index) {
        // Transition is not complete, so each item after the dragged item is still
        // in its normal location and not moved up for the zero sized box that will
        // replace the dragged item.
        final transitionOffset = _extentOffset(_reverse ? -gapExtent : gapExtent, _scrollDirection);
        geometry = (geometry.topLeft - transitionOffset) & geometry.size;
      }
      final position = _scrollDirection == Axis.vertical ? _dragInfo!.dragPosition.dy : _dragInfo!.dragPosition.dx;
      final itemStart = _scrollDirection == Axis.vertical ? geometry.top : geometry.left;
      final itemExtent = _scrollDirection == Axis.vertical ? geometry.height : geometry.width;
      final itemEnd = itemStart + itemExtent;
      final itemMiddle = itemStart + itemExtent / 2;

      if (_reverse) {
        if (newIndex < (item.index + 1) && itemStart <= position && position <= itemMiddle) {
          // Drag up
          newIndex = item.index + 1;
          break;
        } else if (newIndex > item.index && itemMiddle <= position && position <= itemEnd) {
          // Drag down
          newIndex = item.index;
          break;
        } else if (itemStart > position && newIndex < (item.index + 1)) {
          // Drag up quickly
          newIndex = item.index + 1;
        } else if (position > itemEnd && newIndex > item.index) {
          // Drag down quickly
          newIndex = item.index;
        }
      } else {
        if (newIndex > item.index && itemStart <= position && position <= itemMiddle) {
          // Drag up
          newIndex = item.index;
          break;
        } else if (newIndex < (item.index + 1) && itemMiddle <= position && position <= itemEnd) {
          // Drag down
          newIndex = item.index + 1;
          break;
        } else if (position < itemStart && newIndex > item.index) {
          // Drag up quickly
          newIndex = item.index;
        } else if (itemEnd < position && newIndex < (item.index + 1)) {
          // Drag down quickly
          newIndex = item.index + 1;
        }
      }
    }

    if (newIndex != _insertIndex) {
      _insertIndex = newIndex;
      for (final item in _items.values) {
        if (item.index == _dragIndex! || !item.mounted) {
          continue;
        }
        item.updateForGap(newIndex, gapExtent, true, _reverse);
      }
    }
  }

  void _dragEnd(_DragInfo item) {
    setState(() {
      if (_reverse) {
        if (_insertIndex! > 0) {
          _finalDropPosition = _itemOffsetAt(_insertIndex! - 1) - _extentOffset(item.itemExtent, _scrollDirection);
        } else {
          final itemExtent = _sizeExtent(_items[0]!.context.size!, _scrollDirection);
          _finalDropPosition = _itemOffsetAt(_insertIndex!) +
              _extentOffset(itemExtent, _scrollDirection) -
              _extentOffset(item.itemExtent, _scrollDirection);
        }
      } else {
        if (_insertIndex! < widget.itemCount - 1) {
          // Find the location of the item we want to insert before
          _finalDropPosition = _itemOffsetAt(_insertIndex!);
        } else {
          // Inserting into the last spot on the list. If it's the only spot, put
          // it back where it was. Otherwise, grab the second to last and move
          // down by the gap.
          final itemIndex = _items.length > 1 ? _insertIndex! - 1 : _insertIndex!;
          final itemExtent = _sizeExtent(_items[itemIndex]!.context.size!, _scrollDirection);
          _finalDropPosition = _itemOffsetAt(itemIndex) + _extentOffset(itemExtent, _scrollDirection);
        }
      }
    });
    widget.onReorderEnd?.call(_insertIndex!);
  }

  void _dropCompleted() {
    final fromIndex = _dragIndex!;
    var toIndex = _insertIndex!;
    if (fromIndex != toIndex) {
      if (fromIndex < toIndex) {
        // removing the item at oldIndex will shorten the list by 1.
        toIndex -= 1;
      }
      widget.onReorder.call(fromIndex, toIndex);
    }
    setState(() {
      _dragReset();
    });
  }
}

/// A scrolling container that allows the user to interactively reorder the
/// list items.
///
/// This widget is similar to one created by [ListView.builder], and uses
/// an [IndexedWidgetBuilder] to create each item.
///
/// It is up to the application to wrap each child (or an internal part of the
/// child such as a drag handle) with a drag listener that will recognize
/// the start of an item drag and then start the reorder by calling
/// [ReorderableListState.startItemDragReorder]. This is most easily achieved
/// by wrapping each child in a [ReorderableDragStartListener] or a
/// [ReorderableDelayedDragStartListener]. These will take care of recognizing
/// the start of a drag gesture and call the list state's
/// [ReorderableListState.startItemDragReorder] method.
///
/// This widget's [ReorderableListState] can be used to manually start an item
/// reorder, or cancel a current drag. To refer to the
/// [ReorderableListState] either provide a [GlobalKey] or use the static
/// [ReorderableList.of] method from an item's build method.
///
/// See also:
///
///  * [SliverReorderableList], a sliver list that allows the user to reorder
///    its items.
///  * [ReorderableListView], a Material Design list that allows the user to
///    reorder its items.
class ReorderableList extends StatefulWidget {
  /// Creates a scrolling container that allows the user to interactively
  /// reorder the list items.
  ///
  /// The [itemCount] must be greater than or equal to zero.
  const ReorderableList({
    super.key,
    required this.itemBuilder,
    required this.itemCount,
    required this.onReorder,
    this.onReorderStart,
    this.onReorderEnd,
    this.itemExtent,
    this.prototypeItem,
    this.proxyDecorator,
    this.padding,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.controller,
    this.primary,
    this.physics,
    this.shrinkWrap = false,
    this.anchor = 0.0,
    this.cacheExtent,
    this.dragStartBehavior = DragStartBehavior.start,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
    this.restorationId,
    this.clipBehavior = Clip.hardEdge,
  })  : assert(itemCount >= 0),
        assert(
          itemExtent == null || prototypeItem == null,
          'You can only pass itemExtent or prototypeItem, not both',
        );

  /// {@macro reorderable.itemBuilder}
  final IndexedWidgetBuilder itemBuilder;

  /// {@macro reorderable.itemCount}
  final int itemCount;

  /// {@macro reorderable.onReorder}
  final ReorderCallback onReorder;

  /// {@macro reorderable.onReorderStart}
  final void Function(int index)? onReorderStart;

  /// {@macro reorderable.onReorderEnd}
  final void Function(int index)? onReorderEnd;

  /// {@macro reorderable.proxyDecorator}
  final ReorderItemProxyDecorator? proxyDecorator;

  /// The amount of space by which to inset the list contents.
  ///
  /// It defaults to `EdgeInsets.all(0)`.
  final EdgeInsetsGeometry? padding;

  /// {@macro flutter.widgets.scroll_view.scrollDirection}
  final Axis scrollDirection;

  /// {@macro flutter.widgets.scroll_view.reverse}
  final bool reverse;

  /// {@macro flutter.widgets.scroll_view.controller}
  final ScrollController? controller;

  /// {@macro flutter.widgets.scroll_view.primary}
  final bool? primary;

  /// {@macro flutter.widgets.scroll_view.physics}
  final ScrollPhysics? physics;

  /// {@macro flutter.widgets.scroll_view.shrinkWrap}
  final bool shrinkWrap;

  /// {@macro flutter.widgets.scroll_view.anchor}
  final double anchor;

  /// {@macro flutter.rendering.RenderViewportBase.cacheExtent}
  final double? cacheExtent;

  /// {@macro flutter.widgets.scrollable.dragStartBehavior}
  final DragStartBehavior dragStartBehavior;

  /// {@macro flutter.widgets.scroll_view.keyboardDismissBehavior}
  ///
  /// The default is [ScrollViewKeyboardDismissBehavior.manual]
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;

  /// {@macro flutter.widgets.scrollable.restorationId}
  final String? restorationId;

  /// {@macro flutter.material.Material.clipBehavior}
  ///
  /// Defaults to [Clip.hardEdge].
  final Clip clipBehavior;

  /// {@macro flutter.widgets.list_view.itemExtent}
  final double? itemExtent;

  /// {@macro flutter.widgets.list_view.prototypeItem}
  final Widget? prototypeItem;

  /// The state from the closest instance of this class that encloses the given
  /// context.
  ///
  /// This method is typically used by [ReorderableList] item widgets that
  /// insert or remove items in response to user input.
  ///
  /// If no [ReorderableList] surrounds the given context, then this function
  /// will assert in debug mode and throw an exception in release mode.
  ///
  /// This method can be expensive (it walks the element tree).
  ///
  /// See also:
  ///
  ///  * [maybeOf], a similar function that will return null if no
  ///    [ReorderableList] ancestor is found.
  static ReorderableListState of(BuildContext context) {
    final result = context.findAncestorStateOfType<ReorderableListState>();
    assert(() {
      if (result == null) {
        throw FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary('ReorderableList.of() called with a context that does not contain a ReorderableList.'),
          ErrorDescription(
            'No ReorderableList ancestor could be found starting from the context that was passed to ReorderableList.of().',
          ),
          ErrorHint('This can happen when the context provided is from the same StatefulWidget that '
              'built the ReorderableList.'),
          context.describeElement('The context used was'),
        ]);
      }
      return true;
    }());
    return result!;
  }

  /// The state from the closest instance of this class that encloses the given
  /// context.
  ///
  /// This method is typically used by [ReorderableList] item widgets that insert
  /// or remove items in response to user input.
  ///
  /// If no [ReorderableList] surrounds the context given, then this function will
  /// return null.
  ///
  /// This method can be expensive (it walks the element tree).
  ///
  /// See also:
  ///
  ///  * [of], a similar function that will throw if no [ReorderableList] ancestor
  ///    is found.
  static ReorderableListState? maybeOf(BuildContext context) {
    return context.findAncestorStateOfType<ReorderableListState>();
  }

  @override
  ReorderableListState createState() => ReorderableListState();
}

/// The state for a list that allows the user to interactively reorder
/// the list items.
///
/// An app that needs to start a new item drag or cancel an existing one
/// can refer to the [ReorderableList]'s state with a global key:
///
/// ```dart
/// GlobalKey<ReorderableListState> listKey = GlobalKey<ReorderableListState>();
/// ...
/// ReorderableList(key: listKey, ...);
/// ...
/// listKey.currentState.cancelReorder();
/// ```
class ReorderableListState extends State<ReorderableList> {
  final GlobalKey<SliverReorderableState> _sliverReorderableListKey = GlobalKey();

  /// Initiate the dragging of the item at [index] that was started with
  /// the pointer down [event].
  ///
  /// The given [recognizer] will be used to recognize and start the drag
  /// item tracking and lead to either an item reorder, or a cancelled drag.
  /// The list will take ownership of the returned recognizer and will dispose
  /// it when it is no longer needed.
  ///
  /// Most applications will not use this directly, but will wrap the item
  /// (or part of the item, like a drag handle) in either a
  /// [ReorderableDragStartListener] or [ReorderableDelayedDragStartListener]
  /// which call this for the application.
  void startItemDragReorder({
    required int index,
    required PointerDownEvent event,
    required MultiDragGestureRecognizer recognizer,
  }) {
    final list = _sliverReorderableListKey.currentState!;
    list.startItemDragReorder(index: index, event: event, recognizer: recognizer..onStart = list._dragStart);
  }

  /// Cancel any item drag in progress.
  ///
  /// This should be called before any major changes to the item list
  /// occur so that any item drags will not get confused by
  /// changes to the underlying list.
  ///
  /// If no drag is active, this will do nothing.
  void cancelReorder() {
    _sliverReorderableListKey.currentState!.cancelReorder();
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      scrollDirection: widget.scrollDirection,
      reverse: widget.reverse,
      controller: widget.controller,
      primary: widget.primary,
      physics: widget.physics,
      shrinkWrap: widget.shrinkWrap,
      anchor: widget.anchor,
      cacheExtent: widget.cacheExtent,
      dragStartBehavior: widget.dragStartBehavior,
      keyboardDismissBehavior: widget.keyboardDismissBehavior,
      restorationId: widget.restorationId,
      clipBehavior: widget.clipBehavior,
      slivers: <Widget>[
        SliverPadding(
          padding: widget.padding ?? EdgeInsets.zero,
          sliver: SliverReorderableList(
            key: _sliverReorderableListKey,
            itemExtent: widget.itemExtent,
            prototypeItem: widget.prototypeItem,
            itemBuilder: widget.itemBuilder,
            itemCount: widget.itemCount,
            onReorder: widget.onReorder,
            onReorderStart: widget.onReorderStart,
            onReorderEnd: widget.onReorderEnd,
            proxyDecorator: widget.proxyDecorator,
          ),
        ),
      ],
    );
  }
}
