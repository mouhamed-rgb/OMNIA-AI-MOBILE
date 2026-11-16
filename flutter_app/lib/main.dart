import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

void main() => runApp(const OmniaApp());

class OmniaApp extends StatelessWidget {
  const OmniaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData.dark(useMaterial3: true);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'OMNIA AI MOBILE',
      theme: base.copyWith(
        scaffoldBackgroundColor: const Color(0xFF020408),
        colorScheme: base.colorScheme.copyWith(
          primary: const Color(0xFF00FFE0),
          secondary: const Color(0xFFFF00AA),
        ),
        textTheme: GoogleFonts.cairoTextTheme(base.textTheme).apply(
          bodyColor: const Color(0xFFE8FFF9),
          displayColor: const Color(0xFFE8FFF9),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF08131B),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(17),
            borderSide: const BorderSide(color: Color(0xFF164047)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(17),
            borderSide: const BorderSide(color: Color(0xFF164047)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(17),
            borderSide: const BorderSide(color: Color(0xFF00FFE0)),
          ),
        ),
      ),
      home: const ChatScreen(),
    );
  }
}

class ChatMessage {
  const ChatMessage(this.role, this.content);
  final String role;
  final String content;

  Map<String, dynamic> toJson() => {'role': role, 'content': content};

  factory ChatMessage.fromJson(Map<String, dynamic> json) =>
      ChatMessage(json['role'] as String, json['content'] as String);
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final input = TextEditingController();
  final scroll = ScrollController();
  final messages = <ChatMessage>[];
  bool loading = false;
  String model = 'openai/gpt-oss-120b';
  String? error;

  static const models = [
    'openai/gpt-oss-120b',
    'openai/gpt-oss-20b',
    'groq/compound',
    'groq/compound-mini',
  ];

  @override
  void initState() {
    super.initState();
    loadHistory();
  }

