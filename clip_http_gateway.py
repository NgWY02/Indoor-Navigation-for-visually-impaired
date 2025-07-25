#!/usr/bin/env python3
"""
HTTP Gateway for CLIP-as-service
This script creates an HTTP API that bridges to the GRPC CLIP server
"""

import asyncio
import base64
import io
import json
from typing import List, Dict, Any
from contextlib import asynccontextmanager

import uvicorn
from fastapi import FastAPI, File, Form, UploadFile, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import numpy as np
from PIL import Image

# Import the CLIP client
try:
    from clip_client import Client
except ImportError:
    print("Please install clip-client: pip install clip-client")
    exit(1)

# CLIP client instance
clip_client = None

def initialize_clip_client():
    """Initialize the CLIP client connection"""
    global clip_client
    try:
        # Connect to the local GRPC CLIP server
        clip_client = Client(server='grpc://127.0.0.1:51000')
        print("✅ Connected to CLIP server at grpc://127.0.0.1:51000")
        return True
    except Exception as e:
        print(f"❌ Failed to connect to CLIP server: {e}")
        return False

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Handle application lifespan events"""
    # Startup
    success = initialize_clip_client()
    if not success:
        print("⚠️  CLIP server not available. Make sure it's running on port 51000")
    yield
    # Shutdown
    print("🛑 Shutting down CLIP HTTP Gateway")

app = FastAPI(title="CLIP HTTP Gateway", version="1.0.0", lifespan=lifespan)

# Add CORS middleware to allow Flutter app to connect
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allow all origins for development
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class TextRequest(BaseModel):
    text: str

class EmbeddingResponse(BaseModel):
    embedding: List[float]
    dimensions: int

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    global clip_client
    if clip_client is None:
        raise HTTPException(status_code=503, detail="CLIP server not connected")
    
    try:
        # Test the connection with a simple encode
        result = clip_client.encode(['test'])
        return {"status": "healthy", "message": "CLIP server is accessible"}
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"CLIP server error: {str(e)}")

@app.post("/encode", response_model=EmbeddingResponse)
async def encode_image(image: UploadFile = File(...)):
    """Encode an uploaded image using CLIP"""
    global clip_client
    
    if clip_client is None:
        raise HTTPException(status_code=503, detail="CLIP server not connected")
    
    try:
        # Read the image data
        image_data = await image.read()
        
        # Convert to PIL Image
        pil_image = Image.open(io.BytesIO(image_data))
        
        # Convert to RGB if needed
        if pil_image.mode != 'RGB':
            pil_image = pil_image.convert('RGB')
        
        # Resize to 224x224 (CLIP standard)
        pil_image = pil_image.resize((224, 224))
        
        # Save to temporary file (CLIP client expects file paths)
        import tempfile
        import os
        with tempfile.NamedTemporaryFile(suffix='.jpg', delete=False) as tmp_file:
            pil_image.save(tmp_file.name, format='JPEG', quality=95)
            temp_path = tmp_file.name
        
        try:
            # Encode with CLIP using file path
            result = clip_client.encode([temp_path])
        finally:
            # Clean up temporary file
            try:
                os.unlink(temp_path)
            except:
                pass
        
        # Extract the embedding - CLIP client returns numpy array directly
        embedding = None
        
        if isinstance(result, np.ndarray):
            # For single image, result is 2D array [1, embedding_dim]
            if len(result.shape) == 2 and result.shape[0] == 1:
                embedding = result[0].tolist()
            # For single image, result is 1D array [embedding_dim]
            elif len(result.shape) == 1:
                embedding = result.tolist()
            else:
                embedding = result.flatten().tolist()
        elif isinstance(result, list) and len(result) > 0:
            # Handle case where result is a list
            if isinstance(result[0], np.ndarray):
                embedding = result[0].flatten().tolist()
            else:
                embedding = np.array(result[0]).flatten().tolist()
        else:
            # Last resort - try to convert result directly
            embedding = np.array(result).flatten().tolist()
        
        if embedding is None or len(embedding) == 0:
            raise Exception("Failed to extract embedding from CLIP result")
            
        return EmbeddingResponse(
            embedding=embedding,
            dimensions=len(embedding)
        )
        
    except Exception as e:
        print(f"Error encoding image: {e}")
        print(f"Error type: {type(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to encode image: {str(e)}")

@app.post("/encode/text", response_model=EmbeddingResponse)
async def encode_text(request: TextRequest):
    """Encode text using CLIP"""
    global clip_client
    
    if clip_client is None:
        raise HTTPException(status_code=503, detail="CLIP server not connected")
    
    try:
        # Encode the text
        result = clip_client.encode([request.text])
        
        # Extract the embedding - CLIP client returns numpy array directly
        embedding = None
        
        if isinstance(result, np.ndarray):
            # For single text, result is 2D array [1, embedding_dim]
            if len(result.shape) == 2 and result.shape[0] == 1:
                embedding = result[0].tolist()
            # For single text, result is 1D array [embedding_dim]
            elif len(result.shape) == 1:
                embedding = result.tolist()
            else:
                embedding = result.flatten().tolist()
        elif isinstance(result, list) and len(result) > 0:
            # Handle case where result is a list
            if isinstance(result[0], np.ndarray):
                embedding = result[0].flatten().tolist()
            else:
                embedding = np.array(result[0]).flatten().tolist()
        else:
            # Last resort - try to convert result directly
            embedding = np.array(result).flatten().tolist()
        
        if embedding is None or len(embedding) == 0:
            raise Exception("Failed to extract embedding from CLIP result")
            
        return EmbeddingResponse(
            embedding=embedding,
            dimensions=len(embedding)
        )
        
    except Exception as e:
        print(f"Error encoding text: {e}")
        print(f"Error type: {type(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to encode text: {str(e)}")

@app.get("/")
async def root():
    """Root endpoint with API information"""
    return {
        "message": "CLIP HTTP Gateway",
        "version": "1.0.0",
        "endpoints": {
            "health": "/health",
            "encode_image": "/encode (POST with image file)",
            "encode_text": "/encode/text (POST with JSON body)"
        }
    }

if __name__ == "__main__":
    print("🚀 Starting CLIP HTTP Gateway...")
    print("📡 This will connect to CLIP server at grpc://127.0.0.1:51000")
    print("🌐 HTTP API will be available at http://127.0.0.1:8000")
    print("\nMake sure your CLIP server is running first!")
    print("Start it with: python -m clip_server")
    print()
    
    uvicorn.run(
        "clip_http_gateway:app",
        host="0.0.0.0",  # Bind to all interfaces so Android can connect
        port=8000,
        reload=False,
        log_level="info"
    )
