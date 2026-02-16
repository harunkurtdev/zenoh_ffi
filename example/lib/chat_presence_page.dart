import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:zenoh_ffi/zenoh_ffi.dart';

import 'showcase_painters.dart';

/// Chat with Presence & History
///
/// Demonstrates:
/// - Liveliness + pub/sub + queryable combined in one page
/// - declareLivelinessSubscriber(history: true) for presence
/// - livelinessGet() for on-demand refresh of online users
/// - Queryable serving message history via replyJson()
/// - Attachment metadata on messages (username, emoji)
/// - ZenohEncoding.applicationJson for structured messages
/// - Wildcard subscription chat/room/*/messages for multi-room
class ChatPresencePage extends StatefulWidget {
  const ChatPresencePage({super.key});

  @override
  State<ChatPresencePage> createState() => _ChatPresencePageState();
}

class _ChatPresencePageState extends State<ChatPresencePage>
    with TickerProviderStateMixin {
  ZenohSession? _session;
  bool _isDisposed = false;
  bool _isInitializing = true;
  String? _errorMessage;

  // Identity
  late String _username;
  late String _emoji;
  late Color _userColor;
  static final _emojis = ['😀','🤖','🦊','🐱','🐶','🦁','🐼','🐸','🦉','🚀'];
  static final _colors = [
    Colors.blue, Colors.purple, Colors.teal, Colors.orange,
    Colors.pink, Colors.indigo, Colors.green, Colors.red,
  ];

  // Room
  String _currentRoom = 'general';
  final _rooms = ['general', 'random', 'tech'];
  final Map<String, int> _unreadCounts = {};

  // Messages
  final Map<String, List<_ChatMessage>> _roomMessages = {};
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Presence
  ZenohLivelinessToken? _presenceToken;
  ZenohLivelinessSubscriber? _presenceSub;
  final Map<String, _UserInfo> _onlineUsers = {};

  // Zenoh resources
  ZenohSubscriber? _messageSub;
  ZenohQueryable? _historyQueryable;

  // Animations
  late AnimationController _typingController;

  @override
  void initState() {
    super.initState();
    final rand = Random();
    _username = 'user-${rand.nextInt(9000) + 1000}';
    _emoji = _emojis[rand.nextInt(_emojis.length)];
    _userColor = _colors[rand.nextInt(_colors.length)];

    for (final room in _rooms) {
      _roomMessages[room] = [];
      _unreadCounts[room] = 0;
    }

    _typingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeZenoh());
  }

  @override
  void dispose() {
    _isDisposed = true;
    _typingController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _disposeZenoh();
    super.dispose();
  }

  void _disposeZenoh() {
    _presenceToken?.undeclare();
    _presenceSub?.undeclare();
    _messageSub?.undeclare();
    _historyQueryable?.undeclare();
    _session?.close();
  }

  Future<void> _initializeZenoh() async {
    if (_isDisposed) return;
    setState(() {
      _isInitializing = true;
      _errorMessage = null;
    });

    try {
      _session = await ZenohSession.open(
        mode: 'peer',
        endpoints: [
          'tcp/localhost:7447',
          'tcp/127.0.0.1:7447',
          'tcp/10.81.29.92:7447',
          'tcp/10.0.0.2:7447',
        ],
      );

      // 1. Declare presence token
      _presenceToken = await _session!.declareLivelinessToken(
        'chat/presence/$_username',
      );

      // 2. Subscribe to presence with history
      _presenceSub = await _session!.declareLivelinessSubscriber(
        'chat/presence/**',
        history: true,
      );
      _presenceSub!.stream.listen((event) {
        if (!mounted || _isDisposed) return;
        final user = event.key.replaceFirst('chat/presence/', '');
        setState(() {
          if (event.isAlive) {
            _onlineUsers[user] = _UserInfo(
              name: user,
              emoji: _emojis[user.hashCode.abs() % _emojis.length],
              color: _colors[user.hashCode.abs() % _colors.length],
              joinedAt: DateTime.now(),
            );
          } else {
            _onlineUsers.remove(user);
          }
        });
      });

      // 3. Subscribe to messages on all rooms
      _messageSub = await _session!.declareSubscriber('chat/room/*/messages');
      _messageSub!.stream.listen((sample) {
        if (!mounted || _isDisposed) return;
        try {
          final data = jsonDecode(sample.payloadString);
          final room = _extractRoom(sample.key);
          final msg = _ChatMessage(
            sender: data['sender'] ?? '?',
            text: data['text'] ?? '',
            emoji: data['emoji'] ?? '',
            room: room,
            timestamp: DateTime.now(),
            isMine: data['sender'] == _username,
          );
          setState(() {
            _roomMessages.putIfAbsent(room, () => []);
            _roomMessages[room]!.add(msg);
            if (_roomMessages[room]!.length > 200) {
              _roomMessages[room]!.removeAt(0);
            }
            if (room != _currentRoom) {
              _unreadCounts[room] = (_unreadCounts[room] ?? 0) + 1;
            }
          });
          if (room == _currentRoom) {
            _scrollToBottom();
          }
        } catch (_) {}
      });

      // 4. Declare history queryable
      _historyQueryable = await _session!.declareQueryable(
        'chat/room/*/history',
        (query) {
          final room = _extractRoom(query.key);
          final messages = _roomMessages[room] ?? [];
          final last20 = messages.length > 20
              ? messages.sublist(messages.length - 20)
              : messages;
          query.replyJson(query.key, {
            'room': room,
            'messages': last20
                .map((m) => {
                      'sender': m.sender,
                      'text': m.text,
                      'emoji': m.emoji,
                      'ts': m.timestamp.toIso8601String(),
                    })
                .toList(),
          });
        },
      );

      if (!_isDisposed && mounted) {
        setState(() => _isInitializing = false);
      }
    } catch (e) {
      if (!_isDisposed && mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  String _extractRoom(String key) {
    // key = chat/room/{room}/messages or chat/room/{room}/history
    final parts = key.split('/');
    return parts.length >= 3 ? parts[2] : 'general';
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _session == null) return;

    _messageController.clear();

    final payload = jsonEncode({
      'sender': _username,
      'text': text,
      'emoji': _emoji,
      'room': _currentRoom,
    });

    try {
      await _session!.put(
        'chat/room/$_currentRoom/messages',
        Uint8List.fromList(utf8.encode(payload)),
        options: ZenohPutOptions(
          encoding: ZenohEncoding.applicationJson,
          attachment: Uint8List.fromList(
            utf8.encode('user=$_username;emoji=$_emoji'),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Send failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _refreshPresence() async {
    if (_session == null) return;
    try {
      await for (final event in _session!.livelinessGet('chat/presence/**')) {
        if (!mounted || _isDisposed) break;
        final user = event.key.replaceFirst('chat/presence/', '');
        setState(() {
          _onlineUsers[user] = _UserInfo(
            name: user,
            emoji: _emojis[user.hashCode.abs() % _emojis.length],
            color: _colors[user.hashCode.abs() % _colors.length],
            joinedAt: DateTime.now(),
          );
        });
      }
    } catch (_) {}
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _switchRoom(String room) {
    setState(() {
      _currentRoom = room;
      _unreadCounts[room] = 0;
    });
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chat & Presence')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chat & Presence')),
        body: _buildErrorWidget(),
      );
    }
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Chat $_emoji $_username'),
          bottom: TabBar(
            tabs: [
              const Tab(icon: Icon(Icons.chat_bubble), text: 'Chat'),
              Tab(
                icon: Badge(
                  label: Text('${_onlineUsers.length}'),
                  child: const Icon(Icons.people),
                ),
                text: 'Users',
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildChatTab(),
            _buildUsersTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildChatTab() {
    final messages = _roomMessages[_currentRoom] ?? [];
    return Column(
      children: [
        // Room selector
        Container(
          height: 48,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            children: _rooms.map((room) {
              final isActive = room == _currentRoom;
              final unread = _unreadCounts[room] ?? 0;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  selected: isActive,
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('#$room'),
                      if (unread > 0) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$unread',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  onSelected: (_) => _switchRoom(room),
                  selectedColor: Theme.of(context).colorScheme.primaryContainer,
                ),
              );
            }).toList(),
          ),
        ),

        // Messages
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_outline,
                          size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 8),
                      Text(
                        'No messages in #$_currentRoom yet.\nSay hello!',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    return _buildChatBubble(messages[index]);
                  },
                ),
        ),

        // Input
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(20),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  decoration: InputDecoration(
                    hintText: 'Message #$_currentRoom...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              GradientCard(
                margin: EdgeInsets.zero,
                padding: EdgeInsets.zero,
                borderRadius: 24,
                colors: const [Color(0xFF5C6BC0), Color(0xFF3949AB)],
                child: IconButton(
                  onPressed: _sendMessage,
                  icon: const Icon(Icons.send, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChatBubble(_ChatMessage msg) {
    final isMine = msg.isMine;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMine) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: _colors[msg.sender.hashCode.abs() % _colors.length]
                  .withAlpha(40),
              child: Text(
                msg.emoji.isNotEmpty
                    ? msg.emoji
                    : _emojis[msg.sender.hashCode.abs() % _emojis.length],
                style: const TextStyle(fontSize: 14),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isMine
                      ? [const Color(0xFF5C6BC0), const Color(0xFF7E57C2)]
                      : [Colors.grey.shade200, Colors.grey.shade100],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMine ? 16 : 4),
                  bottomRight: Radius.circular(isMine ? 4 : 16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(15),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment:
                    isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!isMine)
                    Text(
                      '${msg.emoji} ${msg.sender}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isMine ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  Text(
                    msg.text,
                    style: TextStyle(
                      fontSize: 15,
                      color: isMine ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatTime(msg.timestamp),
                    style: TextStyle(
                      fontSize: 10,
                      color: isMine ? Colors.white54 : Colors.black38,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isMine) const SizedBox(width: 6),
        ],
      ),
    );
  }

  Widget _buildUsersTab() {
    final users = _onlineUsers.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return Column(
      children: [
        // Header
        GradientCard(
          margin: const EdgeInsets.all(12),
          colors: const [Color(0xFF1B5E20), Color(0xFF2E7D32)],
          child: Row(
            children: [
              const Icon(Icons.wifi, color: Colors.white70),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Online Users',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                    Text(
                      '${users.length} user(s) online via Zenoh liveliness',
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _refreshPresence,
                icon: const Icon(Icons.refresh, color: Colors.white70),
                tooltip: 'Refresh (livelinessGet)',
              ),
            ],
          ),
        ),

        // User list
        Expanded(
          child: users.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person_off,
                          size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 8),
                      Text('No users detected',
                          style: TextStyle(color: Colors.grey[600])),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final user = users[index];
                    final isMe = user.name == _username;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Stack(
                          children: [
                            CircleAvatar(
                              backgroundColor: user.color.withAlpha(40),
                              child: Text(user.emoji,
                                  style: const TextStyle(fontSize: 22)),
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: PulsingDot(
                                color: Colors.green,
                                size: 10,
                                active: true,
                              ),
                            ),
                          ],
                        ),
                        title: Row(
                          children: [
                            Text(
                              user.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            if (isMe) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withAlpha(30),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text('you',
                                    style: TextStyle(
                                        fontSize: 10, color: Colors.blue)),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          'Joined at ${_formatTime(user.joinedAt)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: const Icon(Icons.circle,
                            color: Colors.green, size: 10),
                      ),
                    );
                  },
                ),
        ),

        // Presence info card
        Padding(
          padding: const EdgeInsets.all(12),
          child: Card(
            color: Colors.grey[900],
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Zenoh Presence API',
                      style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                  const SizedBox(height: 4),
                  SelectableText(
                    'Token: chat/presence/$_username\n'
                    'Subscribe: chat/presence/** (history: true)\n'
                    'Refresh: livelinessGet("chat/presence/**")',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Colors.greenAccent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            const Text('Connection Failed',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(_errorMessage ?? '',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: const SelectableText(
                'zenohd -l tcp/0.0.0.0:7447',
                style: TextStyle(fontFamily: 'monospace', fontSize: 14),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _initializeZenoh,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
}

class _ChatMessage {
  final String sender;
  final String text;
  final String emoji;
  final String room;
  final DateTime timestamp;
  final bool isMine;

  _ChatMessage({
    required this.sender,
    required this.text,
    required this.emoji,
    required this.room,
    required this.timestamp,
    required this.isMine,
  });
}

class _UserInfo {
  final String name;
  final String emoji;
  final Color color;
  final DateTime joinedAt;

  _UserInfo({
    required this.name,
    required this.emoji,
    required this.color,
    required this.joinedAt,
  });
}
