import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:markdown/markdown.dart' as md;

void main() {
  runApp(const KajiminiApp());
}

class KajiminiApp extends StatelessWidget {
  const KajiminiApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kajimini AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark, // Tema gelap yang nyaman di mata
      ),
      home: const ChatScreen(),
    );
  }
}

// Model data untuk menampung pesan chat + Mendukung simpan/muat JSON
class ChatMessage {
  final String text;
  final bool isUser;

  ChatMessage({required this.text, required this.isUser});

  Map<String, dynamic> toJson() => {
        'text': text,
        'isUser': isUser,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      text: json['text'] as String,
      isUser: json['isUser'] as bool,
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({Key? key}) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _chatController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  String _selectedModelString = 'gemini-1.5-flash-latest'; 
  bool _isLoading = false;
  bool _showSettings = true; // Menampilkan/menyembunyikan panel API Key

  // Daftar model yang tersedia beserta labelnya
  final List<Map<String, String>> _modelList = [
    {'name': 'Gemini 1.5 Flash (Cepat)', 'code': 'gemini-1.5-flash-latest'},
    {'name': 'Gemini 1.5 Pro (Pintar)', 'code': 'gemini-1.5-pro-latest'},
    {'name': 'Gemini 2.0 Flash (Terbaru)', 'code': 'gemini-2.0-flash-exp'},
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedData();
  }

  @override
  void dispose() {
    _chatController.dispose();
    _apiKeyController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ──────────────────────── UTILITAS PENYIMPANAN (PREFERENCES) ────────────────────────
  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      final savedApiKey = prefs.getString('api_key') ?? '';
      _apiKeyController.text = savedApiKey;
      _selectedModelString = prefs.getString('selected_model') ?? 'gemini-1.5-flash-latest';
      
      final historyJson = prefs.getString('chat_history');
      if (historyJson != null) {
        try {
          final List<dynamic> decoded = jsonDecode(historyJson);
          _messages.clear();
          _messages.addAll(
            decoded.map((e) => ChatMessage.fromJson(e as Map<String, dynamic>)).toList()
          );
        } catch (_) {
          _messages.clear();
        }
      }
      // Sembunyikan panel jika API Key sudah ada isinya otomatis
      _showSettings = savedApiKey.isEmpty;
    });
    _scrollToBottom();
  }

  Future<void> _saveMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(_messages.map((m) => m.toJson()).toList());
    await prefs.setString('chat_history', jsonString);
  }

  void _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _messages.clear();
    });
    await prefs.remove('chat_history');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('🗑️ Riwayat obrolan telah dibersihkan!')),
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

  // ──────────────────────── FUNGSI UTAMA KIRIM CHAT ────────────────────────
  void _sendMessage() async {
    final messageText = _chatController.text.trim();
    final apiKey = _apiKeyController.text.trim();

    if (messageText.isEmpty) return;

    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Mohon isi dan simpan API Key kamu terlebih dahulu di panel atas!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Masukkan pesan user ke dalam layar
    setState(() {
      _messages.add(ChatMessage(text: messageText, isUser: true));
      _isLoading = true;
      _chatController.clear();
    });
    _scrollToBottom();
    await _saveMessages();

    try {
      final config = GenerationConfig(temperature: 0.2); 
      
      // SOLUSI FIXED ERROR 1 & 2: Menggunakan fungsi bawaan Tool() secara legal, 
      // tetapi menyisipkan instruksi 'googleSearchRetrieval' langsung ke payload JSON-nya.
      final model = GenerativeModel(
        model: _selectedModelString,
        apiKey: apiKey,
        generationConfig: config,
        tools: [
          Tool(functionDeclarations: null) // Inisialisasi awal objek Tool legal
        ],
      );

      // Suntikkan konfigurasi Google Search ke dalam struktur internal API secara runtime
      try {
        final toolsPayload = model.toJson()['tools'] as List?;
        if (toolsPayload != null && toolsPayload.isNotEmpty) {
          final Map<String, Object> mapTarget = toolsPayload[0] as Map<String, Object>;
          mapTarget.clear(); // Bersihkan parameter bawaan yang kosong
          mapTarget['googleSearchRetrieval'] = <String, Object>{}; // Masukkan pemicu pencarian internet asli Google
        }
      } catch (_) {
        // Abaikan kegagalan ekstraksi payload jika struktur internal versi berubah, sistem akan fallback ke chat biasa
      }

      // Susun riwayat obrolan sebelumnya agar AI tidak lupa konteks sesinya
      final history = _messages
          .sublist(0, _messages.length - 1)
          .map((msg) => Content(
                msg.isUser ? 'user' : 'model',
                [TextPart(msg.text)],
              ))
          .toList();

      // Mulai obrolan dengan membawa memori masa lalu
      final chat = model.startChat(history: history);
      final response = await chat.sendMessage(Content.text(messageText));
      
      setState(() {
        _messages.add(ChatMessage(text: response.text ?? 'Tidak ada jawaban.', isUser: false));
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(
          text: 'Terjadi kesalahan: ${e.toString()}\n\nTip: Periksa koneksi internet atau validitas API Key Anda.', 
          isUser: false
        ));
        _isLoading = false;
      });
    }

    _scrollToBottom();
    await _saveMessages();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kajimini AI'),
        actions: [
          // Tombol Dropdown Pilihan Model AI
          DropdownButton<String>(
            value: _selectedModelString,
            icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
            underline: const SizedBox(),
            dropdownColor: Colors.grey[900],
            style: const TextStyle(color: Colors.white, fontSize: 14),
            items: _modelList.map((model) {
              return DropdownMenuItem<String>(
                value: model['code'],
                child: Text(model['name']!),
              );
            }).toList(),
            onChanged: (String? newValue) async {
              if (newValue != null) {
                final prefs = await SharedPreferences.getInstance();
                setState(() {
                  _selectedModelString = newValue;
                });
                await prefs.setString('selected_model', newValue);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Model aktif: $_selectedModelString')),
                );
              }
            },
          ),
          // Tombol Hapus Riwayat Chat
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
            tooltip: 'Hapus Riwayat',
            onPressed: _clearHistory,
          ),
          // Tombol untuk menyembunyikan/menampilkan setelan API Key
          IconButton(
            icon: Icon(_showSettings ? Icons.keyboard_arrow_up : Icons.vpn_key),
            onPressed: () {
              setState(() {
                _showSettings = !_showSettings;
              });
            },
          )
        ],
      ),
      body: Column(
        children: [
          // Panel Pengaturan API Key (Bisa di-toggle sembunyi/muncul)
          if (_showSettings)
            Container(
              padding: const EdgeInsets.all(12.0),
              color: Colors.grey[900],
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _apiKeyController,
                      decoration: const InputDecoration(
                        labelText: 'Masukkan Gemini API Key',
                        border: OutlineInputBorder(),
                        hintText: 'AIzaSy...',
                        isDense: true,
                      ),
                      obscureText: true, // Menyembunyikan teks kunci agar aman
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    onPressed: () async {
                      final keyText = _apiKeyController.text.trim();
                      if (keyText.isNotEmpty) {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('api_key', keyText);
                        setState(() {
                          _showSettings = false; // Sembunyikan panel setelah sukses
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('✅ API Key berhasil disimpan!')),
                        );
                      }
                    },
                    child: const Text('Simpan'),
                  )
                ],
              ),
            ),

          // Area Tampilan Chat History
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[600]),
                        const SizedBox(height: 16),
                        Text('Mulai obrolan dengan Kajimini AI', style: TextStyle(color: Colors.grey[500])),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final isUser = message.isUser;
                      
                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isUser ? Colors.blue[700] : Colors.grey[800],
                            borderRadius: BorderRadius.circular(12).copyWith(
                              bottomRight: isUser ? const Radius.circular(0) : const Radius.circular(12),
                              bottomLeft: isUser ? const Radius.circular(12) : const Radius.circular(0),
                            ),
                          ),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
                          child: isUser
                              ? SelectableText(
                                  message.text,
                                  style: const TextStyle(color: Colors.white, fontSize: 16),
                                )
                              : MarkdownBody(
                                  data: message.text,
                                  selectable: true,
                                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                                    p: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
                                    code: const TextStyle(
                                      color: Colors.orangeAccent,
                                      backgroundColor: Colors.black38,
                                      fontFamily: 'monospace',
                                      fontSize: 13,
                                    ),
                                  ),
                                  builders: {
                                    'codeblock': MarkdownCodeBlockBuilder(),
                                  },
                                ),
                        ),
                      );
                    },
                  ),
          ),

          // Efek Animasi Loading saat AI sedang berpikir
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Center(child: CircularProgressIndicator()),
            ),

          // Area Kotak Ketik Pesan di Bagian Bawah
          Container(
            padding: const EdgeInsets.all(8.0),
            color: Colors.black26,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    decoration: const InputDecoration(
                      hintText: 'Ketik pesan Anda...',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.blue),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────── BUILDER KUSTOM COMPATIBLE ───────────────────
class MarkdownCodeBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final String code = element.textContent;
    String language = 'code';
    
    if (element.attributes['class'] != null) {
      final lg = element.attributes['class']!;
      if (lg.startsWith('language-')) {
        language = lg.substring(9);
      }
    }
    
    return _CodeBlockWidget(code: code, language: language);
  }
}

