#!/usr/bin/env python3
"""
HTTP Gateway for CLIP-as-service
This script creates an HTTP API that bridges to the GRPC CLIP server
"""

import asyncio
import base64
import io
import json
from typing import List, Dict, Any, Optional
from contextlib import asynccontextmanager

import uvicorn
from fastapi import FastAPI, File, Form, UploadFile, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import numpy as np
from PIL import Image
import os
import tempfile

# Optional heavy deps are imported lazily
import torch  # type: ignore

# Extend path to access local Inpaint-Anything utilities if not installed as editable
from pathlib import Path
import sys

# Locate Inpaint-Anything repo root to enable imports like `lama_inpaint`
_PROJECT_DIR = Path(__file__).resolve().parent
_IA_ROOT_ENV = os.environ.get("IA_ROOT")
_IA_CANDIDATES = [
    Path(_IA_ROOT_ENV) if _IA_ROOT_ENV else None,
    _PROJECT_DIR / "Inpaint-Anything",
    _PROJECT_DIR / "inpaint-anything",
]
_IA_ROOT = None
for _cand in _IA_CANDIDATES:
    if _cand and _cand.exists():
        _IA_ROOT = _cand
        # Prepend IA root and its segment_anything subdir for imports
        sys.path.insert(0, str(_IA_ROOT))
        if (_IA_ROOT / "segment_anything").exists():
            sys.path.insert(0, str(_IA_ROOT / "segment_anything"))
        print(f"🔎 Using Inpaint-Anything at: {_IA_ROOT}")
        break
if _IA_ROOT is None:
    # Not fatal; we can still run without inpainting
    _IA_ROOT = _PROJECT_DIR / "Inpaint-Anything"

# SAM + LaMa imports (resolved at runtime)
try:
    from segment_anything import sam_model_registry, SamPredictor  # type: ignore
    from segment_anything.automatic_mask_generator import SamAutomaticMaskGenerator  # type: ignore
except Exception:
    sam_model_registry = None
    SamAutomaticMaskGenerator = None
    SamPredictor = None

# YOLO for person detection
try:
    from ultralytics import YOLO  # type: ignore
except Exception:
    YOLO = None

# Try Inpaint-Anything's LaMa API first; if not available, fall back to native LaMa load
try:
    # from Inpaint-Anything (preferred)
    from lama_inpaint import inpaint_img_with_lama  # type: ignore
except Exception:
    inpaint_img_with_lama = None

# Import the CLIP client
try:
    from clip_client import Client
except ImportError:
    print("Please install clip-client: pip install clip-client")
    exit(1)

# CLIP client instance
clip_client = None

# Inpainting model singletons
_sam_mask_generator: Optional[Any] = None
_sam_predictor: Optional[Any] = None
_yolo_model: Optional[Any] = None
_lama_config_path: Optional[str] = None
_lama_ckpt_dir: Optional[str] = None
_lama_model: Optional[Any] = None
_lama_device: str = "cuda" if torch.cuda.is_available() else "cpu"
_device_str: str = _lama_device
_sam_model_type_used: Optional[str] = None
_sam_ckpt_used: Optional[str] = None


def _detect_default_models() -> Dict[str, Optional[str]]:
    """Detect default model paths for SAM and LaMa under Inpaint-Anything."""
    defaults: Dict[str, Optional[str]] = {
        "sam_model_type": None,
        "sam_ckpt": None,
        "lama_config": None,
        "lama_ckpt": None,
    }
    # Search locations: Inpaint-Anything tree and project root
    project_root = Path(__file__).resolve().parent
    ia_root = _IA_ROOT
    root_pretrained = project_root / "pretrained_models"

    # MobileSAM auto-detection removed to force SAM-H unless explicitly configured
    # Support files that include a suffix like -001 in the filename
    candidates_sam_vit_h = []
    for base in [ia_root / "pretrained_models", root_pretrained]:
        if base.exists():
            for f in base.glob("sam_vit_h_4b8939*.pth"):
                candidates_sam_vit_h.append(f)

    if defaults["sam_ckpt"] is None:
        for p in candidates_sam_vit_h:
            if p.exists():
                defaults["sam_model_type"] = "vit_h"
                defaults["sam_ckpt"] = str(p)
                break

    # LaMa config path can be either within IA tree or provided with weights
    lama_cfg_ia = ia_root / "lama" / "configs" / "prediction" / "default.yaml"
    lama_cfg_weights = root_pretrained / "big-lama" / "config.yaml"
    if lama_cfg_ia.exists():
        defaults["lama_config"] = str(lama_cfg_ia)
    elif lama_cfg_weights.exists():
        defaults["lama_config"] = str(lama_cfg_weights)

    # LaMa checkpoint: prefer a directory with models/best.ckpt, else accept the directory
    for base in [ia_root / "pretrained_models", root_pretrained]:
        cand_dir = base / "big-lama"
        if cand_dir.exists():
            best = cand_dir / "models" / "best.ckpt"
            defaults["lama_ckpt"] = str(cand_dir)
            break
    return defaults


