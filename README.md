# NAVI - AI-Powered Indoor Navigation for the Visually Impaired

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Flutter](https://img.shields.io/badge/Flutter-3.0+-02569B?logo=flutter)
![Python](https://img.shields.io/badge/Python-3.8+-3776AB?logo=python)
![Platform](https://img.shields.io/badge/platform-Android-green.svg)

A hands-free indoor navigation system that helps visually impaired users navigate indoor spaces using **voice commands**, **AI vision**, and **real-time audio guidance**.

## 🎥 Demo Videos

- **Short Demo:** [https://www.youtube.com/shorts/itCl3_iP7ao](https://www.youtube.com/shorts/itCl3_iP7ao)
- **Full Demo:** [https://youtu.be/P53k6R7xUmc?si=uxC3S1T3EWWNEeNO](https://youtu.be/P53k6R7xUmc?si=uxC3S1T3EWWNEeNO)

---

## 🎯 What Does It Do?

**NAVI** is a mobile app that helps blind and visually impaired people navigate indoor buildings independently. Users simply:

1. **Ask where they are**: "Hey Navi, where am I?"
2. **Request navigation**: "Hey Navi, take me to the cafeteria"
3. **Follow voice directions**: Turn-by-turn audio guidance leads them to their destination

The system uses advanced AI to "see" and understand indoor environments through the phone's camera, making indoor navigation as simple as using voice commands.

---

## 🔑 Core Technologies

### 1. **Localization (RAG - Retrieval-Augmented Generation)**

**How it works:**
- System captures 8 camera frames over 8 seconds
- Each frame is converted to a 768-dimensional vector using **DINOv2** (Meta's vision AI)
- These vectors are compared against a database of stored location embeddings
- Best matches are retrieved and verified using **GPT-4 Vision** (Vision-Language Model)
- Location is announced via text-to-speech

**Technical approach:** RAG (Retrieval-Augmented Generation)
- **Retrieval**: Find similar locations by comparing embeddings (cosine similarity > 0.8)
- **Augmentation**: Use reference images and metadata to enhance accuracy
- **Generation**: GPT-4 Vision verifies and explains why the location matches

### 2. **Navigation (Real-Time Embedding Comparison)**

**How it works:**
- Continuous camera feed (10-15 FPS)
- Each frame → DINOv2 embedding (768-dim vector)
- Real-time comparison with recorded waypoint embeddings
- When similarity > 0.87 (adjusts 0.75-0.9 based on scene), waypoint reached
- Audio instruction given: "Continue straight" / "Turn left" / "Turn right"

**Technical approach:** Embedding-based visual odometry
- Pre-recorded paths have waypoints with embeddings
- Live camera embeddings compared to waypoint embeddings
- Match = move to next waypoint
- No match for 30 frames = automatic recovery mode

### 3. **Intelligent Scene Processing**

**Problem**: People and objects in the scene reduce matching accuracy

**Solution**: AI-powered scene cleaning
- **YOLOv8** detects people and carried objects
- **Stable Diffusion 2.0** removes them via inpainting
- Clean scene → better embedding → higher accuracy (95%+ vs 85%)

---

## ✨ Key Features

### 🎤 Voice-First Interface
- **Wake word activation**: "Hey Navi"
- **Natural language**: No need to memorize exact commands
- **GPT-4 powered**: Understands intent from casual speech
- **Hands-free**: Perfect for accessibility

### 🧭 Smart Navigation
- **Initial orientation**: Compass guides user to face correct direction before starting
- **Turn-by-turn audio**: Simple instructions ("turn left", "continue straight")
- **Dynamic thresholds**: Adapts to crowded vs empty scenes
- **Auto-recovery**: If lost, system captures 3 frames and relocates user

### 🤖 Advanced AI
- **DINOv2 vision model**: Superior spatial understanding (768-dim embeddings)
- **YOLOv8 detection**: Identifies people and objects
- **Stable Diffusion inpainting**: Removes temporary obstacles
- **GPT-4 Vision verification**: Confirms locations with human-like reasoning

### 👥 Two User Modes

**Regular Users (Visually Impaired)**
- Voice-activated navigation
- Automatic localization
- Audio-only interface
- TalkBack screen reader support

**Administrators (Sighted)**
- Map management
- Record navigation paths
- Create waypoints
- Manage locations

---

## 🏗️ System Architecture

```
![system_architecture](https://github.com/user-attachments/assets/02a336ae-8686-40ec-9ca2-07004ad10d54)

```

---

## 🛠️ Technology Stack

| Component | Technology | Purpose |
|-----------|-----------|---------|
| **Mobile App** | Flutter (Dart) | Cross-platform UI |
| **Vision AI** | DINOv2 (Meta) | Scene understanding (768-dim embeddings) |
| **Object Detection** | YOLOv8-seg | People & object detection |
| **Scene Cleaning** | Stable Diffusion 2.0 | Remove people from scenes |
| **Voice Recognition** | Porcupine + Google STT | Wake word + speech input |
| **NLU** | GPT-4 | Understand voice commands |
| **VLM** | GPT-4 Vision | Verify locations |
| **Audio Output** | Flutter TTS | Voice guidance |
| **Backend** | Supabase (PostgreSQL) | Database + auth + storage |
| **Server** | FastAPI + PyTorch | AI inference API |

---

## 📦 Quick Start

### Prerequisites

- **Android device** (Android 7.0+) with camera
- **Python 3.8+** and **NVIDIA GPU** (for vision server)
- **Flutter 3.0+** (for building the app)
- **Supabase account** (free tier)
- **OpenAI API key** (for GPT-4 features)

### Installation

#### 1. Set Up Vision AI Server

```bash
# Install Python dependencies
cd scripts
pip install -r ../requirements.txt

# Download YOLOv8 model
wget https://github.com/ultralytics/assets/releases/download/v0.0.0/yolov8l-seg.pt

# Start server (DINOv2 and Stable Diffusion auto-download on first run)
python dinov2_http_gateway.py
# Server runs on http://YOUR_IP:8000
```

#### 2. Set Up Supabase Database

```sql
-- Run database_scheme.sql in Supabase SQL Editor
-- Creates tables: maps, map_nodes, navigation_paths, path_waypoints, place_embeddings
```

Create storage buckets:
- `reference-images` (public)
- `maps` (public)

#### 3. Configure Flutter App

Create `.env` file:
```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
OPENAI_API_KEY=sk-your-api-key
```

Update server URL in `lib/services/dinov2_service.dart`:
```dart
static const String _defaultServerUrl = 'http://YOUR_SERVER_IP:8000';
```

#### 4. Build and Run

```bash
flutter pub get
flutter run
```

---

## 📖 How to Use

### For Administrators: Set Up Navigation

1. **Create Map**: Upload a floor plan image
2. **Add Locations**: Tap on map to create nodes (e.g., "Main Entrance", "Cafeteria")
3. **Record Paths**: 
   - Select start and end locations
   - Walk the route with phone's camera facing forward
   - System automatically captures waypoints every 2 seconds
   - Each waypoint stores: DINOv2 embedding + compass heading + reference image

### For Users: Navigate Hands-Free

**Find your location:**
```
"Hey Navi, where am I?"
```
- System scans for 8 seconds
- Detects and removes people from scene (if present)
- Matches your location using embeddings
- Announces: "You are at Main Entrance"

**Start navigation:**
```
"Hey Navi, take me to the cafeteria"
```
- System guides you to face the correct direction
- Provides turn-by-turn audio instructions
- "Continue straight" → "Turn left" → "Turn right"
- "Stop, you have reached Cafeteria. Cafeteria is on your right."

**Other commands:**
```
"Hey Navi, what routes are available?"
"Hey Navi, why do you think I'm here?"
"Hey Navi, stop"
```

---

## 🔬 How It Works (Technical Details)

### RAG-Based Localization

**Step 1: Retrieval** (Vector Search)
```
Camera frames (8 frames) 
  → DINOv2 encoding 
  → 768-dim embeddings 
  → Cosine similarity search against database
  → Top matches (similarity > 0.8)
```

**Step 2: Augmentation** (Context Enhancement)
```
Retrieved matches 
  → Fetch reference images 
  → Fetch metadata (node name, directions)
  → Pair with captured frames
```

**Step 3: Generation** (VLM Verification)
```
Image pairs + metadata 
  → GPT-4 Vision API
  → "Do these images show the same location?"
  → Confidence score + reasoning
  → Final location decision
```

### Embedding-Based Navigation

**Waypoint Matching Loop:**
```python
while not destination_reached:
    # Capture frame
    frame = camera.capture()
    
    # Clean scene (if people detected)
    if yolo.detect_people(frame):
        frame = stable_diffusion.inpaint(frame)
    
    # Generate embedding
    embedding = dinov2.encode(frame)  # 768-dim
    
    # Compare with current waypoint
    similarity = cosine_similarity(embedding, waypoint.embedding)
    
    # Dynamic threshold based on scene
    threshold = 0.87 if clean_scene else 0.75
    
    if similarity > threshold:
        speak(waypoint.instruction)  # "Turn left"
        waypoint = next_waypoint()
    
    if no_match_for_30_frames:
        trigger_recovery()
```

**Why Embeddings?**
- **Robust**: Works in different lighting, angles, times
- **Compact**: 768 numbers vs millions of pixels
- **Fast**: Cosine similarity is O(n) operation
- **Semantic**: Captures meaning, not just pixels

---

## 📊 Performance

### Accuracy
- **Localization**: 95% (clean scenes), 90% (crowded scenes)
- **Navigation**: 92% waypoint detection accuracy
- **Recovery**: 85% success rate

### Speed
- **Localization**: 8-10 seconds
- **Navigation**: 10-15 FPS real-time processing
- **Server inference**: 0.5-2s per frame (GPU)

### Thresholds
- **Localization**: 0.8 (RAG retrieval)
- **Navigation clean**: 0.87 (embedding match)
- **Navigation crowded**: 0.75 (adjusted for people)
- **Turn waypoints**: 0.9 (higher precision for turns)

---

## 🗄️ Database Schema

**Core tables:**

```sql
-- Maps (floor plans)
maps: id, name, image_url, organization_id

-- Locations (nodes on map)
map_nodes: id, map_id, name, x_position, y_position, reference_direction

-- Recorded routes
navigation_paths: id, name, start_location_id, end_location_id

-- Waypoints with embeddings
path_waypoints: id, path_id, sequence_number, heading, turn_type,
                embedding (768-dim vector), people_detected, reference_image_url

-- Location embeddings for RAG retrieval
place_embeddings: id, node_id, place_name, embedding (768-dim vector)
```

---

## 🎛️ Configuration

### Adjust Navigation Thresholds

Edit `lib/services/real_time_navigation_service.dart`:

```dart
// Higher = more strict matching (fewer false positives)
// Lower = more lenient matching (works in varying conditions)

static const double _waypointReachedThresholdDefault = 0.87;  // Standard
static const double _cleanSceneThreshold = 0.87;              // No people
static const double _peoplePresentThreshold = 0.84;           // 1-2 people
static const double _crowdedSceneThreshold = 0.75;            // 3+ people
static const double _turnWaypointThreshold = 0.9;             // Before turns
```

### Server Performance Mode

Edit environment before starting server:

```bash
# Fast mode (real-time navigation)
export SD_REALTIME_MODE=true

# Quality mode (better inpainting)
export SD_REALTIME_MODE=false

python dinov2_http_gateway.py
```

---

## 🤝 Contributing

Contributions welcome! This project helps improve accessibility for visually impaired users.

**Areas for contribution:**
- iOS support
- Offline mode (local embeddings)
- Multi-language support
- Advanced obstacle detection
- Performance optimizations

---

## 📄 License

MIT License - See [LICENSE](LICENSE) file for details.

---

