import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'sliver_list.dart';

/// See:
/// - https://pub.dev/packages/super_sliver_list
/// - https://github.com/flutter/flutter/issues/52207
class SuperSliverList extends SliverMultiBoxAdaptorWidget {
  const SuperSliverList({
    super.key,
    required super.delegate,
  });

  @override
  SliverMultiBoxAdaptorElement createElement() =>
      SliverMultiBoxAdaptorElement(this, replaceMovedChildren: true);

  @override
  RenderSliverMultiBoxAdaptor createRenderObject(BuildContext context) {
    final element = context as SliverMultiBoxAdaptorElement;
    return RenderSuperSliverList(childManager: element);
  }
}