def initialize_inpaint_models() -> bool:
    """Initialize SAM predictor, YOLO person detector, and record LaMa config.

    Expects either environment variables or defaults in Inpaint-Anything tree:
      - SAM_MODEL_TYPE (vit_h | vit_l | vit_b | vit_t)
      - SAM_CKPT
      - LAMA_CONFIG_PATH
      - LAMA_CKPT_DIR (folder containing models and config.yaml)
    """
    global _sam_mask_generator, _sam_predictor, _yolo_model, _lama_config_path, _lama_ckpt_dir

    if SamPredictor is None or sam_model_registry is None:
        print("⚠️ SAM modules not available. Ensure you ran required installs.")
        return False

    defaults = _detect_default_models()

    sam_model_type = os.environ.get("SAM_MODEL_TYPE", defaults.get("sam_model_type") or "vit_h")
    sam_ckpt = os.environ.get("SAM_CKPT", defaults.get("sam_ckpt") or "")
    _lama_config_path = os.environ.get("LAMA_CONFIG_PATH", defaults.get("lama_config") or "")
    _lama_ckpt_dir = os.environ.get("LAMA_CKPT_DIR", defaults.get("lama_ckpt") or "")

    if not sam_ckpt or not Path(sam_ckpt).exists():
        print(f"⚠️ SAM checkpoint not found at '{sam_ckpt}'. Set SAM_CKPT env. Skipping inpaint init.")
        return False
    if not _lama_config_path or not Path(_lama_config_path).exists() or not _lama_ckpt_dir or not Path(_lama_ckpt_dir).exists():
        print("⚠️ LaMa paths not ready. Inpainting will be attempted via Inpaint-Anything API if available.")

    try:
        sam_model = sam_model_registry[sam_model_type](checkpoint=sam_ckpt)
        sam_model.to(device=_device_str)
        # Record and log which SAM is used and on which device
        globals()["_sam_model_type_used"] = sam_model_type
        globals()["_sam_ckpt_used"] = sam_ckpt
        print(f"🔧 SAM device: {_device_str}")
        
        # Initialize SAM predictor for prompted segmentation
        _sam_predictor = SamPredictor(sam_model)
        
        # Initialize YOLO for person detection
        if YOLO is not None:
            try:
                _yolo_model = YOLO('yolov8l.pt')  # Large YOLO model for better accuracy
                _yolo_model.to(_device_str)
                print(f"✅ YOLO person detector loaded on {_device_str}")
            except Exception as e:
                print(f"⚠️ YOLO initialization failed: {e}")
                _yolo_model = None
        else:
            print("⚠️ YOLO not available. Install ultralytics: pip install ultralytics")
        # Try to load native LaMa if Inpaint-Anything lama_inpaint is not importable
        global _lama_model
        if inpaint_img_with_lama is None and _lama_config_path and _lama_ckpt_dir:
            try:
                from omegaconf import OmegaConf  # type: ignore
                from saicinpainting.training.trainers import load_checkpoint  # type: ignore
                import torch as _torch  # type: ignore
                from torch import serialization as _tser  # type: ignore
                import pytorch_lightning.callbacks.model_checkpoint as _pl_mc  # type: ignore

                # Allowlist PL checkpoint and force weights_only=False for PyTorch >= 2.6
                try:
                    _tser.add_safe_globals([_pl_mc.ModelCheckpoint])
                except Exception:
                    pass

                _orig_load = _torch.load
                def _patched_load(*args, **kwargs):
                    kwargs.setdefault('weights_only', False)
                    return _orig_load(*args, **kwargs)

                cfg = OmegaConf.load(_lama_config_path)
                try:
                    _torch.load = _patched_load
                    _lama = load_checkpoint(cfg, _lama_ckpt_dir, strict=False, map_location=_device_str)
                finally:
                    _torch.load = _orig_load

                _lama.freeze()
                _lama.to(_device_str)
                _globals = globals()
                _globals['_lama_model'] = _lama
                print("✅ Initialized SAM and native LaMa model")
            except Exception as e:
                print(f"⚠️ Could not init native LaMa: {e}")
        else:
            print("✅ Initialized SAM and Inpaint-Anything LaMa API available")
        
        print(f"✅ Initialized SAM ({sam_model_type}) on {_device_str}")
        return True
    except Exception as e:
        print(f"❌ Failed to initialize inpaint models: {e}")
        return False


