import 'package:flutter/material.dart';
import 'package:reorderable_plus/reorderable.dart' as reorder;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: const Column(
        children: [
          Expanded(
            flex: 5,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Expanded(child: _ReorderListView()),
                      Text('List', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(child: _ReorderGridView()),
                      Text('Grid', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: SizedBox.shrink()),
        ],
      ),
    );
  }
}

class _ReorderListView extends StatefulWidget {
  const _ReorderListView({Key? key}) : super(key: key);

  @override
  State<_ReorderListView> createState() => _ReorderListViewState();
}

class _ReorderListViewState extends State<_ReorderListView> {
  final data = List.generate(11, (index) => index);

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      // reverse: true,
      slivers: [
        reorder.SliverReorderableList(
          itemBuilder: (context, int index) {
            final item = data[index];
            final height = 48.0 + item * 10.0;
            return reorder.ReorderableDelayedDragStartListener(
              key: ValueKey(item),
              index: index,
              // enabled: item % 2 == 0,
              child: Container(
                height: height,
                alignment: Alignment.center,
                color: (item % 2 == 0 ? Colors.green : Colors.amber).withOpacity(0.6),
                child: Text('$item: $height'),
              ),
            );
          },
          itemCount: data.length,
          onReorder: (oldIndex, newIndex) {
            debugPrint('onReorder: $oldIndex -> $newIndex');
            final item = data.removeAt(oldIndex);
            data.insert(newIndex, item);
          },
          onReorderStart: (p0) {
            debugPrint('onReorderStart');
          },
          onReorderEnd: (p0) {
            debugPrint('onReorderEnd');
          },
          proxyDecorator: (child, index, animation) {
            return Container(
              color: Colors.red.withOpacity(0.3),
              height: 160,
              child: child,
            );
          },
        ),
      ],
    );
  }
}

class _ReorderGridView extends StatefulWidget {
  const _ReorderGridView({Key? key}) : super(key: key);

  @override
  State<_ReorderGridView> createState() => _ReorderGridViewState();
}

class _ReorderGridViewState extends State<_ReorderGridView> {
  final data = List.generate(30, (index) => index);

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      // reverse: true,
      slivers: [
        reorder.SliverReorderableGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 0.618),
          itemBuilder: (context, int index) {
            final item = data[index];
            return reorder.ReorderableDelayedDragStartListener(
              key: ValueKey(item),
              index: index,
              // enabled: item % 2 == 0,
              child: Container(
                alignment: Alignment.center,
                color: (item % 2 == 0 ? Colors.green : Colors.amber).withOpacity(0.6),
                child: Text('$item'),
              ),
            );
          },
          itemCount: data.length,
          onReorder: (oldIndex, newIndex) {
            debugPrint('onReorder: $oldIndex -> $newIndex');
            final item = data.removeAt(oldIndex);
            data.insert(newIndex, item);
          },
          onReorderStart: (p0) {
            debugPrint('onReorderStart');
          },
          onReorderEnd: (p0) {
            debugPrint('onReorderEnd');
          },
          proxyDecorator: (child, index, animation) {
            return Container(
              color: Colors.red.withOpacity(0.3),
              height: 160,
              child: child,
            );
          },
        ),
      ],
    );
  }
}
