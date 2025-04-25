#!/usr/bin/env python3

from ultralytics import YOLO
import cv2 as cv
import numpy as np
from flask import Flask, request, jsonify, Response
import threading
import time
from werkzeug.serving import make_server
import io
from PIL import Image as PILImage
import os

# Carregando o modelo treinado
model_path = r"D:\tuneisappflutter\tuneisappflutter\server\18-12-24-Model-best (2).pt"
if not os.path.exists(model_path):
    raise FileNotFoundError(f"Model file not found at: {model_path}")

model = YOLO(model_path)

# Dicionário de mapeamento das classes
label_dict = model.names

# Cores para diferenciar cada classe
class_colors = {
    0: (0, 255, 0),    # Umidade
    1: (0, 0, 255),    # Corrosão
    2: (255, 0, 0),    # Rachadura
}

app = Flask(__name__)

# Variável global para armazenar o estado da câmera
camera = None
processing_lock = threading.Lock()

def initialize_camera():
    global camera
    camera = cv.VideoCapture(0)
    if not camera.isOpened():
        raise RuntimeError("Não foi possível abrir a câmera")

def process_frame(frame):
    results = model(frame)  # Realiza a predição no frame
    detections = []
    
    for result in results:
        for box in result.boxes:
            cls = int(box.cls)  # Classe do objeto detectado
            conf = float(box.conf)  # Confiança da detecção
            if conf < 0.3:
                continue  # Ignora detecções com baixa confiança

            # Calcular a área da caixa delimitadora
            x_center, y_center, width, height = map(float, box.xywhn[0])
            width_total = width * frame.shape[1]
            height_total = height * frame.shape[0]
            area = width_total * height_total

            # Convertendo coordenadas normalizadas para pixels
            x1 = int((x_center * frame.shape[1]) - width_total / 2)
            y1 = int((x_center * frame.shape[0]) - height_total / 2)
            x2 = int((x_center * frame.shape[1]) + width_total / 2)
            y2 = int((x_center * frame.shape[0]) + height_total / 2)
            
            label = label_dict.get(cls, f"Classe {cls}") 
            color = class_colors.get(cls, (255, 255, 255)) 
            label_text = f"{label} ({conf:.2f})"

            # Desenha a caixa delimitadora
            cv.rectangle(frame, (x1, y1), (x2, y2), color, 2)
            cv.putText(frame, label_text, (x1, y1 - 5), cv.FONT_HERSHEY_SIMPLEX, 0.6, color, 2)

            # Processamento da máscara (com tratamento de erro aprimorado)
            mask = result.masks
            if mask is not None and mask.data is not None:
                try:
                    binary_mask = mask.data[0].cpu().numpy().astype(np.uint8)
                    color_mask = np.zeros_like(frame, dtype=np.uint8)
                    color_mask[:, :] = color
                    mask_applied = cv.bitwise_and(color_mask, color_mask, mask=binary_mask)
                    frame = np.where(mask_applied > 0, cv.addWeighted(frame, 0.7, mask_applied, 0.3, 0), frame)
                except Exception as e:
                    print(f"Erro ao aplicar máscara (não crítico): {e}")

            detections.append({
                "class": label,
                "confidence": conf,
                "x_center": x_center,
                "y_center": y_center,
                "width": width,
                "height": height,
                "area": area
            })
    
    return frame, detections

@app.route('/capture', methods=['GET'])
def capture():
    global camera
    
    if camera is None:
        initialize_camera()
    
    with processing_lock:
        ret, frame = camera.read()
        if not ret:
            return jsonify({"error": "Falha ao capturar frame da câmera"}), 500
        
        processed_frame, detections = process_frame(frame.copy())
        
        # Converter frame para JPEG
        ret, jpeg = cv.imencode('.jpg', processed_frame)
        if not ret:
            return jsonify({"error": "Falha ao codificar imagem"}), 500
        
        # Criar resposta com imagem e dados JSON
        img_io = io.BytesIO(jpeg.tobytes())
        
        return Response(
            img_io.getvalue(),
            mimetype='image/jpeg',
            headers={
                'Detections': str(detections),
                'Access-Control-Expose-Headers': 'Detections'
            }
        )

@app.route('/detect', methods=['POST'])
def detect():
    if 'file' not in request.files:
        return jsonify({"error": "Nenhum arquivo enviado"}), 400
    
    file = request.files['file']
    if file.filename == '':
        return jsonify({"error": "Nenhum arquivo selecionado"}), 400
    
    try:
        # Verifica se é vídeo ou imagem
        is_video = file.filename.lower().endswith(('.mp4', '.avi', '.mov'))
        
        if is_video:
            # Processamento de vídeo (apenas primeiro frame)
            temp_dir = os.path.join(os.path.dirname(__file__), 'temp')
            os.makedirs(temp_dir, exist_ok=True)
            temp_video_path = os.path.join(temp_dir, file.filename)
            file.save(temp_video_path)
            
            cap = cv.VideoCapture(temp_video_path)
            ret, frame = cap.read()
            if not ret:
                return jsonify({"error": "Falha ao ler vídeo"}), 500
            cap.release()
            
            # Remove o arquivo temporário
            os.remove(temp_video_path)
        else:
            # Processamento de imagem
            img_bytes = file.read()
            frame = cv.imdecode(np.frombuffer(img_bytes, np.uint8), cv.IMREAD_COLOR)
            if frame is None:
                return jsonify({"error": "Falha ao decodificar imagem"}), 400
        
        # Processar o frame
        processed_frame, detections = process_frame(frame)
        
        # Converter frame para JPEG
        ret, jpeg = cv.imencode('.jpg', processed_frame)
        if not ret:
            return jsonify({"error": "Falha ao codificar imagem"}), 500
        
        # Retornar imagem processada e detecções
        img_io = io.BytesIO(jpeg.tobytes())
        
        return Response(
            img_io.getvalue(),
            mimetype='image/jpeg',
            headers={
                'Detections': str(detections),
                'Access-Control-Expose-Headers': 'Detections'
            }
        )
        
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({"status": "healthy"}), 200

def run_server():
    # Cria diretório temporário se não existir
    temp_dir = os.path.join(os.path.dirname(__file__), 'temp')
    os.makedirs(temp_dir, exist_ok=True)
    
    # Inicializa a câmera apenas se for usar o endpoint /capture
    # initialize_camera()  # Comentado para inicialização lazy
    
    server = make_server('0.0.0.0', 5000, app)
    print("Servidor iniciado em http://0.0.0.0:5000")
    server.serve_forever()

if __name__ == '__main__':
    run_server()