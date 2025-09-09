# Chapter 5: System Implementation

## 5.3 Settings and Configuration

### 5.3.1 Flutter Dependencies

The Flutter application utilizes a comprehensive set of dependencies to implement the indoor navigation system for visually impaired users. These dependencies are managed through the `pubspec.yaml` file and provide essential functionality for camera access, AI processing, database connectivity, and user interface components.

#### Core Flutter Framework
```yaml
environment:
  sdk: ">=2.17.0 <3.0.0"
```
The application targets Flutter SDK version 2.17.0 and above, ensuring compatibility with modern Dart language features and performance optimizations.

#### Core Navigation Functionality
```yaml
camera: ^0.11.1
flutter_compass: ^0.8.0
permission_handler: ^11.3.1
```
- **camera**: Provides access to device camera hardware for recording 360° navigation videos
- **flutter_compass**: Accesses device compass for directional heading measurements during navigation
- **permission_handler**: Manages runtime permissions for camera, location, and storage access

#### Media Handling Dependencies
```yaml
video_player: ^2.8.6
video_thumbnail: ^0.5.3
image_picker: ^1.1.2
path_provider: ^2.1.3
```
- **video_player**: Enables playback of recorded navigation videos for user verification
- **video_thumbnail**: Generates preview thumbnails from recorded videos
- **image_picker**: Allows users to select images from device gallery for testing purposes
- **path_provider**: Manages file system paths for storing captured videos and temporary files

#### Backend Integration
```yaml
supabase_flutter: ^2.10.0
flutter_dotenv: ^5.2.1
```
- **supabase_flutter**: Provides seamless integration with Supabase backend services for user authentication, real-time database operations, and file storage
- **flutter_dotenv**: Manages environment variables and configuration settings for secure credential storage

#### Utility Dependencies
```yaml
uuid: ^4.4.0
flutter_tts: ^4.0.2
app_links: ^6.3.2
```
- **uuid**: Generates unique identifiers for navigation paths, waypoints, and database records
- **flutter_tts**: Implements text-to-speech functionality for audio navigation guidance
- **app_links**: Handles deep linking for authentication callbacks and external URL handling

#### Asset Configuration
```yaml
flutter:
  uses-material-design: true
  assets:
    - .env
```
The application includes environment configuration for secure credential management:
- **.env**: Environment configuration file containing Supabase credentials and API endpoints

### 5.3.2 FastAPI Server Configuration

The FastAPI server serves as the AI processing backend, providing high-performance computer vision services for the Flutter mobile application. The server is implemented in Python and integrates multiple state-of-the-art AI models for comprehensive scene understanding and processing.

#### Server Architecture and Dependencies

The server is implemented using FastAPI framework with asynchronous processing capabilities, enabling concurrent handling of multiple client requests. The server configuration includes the following key dependencies:

```python
# Core Web Framework (Updated to match conda environment)
fastapi==0.116.1                    # Latest stable FastAPI with enhanced async support
uvicorn==0.23.1                     # Updated ASGI server with enhanced features
python-multipart==0.0.6             # File upload handling
pydantic==2.11.7                    # Latest stable data validation
pydantic_core==2.33.2               # Core validation engine

# Image Processing and Computer Vision
Pillow==11.1.0                       # Python Imaging Library (PIL fork)
numpy==2.0.1                        # Scientific computing, compatible with PyTorch 2.5.1
opencv-python==4.12.0.88            # Computer vision preprocessing

# AI/ML Frameworks
torch==2.5.1                         # PyTorch with CUDA 11.8/12.1 support
torchvision==0.20.1                  # Vision models and transforms for PyTorch 2.5.1
transformers==4.56.0                 # Hugging Face transformers for DINOv2 vision model

# Object Detection
ultralytics==8.3.191                 # YOLOv8 implementation for person detection

# Computer Vision Models (Optional - Advanced Features)
segment_anything @ git+https://github.com/facebookresearch/segment-anything.git  # SAM for segmentation
diffusers==0.35.1                    # Stable Diffusion for inpainting (optional)
```

#### AI Model Integration

The server integrates advanced AI models to provide comprehensive scene understanding:

**DINOv2 Vision Transformer**
- **Purpose**: Advanced feature extraction for spatial understanding and visual place recognition
- **Configuration**: Self-supervised training on large-scale datasets, 768-dimensional embeddings
- **Benefits**: Superior discrimination of similar indoor environments through transformers
- **Integration**: Hosted via HTTP API using Hugging Face transformers library

**YOLOv8 Object Detection**
- **Purpose**: Real-time object and person detection for safety navigation
- **Configuration**: Ultralytics implementation with COCO dataset training
- **Application**: Safety-aware navigation with dynamic obstacle detection

**Segment Anything Model (SAM)**
- **Purpose**: Precise object segmentation and masking
- **Configuration**: Vision Transformer architecture with automatic mask generation
- **Application**: Person detection and removal for privacy protection

**Stable Diffusion Inpainting**
- **Purpose**: Intelligent background reconstruction after object removal
- **Configuration**: Latent Diffusion Model with optimized inference
- **Features**: Real-time processing with adaptive quality settings

**YOLOv8 Object Detection**
- **Purpose**: Real-time object and person detection
- **Configuration**: Ultralytics implementation with COCO dataset training
- **Application**: Safety-aware navigation with dynamic obstacle detection

#### Server Configuration and Startup

The server is configured through environment variables and command-line parameters:

