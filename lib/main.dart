import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

void main() {
  runApp(MaterialApp(
    home: TunnelInspectionApp(),
    debugShowCheckedModeBanner: false,
  ));
}

class TunnelInspectionApp extends StatefulWidget {
  @override
  _TunnelInspectionAppState createState() => _TunnelInspectionAppState();
}

class _TunnelInspectionAppState extends State<TunnelInspectionApp> {
  File? _image;
  File? _video;
  final ImagePicker _picker = ImagePicker();
  String _serverResponse = "Aguardando ação...";
  bool _isLoading = false;
  List<dynamic> _detections = [];
  String _serverUrl = "http://192.168.0.17:5000";
  VideoPlayerController? _videoController;
  bool _isVideoPlaying = false;

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _captureImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(source: ImageSource.camera);
      if (pickedFile != null) {
        setState(() {
          _image = File(pickedFile.path);
          _video = null;
          _videoController?.dispose();
          _videoController = null;
          _serverResponse = "Imagem capturada. Pronto para análise.";
          _detections = [];
        });
      }
    } catch (e) {
      setState(() {
        _serverResponse = "Erro ao capturar imagem: ${e.toString()}";
      });
    }
  }

  Future<void> _captureVideo() async {
    try {
      final XFile? pickedFile = await _picker.pickVideo(source: ImageSource.camera);
      if (pickedFile != null) {
        setState(() {
          _video = File(pickedFile.path);
          _image = null;
          _initializeVideoPlayer();
          _serverResponse = "Vídeo capturado. Pronto para análise.";
          _detections = [];
        });
      }
    } catch (e) {
      setState(() {
        _serverResponse = "Erro ao capturar vídeo: ${e.toString()}";
      });
    }
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        setState(() {
          _image = File(pickedFile.path);
          _video = null;
          _videoController?.dispose();
          _videoController = null;
          _serverResponse = "Imagem selecionada. Pronto para análise.";
          _detections = [];
        });
      }
    } catch (e) {
      setState(() {
        _serverResponse = "Erro ao selecionar imagem: ${e.toString()}";
      });
    }
  }

  Future<void> _pickVideoFromGallery() async {
    try {
      final XFile? pickedFile = await _picker.pickVideo(source: ImageSource.gallery);
      if (pickedFile != null) {
        setState(() {
          _video = File(pickedFile.path);
          _image = null;
          _initializeVideoPlayer();
          _serverResponse = "Vídeo selecionado. Pronto para análise.";
          _detections = [];
        });
      }
    } catch (e) {
      setState(() {
        _serverResponse = "Erro ao selecionar vídeo: ${e.toString()}";
      });
    }
  }

  void _initializeVideoPlayer() {
    if (_video != null) {
      _videoController = VideoPlayerController.file(_video!)
        ..initialize().then((_) {
          setState(() {});
        });
    }
  }

  void _toggleVideoPlayback() {
    if (_videoController != null) {
      if (_isVideoPlaying) {
        _videoController?.pause();
      } else {
        _videoController?.play();
      }
      setState(() {
        _isVideoPlaying = !_isVideoPlaying;
      });
    }
  }

  Future<void> _analyzeImage() async {
    if (_image == null && _video == null) {
      setState(() {
        _serverResponse = "Nenhuma mídia selecionada!";
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _serverResponse = "Processando...";
    });

    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$_serverUrl/detect'),
      );

      if (_image != null) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'file',
            _image!.path,
            contentType: MediaType('image', 'jpeg'),
          ),
        );
      } else if (_video != null) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'file',
            _video!.path,
            contentType: MediaType('video', 'mp4'),
          ),
        );
      }

      var response = await request.send();

      if (response.statusCode == 200) {
        final responseBody = await response.stream.toBytes();
        
        // Verifica se a resposta é uma imagem (JPEG) ou JSON
        if (_isImageResponse(response.headers['content-type'])) {
          final directory = await getApplicationDocumentsDirectory();
          final filePath = '${directory.path}/processed_${DateTime.now().millisecondsSinceEpoch}.jpg';
          await File(filePath).writeAsBytes(responseBody);
          
          setState(() {
            _image = File(filePath);
            _video = null;
            _videoController?.dispose();
            _videoController = null;
          });
        }

        final detectionsHeader = response.headers['detections'];
        if (detectionsHeader != null) {
          try {
            setState(() {
              _detections = json.decode(detectionsHeader);
            });
          } catch (e) {
            print("Erro ao decodificar detecções: $e");
          }
        }

        setState(() {
          _serverResponse = "Análise concluída com sucesso!";
          _isLoading = false;
        });
      } else {
        setState(() {
          _serverResponse = "Erro no servidor: ${response.statusCode}";
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _serverResponse = "Erro na comunicação: ${e.toString()}";
        _isLoading = false;
      });
      print("Erro detalhado: $e");
    }
  }

  bool _isImageResponse(String? contentType) {
    return contentType?.toLowerCase().contains('image/jpeg') ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Inspeção de Túneis'),
        backgroundColor: Colors.deepPurple,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Exibição de mídia
            Container(
              height: 300,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.deepPurple, width: 2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: _buildMediaPreview(),
            ),
            SizedBox(height: 20),
            
            // Botões de captura
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  children: [
                    ElevatedButton.icon(
                      icon: Icon(Icons.camera_alt),
                      label: Text('Foto'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _captureImage,
                    ),
                    SizedBox(height: 5),
                    ElevatedButton.icon(
                      icon: Icon(Icons.videocam),
                      label: Text('Vídeo'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _captureVideo,
                    ),
                  ],
                ),
                Column(
                  children: [
                    ElevatedButton.icon(
                      icon: Icon(Icons.photo_library),
                      label: Text('Galeria'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _pickImageFromGallery,
                    ),
                    SizedBox(height: 5),
                    ElevatedButton.icon(
                      icon: Icon(Icons.video_library),
                      label: Text('Vídeos'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _pickVideoFromGallery,
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: 20),
            
            // Controles de vídeo (se aplicável)
            if (_videoController != null && _videoController!.value.isInitialized)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: Icon(_isVideoPlaying ? Icons.pause : Icons.play_arrow),
                    onPressed: _toggleVideoPlayback,
                    color: Colors.deepPurple,
                  ),
                  Text(
                    'Duração: ${_videoController!.value.duration.toString().split('.').first}',
                    style: TextStyle(color: Colors.deepPurple),
                  ),
                ],
              ),
            
            // Botão de análise
            ElevatedButton(
              child: _isLoading
                  ? CircularProgressIndicator(color: Colors.white)
                  : Text('Analisar Mídia'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 15),
              ),
              onPressed: _isLoading ? null : _analyzeImage,
            ),
            SizedBox(height: 20),
            
            // Resultados
            Card(
              elevation: 4,
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resultado:',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(_serverResponse),
                    SizedBox(height: 20),
                    if (_detections.isNotEmpty) ...[
                      Text(
                        'Detecções:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 10),
                      ..._detections.map((detection) => ListTile(
                        leading: Container(
                          width: 20,
                          height: 20,
                          color: _getColorForDetection(detection['class']),
                        ),
                        title: Text(
                          "${detection['class']} (${(detection['confidence'] * 100).toStringAsFixed(1)}%)",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          "Área: ${detection['area'].toStringAsFixed(0)} px²",
                        ),
                      )).toList(),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaPreview() {
    if (_image != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          _image!,
          fit: BoxFit.cover,
          width: double.infinity,
        ),
      );
    } else if (_videoController != null && _videoController!.value.isInitialized) {
      return AspectRatio(
        aspectRatio: _videoController!.value.aspectRatio,
        child: VideoPlayer(_videoController!),
      );
    } else {
      return Center(
        child: Text(
          'Nenhuma mídia selecionada',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
  }

  Color _getColorForDetection(String className) {
    switch (className.toLowerCase()) {
      case 'umidade':
        return Colors.green;
      case 'corrosão':
        return Colors.blue;
      case 'rachadura':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}