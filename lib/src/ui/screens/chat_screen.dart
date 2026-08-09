import 'package:flutter/material.dart';

import '../../theme.dart';
import '../chat/chat_view.dart';

/// The chat screen as a pushed route (mobile navigation). Reads the session id
/// from route arguments (`/chat?id=<id>` or plain String argument).
class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    String? sessionId;
    if (args is String) {
      sessionId = args;
    } else if (args is Map && args['id'] is String) {
      sessionId = args['id'];
    }

    return Scaffold(
      backgroundColor: MinisTheme.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('OpenMinis'),
      ),
      body: ChatScreenView(sessionId: sessionId),
    );
  }
}
