part of 'reorderable.dart';

class _GridDragInfo extends _DragInfo {
  _GridDragInfo({
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
    dragPosition += details.delta;
    onUpdate?.call(this, dragPosition, details.delta);
  }
}

class _ReorderableGridItem extends _ReorderableItem {
  const _ReorderableGridItem({
    required super.key,
    required super.index,
    required super.child,
    required super.capturedThemes,
  });

  @override
  _ReorderableItemState<_ReorderableItem> createState() => _ReorderableGridItemState();
}

class _ReorderableGridItemState extends _ReorderableItemState<_ReorderableGridItem> {
  @override
  Offset _calculateNewTargetOffset(int gapIndex, double gapExtent, bool reverse) {
    final int minPos = min(_reorderableState._dragIndex!, _reorderableState._insertIndex!);
    final int maxPos = max(_reorderableState._dragIndex!, _reorderableState._insertIndex!);

    if (index < minPos || index > maxPos) return Offset.zero;

    final direction = _reorderableState._insertIndex! > _reorderableState._dragIndex! ? -1 : 1;
    return _itemOffsetAt(index + direction) - _itemOffsetAt(index);
  }

  Offset _itemOffsetAt(int index) {
    final renderBox = _reorderableState._items[index]?.context.findRenderObject() as RenderBox?;
    if (renderBox == null) return Offset.zero;
    final parentRenderObject = context.findRenderObject() as RenderBox;
    return parentRenderObject.globalToLocal(renderBox.localToGlobal(Offset.zero));
  }
}

class SliverReorderableGrid extends SliverReorderable {
  const SliverReorderableGrid({
    super.key,
    required super.itemBuilder,
    super.findChildIndexCallback,
    required super.itemCount,
    required super.onReorder,
    required this.gridDelegate,
    super.onReorderStart,
    super.onReorderEnd,
    super.proxyDecorator,
  });

  final SliverGridDelegate gridDelegate;

  @override
  SliverReorderableState<SliverReorderable> createState() => _SliverReorderableGridState();
}

class _SliverReorderableGridState extends SliverReorderableState<SliverReorderableGrid> {
  @override
  Widget build(BuildContext context) {
    assert(debugCheckHasOverlay(context));
    final childrenDelegate = SliverChildBuilderDelegate(
      _itemBuilder,
      childCount: widget.itemCount,
      findChildIndexCallback: widget.findChildIndexCallback,
    );
    return SliverGrid(
      delegate: childrenDelegate,
      gridDelegate: widget.gridDelegate,
    );
  }

  @override
  _ReorderableItem _createReorderableItem(Key key, int index, BuildContext overlayContext, Widget child) {
    return _ReorderableGridItem(
      key: _ReorderableItemGlobalKey(key, index, this),
      index: index,
      capturedThemes: InheritedTheme.capture(from: context, to: overlayContext),
      child: child,
    );
  }

  @override
  _DragInfo _createDragInfo(_ReorderableItemState item, Offset position) {
    return _GridDragInfo(
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

    var newIndex = _insertIndex!;
    for (final item in _items.values) {
      final renderBox = item.context.findRenderObject() as RenderBox;
      final rect = renderBox.localToGlobal(Offset.zero) & renderBox.size;
      if (rect.contains(_dragInfo!.dragPosition)) {
        newIndex = item.index;
        break;
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
      _finalDropPosition = _itemOffsetAt(_insertIndex!);
    });
    widget.onReorderEnd?.call(_insertIndex!);
  }

  void _dropCompleted() {
    final fromIndex = _dragIndex!;
    final toIndex = _insertIndex!;
    if (fromIndex != toIndex) {
      widget.onReorder.call(fromIndex, toIndex);
    }
    setState(() {
      _dragReset();
    });
  }
}

class ReorderableGrid extends StatefulWidget {
  /// Creates a scrolling container that allows the user to interactively
  /// reorder the grid items.
  ///
  /// The [itemCount] must be greater than or equal to zero.
  const ReorderableGrid({
    super.key,
    required this.gridDelegate,
    required this.itemBuilder,
    required this.itemCount,
    required this.onReorder,
    this.onReorderStart,
    this.onReorderEnd,
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
  }) : assert(itemCount >= 0);

  /// The delegate that controls the size and position of the children.
  final SliverGridDelegate gridDelegate;

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

  /// The amount of space by which to inset the grid contents.
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

  /// The state from the closest instance of this class that encloses the given
  /// context.
  ///
  /// This method is typically used by [ReorderableGrid] item widgets that
  /// insert or remove items in response to user input.
  ///
  /// If no [ReorderableGrid] surrounds the given context, then this function
  /// will assert in debug mode and throw an exception in release mode.
  ///
  /// This method can be expensive (it walks the element tree).
  ///
  /// See also:
  ///
  ///  * [maybeOf], a similar function that will return null if no
  ///    [ReorderableGrid] ancestor is found.
  static ReorderableGridState of(BuildContext context) {
    final result = context.findAncestorStateOfType<ReorderableGridState>();
    assert(() {
      if (result == null) {
        throw FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary('ReorderableGrid.of() called with a context that does not contain a ReorderableGrid.'),
          ErrorDescription(
            'No ReorderableGrid ancestor could be found starting from the context that was passed to ReorderableGrid.of().',
          ),
          ErrorHint('This can happen when the context provided is from the same StatefulWidget that '
              'built the ReorderableGrid.'),
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
  /// This method is typically used by [ReorderableGrid] item widgets that insert
  /// or remove items in response to user input.
  ///
  /// If no [ReorderableGrid] surrounds the context given, then this function will
  /// return null.
  ///
  /// This method can be expensive (it walks the element tree).
  ///
  /// See also:
  ///
  ///  * [of], a similar function that will throw if no [ReorderableGrid] ancestor
  ///    is found.
  static ReorderableGridState? maybeOf(BuildContext context) {
    return context.findAncestorStateOfType<ReorderableGridState>();
  }

  @override
  ReorderableGridState createState() => ReorderableGridState();
}

/// The state for a grid that allows the user to interactively reorder
/// the grid items.
///
/// An app that needs to start a new item drag or cancel an existing one
/// can refer to the [ReorderableGrid]'s state with a global key:
///
/// ```dart
/// GlobalKey<ReorderableGridState> gridKey = GlobalKey<ReorderableGridState>();
/// ...
/// ReorderableGrid(key: gridKey, ...);
/// ...
/// gridKey.currentState.cancelReorder();
/// ```
class ReorderableGridState extends State<ReorderableGrid> {
  final GlobalKey<SliverReorderableState> _globalKey = GlobalKey();

  /// Initiate the dragging of the item at [index] that was started with
  /// the pointer down [event].
  ///
  /// The given [recognizer] will be used to recognize and start the drag
  /// item tracking and lead to either an item reorder, or a cancelled drag.
  /// The grid will take ownership of the returned recognizer and will dispose
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
    final state = _globalKey.currentState!;
    state.startItemDragReorder(index: index, event: event, recognizer: recognizer..onStart = state._dragStart);
  }

  /// Cancel any item drag in progress.
  ///
  /// This should be called before any major changes to the item list
  /// occur so that any item drags will not get confused by
  /// changes to the underlying list.
  ///
  /// If no drag is active, this will do nothing.
  void cancelReorder() {
    _globalKey.currentState!.cancelReorder();
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
          sliver: SliverReorderableGrid(
            key: _globalKey,
            gridDelegate: widget.gridDelegate,
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
