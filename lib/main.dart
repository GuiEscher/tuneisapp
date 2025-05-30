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
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:open_file/open_file.dart';
import 'package:intl/intl.dart';
import 'dart:typed_data';

void main() {
  runApp(MaterialApp(
    home: SplashScreen(),
    debugShowCheckedModeBanner: false,
  ));
}

class SplashScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Future.delayed(Duration(seconds: 3), () {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => TunnelInspectionApp()),
      );
    });

    return Scaffold(
      backgroundColor: Colors.deepPurpleAccent,
      body: Center(
        child: Text(
          "Túneis App",
          style: GoogleFonts.poppins(
            fontSize: 36,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
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
  String _serverUrl = "https://backendtuneisapp-fcue.onrender.com";
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

    const maxRetries = 3;
    const retryDelay = Duration(seconds: 5);
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
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
          
          if (response.headers['content-type']?.toLowerCase().contains('application/zip') ?? false) {
            final archive = ZipDecoder().decodeBytes(responseBody);
            final directory = await getApplicationDocumentsDirectory();
            
            var files = archive.files.where((file) => file.name.endsWith('.jpg')).toList();
            files.sort((a, b) => a.name.compareTo(b.name));
            
            for (final file in files) {
              final frameFile = File('${directory.path}/${file.name}');
              await frameFile.writeAsBytes(file.content);
              _processedFrames.add(frameFile);
              print("Frame ${file.name} salvo, tamanho: ${file.content.length} bytes");
            }
            
            setState(() {
              _totalFrames = int.tryParse(response.headers['frame-count'] ?? '') ?? _processedFrames.length;
              _video = null;
              _videoController?.dispose();
              _videoController = null;
            });
          } else {
            final directory = await getApplicationDocumentsDirectory();
            final filePath = '${directory.path}/processed_${DateTime.now().millisecondsSinceEpoch}.jpg';
            await File(filePath).writeAsBytes(responseBody);
            
            setState(() {
              _image = File(filePath);
              _video = null;
              _videoController?.dispose();
              _videoController = null;
              _processedFrames.add(_image!);
              print("Imagem processada salva, tamanho: ${responseBody.length} bytes");
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
          return; // Success, exit function
        } else {
          setState(() {
            _serverResponse = "Erro no servidor: ${response.statusCode}";
            _isLoading = false;
          });
          return; // Exit on non-200 status
        }
      } catch (e) {
        print("Tentativa $attempt falhou: $e");
        if (attempt == maxRetries) {
          setState(() {
            _serverResponse = "Erro na comunicação: ${e.toString()}";
            _isLoading = false;
          });
          return;
        }
        await Future.delayed(retryDelay);
      }
    }
  }

  Future<void> _generateReport() async {
    if (_detections.isEmpty && _processLogs.isEmpty && _processedFrames.isEmpty) {
      setState(() {
        _serverResponse = "Nenhuma análise realizada para gerar relatório!";
      });
      return;
    }

    final pdf = pw.Document();
    final date = DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now());
    final shortDate = DateFormat('dd/MM/yyyy').format(DateTime.now());

    // Load font for better styling
    final font = await pw.Font.ttf(await DefaultAssetBundle.of(context).load('assets/fonts/Poppins-Regular.ttf'));
    final boldFont = await pw.Font.ttf(await DefaultAssetBundle.of(context).load('assets/fonts/Poppins-Bold.ttf'));

    // Count detections by class
    final detectionCounts = <String, int>{};
    for (var detection in _detections) {
      final className = detection['class'] as String;
      detectionCounts[className] = (detectionCounts[className] ?? 0) + 1;
    }
    final totalDetections = _detections.length;

    // Build introduction text
    final introText = totalDetections > 0
        ? 'Na análise realizada no dia $shortDate, foram encontradas $totalDetections anomalias nas imagens processadas pelo Túneis App. '
          'O sistema identificou as seguintes condições: '
          '${detectionCounts.entries.map((e) => "${e.value} ocorrência(s) de ${e.key.toLowerCase()}").toList().asMap().entries.map((e) => e.key == detectionCounts.length - 1 ? e.value : "${e.value}, ").join("")}${detectionCounts.length > 1 ? "" : ""}. '
          'O Túneis App utiliza inteligência artificial avançada para detectar anomalias como umidade, corrosão e rachaduras em estruturas de túneis, '
          'fornecendo informações críticas para a manutenção preventiva e a segurança operacional. '
          'As detecções apresentadas neste relatório indicam áreas que requerem atenção imediata, com níveis de confiança associados a cada identificação. '
          'Recomenda-se uma inspeção detalhada por equipes técnicas para avaliar as condições identificadas e planejar ações corretivas.'
        : 'Na análise realizada no dia $shortDate, nenhuma anomalia foi detectada nas imagens processadas pelo Túneis App. '
          'O Túneis App emprega tecnologia de inteligência artificial para identificar anomalias como umidade, corrosão e rachaduras em túneis, '
          'garantindo a integridade estrutural por meio de monitoramento automatizado. '
          'A ausência de detecções neste relatório sugere que a seção inspecionada está em condições adequadas, mas recomenda-se a continuidade das inspeções regulares.';

    // Load all processed frames
    final frameProviders = <pw.ImageProvider>[];
    for (var frame in _processedFrames) {
      try {
        final imageBytes = await frame.readAsBytes();
        frameProviders.add(pw.MemoryImage(imageBytes));
        print("Frame adicionado ao PDF, tamanho: ${imageBytes.length} bytes");
      } catch (e) {
        print("Erro ao carregar frame para PDF: $e");
        _processLogs.add("Erro ao carregar frame ${frame.path}: $e");
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return [
            // Header
            pw.Container(
              padding: pw.EdgeInsets.all(20),
              color: PdfColors.deepPurple,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text(
                    'Túneis App - Relatório de Análise',
                    style: pw.TextStyle(
                      font: boldFont,
                      fontSize: 24,
                      color: PdfColors.white,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    date,
                    style: pw.TextStyle(
                      font: font,
                      fontSize: 12,
                      color: PdfColors.white,
                      fontStyle: pw.FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // Introduction
            pw.Text(
              'Introdução',
              style: pw.TextStyle(
                font: boldFont,
                fontSize: 18,
                color: PdfColors.deepPurple,
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              introText,
              style: pw.TextStyle(
                font: font,
                fontSize: 12,
                lineSpacing: 1.5,
              ),
              textAlign: pw.TextAlign.justify,
            ),
            pw.SizedBox(height: 20),

            // Analysis Results
            pw.Text(
              'Resultados da Análise',
              style: pw.TextStyle(
                font: boldFont,
                fontSize: 18,
                color: PdfColors.deepPurple,
              ),
            ),
            pw.SizedBox(height: 10),
            if (_detections.isNotEmpty)
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      pw.Padding(
                        padding: pw.EdgeInsets.all(8),
                        child: pw.Text('Classe', style: pw.TextStyle(font: boldFont)),
                      ),
                      pw.Padding(
                        padding: pw.EdgeInsets.all(8),
                        child: pw.Text('Confiança', style: pw.TextStyle(font: boldFont)),
                      ),
                    ],
                  ),
                  ..._detections.map((detection) => pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: pw.EdgeInsets.all(8),
                            child: pw.Text(detection['class'], style: pw.TextStyle(font: font)),
                          ),
                          pw.Padding(
                            padding: pw.EdgeInsets.all(8),
                            child: pw.Text(
                              '${(detection['confidence'] * 100).toStringAsFixed(1)}%',
                              style: pw.TextStyle(font: font),
                            ),
                          ),
                        ],
                      )),
                ],
              )
            else
              pw.Text(
                'Nenhuma detecção encontrada.',
                style: pw.TextStyle(font: font, fontSize: 14),
              ),
            pw.SizedBox(height: 20),

            // Processed Images
            if (frameProviders.isNotEmpty) ...[
              pw.Text(
                _processedFrames.length > 1 ? 'Imagens Processadas' : 'Imagem Processada',
                style: pw.TextStyle(
                  font: boldFont,
                  fontSize: 18,
                  color: PdfColors.deepPurple,
                ),
              ),
              pw.SizedBox(height: 10),
              ...frameProviders.asMap().entries.map((entry) {
                final index = entry.key;
                final provider = entry.value;
                return pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      _processedFrames.length > 1 ? 'Frame ${index + 1}' : 'Imagem',
                      style: pw.TextStyle(
                        font: boldFont,
                        fontSize: 14,
                      ),
                    ),
                    pw.SizedBox(height: 5),
                    pw.Image(
                      provider,
                      width: 300,
                      height: 200,
                      fit: pw.BoxFit.contain,
                    ),
                    pw.SizedBox(height: 20),
                  ],
                );
              }).toList(),
            ],

            // Processing Logs
            pw.Text(
              'Logs de Processamento',
              style: pw.TextStyle(
                font: boldFont,
                fontSize: 18,
                color: PdfColors.deepPurple,
              ),
            ),
            pw.SizedBox(height: 10),
            if (_processLogs.isNotEmpty)
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: _processLogs.map((log) => pw.Padding(
                      padding: pw.EdgeInsets.only(bottom: 5),
                      child: pw.Text(
                        log,
                        style: pw.TextStyle(
                          font: font,
                          fontSize: 12,
                          color: log.contains('Erro') ? PdfColors.red : PdfColors.black,
                        ),
                      ),
                    )).toList(),
              )
            else
              pw.Text(
                'Nenhum log disponível.',
                style: pw.TextStyle(font: font, fontSize: 14),
              ),
          ];
        },
      ),
    );

    // Save and open the PDF
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/tuneisapp_report_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());
    await OpenFile.open(filePath);

    setState(() {
      _serverResponse = "Relatório gerado com sucesso!";
    });
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
                ElevatedButton.icon(
                  icon: Icon(Icons.camera_alt),
                  label: Text('Foto'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _captureImage,
                ),
                ElevatedButton.icon(
                  icon: Icon(Icons.photo_library),
                  label: Text('Galeria'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _pickImageFromGallery,
                ),
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
            
            ElevatedButton(
              child: Text('Gerar Relatório'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurpleAccent,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 15),
              ),
              onPressed: _generateReport,
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
          child: FutureBuilder<Uint8List>(
            future: _processedFrames[_currentFrameIndex].readAsBytes(),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return Image.memory(
                  snapshot.data!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  errorBuilder: (context, error, stackTrace) {
                    print("Erro ao renderizar frame: $error");
                    return Center(child: Text("Erro ao carregar frame"));
                  },
                );
              } else if (snapshot.hasError) {
                print("Erro ao carregar bytes do frame: ${snapshot.error}");
                return Center(child: Text("Erro ao carregar frame"));
              }
              return Center(child: CircularProgressIndicator());
            },
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