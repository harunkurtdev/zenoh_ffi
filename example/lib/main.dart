import 'package:flutter/material.dart';
import 'zenoh_pub_sub_page.dart';
import 'multiple_subscriber_page.dart';
import 'stream_page.dart';
import 'todo_page.dart';
import 'liveliness_page.dart';
import 'scout_page.dart';
import 'sensor_dashboard_page.dart';
import 'service_page.dart';
import 'kv_store_page.dart';

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
          // --- Basic Examples ---
          _buildSectionHeader('Basic Examples'),
          const SizedBox(height: 8),
          _buildNavButton(
            context,
            'Basic Pub/Sub',
            'Publish and subscribe to messages',
            Icons.swap_horiz,
            Colors.blue,
            const ZenohHomePage(),
          ),
          const SizedBox(height: 8),
          _buildNavButton(
            context,
            'Multiple Subscribers',
            'Multiple subscribers on different key expressions',
            Icons.people,
            Colors.teal,
            const MultipleSubscribersPage(),
          ),
          const SizedBox(height: 8),
          _buildNavButton(
            context,
            'Stream API',
            'StreamBuilder integration with Zenoh',
            Icons.stream,
            Colors.purple,
            const ZenohStreamPage(),
          ),
          const SizedBox(height: 8),
          _buildNavButton(
            context,
            'Distributed Todo List',
            'Peer mode with queryable for shared state',
            Icons.checklist,
            Colors.green,
            const TodoPage(),
          ),

          const SizedBox(height: 24),

          // --- Advanced Examples ---
          _buildSectionHeader('Advanced Examples'),
          const SizedBox(height: 8),
          _buildNavButton(
            context,
            'Liveliness Monitor',
            'IoT fleet management - track device presence',
            Icons.monitor_heart,
            Colors.red,
            const LivelinessPage(),
          ),
          const SizedBox(height: 8),
          _buildNavButton(
            context,
            'Network Scout',
            'Discover peers/routers & config builder',
            Icons.radar,
            Colors.indigo,
            const ScoutPage(),
          ),
          const SizedBox(height: 8),
          _buildNavButton(
            context,
            'Sensor Dashboard',
            'QoS, publishers, encodings, attachments, express mode',
            Icons.sensors,
            Colors.orange,
            const SensorDashboardPage(),
          ),
          const SizedBox(height: 8),
          _buildNavButton(
            context,
            'Request/Reply Service',
            'Queryable, getCollect, ZenohRetry, query payload',
            Icons.question_answer,
            Colors.cyan,
            const ServicePage(),
          ),
          const SizedBox(height: 8),
          _buildNavButton(
            context,
            'Key-Value Store',
            'CRUD, delete, SampleKind, wildcard subscription',
            Icons.storage,
            Colors.brown,
            const KvStorePage(),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _buildNavButton(BuildContext context, String title, String subtitle,
      IconData icon, Color color, Widget page) {
    return Card(
      elevation: 2,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.15),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: Icon(Icons.chevron_right, color: Colors.grey[400]),
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
        },
      ),
    );
  }
}
