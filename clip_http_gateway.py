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

# Stable Diffusion inpainting
try:
    from diffusers import StableDiffusionInpaintPipeline, EulerAncestralDiscreteScheduler  # type: ignore
    import torch  # type: ignore
except Exception:
    StableDiffusionInpaintPipeline = None
    EulerAncestralDiscreteScheduler = None

# Import the CLIP client
try:
    from clip_client import Client
except ImportError:
    print("Please install clip-client: pip install clip-client")
    exit(1)

# Import CLIP ViT-L/14 for better hallway discrimination
try:
    import open_clip
    VITL14_AVAILABLE = True
except ImportError:
    print("⚠️ open-clip-torch not available. Install with: pip install open-clip-torch")
    VITL14_AVAILABLE = False

# CLIP client instance (fallback)
clip_client = None

# CLIP ViT-L/14 model instances (primary)
clip_vitl14_model = None
clip_vitl14_preprocess = None
clip_vitl14_tokenizer = None

# Inpainting model singletons
_sam_mask_generator: Optional[Any] = None
_sam_predictor: Optional[Any] = None
_yolo_model: Optional[Any] = None
_sd_inpaint_pipeline: Optional[Any] = None
_device_str: str = "cuda" if torch.cuda.is_available() else "cpu"
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
    global _sam_mask_generator, _sam_predictor, _yolo_model, _lama_config_path, _lama_ckpt_dir, _sd_inpaint_pipeline

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
                _yolo_model = YOLO('yolov8l-seg.pt')  # Large YOLO segmentation model for detection + segmentation
                _yolo_model.to(_device_str)
                print(f"✅ YOLOv8 segmentation model loaded on {_device_str}")
            except Exception as e:
                print(f"⚠️ YOLO initialization failed: {e}")
                _yolo_model = None
        else:
            print("⚠️ YOLO not available. Install ultralytics: pip install ultralytics")
        
        # Initialize Stable Diffusion inpainting pipeline
        if StableDiffusionInpaintPipeline is not None:
            try:
                # Respect override via env, otherwise try safetensors-first models in order
                preferred = os.environ.get("SD_INPAINT_MODEL")
                candidate_models = [preferred] if preferred else [
                    "runwayml/stable-diffusion-inpainting",           # SD 1.5 inpaint (fast) – may use .bin
                    "stabilityai/stable-diffusion-2-inpainting",      # SD 2 inpaint – safetensors available
                ]

                last_err = None
                for model_id in candidate_models:
                    if not model_id:
                        continue
                    print(f"🔄 Loading Stable Diffusion inpainting model: {model_id}")
                    try:
                        _sd_inpaint_pipeline = StableDiffusionInpaintPipeline.from_pretrained(
                            model_id,
                            torch_dtype=torch.float16 if _device_str == "cuda" else torch.float32,
                            safety_checker=None,
                            requires_safety_checker=False,
                            use_safetensors=True,
                            variant="fp16",
                        )
                        _sd_inpaint_pipeline.to(_device_str)
                        # Success
                        break
                    except Exception as ie:
                        print(f"⚠️ Failed loading '{model_id}': {ie}")
                        last_err = ie
                        _sd_inpaint_pipeline = None

                if _sd_inpaint_pipeline is None:
                    raise RuntimeError(str(last_err) if last_err else "Could not load any SD inpaint model")

                # Performance optimizations (fast path)
                if _device_str == "cuda":
                    _sd_inpaint_pipeline.enable_attention_slicing()
                    try:
                        _sd_inpaint_pipeline.enable_vae_tiling()
                    except Exception:
                        pass
                    try:
                        _sd_inpaint_pipeline.enable_xformers_memory_efficient_attention()
                    except Exception:
                        pass

                try:
                    if EulerAncestralDiscreteScheduler is not None:
                        _sd_inpaint_pipeline.scheduler = EulerAncestralDiscreteScheduler.from_config(
                            _sd_inpaint_pipeline.scheduler.config
                        )
                except Exception:
                    pass

                try:
                    torch.set_float32_matmul_precision("high")
                except Exception:
                    pass
                print(f"✅ Stable Diffusion inpainting loaded on {_device_str}")
            except Exception as e:
                print(f"⚠️ Stable Diffusion initialization failed: {e}")
                _sd_inpaint_pipeline = None
        else:
            print("⚠️ Stable Diffusion not available. Install diffusers: pip install diffusers")
        
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


