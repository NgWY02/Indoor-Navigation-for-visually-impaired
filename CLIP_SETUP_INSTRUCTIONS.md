# CLIP System Setup Instructions

## Problem Solved
Your CLIP server runs on GRPC (port 51000) but Flutter can't directly communicate with GRPC servers. This setup creates an HTTP gateway that bridges the gap.

## Architecture
```
Flutter App  ──HTTP──>  HTTP Gateway  ──GRPC──>  CLIP Server
   (port 8000)            (port 8000)              (port 51000)
```

## Installation Steps

### 1. Install Dependencies
```bash
pip install clip-server clip-client fastapi uvicorn pillow numpy
```

### 2. Start the System
Run the batch script:
```bash
start_clip_system.bat
```

Or start manually:

**Terminal 1 - CLIP Server:**
```bash
python -m clip_server
```

**Terminal 2 - HTTP Gateway:**
```bash
python clip_http_gateway.py
```

### 3. Verify Installation
Open in browser:
- http://127.0.0.1:8000 - API documentation
- http://127.0.0.1:8000/health - Health check

### 4. Test with Flutter
Your Flutter app will now connect to `http://127.0.0.1:8000` instead of the GRPC server.

## API Endpoints

The HTTP Gateway provides these endpoints for your Flutter app:

- `GET /health` - Check if CLIP server is ready
- `POST /encode` - Upload image file for embedding
- `POST /encode/text` - Send JSON with text for embedding

## Response Format
```json
{
  "embedding": [0.1, 0.2, 0.3, ...],
  "dimensions": 512
}
```

## Troubleshooting

### "Failed to connect to CLIP server"
1. Make sure CLIP server is running: `python -m clip_server`
2. Check if it's running on port 51000
3. Wait a few seconds after starting before running the gateway

### "HTTP Gateway not responding"
1. Check if Python dependencies are installed
2. Make sure port 8000 is not in use
3. Verify the gateway script is running

### "Flutter app can't connect"
1. Make sure both CLIP server and HTTP gateway are running
2. Test the endpoints in browser first
3. Check Flutter app is connecting to port 8000, not 51000

## Status Indicators

When everything is working:
- ✅ CLIP server shows "Endpoint ready" on port 51000
- ✅ HTTP gateway shows "Application startup complete"
- ✅ http://127.0.0.1:8000/health returns "healthy"
- ✅ Flutter app can create nodes without connection errors