  Future<void> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('omnia_history');
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      if (!mounted) return;
      setState(() {
        messages.addAll(list.map((item) =>
            ChatMessage.fromJson(item as Map<String, dynamic>)));
      });
    } catch (_) {
      await prefs.remove('omnia_history');
    }
  }

  Future<void> saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'omnia_history',
      jsonEncode(messages.map((message) => message.toJson()).toList()),
    );
  }

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty || loading) return;

    if (apiBaseUrl.isEmpty) {
      setState(() => error =
          'لم يتم إعداد API_BASE_URL في إعدادات GitHub Actions.');
      return;
    }

    input.clear();
    setState(() {
      error = null;
      messages.add(ChatMessage('user', text));
      loading = true;
    });
    await saveHistory();
    jumpBottom();

    try {
      // Normalize the backend URL before building the chat endpoint.
      var cleanBase = apiBaseUrl.trim();
      cleanBase = cleanBase
          .replaceAll('\uFEFF', '')
          .replaceAll('\u200E', '')
          .replaceAll('\u200F', '')
          .trim();
      if (cleanBase.startsWith('"') && cleanBase.endsWith('"')) {
        cleanBase = cleanBase.substring(1, cleanBase.length - 1).trim();
      }
      if (cleanBase.startsWith("'") && cleanBase.endsWith("'")) {
        cleanBase = cleanBase.substring(1, cleanBase.length - 1).trim();
      }
      cleanBase = cleanBase.replaceAll(RegExp(r'/+$'), '');
      final baseUri = Uri.tryParse(cleanBase);
      if (baseUri == null ||
          !baseUri.hasScheme ||
          !['https', 'http'].contains(baseUri.scheme.toLowerCase()) ||
          baseUri.host.isEmpty) {
        throw const FormatException(
          'رابط الخادم غير صالح. تحقق من API_BASE_URL في GitHub Actions.',
        );
      }
      final endpoint = Uri.parse('$cleanBase/api/chat');
      final response = await http
          .post(
            endpoint,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'model': model,
              'messages': messages.map((m) => m.toJson()).toList(),
            }),
          )
          .timeout(const Duration(seconds: 65));

      final dynamic decoded = jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = decoded is Map
            ? (decoded['error']?.toString() ?? 'HTTP ${response.statusCode}')
            : 'HTTP ${response.statusCode}';
        throw Exception(message);
      }

      final answer = decoded['choices'][0]['message']['content'] as String;
      if (!mounted) return;
      setState(() => messages.add(ChatMessage('assistant', answer)));
      await saveHistory();
    } catch (exception) {
      if (mounted) {
        setState(() => error = 'تعذر الاتصال بالخادم: $exception');
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
        jumpBottom();
      }
    }
  }

  void jumpBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) {
        scroll.animateTo(
          scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> clearChat() async {
    if (loading) return;
    setState(() {
      messages.clear();
      error = null;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('omnia_history');
  }

  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF050C12),
          title: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00FFE0), Color(0xFFFF00AA)],
                  ),
                ),
                child: const Icon(Icons.auto_awesome,
                    color: Color(0xFF020408)),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('OMNIA AI',
                      style: GoogleFonts.orbitron(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2)),
                  const Text('MOBILE INTELLIGENCE',
                      style: TextStyle(
                          fontSize: 9,
                          color: Color(0xFF00FFE0),
                          letterSpacing: 1.4)),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              onPressed: loading ? null : clearChat,
              tooltip: 'محادثة جديدة',
              icon: const Icon(Icons.add_comment_outlined,
                  color: Color(0xFF00FFE0)),
            ),
          ],
        ),
        body: Column(
          children: [
            Container(
              margin: const EdgeInsets.all(13),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF07151A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF164047)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.hub_outlined,
                      color: Color(0xFF00FFE0), size: 18),
                  const SizedBox(width: 8),
                  const Text('نموذج الذكاء',
                      style: TextStyle(fontSize: 12, color: Colors.white70)),
                  const Spacer(),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: model,
                      dropdownColor: const Color(0xFF08131B),
                      style: const TextStyle(
                          color: Color(0xFF00FFE0), fontSize: 11),
                      items: models
                          .map((item) => DropdownMenuItem(
                              value: item, child: Text(item)))
                          .toList(),
                      onChanged: loading
                          ? null
                          : (value) =>
                              setState(() => model = value ?? model),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: messages.isEmpty
                  ? welcome()
                  : ListView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.all(14),
                      itemCount: messages.length + (loading ? 1 : 0),
                      itemBuilder: (context, index) => index == messages.length
                          ? typing()
                          : bubble(messages[index]),
                    ),
            ),
            if (error != null)
              Container(
                width: double.infinity,
                margin:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF35111F),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(error!,
                    style: const TextStyle(
                        color: Color(0xFFFF8ABF), fontSize: 12)),
              ),
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 12),
                decoration: const BoxDecoration(
                  color: Color(0xFF050C12),
                  border: Border(
                      top: BorderSide(color: Color(0xFF15343A))),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: input,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.newline,
                        decoration: const InputDecoration(
                          hintText: 'اكتب رسالتك إلى OMNIA...',
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 13),
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(
                            colors: [Color(0xFF00FFE0), Color(0xFF00A99A)]),
                      ),
                      child: IconButton(
                        onPressed: loading ? null : send,
                        icon: Icon(
                            loading ? Icons.hourglass_top : Icons.send_rounded,
                            color: const Color(0xFF020408)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget welcome() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.auto_awesome,
                  size: 58, color: Color(0xFF00FFE0)),
              const SizedBox(height: 18),
              Text('مرحباً بك في OMNIA AI',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(
                      fontSize: 23, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('ذكاء اصطناعي متقدم، الآن في هاتفك.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54)),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['اشرح لي فكرة معقدة', 'اكتب لي كوداً', 'ساعدني في الدراسة']
                    .map((suggestion) => ActionChip(
                          label: Text(suggestion,
                              style: const TextStyle(
                                  color: Color(0xFF00FFE0), fontSize: 11)),
                          backgroundColor: const Color(0xFF081A20),
                          onPressed: () {
                            input.text = suggestion;
                            send();
                          },
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
      );

  Widget bubble(ChatMessage message) {
    final isUser = message.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        margin: const EdgeInsets.only(bottom: 13),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF10302F) : const Color(0xFF0A141D),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
              color: isUser
                  ? const Color(0xFF17615A)
                  : const Color(0xFF19323B)),
        ),
        child: isUser
            ? SelectableText(message.content,
                style: const TextStyle(fontSize: 14, height: 1.55))
            : MarkdownBody(
                data: message.content,
                selectable: true,
                styleSheet: MarkdownStyleSheet(
                  p: const TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: Color(0xFFE8FFF9)),
                  code: const TextStyle(
                      color: Color(0xFF00FFE0),
                      backgroundColor: Color(0xFF020408)),
                  h1: const TextStyle(color: Color(0xFF00FFE0)),
                  h2: const TextStyle(color: Color(0xFF00FFE0)),
                ),
              ),
      ),
    );
  }

  Widget typing() => const Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFF00FFE0))),
              SizedBox(width: 10),
              Text('OMNIA يكتب الآن...',
                  style: TextStyle(
                      color: Color(0xFF00FFE0), fontSize: 12)),
            ],
          ),
        ),
      );
}
''), '')
          .trim();
      final baseUri = Uri.tryParse(cleanBase);
      if (baseUri == null ||
          !baseUri.hasScheme ||
          !['https', 'http'].contains(baseUri.scheme.toLowerCase()) ||
          baseUri.host.isEmpty) {
        throw const FormatException(
          'رابط الخادم غير صالح. تحقق من API_BASE_URL في GitHub Actions.',
        );
      }
      final basePath = baseUri.path.replaceFirst(RegExp(r'/+
            body: jsonEncode({
              'model': model,
              'messages': messages.map((m) => m.toJson()).toList(),
            }),
          )
          .timeout(const Duration(seconds: 65));

      final dynamic decoded = jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = decoded is Map
            ? (decoded['error']?.toString() ?? 'HTTP ${response.statusCode}')
            : 'HTTP ${response.statusCode}';
        throw Exception(message);
      }

      final answer = decoded['choices'][0]['message']['content'] as String;
      if (!mounted) return;
      setState(() => messages.add(ChatMessage('assistant', answer)));
      await saveHistory();
    } catch (exception) {
      if (mounted) {
        setState(() => error = 'تعذر الاتصال بالخادم: $exception');
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
        jumpBottom();
      }
    }
  }

  void jumpBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) {
        scroll.animateTo(
          scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> clearChat() async {
    if (loading) return;
    setState(() {
      messages.clear();
      error = null;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('omnia_history');
  }

  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF050C12),
          title: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00FFE0), Color(0xFFFF00AA)],
                  ),
                ),
                child: const Icon(Icons.auto_awesome,
                    color: Color(0xFF020408)),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('OMNIA AI',
                      style: GoogleFonts.orbitron(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2)),
                  const Text('MOBILE INTELLIGENCE',
                      style: TextStyle(
                          fontSize: 9,
                          color: Color(0xFF00FFE0),
                          letterSpacing: 1.4)),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              onPressed: loading ? null : clearChat,
              tooltip: 'محادثة جديدة',
              icon: const Icon(Icons.add_comment_outlined,
                  color: Color(0xFF00FFE0)),
            ),
          ],
        ),
        body: Column(
          children: [
            Container(
              margin: const EdgeInsets.all(13),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF07151A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF164047)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.hub_outlined,
                      color: Color(0xFF00FFE0), size: 18),
                  const SizedBox(width: 8),
                  const Text('نموذج الذكاء',
                      style: TextStyle(fontSize: 12, color: Colors.white70)),
                  const Spacer(),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: model,
                      dropdownColor: const Color(0xFF08131B),
                      style: const TextStyle(
                          color: Color(0xFF00FFE0), fontSize: 11),
                      items: models
                          .map((item) => DropdownMenuItem(
                              value: item, child: Text(item)))
                          .toList(),
                      onChanged: loading
                          ? null
                          : (value) =>
                              setState(() => model = value ?? model),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: messages.isEmpty
                  ? welcome()
                  : ListView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.all(14),
                      itemCount: messages.length + (loading ? 1 : 0),
                      itemBuilder: (context, index) => index == messages.length
                          ? typing()
                          : bubble(messages[index]),
                    ),
            ),
            if (error != null)
              Container(
                width: double.infinity,
                margin:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF35111F),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(error!,
                    style: const TextStyle(
                        color: Color(0xFFFF8ABF), fontSize: 12)),
              ),
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 12),
                decoration: const BoxDecoration(
                  color: Color(0xFF050C12),
                  border: Border(
                      top: BorderSide(color: Color(0xFF15343A))),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: input,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.newline,
                        decoration: const InputDecoration(
                          hintText: 'اكتب رسالتك إلى OMNIA...',
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 13),
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(
                            colors: [Color(0xFF00FFE0), Color(0xFF00A99A)]),
                      ),
                      child: IconButton(
                        onPressed: loading ? null : send,
                        icon: Icon(
                            loading ? Icons.hourglass_top : Icons.send_rounded,
                            color: const Color(0xFF020408)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget welcome() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.auto_awesome,
                  size: 58, color: Color(0xFF00FFE0)),
              const SizedBox(height: 18),
              Text('مرحباً بك في OMNIA AI',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(
                      fontSize: 23, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('ذكاء اصطناعي متقدم، الآن في هاتفك.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54)),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['اشرح لي فكرة معقدة', 'اكتب لي كوداً', 'ساعدني في الدراسة']
                    .map((suggestion) => ActionChip(
                          label: Text(suggestion,
                              style: const TextStyle(
                                  color: Color(0xFF00FFE0), fontSize: 11)),
                          backgroundColor: const Color(0xFF081A20),
                          onPressed: () {
                            input.text = suggestion;
                            send();
                          },
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
      );

  Widget bubble(ChatMessage message) {
    final isUser = message.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        margin: const EdgeInsets.only(bottom: 13),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF10302F) : const Color(0xFF0A141D),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
              color: isUser
                  ? const Color(0xFF17615A)
                  : const Color(0xFF19323B)),
        ),
        child: isUser
            ? SelectableText(message.content,
                style: const TextStyle(fontSize: 14, height: 1.55))
            : MarkdownBody(
                data: message.content,
                selectable: true,
                styleSheet: MarkdownStyleSheet(
                  p: const TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: Color(0xFFE8FFF9)),
                  code: const TextStyle(
                      color: Color(0xFF00FFE0),
                      backgroundColor: Color(0xFF020408)),
                  h1: const TextStyle(color: Color(0xFF00FFE0)),
                  h2: const TextStyle(color: Color(0xFF00FFE0)),
                ),
              ),
      ),
    );
  }

  Widget typing() => const Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFF00FFE0))),
              SizedBox(width: 10),
              Text('OMNIA يكتب الآن...',
                  style: TextStyle(
                      color: Color(0xFF00FFE0), fontSize: 12)),
            ],
          ),
        ),
      );
}
), '');
      final endpoint = baseUri.replace(
        path: '$basePath/api/chat',
        query: null,
        fragment: null,
      );
      final response = await http
          .post(
            endpoint,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'model': model,
              'messages': messages.map((m) => m.toJson()).toList(),
            }),
          )
          .timeout(const Duration(seconds: 65));

      final dynamic decoded = jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = decoded is Map
            ? (decoded['error']?.toString() ?? 'HTTP ${response.statusCode}')
            : 'HTTP ${response.statusCode}';
        throw Exception(message);
      }

      final answer = decoded['choices'][0]['message']['content'] as String;
      if (!mounted) return;
      setState(() => messages.add(ChatMessage('assistant', answer)));
      await saveHistory();
    } catch (exception) {
      if (mounted) {
        setState(() => error = 'تعذر الاتصال بالخادم: $exception');
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
        jumpBottom();
      }
    }
  }

  void jumpBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) {
        scroll.animateTo(
          scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> clearChat() async {
    if (loading) return;
    setState(() {
      messages.clear();
      error = null;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('omnia_history');
  }

  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF050C12),
          title: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00FFE0), Color(0xFFFF00AA)],
                  ),
                ),
                child: const Icon(Icons.auto_awesome,
                    color: Color(0xFF020408)),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('OMNIA AI',
                      style: GoogleFonts.orbitron(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2)),
                  const Text('MOBILE INTELLIGENCE',
                      style: TextStyle(
                          fontSize: 9,
                          color: Color(0xFF00FFE0),
                          letterSpacing: 1.4)),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              onPressed: loading ? null : clearChat,
              tooltip: 'محادثة جديدة',
              icon: const Icon(Icons.add_comment_outlined,
                  color: Color(0xFF00FFE0)),
            ),
          ],
        ),
        body: Column(
          children: [
            Container(
              margin: const EdgeInsets.all(13),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF07151A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF164047)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.hub_outlined,
                      color: Color(0xFF00FFE0), size: 18),
                  const SizedBox(width: 8),
                  const Text('نموذج الذكاء',
                      style: TextStyle(fontSize: 12, color: Colors.white70)),
                  const Spacer(),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: model,
                      dropdownColor: const Color(0xFF08131B),
                      style: const TextStyle(
                          color: Color(0xFF00FFE0), fontSize: 11),
                      items: models
                          .map((item) => DropdownMenuItem(
                              value: item, child: Text(item)))
                          .toList(),
                      onChanged: loading
                          ? null
                          : (value) =>
                              setState(() => model = value ?? model),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: messages.isEmpty
                  ? welcome()
                  : ListView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.all(14),
                      itemCount: messages.length + (loading ? 1 : 0),
                      itemBuilder: (context, index) => index == messages.length
                          ? typing()
                          : bubble(messages[index]),
                    ),
            ),
            if (error != null)
              Container(
                width: double.infinity,
                margin:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF35111F),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(error!,
                    style: const TextStyle(
                        color: Color(0xFFFF8ABF), fontSize: 12)),
              ),
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 12),
                decoration: const BoxDecoration(
                  color: Color(0xFF050C12),
                  border: Border(
                      top: BorderSide(color: Color(0xFF15343A))),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: input,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.newline,
                        decoration: const InputDecoration(
                          hintText: 'اكتب رسالتك إلى OMNIA...',
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 13),
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(
                            colors: [Color(0xFF00FFE0), Color(0xFF00A99A)]),
                      ),
                      child: IconButton(
                        onPressed: loading ? null : send,
                        icon: Icon(
                            loading ? Icons.hourglass_top : Icons.send_rounded,
                            color: const Color(0xFF020408)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget welcome() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.auto_awesome,
                  size: 58, color: Color(0xFF00FFE0)),
              const SizedBox(height: 18),
              Text('مرحباً بك في OMNIA AI',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(
                      fontSize: 23, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('ذكاء اصطناعي متقدم، الآن في هاتفك.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54)),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['اشرح لي فكرة معقدة', 'اكتب لي كوداً', 'ساعدني في الدراسة']
                    .map((suggestion) => ActionChip(
                          label: Text(suggestion,
                              style: const TextStyle(
                                  color: Color(0xFF00FFE0), fontSize: 11)),
                          backgroundColor: const Color(0xFF081A20),
                          onPressed: () {
                            input.text = suggestion;
                            send();
                          },
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
      );

  Widget bubble(ChatMessage message) {
    final isUser = message.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        margin: const EdgeInsets.only(bottom: 13),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF10302F) : const Color(0xFF0A141D),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
              color: isUser
                  ? const Color(0xFF17615A)
                  : const Color(0xFF19323B)),
        ),
        child: isUser
            ? SelectableText(message.content,
                style: const TextStyle(fontSize: 14, height: 1.55))
            : MarkdownBody(
                data: message.content,
                selectable: true,
                styleSheet: MarkdownStyleSheet(
                  p: const TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: Color(0xFFE8FFF9)),
                  code: const TextStyle(
                      color: Color(0xFF00FFE0),
                      backgroundColor: Color(0xFF020408)),
                  h1: const TextStyle(color: Color(0xFF00FFE0)),
                  h2: const TextStyle(color: Color(0xFF00FFE0)),
                ),
              ),
      ),
    );
  }

  Widget typing() => const Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFF00FFE0))),
              SizedBox(width: 10),
              Text('OMNIA يكتب الآن...',
                  style: TextStyle(
                      color: Color(0xFF00FFE0), fontSize: 12)),
            ],
          ),
        ),
      );
}
