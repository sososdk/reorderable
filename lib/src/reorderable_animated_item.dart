part of 'reorderable_sliver.dart';

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
