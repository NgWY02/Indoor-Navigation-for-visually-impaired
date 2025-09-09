# FastAPI Server Library Versions - Detailed Specification

## Core Web Framework Components

### **FastAPI Core Libraries**
```txt
fastapi==0.116.1
uvicorn==0.23.1
python-multipart==0.0.6
pydantic==2.11.7
pydantic_core==2.33.2
```

**Version Rationale:**
- **FastAPI 0.116.1**: Latest stable release with enhanced async/await support, improved API documentation, and advanced validation features
- **Uvicorn 0.23.1**: ASGI server with enhanced logging, configuration options, and production optimizations
- **python-multipart 0.0.6**: File upload and form data processing for image endpoints
- **Pydantic 2.11.7**: Latest stable data validation and serialization with improved performance
- **pydantic_core 2.33.2**: Core validation engine for Pydantic with optimized performance

## Computer Vision and Image Processing

### **Core Image Processing**
```txt
Pillow==11.1.0
numpy==2.0.1
opencv-python==4.12.0.88
```

**Version Rationale:**
- **Pillow 11.1.0**: Latest Python Imaging Library fork with improved performance and bug fixes
- **NumPy 2.0.1**: Latest stable scientific computing library with enhanced performance
- **OpenCV 4.12.0.88**: Latest computer vision library with improved algorithms and bug fixes

## AI/ML Frameworks and Models

### **PyTorch Ecosystem**
```txt
torch==2.5.1
torchvision==0.20.1
torchaudio==2.5.1
```

**Version Rationale:**
- **PyTorch 2.5.1**: Latest stable release with significant performance improvements and CUDA 12.x support
- **TorchVision 0.20.1**: Compatible vision models and transforms for PyTorch 2.5.1
- **TorchAudio 2.5.1**: Audio processing capabilities for potential voice navigation features

### **Transformers Library (DINOv2)**
```txt
transformers==4.56.0
```

**Version Rationale:**
- **Transformers 4.56.0**: Latest Hugging Face library with enhanced DINOv2 support for superior spatial understanding and landmark detection


## Object Detection and Segmentation

### **YOLO Object Detection**
```txt
ultralytics==8.3.191
```

**Version Rationale:**
- **Ultralytics 8.3.191**: Latest YOLOv8 implementation with improved person detection and performance optimizations

### **SAM (Segment Anything Model)**
```txt
segment_anything @ git+https://github.com/facebookresearch/segment-anything.git
```

**Version Rationale:**
- **Git Installation**: Latest development version from Facebook Research repository
- **Installation**: `pip install git+https://github.com/facebookresearch/segment-anything.git`

## Generative AI (Optional)

### **Stable Diffusion**
```txt
diffusers==0.35.1
```

**Version Rationale:**
- **Diffusers 0.35.1**: Latest Hugging Face diffusers library with improved inpainting capabilities
- **Optional**: Only required if using Stable Diffusion for background removal

## Development and Testing

### **Testing Framework**
```txt
pytest==7.4.3
pytest-asyncio==0.21.1
```

**Version Rationale:**
- **pytest 7.4.3**: Standard Python testing framework
- **pytest-asyncio 0.21.1**: Async testing support for FastAPI endpoints

### **HTTP Client**
```txt
requests==2.32.5
```

**Version Rationale:**
- **requests 2.32.5**: Latest HTTP library for testing API endpoints with security improvements

## Installation Instructions

### **Basic Installation**
```bash
# Install core dependencies
pip install -r requirements.txt

# Install optional GPU support (if needed)
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
```

### **Development Installation**
```bash
# Install with development dependencies
pip install -r requirements.txt
pip install pytest pytest-asyncio

# For GPU acceleration (optional)
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
```

### **Troubleshooting Installation**

#### **PyTorch GPU Support**
```bash
# For CUDA 11.8
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118

# For CUDA 12.1
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
```

#### **Common Issues**
1. **PyTorch Installation**: Ensure CUDA version compatibility
2. **OpenCLIP**: May require specific PyTorch version
3. **Transformers**: Latest version may have breaking changes

## Version Compatibility Matrix

| Library | Version | Compatible With | Notes |
|---------|---------|-----------------|-------|
| PyTorch | 2.5.1 | CUDA 11.8, 12.1 | GPU acceleration |
| Transformers | 4.56.0 | PyTorch 2.5.1 | DINOv2 vision model |
| Ultralytics | 8.3.191 | PyTorch 2.5.1 | YOLOv8 object detection |
| FastAPI | 0.116.1 | Python 3.8+ | Async support |

## Environment Setup

### **Conda Environment (Recommended)**
```bash
# Create new environment
conda create -n navigation_ai python=3.10
conda activate navigation_ai

# Install PyTorch with CUDA (if GPU available)
conda install pytorch torchvision torchaudio pytorch-cuda=11.8 -c pytorch -c nvidia

# Install remaining dependencies
pip install -r requirements.txt
```

### **Docker Setup (Alternative)**
```dockerfile
FROM python:3.10-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY . /app
WORKDIR /app

EXPOSE 8000
CMD ["uvicorn", "clip_http_gateway:app", "--host", "0.0.0.0", "--port", "8000"]
```

## Performance Optimization

### **GPU Acceleration**
- Ensure PyTorch is installed with CUDA support
- Use `torch.cuda.is_available()` to detect GPU
- Models automatically use GPU when available

### **Memory Management**
- Large models (ViT-L/14) require significant RAM
- Use batch processing to manage memory usage
- Implement model caching for better performance

### **Concurrent Processing**
- FastAPI supports multiple concurrent requests
- Use async/await for non-blocking operations
- Configure uvicorn workers for production deployment

This specification ensures compatibility, performance, and maintainability of the FastAPI server for the indoor navigation system.
