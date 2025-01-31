import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'splash_screen.dart';

void main() {
  runApp(MaterialApp(
    home: SplashScreen(),
    debugShowCheckedModeBanner: false,
  ));
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  File? _image;
  final ImagePicker _picker = ImagePicker();

  final Map<String, double> categoryMap = {
    "fissura": 0.0,
    "infiltração": 1.0,
    "erosão": 2.0,
  };

  Future<void> _captureImage() async {
    try {
      final XFile? pickedFile = 
          await _picker.pickImage(source: ImageSource.camera);
      if (pickedFile != null) {
        setState(() {
          _image = File(pickedFile.path);
        });
        print("Imagem capturada: ${pickedFile.path}");
      }
    } catch (e) {
      print("Erro ao capturar a imagem: $e");
    }
  }

  Future<void> _runModel() async {
    if (_image == null) {
      print("Nenhuma imagem selecionada!");
      return;
    }

    try {
      Uint8List imageBytes = await _image!.readAsBytes();
      print("Imagem convertida em bytes: ${imageBytes.length} bytes");

      List<String> categories = ["fissura", "infiltração", "erosão"];
      List<double> inputList =
          categories.map((c) => categoryMap[c] ?? -1.0).toList();
      Float32List input = Float32List.fromList(inputList);

      print("Entrada numérica do modelo: $input");

      var output = categories[0];
      print("Resultado simulado: $output");
    } catch (e) {
      print("Erro ao processar a imagem para o modelo: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    Color buttonTextColor = Colors.purple; // Cor do texto do botão

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text("Túneis app - Inspeção")),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _image != null
                  ? Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: buttonTextColor, width: 4),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.file(
                          _image!,
                          width: 300,
                          height: 300,
                          fit: BoxFit.cover,
                        ),
                      ),
                    )
                  : Text("Nenhuma imagem capturada"),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _captureImage,
                style: ElevatedButton.styleFrom(
                  foregroundColor: buttonTextColor, // Cor do texto
                ),
                child: Text("Tirar Foto"),
              ),
              SizedBox(height: 10),
              ElevatedButton(
                onPressed: _runModel,
                style: ElevatedButton.styleFrom(
                  foregroundColor: buttonTextColor, // Cor do texto
                ),
                child: Text("Executar Modelo"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