def _get_yolo_person_masks(img: np.ndarray) -> List[np.ndarray]:
    """Use YOLOv8 segmentation to detect and segment people in one step."""
    if _yolo_model is None:
        return []
    
    try:
        import time
        yolo_start = time.time()
        
        results = _yolo_model(img, verbose=False)
        person_masks = []
        
        for result in results:
            # Check if segmentation masks are available
            if hasattr(result, 'masks') and result.masks is not None:
                boxes = result.boxes
                masks = result.masks
                
                for i, box in enumerate(boxes):
                    # YOLO class 0 is 'person' in COCO dataset
                    if int(box.cls) == 0 and float(box.conf) > 0.5:  # confidence threshold
                        # Get the segmentation mask
                        mask = masks.data[i].cpu().numpy()
                        # Resize mask to original image size if needed
                        if mask.shape != img.shape[:2]:
                            mask_pil = Image.fromarray((mask * 255).astype(np.uint8))
                            mask_resized = mask_pil.resize((img.shape[1], img.shape[0]))
                            mask = np.array(mask_resized)
                        else:
                            mask = (mask * 255).astype(np.uint8)
                        
                        person_masks.append(mask)
            else:
                # Fallback to bounding boxes if segmentation not available
                boxes = result.boxes
                if boxes is not None:
                    for box in boxes:
                        if int(box.cls) == 0 and float(box.conf) > 0.5:
                            x1, y1, x2, y2 = [int(coord) for coord in box.xyxy[0].cpu().numpy()]
                            mask = np.zeros((img.shape[0], img.shape[1]), dtype=np.uint8)
                            mask[y1:y2, x1:x2] = 255
                            person_masks.append(mask)
        
        yolo_time = time.time() - yolo_start
        print(f"🎯 YOLOv8-seg detected and segmented {len(person_masks)} people ({yolo_time:.2f}s)")
        return person_masks
    except Exception as e:
        print(f"⚠️ YOLO segmentation failed: {e}")
        return []


def _detect_people_bboxes(img: np.ndarray) -> List[List[float]]:
    """Use YOLO to detect person bounding boxes in the image (legacy function for compatibility)."""
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
    """Use SAM to generate masks for detected person bounding boxes (optimized for speed)."""
    if _sam_predictor is None or not bboxes:
        return []
    
    try:
        import time
        sam_start = time.time()
        
        # SPEED OPTIMIZATION: Resize image for faster SAM processing
        original_h, original_w = img.shape[:2]
        max_dim = 512  # Much more aggressive reduction for speed
        if max(original_h, original_w) > max_dim:
            scale = max_dim / max(original_h, original_w)
            new_h, new_w = int(original_h * scale), int(original_w * scale)
            img_resized = np.array(Image.fromarray(img).resize((new_w, new_h)))
            scale_factor = scale
        else:
            img_resized = img
            scale_factor = 1.0
        
        _sam_predictor.set_image(img_resized)
        masks = []
        
        for bbox in bboxes:
            x1, y1, x2, y2 = bbox
            
            # Scale bounding box if image was resized
            if scale_factor != 1.0:
                x1, y1, x2, y2 = x1 * scale_factor, y1 * scale_factor, x2 * scale_factor, y2 * scale_factor
            
            # Use bounding box as prompt for SAM
            input_box = np.array([x1, y1, x2, y2])
            
            mask, scores, logits = _sam_predictor.predict(
                point_coords=None,
                point_labels=None,
                box=input_box[None, :],
                multimask_output=False,  # Single mask for speed
            )
            
            if mask is not None and len(mask) > 0:
                # Scale mask back to original size if needed
                if scale_factor != 1.0:
                    mask_resized = np.array(Image.fromarray((mask[0] > 0).astype(np.uint8) * 255).resize((original_w, original_h)))
                    person_mask = mask_resized
                else:
                    person_mask = (mask[0] > 0).astype(np.uint8) * 255
                masks.append(person_mask)
        
        sam_time = time.time() - sam_start
        print(f"🎯 SAM generated {len(masks)} person masks from bounding boxes (scale: {scale_factor:.2f}, {sam_time:.2f}s)")
        return masks
    except Exception as e:
        print(f"⚠️ SAM mask generation failed: {e}")
        return []


