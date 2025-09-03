@echo off
echo Starting CLIP ViT-L/14 System for Better Hallway Navigation...
echo.

echo Starting CLIP ViT-L/14 HTTP Gateway...
echo This integrates ViT-L/14 + SAM + LaMa + Stable Diffusion + YOLO
echo.
start "CLIP ViT-L/14 Gateway" cmd /k "conda activate dinov2 && python clip_http_gateway.py"

echo Waiting 20 seconds for ViT-L/14 model to load...
echo (ViT-L/14 is larger and takes longer to initialize)
timeout /t 20 /nobreak > nul

echo.
echo ✅ CLIP ViT-L/14 system is starting up!
echo.
echo 🤖 Integrated ViT-L/14 Gateway: 192.168.0.103:8000 (for Flutter app)
echo.
echo 🎯 ViT-L/14 Benefits:
echo    - 427M parameters (vs 151M in ViT-B/32)
echo    - 768-dimensional embeddings (vs 512)
echo    - Much better discrimination for similar scenes
echo    - Should solve hallway navigation issues
echo.
echo 🛠️ Integrated Features:
echo    - CLIP ViT-L/14 for embeddings
echo    - SAM for precise segmentation
echo    - LaMa + Stable Diffusion for inpainting
echo    - YOLO for person detection
echo.
echo Your Flutter app will connect to port 8000 as before.
echo.
echo Press any key to test the services...
pause
start http://192.168.0.103:8000
start http://192.168.0.103:8000/health