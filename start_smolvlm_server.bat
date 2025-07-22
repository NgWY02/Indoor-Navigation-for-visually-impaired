@echo off
REM SmolVLM Server Startup Script for Windows

REM Default configuration
set MODEL_PATH=ggml-org/SmolVLM2-500M-Video-Instruct-GGUF
set HOST=0.0.0.0
set PORT=8080
set GPU_LAYERS=99

echo 🚀 Starting SmolVLM Server for Indoor Navigation...
echo 📍 Host: %HOST%
echo 🔌 Port: %PORT%
echo 🎯 Model: %MODEL_PATH%
echo 💻 GPU Layers: %GPU_LAYERS%
echo.

REM Check if llama-server exists
where llama-server >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo ❌ llama-server not found!
    echo Please install llama.cpp first:
    echo   git clone https://github.com/ggerganov/llama.cpp.git
    echo   cd llama.cpp
    echo   make
    echo.
    echo Or download pre-built binaries from:
    echo   https://github.com/ggerganov/llama.cpp/releases
    pause
    exit /b 1
)

echo ✅ Starting server...
echo 📱 Configure your Flutter app to use: http://YOUR_IP_ADDRESS:%PORT%
echo 🛑 Press Ctrl+C to stop the server
echo.

REM Start the server
llama-server -hf "%MODEL_PATH%" -ngl %GPU_LAYERS% --host %HOST% --port %PORT%