def inpaint_people_from_image_bytes(image_bytes: bytes) -> Optional[Image.Image]:
    """Use YOLO to detect people, then either SAM (precise) or YOLO boxes (fast) for masking, then Stable Diffusion to inpaint.

    Returns a PIL image on success, or None to indicate passthrough.
    """
    global _sd_inpaint_pipeline
    if _sam_predictor is None:
        return None
    img = _np_image_from_bytes(image_bytes)
    try:
        # Step 1 & 2 Combined: Use YOLOv8 segmentation to detect and segment people in one step
        candidate_masks = _get_yolo_person_masks(img)
        if not candidate_masks:
            print("ℹ️ No people detected by YOLOv8 segmentation")
            return None
        # Union all candidate masks
        union_mask = np.zeros((img.shape[0], img.shape[1]), dtype=np.uint8)
        for m in candidate_masks:
            union_mask |= (m > 0).astype(np.uint8) * 255
        union_mask = _dilate_mask_binary(union_mask, kernel_size=11)
        
        # Step 3: Use Stable Diffusion for inpainting with ROI crop for speed
        inpainted = None
        if _sd_inpaint_pipeline is not None:
            try:
                import time
                pil_image_full = Image.fromarray(img)
                pil_mask_full = Image.fromarray(union_mask)

                # Compute ROI from mask to avoid processing the whole image
                ys, xs = np.where(union_mask > 0)
                if len(xs) == 0 or len(ys) == 0:
                    return None
                x1, x2 = int(xs.min()), int(xs.max())
                y1, y2 = int(ys.min()), int(ys.max())

                # Pad ROI a bit
                pad = int(0.12 * max(pil_image_full.size[0], pil_image_full.size[1]))
                x1 = max(0, x1 - pad)
                y1 = max(0, y1 - pad)
                x2 = min(pil_image_full.size[0], x2 + pad)
                y2 = min(pil_image_full.size[1], y2 + pad)

                # Crop ROI
                pil_image_roi = pil_image_full.crop((x1, y1, x2, y2))
                pil_mask_roi = pil_mask_full.crop((x1, y1, x2, y2))

                # Resize ROI directly to 512x512 (no letterbox) to avoid border lines
                target_size = 512
                image_512 = pil_image_roi.resize((target_size, target_size), Image.BICUBIC)
                # Use NEAREST for mask to keep hard edges; we'll feather later
                mask_512 = pil_mask_roi.resize((target_size, target_size), Image.NEAREST)

                # Inference (fast settings)
                start_time = time.time()
                with torch.no_grad():
                    result = _sd_inpaint_pipeline(
                        prompt="empty hallway, clean indoor space",
                        image=image_512,
                        mask_image=mask_512,
                        num_inference_steps=8,
                        guidance_scale=3.0,
                        strength=1.0,
                    )
                inference_time = time.time() - start_time

                # Take output and resize back to ROI size
                out_512 = result.images[0]
                out_roi = out_512.resize((x2 - x1, y2 - y1), Image.BICUBIC)

                # Paste back into original using a feathered mask to avoid seams/lines
                composed = pil_image_full.copy()
                from PIL import ImageFilter
                paste_mask = pil_mask_roi.resize((x2 - x1, y2 - y1), Image.LANCZOS).convert("L")
                paste_mask = paste_mask.filter(ImageFilter.GaussianBlur(5))
                composed.paste(out_roi, (x1, y1), mask=paste_mask)

                inpainted = np.array(composed)
                used_pipeline = 'stable_diffusion'
                print(f"✅ Inpainted using SD1.5 + ROI ({inference_time:.2f}s, ROI {(x2-x1)}x{(y2-y1)})")

            except Exception as e:
                print(f"⚠️ Stable Diffusion inpainting failed: {e}")
                inpainted = None
        else:
            print("⚠️ Stable Diffusion not available for inpainting")
        
        if inpainted is None:
            print("⚠️ All inpainting methods failed, using original image")
            return None
        return Image.fromarray(inpainted)
    except Exception as e:
        print(f"⚠️ Inpainting failed, forwarding original image. Reason: {e}")
        return None

