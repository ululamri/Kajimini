import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

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

// Model data untuk menampung pesan chat
class ChatMessage {
  final String text;
  final bool isUser;

  ChatMessage({required this.text, required this.isUser});
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
  
  // Model string resmi dan paling stabil dari Google
  String _selectedModelString = 'gemini-1.5-flash-latest'; 
  bool _isLoading = false;
  bool _showSettings = true; // Menampilkan/menyembunyikan panel API Key

  // Daftar model yang tersedia beserta labelnya
  final List<Map<String, String>> _modelList = [
    {'name': 'Gemini 1.5 Flash (Cepat)', 'code': 'gemini-1.5-flash-latest'},
    {'name': 'Gemini 1.5 Pro (Pintar)', 'code': 'gemini-1.5-pro-latest'},
    {'name': 'Gemini 2.0 Flash (Terbaru)', 'code': 'gemini-2.0-flash-exp'},
  ];

  // Fungsi Utama untuk mengirim pesan ke Server Google Gemini
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

    try {
      // Inisialisasi model secara dinamis sesuai pilihan Dropdown
      final model = GenerativeModel(
        model: _selectedModelString,
        apiKey: apiKey,
      );

      // Kirim data ke Google AI
      final response = await model.generateContent([Content.text(messageText)]);
      
      setState(() {
        _messages.add(ChatMessage(text: response.text ?? 'Tidak ada jawaban.', isUser: false));
        _isLoading = false;
      });
    } catch (e) {
      // Jika terjadi kesalahan (seperti SocketException atau API Key salah)
      setState(() {
        _messages.add(ChatMessage(
          text: 'Terjadi kesalahan: ${e.toString()}\n\nTip: Periksa koneksi internet atau validitas API Key Anda.', 
          isUser: false
        ));
        _isLoading = false;
      });
    }
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
            onChanged: (String? newValue) {
              setState(() {
                if (newValue != null) {
                  _selectedModelString = newValue;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Model aktif: $_selectedModelString')),
                  );
                }
              });
            },
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
                    onPressed: () {
                      if (_apiKeyController.text.trim().isNotEmpty) {
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
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      return Align(
                        alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: message.isUser ? Colors.blue[700] : Colors.grey[800],
                            borderRadius: BorderRadius.circular(12).copyWith(
                              bottomRight: message.isUser ? const Radius.circular(0) : const Radius.circular(12),
                              bottomLeft: message.isUser ? const Radius.circular(12) : const Radius.circular(0),
                            ),
                          ),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                          child: Text(
                            message.text,
                            style: const TextStyle(color: Colors.white, fontSize: 16),
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