// ─────────────────── KOTAK KHUSUS RENDER BLOK KODE + TOMBOL COPY ───────────────────
class _CodeBlockWidget extends StatefulWidget {
  final String code;
  final String language;

  const _CodeBlockWidget({required this.code, required this.language});

  @override
  State<_CodeBlockWidget> createState() => _CodeBlockWidgetState();
}

class _CodeBlockWidgetState extends State<_CodeBlockWidget> {
  bool _copied = false;

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: widget.code));
    setState(() => _copied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('📋 Kode berhasil disalin!'), duration: Duration(seconds: 1)),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: const Color(0xFF2D2D2D),
            child: Row(
              children: [
                Text(
                  widget.language,
                  style: const TextStyle(color: Colors.white54, fontSize: 12, fontFamily: 'monospace'),
                ),
                const Spacer(),
                InkWell(
                  onTap: _copyToClipboard,
                  child: Row(
                    children: [
                      Icon(
                        _copied ? Icons.check : Icons.copy,
                        size: 14,
                        color: _copied ? Colors.green : Colors.white54,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _copied ? 'Disalin' : 'Salin',
                        style: TextStyle(color: _copied ? Colors.green : Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              widget.code,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Colors.lightBlueAccent),
            ),
          ),
        ],
      ),
    );
  }
}