def initialize_vitl14_model():
    """Initialize CLIP ViT-L/14 model for better hallway discrimination"""
    global clip_vitl14_model, clip_vitl14_preprocess, clip_vitl14_tokenizer
    
    if not VITL14_AVAILABLE:
        return False
        
    try:
        print(f"🔄 Loading CLIP ViT-L/14 model on {_device_str}...")
        
        # Load ViT-L/14 model from OpenAI
        clip_vitl14_model, _, clip_vitl14_preprocess = open_clip.create_model_and_transforms(
            'ViT-L-14', 
            pretrained='openai',
            device=_device_str
        )
        
        clip_vitl14_tokenizer = open_clip.get_tokenizer('ViT-L-14')
        
        print(f"✅ CLIP ViT-L/14 model loaded successfully on {_device_str}")
        print(f"📊 Model parameters: ~427M (much better hallway discrimination)")
        
        return True
        
    except Exception as e:
        print(f"❌ Failed to load CLIP ViT-L/14 model: {e}")
        return False

def initialize_clip_client():
    """Initialize the CLIP client connection (fallback)"""
    global clip_client
    try:
        # Connect to the local GRPC CLIP server
        clip_client = Client(server='grpc://127.0.0.1:51000')
        print("✅ Connected to CLIP server at grpc://127.0.0.1:51000")
        return True
    except Exception as e:
        print(f"❌ Failed to connect to CLIP server: {e}")
        return False

def encode_with_vitl14(pil_image: Image.Image) -> List[float]:
    """Encode image using ViT-L/14 model"""
    global clip_vitl14_model, clip_vitl14_preprocess
    
    if clip_vitl14_model is None:
        raise Exception("ViT-L/14 model not loaded")
    
    # Preprocess and encode
    image_tensor = clip_vitl14_preprocess(pil_image).unsqueeze(0).to(_device_str)
    
    with torch.no_grad():
        features = clip_vitl14_model.encode_image(image_tensor)
        features = features / features.norm(dim=-1, keepdim=True)
    
    return features.cpu().numpy().flatten().tolist()

