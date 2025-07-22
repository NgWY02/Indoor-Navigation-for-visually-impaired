#!/bin/bash
# SmolVLM Server Startup Script

# Default configuration
MODEL_PATH="ggml-org/SmolVLM2-500M-Video-Instruct-GGUF"
HOST="0.0.0.0"
PORT="8080"
GPU_LAYERS="99"

echo "🚀 Starting SmolVLM Server for Indoor Navigation..."
echo "📍 Host: $HOST"
echo "🔌 Port: $PORT"
echo "🎯 Model: $MODEL_PATH"
echo "💻 GPU Layers: $GPU_LAYERS"
echo ""

# Check if llama-server exists
if ! command -v llama-server &> /dev/null; then
    echo "❌ llama-server not found!"
    echo "Please install llama.cpp first:"
    echo "  git clone https://github.com/ggerganov/llama.cpp.git"
    echo "  cd llama.cpp"
    echo "  make"
    echo ""
    echo "Or download pre-built binaries from:"
    echo "  https://github.com/ggerganov/llama.cpp/releases"
    exit 1
fi

echo "✅ Starting server..."
echo "📱 Configure your Flutter app to use: http://$(hostname -I | awk '{print $1}'):$PORT"
echo "🛑 Press Ctrl+C to stop the server"
echo ""

# Start the server
llama-server -hf "$MODEL_PATH" -ngl "$GPU_LAYERS" --host "$HOST" --port "$PORT"
