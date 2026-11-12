import 'dart:async';

import 'package:flutter/material.dart';

import '../core/media_library.dart';
import '../widgets/thumb.dart';

class SlideshowPage extends StatefulWidget {
  const SlideshowPage({super.key});
  @override
  State<SlideshowPage> createState() => _SlideshowPageState();
}

class _SlideshowPageState extends State<SlideshowPage> {
  final items = MediaLibrary.instance.all.take(60).toList();
  final pc = PageController();
  Timer? t;
  bool playing = true;

  @override
  void initState() {
    super.initState();
    t = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!playing || !pc.hasClients || items.isEmpty) return;
      pc.animateToPage(((pc.page ?? 0).round() + 1) % items.length, duration: const Duration(milliseconds: 600), curve: Curves.easeInOut);
    });
  }

  @override
  void dispose() {
    t?.cancel();
    pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: const Text('Slideshow'), actions: [
          IconButton(icon: Icon(playing ? Icons.pause : Icons.play_arrow), onPressed: () => setState(() => playing = !playing)),
        ]),
        body: PageView.builder(
          controller: pc,
          itemCount: items.length,
          itemBuilder: (_, i) => PhotoThumb(items[i], size: 1600, fit: BoxFit.contain),
        ),
      );
}
