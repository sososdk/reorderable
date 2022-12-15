// import 'package:flutter/rendering.dart';
// import 'package:flutter/widgets.dart';
//
// import 'reorderable_sliver.dart';
// import 'sliver_list.dart';
//
// class ReorderableSliverListMultiBoxAdaptorElement
//     extends ReorderableSliverMultiBoxAdaptorElement {
//   ReorderableSliverListMultiBoxAdaptorElement(super.widget,
//       {super.replaceMovedChildren = false});
//
//   @override
//   convertChildParentData(SliverMultiBoxAdaptorParentData parentData) {
//     // TODO: implement convertChildParentData
//     throw UnimplementedError();
//   }
//
//   @override
//   void updateChildParentData(Element element, data) {
//     // TODO: implement updateChildParentData
//   }
// }
//
// class ReorderableSliverList extends ReorderableSliverMultiBoxAdaptorWidget {
//   const ReorderableSliverList({
//     super.key,
//     required super.delegate,
//   });
//
//   @override
//   ReorderableSliverMultiBoxAdaptorElement createElement() =>
//       ReorderableSliverListMultiBoxAdaptorElement(this,
//           replaceMovedChildren: true);
//
//   @override
//   RenderSliverMultiBoxAdaptor createRenderObject(BuildContext context) {
//     final element = context as ReorderableSliverMultiBoxAdaptorElement;
//     return RenderSuperSliverList(childManager: element);
//   }
// }
