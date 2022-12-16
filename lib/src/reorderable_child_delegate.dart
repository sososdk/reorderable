part of 'reorderable_sliver.dart';

// ignore_for_file: lines_longer_than_80_chars

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
