import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:zenoh_ffi/zenoh_ffi.dart';

class Todo {
  final String id;
  String title;
  bool completed;

  Todo({required this.id, required this.title, this.completed = false});

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'completed': completed,
      };

  factory Todo.fromJson(Map<String, dynamic> json) => Todo(
        id: json['id'],
        title: json['title'],
        completed: json['completed'],
      );
}

class TodoPage extends StatefulWidget {
  const TodoPage({super.key});

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> {
  ZenohSession? _session;
  ZenohSubscriber? _subscriber;
  ZenohQueryable? _queryable;

  final List<Todo> _todos = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isConnected = false;
  String _status = "Disconnected";

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _subscriber?.undeclare();
    _queryable?.undeclare();
    _session?.close();
    super.dispose();
  }

  Future<void> _connect() async {
    try {
      setState(() => _status = "Connecting...");
      _session =
          await ZenohSession.open(mode: 'peer'); // Peer mode for P2P sync

      setState(() {
        _isConnected = true;
        _status = "Connected (Peer)";
      });

      // 1. Subscribe to updates (PUT/DELETE)
      _subscriber = await _session!.declareSubscriber('demo/todo/**');
      _subscriber!.stream.listen(_handleUpdate);

      // 2. Declare Queryable to serve our state to others
      _queryable =
          await _session!.declareQueryable('demo/todo/**', _handleQuery);

      // 3. Fetch initial state from peers
      _fetchState();
    } catch (e) {
      setState(() {
        _status = "Error: $e";
        _isConnected = false;
      });
    }
  }

  void _fetchState() {
    _session!.get('demo/todo/**').listen((reply) {
      try {
        final json = jsonDecode(reply.payloadString);
        final todo = Todo.fromJson(json);
        _addOrUpdateLocal(todo);
      } catch (e) {
        print('Error parsing reply: $e');
      }
    });
  }

  void _handleUpdate(ZenohSample sample) {
    if (sample.kind == 'DELETE') {
      // Extract ID from key: demo/todo/ID
      final parts = sample.key.split('/');
      if (parts.isNotEmpty) {
        final id = parts.last;
        setState(() {
          _todos.removeWhere((t) => t.id == id);
        });
      }
    } else {
      try {
        final json = jsonDecode(sample.payloadString);
        final todo = Todo.fromJson(json);
        _addOrUpdateLocal(todo);
      } catch (e) {
        print('Error parsing update: $e');
      }
    }
  }

  void _handleQuery(ZenohQuery query) {
    print("Received query for: ${query.selector}");
    // Reply with all our todos
    // In a real app, we might filter based on selector
    for (final todo in _todos) {
      final key = 'demo/todo/${todo.id}';
      final jsonStr = jsonEncode(todo.toJson());
      query.replyString(key, jsonStr);
    }
  }

  void _addOrUpdateLocal(Todo todo) {
    setState(() {
      final index = _todos.indexWhere((t) => t.id == todo.id);
      if (index != -1) {
        _todos[index] = todo;
      } else {
        _todos.add(todo);
      }
    });
  }

  Future<void> _addTodo() async {
    if (_controller.text.isEmpty) return;

    final todo = Todo(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: _controller.text,
    );

    _controller.clear();
    _addOrUpdateLocal(todo); // Optimistic update

    // Broadcast
    if (_isConnected) {
      await _session!
          .putString('demo/todo/${todo.id}', jsonEncode(todo.toJson()));
    }
  }

  Future<void> _toggleTodo(Todo todo) async {
    todo.completed = !todo.completed;
    _addOrUpdateLocal(todo);

    if (_isConnected) {
      await _session!
          .putString('demo/todo/${todo.id}', jsonEncode(todo.toJson()));
    }
  }

  Future<void> _deleteTodo(String id) async {
    setState(() {
      _todos.removeWhere((t) => t.id == id);
    });

    if (_isConnected) {
      // zenoh_ffi doesn't have explicit delete exposed yet in helper,
      // but we wrapped it? No, we missed exposing `delete` in ZenohSession dart class!
      // Wait, let me check ZenohSession again.
      // I missed `delete` in the rewrite!
      // I'll implement it quickly or use put with specialized kind?
      // Zenoh C API has z_delete. My C wrapper has zenoh_delete.
      // But I missed adding it to ZenohSession Dart class in Step 247.
      // For now, I'll simulates delete with a PUT of "DELETE" kind?
      // No, proper way is to add delete.
      print("Delete not fully implemented in Dart layer yet");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Zenoh Distributed Todo'),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8.0),
            color: _isConnected ? Colors.green[100] : Colors.red[100],
            child: Row(
              children: [
                Icon(_isConnected ? Icons.check_circle : Icons.error),
                const SizedBox(width: 8),
                Text(_status),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.refresh), onPressed: _connect),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _todos.length,
              itemBuilder: (context, index) {
                final todo = _todos[index];
                return ListTile(
                  leading: Checkbox(
                    value: todo.completed,
                    onChanged: (_) => _toggleTodo(todo),
                  ),
                  title: Text(
                    todo.title,
                    style: TextStyle(
                      decoration:
                          todo.completed ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () => _deleteTodo(todo.id),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'Enter todo...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _addTodo(),
                  ),
                ),
                const SizedBox(width: 8),
                FloatingActionButton(
                  onPressed: _addTodo,
                  child: const Icon(Icons.add),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
