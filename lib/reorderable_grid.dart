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
      // When dragging, the dragged item is still in the list but has been replaced
      // by a zero height SizedBox, so that the gap can move around. To make the
      // list extent stable we add a dummy entry to the end.
      childCount: widget.itemCount + (_dragInfo != null ? 1 : 0),
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
      if (item.index == _dragIndex! || !item.mounted) {
        continue;
      }

      for (var item in _items.values) {
        final renderBox = item.context.findRenderObject() as RenderBox;
        final size = renderBox.size;
        final position = renderBox.globalToLocal(_dragInfo!.dragPosition);
        if (position.dx > 0 && position.dy > 0 && position.dx < size.width && position.dy < size.height) {
          newIndex = item.index;
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
