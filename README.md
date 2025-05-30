# Túneis App

**Túneis App** é um aplicativo móvel multiplataforma construído com **Flutter** para inspeção de túneis ferroviários. Ele permite capturar imagens ou vídeos das estruturas dos túneis e analisar possíveis patologias (ex: fissuras, infiltrações, corrosão) por meio de um modelo de detecção baseado em deep learning hospedado em um servidor backend:  
🔗 https://backendtuneisapp-fcue.onrender.com

Com uma interface intuitiva, captura de mídia, análise em tempo real e geração automática de relatórios em PDF, o app é uma ferramenta valiosa para engenheiros e inspetores.

---

## Funcionalidades

- **📸 Captura de Mídia**: Use a câmera do dispositivo ou selecione imagens/vídeos da galeria (via `image_picker`).
- **🧠 Detecção de Patologias**: Identificação de problemas estruturais como rachaduras, corrosão e umidade, com **pontuações de confiança**.
- **👀 Visualização de Mídia**: Pré-visualização com navegação quadro a quadro em vídeos processados.
- **📄 Relatórios em PDF**: Geração de relatórios com imagens processadas, resultados e logs (via `pdf`).
- **🖼 Interface Intuitiva**: Layout limpo com botões claros e estilização usando `google_fonts` (Poppins).
- **🛠 Tratamento de Erros Robusto**: Requisições com até 3 tentativas e atraso de 5s para garantir comunicação confiável com o servidor.

---

## Pré-requisitos

- **Flutter SDK**: Versão 3.0 ou superior ([instalar](https://flutter.dev/docs/get-started/install))
- **Dart**: Já incluído no Flutter
- **IDE**: Android Studio, VS Code ou outra com suporte ao Flutter
- **Dependências**: Listadas no `pubspec.yaml`
- **Servidor Backend**: Acesso à API [https://backendtuneisapp-fcue.onrender.com](https://backendtuneisapp-fcue.onrender.com)
- **Dispositivo/Emulador**: Android ou iOS com acesso à câmera

---

## Instalação

### 1. Clone o repositório
```bash
git clone <repository-url>
cd tuneis-app


