@echo off
echo Starting DINOv2 System for Better Hallway Navigation...
echo.

echo Starting DINOv2 HTTP Gateway...
echo This integrates DINOv2 + Stable Diffusion + YOLO
echo.
start "DINOV2" cmd /k "conda activate dinov2 && python dinov2_http_gateway.py"

echo Waiting 20 seconds for DINOv2 model to load...
echo (DINOv2 is a large model and takes time to initialize)
timeout /t 20 /nobreak > nul

echo.
echo ✅ DINOv2 system is starting up!
echo.
echo 🤖 Integrated DINOv2 Gateway: 192.168.0.103:8000 (for Flutter app)
echo.
echo 🎯 DINOv2 Benefits:
echo    - Self-supervised learning with superior spatial understanding
echo    - 768-dimensional embeddings with better scene discrimination
echo    - Excellent performance on navigation and localization tasks
echo    - Should solve hallway navigation issues
echo.
echo 🛠️ Integrated Features:
echo    - DINOv2 for superior embeddings
echo    - LaMa + Stable Diffusion for inpainting
echo    - YOLO for person detection and segmentation
echo.
echo Your Flutter app will connect to port 8000 as before.
echo.
echo Press any key to test the services...
pause
start http://192.168.0.103:8000
start http://192.168.0.103:8000/health