import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// 🔁 Replace with your public InfinityFree URL after deploying backend
const String kProxyUrl = 'https://YOUR-SITE.infinityfreeapp.com/api-proxy.php';

void main() => runApp(const CourseDeepApp());

class CourseDeepApp extends StatelessWidget {
  const CourseDeepApp({super.key});
  @override
  Widget build(BuildContext c) => MaterialApp(
        title: 'CourseDeep',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
        home: const ChatPage(),
      );
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _ctrl = TextEditingController();
  final _log = <MapEntry<String, String>>[];
  bool _busy = false;

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() { _log.add(MapEntry('You', text)); _busy = true; });
    _ctrl.clear();
    try {
      final r = await http.post(Uri.parse(kProxyUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'message': text}));
      final body = jsonDecode(r.body);
      final reply = body['choices']?[0]?['message']?['content']
          ?? body['error'] ?? '(no reply)';
      setState(() => _log.add(MapEntry('CourseDeep', reply)));
    } catch (e) {
      setState(() => _log.add(MapEntry('Error', e.toString())));
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: const Text('CourseDeep')),
        body: Column(children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _log.length,
              itemBuilder: (_, i) {
                final e = _log[i];
                final isUser = e.key == 'You';
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(10),
                    constraints: const BoxConstraints(maxWidth: 300),
                    decoration: BoxDecoration(
                      color: isUser ? Colors.deepPurple.shade100 : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('${e.key}: ${e.value}'),
                  ),
                );
              },
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  decoration: const InputDecoration(
                      hintText: 'Ask CourseDeep...',
                      border: OutlineInputBorder()),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(icon: const Icon(Icons.send), onPressed: _send),
            ]),
          ),
        ]),
      );
}
