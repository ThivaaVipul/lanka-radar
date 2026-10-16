import 'package:flutter/material.dart';

class LankaRadarApp extends StatelessWidget {
  const LankaRadarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lanka Radar',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF0F766E)),
      home: const _EmptyHome(),
    );
  }
}

class _EmptyHome extends StatelessWidget {
  const _EmptyHome();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lanka Radar')),
      body: const Center(child: Text('Nothing yet')),
    );
  }
}