def encode_text_with_vitl14(text: str) -> List[float]:
    """Encode text using ViT-L/14 model"""
    global clip_vitl14_model, clip_vitl14_tokenizer
    
    if clip_vitl14_model is None:
        raise Exception("ViT-L/14 model not loaded")
    
    # Tokenize and encode
    text_tokens = clip_vitl14_tokenizer([text]).to(_device_str)
    
    with torch.no_grad():
        features = clip_vitl14_model.encode_text(text_tokens)
        features = features / features.norm(dim=-1, keepdim=True)
    
    return features.cpu().numpy().flatten().tolist()

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Handle application lifespan events"""
    # Startup - Try ViT-L/14 first, fallback to GRPC client
    vitl14_success = initialize_vitl14_model()
    if not vitl14_success:
        print("⚠️ ViT-L/14 model failed to load, trying GRPC client fallback...")
        clip_success = initialize_clip_client()
        if not clip_success:
            print("⚠️ Both ViT-L/14 and GRPC CLIP server failed. Some endpoints may not work.")
    else:
        print("✅ Using ViT-L/14 model for better hallway discrimination")
    
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
    global clip_vitl14_model, clip_client
    
    # Check ViT-L/14 first (preferred)
    if clip_vitl14_model is not None:
        return {
            "status": "healthy", 
            "message": "CLIP ViT-L/14 server is ready",
            "model": "ViT-L/14",
            "device": _device_str,
            "parameters": "~427M",
            "features": ["SAM", "Stable Diffusion", "YOLO"]
        }
    
    # Fallback to GRPC client
    elif clip_client is not None:
        try:
            # Test the connection with a simple encode
            result = clip_client.encode(['test'])
            return {"status": "healthy", "message": "CLIP server is accessible"}
        except Exception as e:
            raise HTTPException(status_code=503, detail=f"CLIP server error: {str(e)}")
    
    else:
        raise HTTPException(status_code=503, detail="No CLIP model available")

@app.post("/encode", response_model=EmbeddingResponse)
async def encode_image(image: UploadFile = File(...)):
    """Encode an uploaded image using CLIP (ViT-L/14 preferred, fallback to GRPC)"""
    global clip_vitl14_model, clip_client
    
    try:
        # Read and process image
        image_data = await image.read()
        pil_image = Image.open(io.BytesIO(image_data))
        
        # Convert to RGB if needed
        if pil_image.mode != 'RGB':
            pil_image = pil_image.convert('RGB')
        
        # Try ViT-L/14 first (better hallway discrimination)
        if clip_vitl14_model is not None:
            embedding = encode_with_vitl14(pil_image)
            return EmbeddingResponse(embedding=embedding, dimensions=len(embedding))
        
        # Fallback to GRPC client
        elif clip_client is not None:
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
                
            return EmbeddingResponse(embedding=embedding, dimensions=len(embedding))
        
        else:
            raise HTTPException(status_code=503, detail="No CLIP model available")
        
    except Exception as e:
        print(f"Error encoding image: {e}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to encode image: {str(e)}")


@app.post("/encode/inpainted", response_model=EmbeddingResponse)
async def encode_image_inpainted(image: UploadFile = File(...)):
    """Inpaint likely people using SAM+Stable Diffusion before encoding with CLIP ViT-L/14.

    Falls back to original image if inpainting is unavailable or fails.
    """
    global clip_vitl14_model, clip_client

    # Check if any CLIP model is available
    if clip_vitl14_model is None and clip_client is None:
        raise HTTPException(status_code=503, detail="No CLIP model available")

    try:
        # Read the image data
        image_data = await image.read()

        # Try inpainting pipeline
        pil_image = inpaint_people_from_image_bytes(image_data) or Image.open(io.BytesIO(image_data)).convert("RGB")

        # Use ViT-L/14 if available, otherwise fallback to GRPC client
        if clip_vitl14_model is not None:
            embedding = encode_with_vitl14(pil_image)
            return EmbeddingResponse(embedding=embedding, dimensions=len(embedding))
        elif clip_client is not None:
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
        else:
            raise HTTPException(status_code=503, detail="No CLIP model available")
    except Exception as e:
        print(f"Error inpaint-encoding image: {e}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to encode inpainted image: {str(e)}")


@app.post("/encode/preprocessed", response_model=EmbeddingResponse)
async def encode_image_preprocessed(image: UploadFile = File(...)):
    """Alias for clients expecting /encode/preprocessed - uses ViT-L/14 with Stable Diffusion inpainting."""
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
            "stable_diffusion_device": _device_str,
            "sam_model_type": _sam_model_type_used,
            "sam_ckpt": _sam_ckpt_used,
        },
        "endpoints": {
            "health": "/health",
            "encode_image": "/encode (POST with image file)",
            "encode_text": "/encode/text (POST with JSON body)",
            "encode_image_inpainted": "/encode/inpainted (POST with image file; SAM+Stable Diffusion preprocessed)"
        }
    }

if __name__ == "__main__":
    print("🚀 Starting CLIP ViT-L/14 HTTP Gateway...")
    print("🤖 Direct ViT-L/14 model integration (no external server needed)")
    print("🌐 HTTP API will be available at http://192.168.0.104:8000")
    print("🎯 Features: ViT-L/14 + SAM + Stable Diffusion + YOLO (LaMa removed)")
    print("📊 768-dimensional embeddings for better hallway discrimination")
    print()
    
    uvicorn.run(
        "clip_http_gateway:app",
        host="0.0.0.0",  # Bind to all interfaces so Android can connect
        port=8000,
        reload=False,
        log_level="info"
    )