def _np_image_from_bytes(image_bytes: bytes) -> np.ndarray:
    pil = Image.open(io.BytesIO(image_bytes))
    if pil.mode != "RGB":
        pil = pil.convert("RGB")
    return np.array(pil)


def _dilate_mask_binary(mask: np.ndarray, kernel_size: int = 15) -> np.ndarray:
    try:
        import cv2  # type: ignore
        k = np.ones((kernel_size, kernel_size), np.uint8)
        dil = cv2.dilate((mask > 0).astype(np.uint8) * 255, k, iterations=1)
        return (dil > 0).astype(np.uint8) * 255
    except Exception:
        # Fallback: simple max filter using numpy (slow for large images)
        pad = kernel_size // 2
        padded = np.pad((mask > 0).astype(np.uint8), pad, mode="edge")
        out = np.zeros_like(mask, dtype=np.uint8)
        for dy in range(kernel_size):
            for dx in range(kernel_size):
                out |= padded[dy:dy + out.shape[0], dx:dx + out.shape[1]]
        return (out > 0).astype(np.uint8) * 255


def _detect_people_bboxes(img: np.ndarray) -> List[List[float]]:
    """Use YOLO to detect person bounding boxes in the image."""
    if _yolo_model is None:
        return []
    
    try:
        results = _yolo_model(img, verbose=False)
        person_bboxes = []
        
        for result in results:
            boxes = result.boxes
            if boxes is not None:
                for box in boxes:
                    # YOLO class 0 is 'person' in COCO dataset
                    if int(box.cls) == 0 and float(box.conf) > 0.5:  # confidence threshold
                        # Convert to [x1, y1, x2, y2] format
                        x1, y1, x2, y2 = box.xyxy[0].cpu().numpy()
                        person_bboxes.append([float(x1), float(y1), float(x2), float(y2)])
        
        print(f"🔍 YOLO detected {len(person_bboxes)} people")
        return person_bboxes
    except Exception as e:
        print(f"⚠️ YOLO detection failed: {e}")
        return []


def _get_sam_masks_from_bboxes(img: np.ndarray, bboxes: List[List[float]]) -> List[np.ndarray]:
    """Use SAM to generate masks for detected person bounding boxes."""
    if _sam_predictor is None or not bboxes:
        return []
    
    try:
        _sam_predictor.set_image(img)
        masks = []
        
        for bbox in bboxes:
            x1, y1, x2, y2 = bbox
            # Use bounding box as prompt for SAM
            input_box = np.array([x1, y1, x2, y2])
            
            mask, scores, logits = _sam_predictor.predict(
                point_coords=None,
                point_labels=None,
                box=input_box[None, :],
                multimask_output=False,
            )
            
            if mask is not None and len(mask) > 0:
                # Convert to uint8 format
                person_mask = (mask[0] > 0).astype(np.uint8) * 255
                masks.append(person_mask)
        
        print(f"🎯 SAM generated {len(masks)} person masks from bounding boxes")
        return masks
    except Exception as e:
        print(f"⚠️ SAM mask generation failed: {e}")
        return []


