import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const KajiminiApp());
}

class KajiminiApp extends StatelessWidget {
  const KajiminiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kajimini',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal, // Mengubah warna tema agar lebih modern
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

// LAYAR UTAMA: Pengendali Tab Bawah
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  String _apiKey = '';

  @override
  void initState() {
    super.initState();
    _loadApiKey();
  }

  // Mengambil API Key yang tersimpan di HP
  Future<void> _loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiKey = prefs.getString('api_key') ?? '';
    });
  }

  // Menyimpan API Key ke dalam HP
  Future<void> _saveApiKey(String newKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_key', newKey.trim());
    setState(() {
      _apiKey = newKey.trim();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _selectedIndex == 0 
          ? ChatScreen(apiKey: _apiKey) 
          : SettingsScreen(
              currentApiKey: _apiKey,
              onSave: _saveApiKey,
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Pengaturan',
          ),
        ],
      ),
    );
  }
}

// TAB 2: LAYAR PENGATURAN
class SettingsScreen extends StatelessWidget {
  final String currentApiKey;
  final Function(String) onSave;

  SettingsScreen({super.key, required this.currentApiKey, required this.onSave});

  final TextEditingController _keyController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    _keyController.text = currentApiKey;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan Kajimini', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 2,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Konfigurasi AI',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Masukkan API Key Google AI Studio milikmu. Kunci ini akan disimpan secara permanen & aman di memori HP-mu.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _keyController,
              decoration: InputDecoration(
                hintText: 'Tempel (Paste) API Key di sini...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.vpn_key),
              ),
              obscureText: true, // Menyembunyikan teks API Key (sensor)
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.tealAccent,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                ),
                onPressed: () {
                  onSave(_keyController.text);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('API Key berhasil disimpan!'), backgroundColor: Colors.green),
                  );
                },
                child: const Text('SIMPAN KONFIGURASI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// TAB 1: LAYAR CHAT UTAMA
class ChatScreen extends StatefulWidget {
  final String apiKey;
  const ChatScreen({super.key, required this.apiKey});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  GenerativeModel? _model;
  ChatSession? _chatSession;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  final List<Map<String, dynamic>> _messages = [];
  bool _isLoading = false;
  File? _selectedFile;

  @override
  void initState() {
    super.initState();
    _initModel();
  }

  // Jika API Key diganti di pengaturan, otomatis perbarui model AI-nya
  @override
  void didUpdateWidget(ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiKey != widget.apiKey) {
      _initModel();
    }
  }

  void _initModel() {
    if (widget.apiKey.isNotEmpty) {
      _model = GenerativeModel(
        model: 'gemini-1.5-flash',
        apiKey: widget.apiKey,
      );
      _chatSession = _model!.startChat();
    } else {
      _model = null;
      _chatSession = null;
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf', 'txt'],
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedFile = File(result.files.single.path!);
      });
    }
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty && _selectedFile == null) return;
    
    if (widget.apiKey.isEmpty) {
      _showSnackBar('Peringatan: Isi API Key di Tab Pengaturan terlebih dahulu!', Colors.orange);
      return;
    }

    if (_chatSession == null) _initModel();

    final userText = text;
    final fileToSend = _selectedFile;

    setState(() {
      _messages.add({
        'role': 'user', 
        'text': userText,
        'file_path': fileToSend?.path
      });
      _isLoading = true;
      _selectedFile = null;
    });
    _textController.clear();
    _scrollToBottom();

    try {
      List<Content> contents = [];
      
      if (fileToSend != null) {
        final bytes = await fileToSend.readAsBytes();
        final mimeType = userText.endsWith('.pdf') ? 'application/pdf' : 'image/jpeg';
        contents.add(Content.multi([
          TextPart(userText.isEmpty ? "Tolong analisa file ini" : userText),
          DataPart(mimeType, bytes)
        ]));
      } else {
        contents.add(Content.text(userText));
      }

      final response = await _chatSession!.sendMessage(contents.first);
      final responseText = response.text;

      if (responseText != null) {
        setState(() {
          _messages.add({'role': 'gemini', 'text': responseText});
        });
      }
    } catch (e) {
      _showSnackBar('Terjadi kesalahan: $e', Colors.red);
    } finally {
      setState(() {
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  Future<void> _downloadResponse(String text) async {
    await Permission.storage.request();

    try {
      Directory? directory;
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download');
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      if (!await directory.exists()) {
        directory = await getDownloadsDirectory();
      }

      final fileName = 'Kajimini_Response_${DateTime.now().millisecondsSinceEpoch}.txt';
      final file = File('${directory!.path}/$fileName');
      
      await file.writeAsString(text);
      _showSnackBar('Berhasil disimpan di folder Download: $fileName', Colors.green);
    } catch (e) {
      _showSnackBar('Gagal menyimpan file: $e', Colors.red);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: const TextStyle(color: Colors.white)), backgroundColor: color),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kajimini', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        elevation: 0,
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isUser = message['role'] == 'user';
                final hasFile = message['file_path'] != null;

                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
                    decoration: BoxDecoration(
                      color: isUser ? Colors.teal[800] : Colors.grey[850],
                      borderRadius: BorderRadius.circular(16).copyWith(
                        bottomRight: isUser ? const Radius.circular(4) : null,
                        bottomLeft: !isUser ? const Radius.circular(4) : null,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (hasFile) ...[
                          Row(
                            children: [
                              const Icon(Icons.insert_drive_file, color: Colors.amberAccent, size: 18),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  message['file_path'].split('/').last,
                                  style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.amberAccent),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const Divider(),
                        ],
                        MarkdownBody(
                          data: message['text'] ?? '',
                          styleSheet: MarkdownStyleSheet(
                            p: const TextStyle(color: Colors.white, fontSize: 15),
                            code: const TextStyle(backgroundColor: Colors.black45, color: Colors.tealAccent),
                          ),
                        ),
                        if (!isUser) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.bottomRight,
                            child: IconButton(
                              icon: const Icon(Icons.download, size: 18, color: Colors.tealAccent),
                              onPressed: () => _downloadResponse(message['text'] ?? ''),
                              tooltip: 'Simpan Jawaban',
                            ),
                          )
                        ]
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(),
            ),
          if (_selectedFile != null)
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.amber.withOpacity(0.2),
              child: Row(
                children: [
                  const Icon(Icons.attach_file, color: Colors.amber),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Siap dikirim: ${_selectedFile!.path.split('/').last}')),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () => setState(() => _selectedFile = null),
                  )
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.all(12.0),
            color: Theme.of(context).colorScheme.surface,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.add_photo_alternate, color: Colors.tealAccent),
                  onPressed: _pickFile,
                ),
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: InputDecoration(
                      hintText: widget.apiKey.isEmpty ? 'Isi API Key di tab Pengaturan...' : 'Ketik pesan...',
                      filled: true,
                      fillColor: Colors.grey[900],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onSubmitted: _sendMessage,
                    enabled: widget.apiKey.isNotEmpty,
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: widget.apiKey.isNotEmpty ? Colors.teal : Colors.grey,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white),
                    onPressed: () => _sendMessage(_textController.text),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}