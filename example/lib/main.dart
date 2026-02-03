import 'package:flutter/material.dart';
import 'zenoh_pub_sub_page.dart';
import 'multiple_subscriber_page.dart';
import 'stream_page.dart';
import 'todo_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zenoh Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Zenoh Dart Examples')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildNavButton(context, 'Basic Pub/Sub', const ZenohPubSubPage()),
          const SizedBox(height: 8),
          _buildNavButton(
              context, 'Multiple Subscribers', const MultipleSubscribersPage()),
          const SizedBox(height: 8),
          _buildNavButton(context, 'Stream API', const ZenohStreamPage()),
          const SizedBox(height: 8),
          _buildNavButton(context, 'Distributed Todo List', const TodoPage()),
        ],
      ),
    );
  }

  Widget _buildNavButton(BuildContext context, String title, Widget page) {
    return ElevatedButton(
      onPressed: () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
      },
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(title, style: const TextStyle(fontSize: 18)),
      ),
    );
  }
}
