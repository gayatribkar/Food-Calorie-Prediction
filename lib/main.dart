import 'dart:io';
import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_markdown/flutter_markdown.dart'; 
import 'package:speech_to_text/speech_to_text.dart' as stt;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Image Picker Example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  File? _imageFile;
  final List<Map<String, String>> _messages = []; 
  final TextEditingController _controller = TextEditingController();
  bool _isTyping = false;
  bool _isListening = false;
  stt.SpeechToText? _speechToText;
  Timer? _timeoutTimer; // Timer to handle pause duration

  @override
  void initState() {
    super.initState();
    _speechToText = stt.SpeechToText();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    bool available = await _speechToText!.initialize();
    if (available) {
      setState(() {});
    }
  }

  Future<void> _startListening() async {
    setState(() {
      _isListening = true;
    });

    _speechToText!.listen(
      onResult: (result) {
        setState(() {
          _controller.text = result.recognizedWords;
        });

        // Restart the timeout timer on every result to handle pauses
        _restartTimeoutTimer();
      },
      onSoundLevelChange: (level) {},
    );
  }

  Future<void> _stopListening() async {
    setState(() {
      _isListening = false;
    });

    _speechToText!.stop();

    _timeoutTimer?.cancel();
  }

  void _restartTimeoutTimer() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 5), () {
      if (_isListening) {
        _stopListening();
      }
    });
  }

  Future<void> _pickImage() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Image Source'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo),
              title: const Text('Gallery'),
              onTap: () async {
                Navigator.pop(context);
                final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
                if (pickedFile != null) {
                  setState(() {
                    _imageFile = File(pickedFile.path);
                    _messages.clear(); 
                  });
                  _uploadImageAndFetchResponse(_imageFile!);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera),
              title: const Text('Camera'),
              onTap: () async {
                Navigator.pop(context);
                final pickedFile = await ImagePicker().pickImage(source: ImageSource.camera);
                if (pickedFile != null) {
                  setState(() {
                    _imageFile = File(pickedFile.path);
                    _messages.clear(); 
                  });
                  _uploadImageAndFetchResponse(_imageFile!);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _uploadImageAndFetchResponse(File imageFile) async {
    try {
      setState(() {
        _isTyping = true;
      });

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('http://192.168.0.153:5000/analyze-image'),
      );

      request.files.add(
        await http.MultipartFile.fromPath(
          'image',
          imageFile.path,
        ),
      );

      var response = await request.send();

      if (response.statusCode == 200) {
        var responseBody = await response.stream.bytesToString();
        var decodedResponse = json.decode(responseBody);

        // Extract the message content
        var messageContent = decodedResponse['choices'][0]['message']['content'];

        setState(() {
          _messages.add({"role": "assistant", "content": messageContent});
          _isTyping = false;
        });
      } else {
        print('Failed with status code: ${response.statusCode}');
        setState(() {
          _isTyping = false;
        });
      }
    } catch (e) {
      print('Error uploading image: $e');
      setState(() {
        _isTyping = false;
      });
    }
  }

  Future<void> _sendMessage(String message) async {
    setState(() {
      _messages.add({"role": "user", "content": message});
      _isTyping = true;
    });

    try {
      var response = await http.post(
        Uri.parse('http://192.168.0.153:5000/chat'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({"message": message}),
      );

      if (response.statusCode == 200) {
        var decodedResponse = json.decode(response.body);
        var messageContent = decodedResponse['choices'][0]['message']['content'];

        setState(() {
          _messages.add({"role": "assistant", "content": messageContent});
          _isTyping = false;
        });
      } else {
        print('Failed with status code: ${response.statusCode}');
        setState(() {
          _isTyping = false;
        });
      }
    } catch (e) {
      print('Error sending message: $e');
      setState(() {
        _isTyping = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calorie App'),
      ),
      body: Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: Column(
          children: <Widget>[
            if (_imageFile != null)
              Image.file(
                _imageFile!,
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height * 0.2,
                fit: BoxFit.contain,
              ),
            ElevatedButton(
              onPressed: _pickImage,
              child: const Text('Pick Image'),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _messages.length + (_isTyping ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _messages.length && _isTyping) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text("Typing..."),
                      ),
                    );
                  }

                  var message = _messages[index];
                  return Align(
                    alignment: message['role'] == 'user' ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 15),
                      decoration: BoxDecoration(
                        color: message['role'] == 'user' ? Colors.blue[100] : Colors.grey[300],
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: MarkdownBody(data: message['content']!),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10.0),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(hintText: 'Type your message here...'),
                    ),
                  ),
                  IconButton(
                    icon: Icon(_isListening ? Icons.stop : Icons.mic),
                    onPressed: () {
                      if (_isListening) {
                        _stopListening();
                      } else {
                        _startListening();
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: () {
                      if (_controller.text.isNotEmpty) {
                        _sendMessage(_controller.text);
                        _controller.clear();
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
