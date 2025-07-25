@echo off
echo Starting CLIP-as-service system...
echo.

echo Step 1: Starting CLIP GRPC server...
echo This will start the main CLIP server on port 51000
echo.
start "CLIP Server" cmd /k "python -m clip_server"

echo Waiting 10 seconds for CLIP server to initialize...
timeout /t 10 /nobreak > nul

echo.
echo Step 2: Starting HTTP Gateway...
echo This will start the HTTP bridge on port 8000
echo.
start "CLIP HTTP Gateway" cmd /k "python clip_http_gateway.py"

echo.
echo ✅ Both services are starting up!
echo.
echo 📡 CLIP GRPC Server: 127.0.0.1:51000  (internal)
echo 🌐 HTTP Gateway:     127.0.0.1:8000   (for Flutter app)
echo.
echo Your Flutter app will connect to the HTTP Gateway at port 8000
echo which will forward requests to the CLIP server at port 51000.
echo.
echo Press any key to open the services in browser for testing...
pause
start http://127.0.0.1:8000
start http://127.0.0.1:8000/health