```bash
# Server Configuration
HOST=192.168.0.103
PORT=8000
WORKERS=4

# Model Configuration
CLIP_MODEL=ViT-L/14
SAM_MODEL_TYPE=vit_h
SD_MODEL_TYPE=runwayml/stable-diffusion-inpainting

# Performance Settings
SD_REALTIME_MODE=true
MAX_BATCH_SIZE=4
```

The server startup process includes:
1. **Model Loading**: Sequential loading of all AI models with progress indication
2. **Service Initialization**: Establishing HTTP endpoints and middleware
3. **Health Checks**: Automatic verification of all integrated services
4. **CORS Configuration**: Cross-origin resource sharing for mobile app connectivity

#### API Endpoints and Functionality

The FastAPI server exposes several RESTful endpoints for the Flutter application:

**Core Processing Endpoints**
- `POST /process_image`: Main image processing with CLIP embedding generation
- `POST /detect_objects`: YOLO-based object detection for safety analysis
- `POST /remove_people`: SAM + Stable Diffusion pipeline for privacy protection

**Utility Endpoints**
- `GET /health`: Service health and status monitoring
- `GET /models`: Available model information and capabilities
- `POST /batch_process`: Batch processing for multiple images

**Configuration Endpoints**
- `POST /update_settings`: Dynamic parameter adjustment
- `GET /performance_stats`: Real-time performance monitoring

### 5.3.3 Supabase Configuration

Supabase serves as the backend-as-a-service platform, providing authentication, database, and storage capabilities for the indoor navigation system. The configuration integrates seamlessly with the Flutter application through the `supabase_flutter` package.

#### Authentication Configuration

The Supabase authentication is configured in the Flutter application initialization:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();

  final supabaseService = SupabaseService();
  await supabaseService.initialize();

  runApp(MyApp());
}
```

The SupabaseService initialization includes:
```dart
Future<void> initialize() async {
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  await _initializeStorage();
}
```

#### Environment Configuration

The application uses environment variables for Supabase configuration, stored in a `.env` file:

```env
# Supabase Configuration
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key-here

# Optional: Additional configuration
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
```

#### Database Schema and Row Level Security

The Supabase database implements a multi-tenant architecture with comprehensive Row Level Security (RLS) policies:

**Core Tables and Relationships**
- **profiles**: User accounts linked to organizations
- **organizations**: Multi-tenant data isolation containers
- **maps**: Indoor environment representations
- **map_nodes**: Physical locations with coordinate data
- **place_embeddings**: AI-generated visual signatures
- **node_connections**: Navigable pathways between locations
- **navigation_paths**: Complete routes with waypoint sequences
- **path_waypoints**: Sequential navigation points with embeddings

**Row Level Security Policies**
```sql
-- Organization-based access control
ALTER TABLE maps ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can access maps from their organization"
ON maps FOR ALL USING (organization_id IN (
  SELECT organization_id FROM profiles WHERE id = auth.uid()
));
```

#### Storage Configuration

Supabase Storage is configured with dedicated buckets for different content types:

```dart
Future<void> _initializeStorage() async {
  try {
    await _createBucketIfNotExists('maps');
    await _createBucketIfNotExists('place_images');
  } catch (e) {
    print('Storage initialization error: $e');
  }
}
```

**Storage Buckets**
- **maps**: Floor plan images and building layouts
- **place_images**: Navigation waypoint photographs
- **user_uploads**: User-generated content and custom images

#### Real-time Subscriptions

The application leverages Supabase's real-time capabilities for live updates:

```dart
final subscription = supabase
  .channel('navigation_paths')
  .onPostgresChanges(
    event: PostgresChangeEvent.all,
    schema: 'public',
    table: 'navigation_paths',
    callback: (payload) => updateNavigationState(payload),
  )
  .subscribe();
```

#### Authentication Flow Integration

The Supabase authentication integrates with Flutter's navigation system:

```dart
void _handleDeepLink(Uri uri) {
  final params = Uri.splitQueryString(uri.fragment);
  final accessToken = params['access_token'];
  final refreshToken = params['refresh_token'];

  if (accessToken != null && refreshToken != null) {
    if (uri.path.contains('reset')) {
      _navigateToNewPasswordScreen(accessToken, refreshToken);
    } else {
      _handleEmailConfirmation(accessToken, refreshToken);
    }
  }
}
```

#### Performance Optimization

The Supabase configuration includes several performance optimization strategies:

**Database Indexing**
- Foreign key relationships are automatically indexed
- Composite indexes on frequently queried columns
- Partial indexes for active records

**Connection Pooling**
- Automatic connection management through Supabase client
- Request batching for multiple database operations
- Connection reuse for improved performance

**Caching Strategy**
- Local caching of frequently accessed data
- Offline queue for network-dependent operations
- Selective synchronization based on data freshness

#### Monitoring and Analytics

Supabase provides built-in monitoring capabilities:

```dart
// Query performance monitoring
final response = await supabase
  .from('navigation_paths')
  .select()
  .explain(); // Shows query execution plan

// Real-time metrics
final metrics = await supabase
  .rest
  .rpc('get_database_metrics');
```

#### Security Configuration

The Supabase setup implements multiple security layers:

**API Key Management**
- Public anonymous key for client-side operations
- Service role key for server-side administrative tasks
- Environment-based key rotation

**Network Security**
- HTTPS-only communication
- CORS configuration for mobile app connectivity
- Rate limiting and abuse prevention

**Data Encryption**
- Automatic encryption of sensitive data at rest
- TLS 1.3 encryption for data in transit
- Secure key management for encryption operations

This comprehensive configuration ensures secure, scalable, and performant backend services for the indoor navigation system, supporting both real-time navigation and administrative management functions.
