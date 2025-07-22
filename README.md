# Indoor Navigation for Visually Impaired

A Flutter application that provides indoor navigation assistance using computer vision and SmolVLM (Vision Language Model) for place recognition.

## 🎯 Features

- **360° Scanning**: Comprehensive location scanning with compass guidance
- **SmolVLM Integration**: Advanced place recognition using Vision Language Models
- **Audio Feedback**: Text-to-speech guidance throughout the process
- **Real-time Processing**: Live camera feed with server-based analysis
- **Accessible Design**: Built specifically for visually impaired users

## 🚀 Quick Start

### 1. Start SmolVLM Server

**Windows:**
```bash
start_smolvlm_server.bat
```

**Linux/macOS:**
```bash
chmod +x start_smolvlm_server.sh
./start_smolvlm_server.sh
```

**Manual Setup:**
```bash
llama-server -hf ggml-org/SmolVLM2-500M-Video-Instruct-GGUF -ngl 99 --host 0.0.0.0 --port 8080
```

### 2. Configure the App

1. Open the app
2. Enter your server URL (e.g., `http://192.168.0.104:8080`)
3. Use "Test" button to verify connection
4. Start scanning!

## 📖 Documentation

- [SmolVLM Integration Guide](SMOLVLM_INTEGRATION.md) - Detailed setup and usage
- [Original TensorFlow Lite version](lib/main.dart) - Legacy implementation

## 🛠️ Development

### Prerequisites
- Flutter SDK
- llama.cpp with SmolVLM support
- Network connectivity between device and server

### Dependencies
```yaml
dependencies:
  flutter:
    sdk: flutter
  camera: ^0.11.1
  http: ^1.1.0  # For SmolVLM API calls
  flutter_compass: ^0.8.0
  flutter_tts: ^4.0.2
  # ... other dependencies
```

### Installation
```bash
git clone <repository>
cd Indoor-Navigation-for-visually-impaired
flutter pub get
flutter run
```

## 🏗️ Architecture

### SmolVLM Approach (Current)
```
Camera → SmolVLM Server → Text Description → Embedding → Comparison
```

### TensorFlow Lite Approach (Legacy)
```
Camera → MobileNetV2 → Numerical Embedding → Cosine Similarity
```

## 📱 Usage

1. **Server Setup**: Start SmolVLM server on your computer
2. **Configuration**: Enter server URL in the app
3. **Scanning**: Use 360° scan to capture location features
4. **Recognition**: App processes images through SmolVLM for identification
5. **Audio Feedback**: Receive spoken guidance throughout the process

## 🔧 Troubleshooting

### Connection Issues
- Verify server is running and accessible
- Check firewall settings
- Use correct IP address format

### Performance Issues
- Ensure adequate server resources
- Use GPU acceleration (`-ngl 99`)
- Consider network bandwidth

## 📄 License

[Add your license information here]

## 🤝 Contributing

[Add contributing guidelines here]

