import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:photo_view/photo_view.dart';
import 'package:archive/archive.dart';

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
  String _serverUrl = "http://192.168.0.11:5000";
  VideoPlayerController? _videoController;
  bool _isVideoPlaying = false;
  List<File> _processedFrames = [];
  int _currentFrameIndex = 0;
  List<String> _processLogs = [];
  int _totalFrames = 0;

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
          _processedFrames.clear();
          _currentFrameIndex = 0;
          _processLogs.clear();
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
          _processedFrames.clear();
          _currentFrameIndex = 0;
          _processLogs.clear();
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
          _processedFrames.clear();
          _currentFrameIndex = 0;
          _processLogs.clear();
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
          _processedFrames.clear();
          _currentFrameIndex = 0;
          _processLogs.clear();
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
      _processedFrames.clear();
      _currentFrameIndex = 0;
      _processLogs.clear();
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
        
        // Verifica se é um vídeo (retorna ZIP) ou imagem (retorna JPEG)
        if (response.headers['content-type']?.toLowerCase().contains('application/zip') ?? false) {
          // Processamento de vídeo - extrai frames do ZIP
          final archive = ZipDecoder().decodeBytes(responseBody);
          final directory = await getApplicationDocumentsDirectory();
          
          // Ordena os arquivos pelo nome para manter a ordem dos frames
          var files = archive.files.where((file) => file.name.endsWith('.jpg')).toList();
          files.sort((a, b) => a.name.compareTo(b.name));
          
          for (final file in files) {
            final frameFile = File('${directory.path}/${file.name}');
            await frameFile.writeAsBytes(file.content);
            _processedFrames.add(frameFile);
          }
          
          setState(() {
            _totalFrames = int.tryParse(response.headers['frame-count'] ?? '') ?? _processedFrames.length;
            _video = null;
            _videoController?.dispose();
            _videoController = null;
          });
        } else {
          // Processamento de imagem normal
          final directory = await getApplicationDocumentsDirectory();
          final filePath = '${directory.path}/processed_${DateTime.now().millisecondsSinceEpoch}.jpg';
          await File(filePath).writeAsBytes(responseBody);
          
          setState(() {
            _image = File(filePath);
            _video = null;
            _videoController?.dispose();
            _videoController = null;
            _processedFrames.add(_image!);
          });
        }

        // Processa as detecções
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

        // Processa os logs
        final logsHeader = response.headers['logs'];
        if (logsHeader != null) {
          try {
            setState(() {
              _processLogs = List<String>.from(json.decode(logsHeader));
            });
          } catch (e) {
            print("Erro ao decodificar logs: $e");
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

  void _showFullScreenImage(File imageFile) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text('Visualização Ampliada'),
          ),
          body: PhotoView(
            imageProvider: FileImage(imageFile),
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 2,
          ),
        ),
      ),
    );
  }

  void _showNextFrame() {
    if (_processedFrames.isNotEmpty && _currentFrameIndex < _processedFrames.length - 1) {
      setState(() {
        _currentFrameIndex++;
      });
    }
  }

  void _showPreviousFrame() {
    if (_processedFrames.isNotEmpty && _currentFrameIndex > 0) {
      setState(() {
        _currentFrameIndex--;
      });
    }
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
            Container(
              height: 300,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.deepPurple, width: 2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: _buildMediaPreview(),
            ),
            SizedBox(height: 10),
            
            if (_processedFrames.length > 1)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back),
                    onPressed: _showPreviousFrame,
                    color: Colors.deepPurple,
                  ),
                  Text(
                    'Frame ${_currentFrameIndex + 1} de ${_processedFrames.length}',
                    style: TextStyle(color: Colors.deepPurple),
                  ),
                  IconButton(
                    icon: Icon(Icons.arrow_forward),
                    onPressed: _showNextFrame,
                    color: Colors.deepPurple,
                  ),
                ],
              ),
            
            SizedBox(height: 10),
            
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
            SizedBox(height: 10),
            
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
            SizedBox(height: 10),
            
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
            
            if (_processLogs.isNotEmpty) ...[
              SizedBox(height: 20),
              Card(
                elevation: 4,
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Logs do Processamento:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurple,
                        ),
                      ),
                      SizedBox(height: 10),
                      Container(
                        height: 150,
                        child: ListView.builder(
                          itemCount: _processLogs.length,
                          itemBuilder: (context, index) {
                            return Padding(
                              padding: EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                _processLogs[index],
                                style: TextStyle(
                                  fontFamily: 'monospace', 
                                  fontSize: 12,
                                  color: _processLogs[index].contains('Erro') ? Colors.red : Colors.black,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMediaPreview() {
    if (_processedFrames.isNotEmpty) {
      return GestureDetector(
        onTap: () => _showFullScreenImage(_processedFrames[_currentFrameIndex]),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            _processedFrames[_currentFrameIndex],
            fit: BoxFit.cover,
            width: double.infinity,
          ),
        ),
      );
    } else if (_image != null) {
      return GestureDetector(
        onTap: () => _showFullScreenImage(_image!),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            _image!,
            fit: BoxFit.cover,
            width: double.infinity,
          ),
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