def inpaint_people_from_image_bytes(image_bytes: bytes) -> Optional[Image.Image]:
    """Use YOLO to detect people, SAM to segment them precisely, then LaMa to inpaint.

    Returns a PIL image on success, or None to indicate passthrough.
    """
    if _sam_predictor is None:
        return None
    img = _np_image_from_bytes(image_bytes)
    try:
        # Step 1: Use YOLO to detect person bounding boxes
        person_bboxes = _detect_people_bboxes(img)
        if not person_bboxes:
            print("ℹ️ No people detected by YOLO")
            return None
        
        # Step 2: Use SAM with bounding box prompts to get precise masks
        candidate_masks = _get_sam_masks_from_bboxes(img, person_bboxes)
        if not candidate_masks:
            print("ℹ️ SAM failed to generate masks from person bboxes")
            return None
        # Union all candidate masks
        union_mask = np.zeros((img.shape[0], img.shape[1]), dtype=np.uint8)
        for m in candidate_masks:
            union_mask |= (m > 0).astype(np.uint8) * 255
        union_mask = _dilate_mask_binary(union_mask, kernel_size=15)
        used_pipeline = None
        if inpaint_img_with_lama is not None and _lama_config_path and _lama_ckpt_dir:
            try:
                # Patch torch.load to ensure weights_only=False for PyTorch >=2.6
                import torch as _torch  # type: ignore
                from torch import serialization as _tser  # type: ignore
                import pytorch_lightning.callbacks.model_checkpoint as _pl_mc  # type: ignore

                _orig_load = _torch.load
                def _patched_load(*args, **kwargs):
                    kwargs.setdefault('weights_only', False)
                    return _orig_load(*args, **kwargs)

                inpainted = None
                try:
                    _tser.add_safe_globals([_pl_mc.ModelCheckpoint])  # allowlist PL checkpoint
                except Exception:
                    pass

                try:
                    _torch.load = _patched_load  # monkeypatch during IA call
                    inpainted = inpaint_img_with_lama(
                        img, union_mask, _lama_config_path, _lama_ckpt_dir, device=_device_str
                    )
                    used_pipeline = 'ia_lama'
                finally:
                    _torch.load = _orig_load
            except Exception as e:
                print(f"⚠️ Inpaint-Anything LaMa failed: {e}. Falling back to native LaMa if available.")
                inpainted = None

        if inpainted is None and _lama_model is None and _lama_config_path and _lama_ckpt_dir:
            # Try lazy-initialize native LaMa now for fallback
            try:
                from omegaconf import OmegaConf  # type: ignore
                from saicinpainting.training.trainers import load_checkpoint  # type: ignore
                from torch.serialization import add_safe_globals  # type: ignore
                import pytorch_lightning.callbacks.model_checkpoint as pl_mc  # type: ignore
                add_safe_globals([pl_mc.ModelCheckpoint])
                cfg = OmegaConf.load(_lama_config_path)
                globals()['_lama_model'] = load_checkpoint(cfg, _lama_ckpt_dir, strict=False, map_location=_device_str)
                globals()['_lama_model'].freeze()
                globals()['_lama_model'].to(_device_str)
                print("✅ Lazy-initialized native LaMa model for fallback")
            except Exception as e:
                print(f"⚠️ Lazy native LaMa init failed: {e}")

        if inpainted is None and _lama_model is not None:
            # Native LaMa run
            try:
                import torch  # type: ignore
                from saicinpainting.evaluation.utils import move_to_device  # type: ignore
                from saicinpainting.evaluation.data import pad_img_to_modulo  # type: ignore
                img_padded, _ = pad_img_to_modulo(img, 8)
                mask_padded, _ = pad_img_to_modulo(union_mask[..., None], 8)
                mask_padded = mask_padded[..., 0]
                img_t = torch.from_numpy(img_padded).permute(2, 0, 1).float()[None] / 255.0
                mask_t = torch.from_numpy(mask_padded[None, None].astype(np.float32))
                batch = move_to_device({"image": img_t, "mask": mask_t}, _device_str)
                with torch.no_grad():
                    res = _lama_model(batch)
                out = res.get('inpainted') or res.get('output') or res.get('predicted_image')
                if isinstance(out, (list, tuple)):
                    out = out[0]
                out_img = (out[0].permute(1, 2, 0).clamp(0, 1).cpu().numpy() * 255.0).astype(np.uint8)
                h, w = img.shape[:2]
                inpainted = out_img[:h, :w]
                used_pipeline = 'native_lama'
            except Exception as e:
                print(f"⚠️ Native LaMa inference failed: {e}")
                return None
        if inpainted is None:
            return None
        return Image.fromarray(inpainted)
    except Exception as e:
        print(f"⚠️ Inpainting failed, forwarding original image. Reason: {e}")
        return None

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
    # Initialize SAM + LaMa (optional)
    try:
        inpaint_ok = initialize_inpaint_models()
        if not inpaint_ok:
            print("⚠️ Inpaint models not initialized. /encode/inpainted will passthrough.")
    except Exception as e:
        print(f"⚠️ Failed to init inpaint models: {e}")
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


