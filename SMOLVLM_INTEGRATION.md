# SmolVLM Integration for Indoor Navigation

This version of the indoor navigation app has been updated to use SmolVLM instead of TensorFlow Lite for place recognition.

## Server Setup

1. **Install llama.cpp with SmolVLM support:**
```bash
# Clone and build llama.cpp (if not already done)
git clone https://github.com/ggerganov/llama.cpp.git
cd llama.cpp
make

# Or use pre-built binaries
```

2. **Start the SmolVLM server:**
```bash
# Using the command you provided:
llama-server -hf ggml-org/SmolVLM2-500M-Video-Instruct-GGUF -ngl 99 --host 0.0.0.0 --port 8080

# Alternative if using local model:
./llama-server -m path/to/smolvlm-model.gguf -ngl 99 --host 0.0.0.0 --port 8080
```

3. **Configure the app:**
   - In the app, enter your server URL (e.g., `http://192.168.0.104:8080`)
   - Use "Test" button to verify connection
   - The IP address should be your computer's local network IP

## How it Works

### Original TensorFlow Lite Approach:
- Used MobileNetV2 feature extractor to generate numerical embeddings
- Stored embeddings in Supabase database
- Compared new images using cosine similarity

### New SmolVLM Approach:
- Captures images during 360° scan
- Sends images to SmolVLM server for detailed description
- Converts descriptions to embeddings for comparison
- Uses majority voting across multiple scan points

## Key Changes Made:

### 1. Replaced TensorFlow Lite Model
- Removed `tflite_flutter` dependency
- Added `http` dependency for API calls
- Created `SmolVLMService` class for server communication

### 2. Updated Data Processing
- `_captureAndStoreEmbedding()` now uses SmolVLM API
- `_process360ScanResults()` processes VLM responses
- Embeddings generated from text descriptions instead of raw image features

### 3. Server Configuration
- Added server URL configuration in UI
- Connection testing functionality
- Real-time server status feedback

## Benefits of SmolVLM Integration:

1. **Better Context Understanding**: VLM can understand complex scenes and relationships
2. **More Descriptive Features**: Text descriptions capture semantic meaning
3. **Flexible Deployment**: Server can run on more powerful hardware
4. **Easier Debugging**: Human-readable descriptions help troubleshooting
5. **Extensible**: Can easily add new prompts or analysis types

## Network Requirements:

- Both device and server must be on same network
- Server must be accessible via IP address
- Consider firewall settings on server machine
- Ensure sufficient bandwidth for image transmission

## Usage Tips:

1. **Server Performance**: 
   - Use GPU acceleration (`-ngl 99`) for better performance
   - Adjust model size based on hardware capabilities

2. **Network Configuration**:
   - Use your computer's local IP, not `localhost`
   - Test connection before starting scan
   - Ensure stable WiFi connection

3. **Scanning Process**:
   - Same 360° scanning procedure as before
   - App will process images through SmolVLM
   - Results based on semantic similarity of descriptions

## Troubleshooting:

1. **Connection Issues**:
   - Verify server is running and accessible
   - Check firewall settings
   - Use correct IP address format

2. **Performance Issues**:
   - Reduce image quality if transmission is slow
   - Ensure adequate server resources
   - Consider local vs remote deployment

3. **Recognition Accuracy**:
   - Ensure good lighting during scans
   - Include distinctive features in scans
   - Build database with varied angles/conditions
