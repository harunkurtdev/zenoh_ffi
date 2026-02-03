import 'package:flutter/material.dart';
import 'package:zenoh_ffi/zenoh_ffi.dart';

class ZenohHomePage extends StatefulWidget {
  const ZenohHomePage({super.key});

  @override
  State<ZenohHomePage> createState() => _ZenohHomePageState();
}

class _ZenohHomePageState extends State<ZenohHomePage> {
  ZenohSession? _session;
  ZenohSubscriber? _subscriber;
  String _receivedValue = 'Waiting for data...';
  bool _isInitializing = true;
  String? _errorMessage;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    // Use addPostFrameCallback to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeZenoh();
    });
  }

  @override
  void reassemble() {
    super.reassemble();
    // Hot reload detected - clean up old subscriptions
    print('Hot reload detected - cleaning up...');
    _disposeResources().then((_) {
      // Reinitialize
      if (mounted && !_isDisposed) {
        setState(() {
          _isInitializing = true;
          _errorMessage = null;
        });
        _initializeZenoh();
      }
    });
  }

  Future<void> _initializeZenoh() async {
    if (_isDisposed) return;

    try {
      // Initialize session
      _session = await ZenohSession.open(mode: 'client', endpoints: [
        'tcp/localhost:7447',
        'tcp/10.51.45.140:7447',
        'tcp/127.0.0.1:7447',
        'tcp/10.0.0.2:7447', // android emulator localhost
      ]);

      // Subscribe
      _subscriber =
          await _session!.declareSubscriber('mqtt/demo/sensor/temperature');

      _subscriber!.stream.listen((sample) {
        if (mounted && !_isDisposed) {
          setState(() {
            _receivedValue =
                'Key: ${sample.key}\nValue: ${sample.payloadString}\nKind: ${sample.kind}';
          });
        }
      });

      if (!_isDisposed && mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage = null;
        });
      }
    } catch (e) {
      print('Error initializing Zenoh: $e');
      if (mounted && !_isDisposed) {
        setState(() {
          _isInitializing = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Zenoh Demo'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isInitializing)
              const Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Subscribing to demo/example...'),
                ],
              )
            else if (_errorMessage != null)
              Column(
                children: [
                  const Icon(Icons.error, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  Text('Error: $_errorMessage'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _isInitializing = true;
                        _errorMessage = null;
                      });
                      _initializeZenoh();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              )
            else
              Column(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 48),
                  const SizedBox(height: 16),
                  Text('Subscribed to "mqtt/demo/sensor/temperature"'),
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _receivedValue,
                      style: const TextStyle(fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _subscriber != null && !_isInitializing
                  ? () {
                      try {
                        _session?.putString(
                            'demo/example', 'Hello from Flutter!');
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Message published!')),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e')),
                          );
                        }
                      }
                    }
                  : null,
              child: const Text('Publish Message'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    _disposeResources();
    super.dispose();
  }

  Future<void> _disposeResources() async {
    await _session?.close();
  }
}