class InpaintPreviewRequest(BaseModel):
    image: str  # base64-encoded image

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


@app.post("/encode/inpainted", response_model=EmbeddingResponse)
async def encode_image_inpainted(image: UploadFile = File(...)):
    """Inpaint likely people using SAM+LaMa before encoding with CLIP.

    Falls back to original image if inpainting is unavailable or fails.
    """
    global clip_client

    if clip_client is None:
        raise HTTPException(status_code=503, detail="CLIP server not connected")

    try:
        # Read the image data
        image_data = await image.read()

        # Try inpainting pipeline
        pil_image = inpaint_people_from_image_bytes(image_data) or Image.open(io.BytesIO(image_data)).convert("RGB")

        # Resize for CLIP
        pil_image = pil_image.resize((224, 224))

        # Encode via file path
        with tempfile.NamedTemporaryFile(suffix='.jpg', delete=False) as tmp_file:
            pil_image.save(tmp_file.name, format='JPEG', quality=95)
            temp_path = tmp_file.name

        try:
            result = clip_client.encode([temp_path])
        finally:
            try:
                os.unlink(temp_path)
            except Exception:
                pass

        # Extract embedding
        embedding = None
        if isinstance(result, np.ndarray):
            if len(result.shape) == 2 and result.shape[0] == 1:
                embedding = result[0].tolist()
            elif len(result.shape) == 1:
                embedding = result.tolist()
            else:
                embedding = result.flatten().tolist()
        elif isinstance(result, list) and len(result) > 0:
            if isinstance(result[0], np.ndarray):
                embedding = result[0].flatten().tolist()
            else:
                embedding = np.array(result[0]).flatten().tolist()
        else:
            embedding = np.array(result).flatten().tolist()

        if embedding is None or len(embedding) == 0:
            raise Exception("Failed to extract embedding from CLIP result")

        return EmbeddingResponse(embedding=embedding, dimensions=len(embedding))
    except Exception as e:
        print(f"Error inpaint-encoding image: {e}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to encode inpainted image: {str(e)}")


@app.post("/encode/preprocessed", response_model=EmbeddingResponse)
async def encode_image_preprocessed(image: UploadFile = File(...)):
    """Alias for clients expecting /encode/preprocessed."""
    return await encode_image_inpainted(image)


@app.post("/inpaint/preview")
async def inpaint_preview(request: InpaintPreviewRequest):
    """Return an inpainted image (people removed) as base64 for quick visual testing.

    If inpainting is not available, returns the original image.
    Response JSON: { processed_image: <base64> }
    """
    try:
        image_bytes = base64.b64decode(request.image)
        pil_image = inpaint_people_from_image_bytes(image_bytes)
        used_fallback = False
        if pil_image is None:
            # As a last resort (so the UI shows something), send original back
            used_fallback = True
            pil_image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
        with tempfile.NamedTemporaryFile(suffix='.jpg', delete=False) as tmp_file:
            pil_image.save(tmp_file.name, format='JPEG', quality=92)
            temp_path = tmp_file.name
        try:
            with open(temp_path, 'rb') as f:
                out_b64 = base64.b64encode(f.read()).decode('utf-8')
        finally:
            try:
                os.unlink(temp_path)
            except Exception:
                pass
        return {"processed_image": out_b64, "fallback": used_fallback}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Inpaint preview failed: {str(e)}")

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
        "devices": {
            "sam_device": _device_str,
            "lama_device": _device_str,
            "sam_model_type": _sam_model_type_used,
            "sam_ckpt": _sam_ckpt_used,
        },
        "endpoints": {
            "health": "/health",
            "encode_image": "/encode (POST with image file)",
            "encode_text": "/encode/text (POST with JSON body)",
            "encode_image_inpainted": "/encode/inpainted (POST with image file; SAM+LaMa preprocessed)"
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
