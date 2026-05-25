import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gemini Super App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.cyan,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const String _apiKey = String.fromEnvironment('API_KEY');
  
  late final GenerativeModel _model;
  late final ChatSession _chatSession;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  final List<Map<String, dynamic>> _messages = [];
  bool _isLoading = false;
  File? _selectedFile;

  @override
  void initState() {
    super.initState();
    // PERBAIKAN: Menghapus tools GoogleSearchRetrieval karena belum didukung SDK Dart saat ini
    _model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: _apiKey,
    );
    _chatSession = _model.startChat();
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
    if (_apiKey.isEmpty) {
      _showSnackBar('API Key tidak ditemukan!', Colors.red);
      return;
    }

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

      final response = await _chatSession.sendMessage(contents.first);
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

      final fileName = 'Gemini_Response_${DateTime.now().millisecondsSinceEpoch}.txt';
      final file = File('${directory!.path}/$fileName');
      
      await file.writeAsString(text);
      _showSnackBar('File berhasil disimpan di folder Download: $fileName', Colors.green);
    } catch (e) {
      _showSnackBar('Gagal menyimpan file: $e', Colors.red);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
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
        title: const Text('Gemini Super App', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 2,
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
                      color: isUser ? Colors.cyan[700] : Colors.grey[850],
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (hasFile) ...[
                          Row(
                            children: [
                              const Icon(Icons.insert_drive_file, color: Colors.amber, size: 18),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  message['file_path'].split('/').last,
                                  style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.amber),
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
                          ),
                        ),
                        if (!isUser) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.bottomRight,
                            child: IconButton(
                              icon: const Icon(Icons.download, size: 18, color: Colors.cyanAccent),
                              onPressed: () => _downloadResponse(message['text'] ?? ''),
                              tooltip: 'Simpan Jawaban ke HP (.txt)',
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
            padding: const EdgeInsets.all(8.0),
            color: Theme.of(context).colorScheme.surface,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.add_photo_alternate, color: Colors.cyanAccent),
                  onPressed: _pickFile,
                  tooltip: 'Pilih File/Gambar',
                ),
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: InputDecoration(
                      hintText: 'Tanyakan apa saja (Teks/Gambar)...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onSubmitted: _sendMessage,
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: Colors.cyan,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.black),
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
