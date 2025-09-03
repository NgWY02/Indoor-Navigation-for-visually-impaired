@echo offecho   - Small ROIecho ≡ƒôè Expected Performance (GPU-dependent):
echo   - Small people: ~0.7-1.0 seconds
echo   - Medium people: ~0.9-1.3 seconds
echo   - Large groups: ~1.0-1.8 secondsëñ256px): echo   Γ£à Dynamic inference steps (4-5 for real-time, 12-15 for quality)56px target, 4 steps, guidance 2.5
echo   - Medium ROIs (Γëñ384px): 320px target, 5 steps, guidance 3.0
echo   - Large ROIs: 384px target, 5 steps, guidance 4.0M 🚀 Speed-Optimized Stable Diffusion Inpainting Setup
REM This script demonstrates how to use the new speed optimizations

echo 🚀 Setting up Speed-Optimized Stable Diffusion Inpainting
echo.

REM Set real-time mode for maximum speed (default)
set SD_REALTIME_MODE=true
echo ⚡ Real-time mode enabled (SD_REALTIME_MODE=true)
echo   - Small ROIs (≤256px): 256px target, 4 steps, guidance 2.5
echo   - Medium ROIs (≤384px): 320px target, 5 steps, guidance 3.0
echo   - Large ROIs: 384px target, 6 steps, guidance 4.0
echo   - Simplified prompts: "empty space, background"
echo   - Fast compositing (no Gaussian blur)
echo.

REM Alternative: Quality mode (slower but better quality)
REM set SD_REALTIME_MODE=false
REM echo 🎯 Quality mode enabled (SD_REALTIME_MODE=false)
REM echo   - Higher resolution targets (512px)
REM echo   - More inference steps (12-15)
REM echo   - Higher guidance scale (6.0-7.5)
REM echo   - Detailed prompts and Gaussian blur compositing

echo.
echo 📊 Expected Performance (GPU-dependent):
echo   - Small people: ~0.8-1.2 seconds
echo   - Medium people: ~1.0-1.5 seconds
echo   - Large groups: ~1.2-2.0 seconds
echo.

echo 🎯 Usage Examples:
echo   1. For maximum speed (default): Keep SD_REALTIME_MODE=true
echo   2. For better quality: Set SD_REALTIME_MODE=false before running
echo.

echo 🔧 Technical Optimizations Applied:
echo   ✅ DPMSolverMultistepScheduler with Karras sigmas
echo   ✅ Adaptive resolution scaling based on ROI size
echo   ✅ Dynamic inference steps (4-8 for real-time, 12-15 for quality)
echo   ✅ Lower guidance scale (2.5-4.0 for real-time, 6.0-7.5 for quality)
echo   ✅ Simplified prompts for faster processing
echo   ✅ Removed Gaussian blur masking in real-time mode
echo.

echo 📝 To change modes:
echo   set SD_REALTIME_MODE=false  (for quality mode)
echo   set SD_REALTIME_MODE=true   (for speed mode)
echo.

pause
