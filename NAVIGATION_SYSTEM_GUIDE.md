# Indoor Navigation System for Visually Impaired Users

## Overview
This comprehensive navigation system provides real-time guidance for visually impaired users using CLIP embeddings and visual recognition. The system localizes the user's position, shows available routes, and provides turn-by-turn navigation with voice guidance.

## System Architecture

### 1. Position Localization Service (`position_localization_service.dart`)
**Purpose**: Determines user's current location using visual similarity matching

**Key Features**:
- Captures images from the camera and generates CLIP embeddings
- Compares current view with stored location embeddings in the database
- Returns location matches with confidence scores
- Provides a list of available routes from the current position

**Usage**:
```dart
final locationService = PositionLocalizationService(
  clipService: clipService,
  supabaseService: supabaseService,
);

// Localize position from camera image
final location = await locationService.localizePosition(imageFile);

// Get available routes from current location
final routes = await locationService.getAvailableRoutes(location.nodeId);
```

### 2. Real-Time Navigation Service (`real_time_navigation_service.dart`)
**Purpose**: Provides turn-by-turn navigation guidance with embedding comparison

**Key Features**:
- Processes camera frames continuously during navigation
- Compares current view with target waypoint embeddings
- Provides voice instructions and visual guidance
- Detects when waypoints are reached and updates navigation state
- Handles off-track situations and user repositioning

**Navigation States**:
- `idle`: Not navigating
- `navigating`: Active navigation in progress
- `approachingWaypoint`: Close to next waypoint
- `reorientingUser`: Helping user get back on track
- `destinationReached`: Navigation complete
- `offTrack`: User deviated from route

### 3. Navigation Main Screen (`navigation_main_screen.dart`)
**Purpose**: Main UI that orchestrates the entire navigation experience

**Screen Flow**:
1. **Initialization**: Set up camera and services
2. **Position Localization**: Determine current location
3. **Route Selection**: Show available routes to choose from
4. **Route Confirmation**: Confirm selected route details
5. **Active Navigation**: Real-time guidance with visual and audio feedback

## How It Works

### Step 1: Localization
1. User opens the navigation screen
2. Camera initializes and user taps "Find My Location"
3. System captures image and generates CLIP embedding
4. Compares with stored location embeddings in database
5. Returns best matching location with confidence score

### Step 2: Route Selection
1. System queries database for navigation paths starting from current location
2. Shows list of available destinations with:
   - Distance and estimated walking time
   - Number of steps and waypoints
   - Route name and description
3. User selects desired destination

### Step 3: Real-Time Navigation
1. System starts navigation timer (processes frames every 2 seconds)
2. For each frame:
   - Captures image and generates embedding
   - Compares with current target waypoint embedding
   - Calculates similarity score
   - Provides appropriate guidance based on similarity

### Step 4: Waypoint Progression
- **High similarity (>0.8)**: Waypoint reached, move to next
- **Medium similarity (0.5-0.8)**: Provide directional guidance
- **Low similarity (<0.5)**: User may be off-track, provide reorientation help

## Database Schema Integration

### Required Tables:
1. **`map_nodes`**: Location points with coordinates
2. **`navigation_paths`**: Recorded paths between locations
3. **`path_waypoints`**: Individual waypoints with CLIP embeddings
4. **`place_embeddings`**: Reference embeddings for locations

### Key Relationships:
```sql
navigation_paths.start_location_id → map_nodes.id
navigation_paths.end_location_id → map_nodes.id
path_waypoints.path_id → navigation_paths.id
place_embeddings.node_id → map_nodes.id
```

## Voice Guidance Examples

### Navigation Instructions:
- "Continue walking straight ahead"
- "Prepare to turn left in 10 meters"
- "You are approaching the next waypoint"
- "Look for the staircase entrance"
- "Destination reached: Main Library Entrance"

### Status Updates:
- "Starting navigation to Library"
- "Waypoint 3 of 7 reached"
- "You may be off track. Please look around to reorient."
- "Navigation complete"

## Configuration Options

### Thresholds (adjustable in services):
- **Waypoint reached threshold**: 0.8 (80% similarity)
- **Off-track threshold**: 0.5 (50% similarity)
- **Minimum confidence**: 0.7 (70% for location matching)
- **Frame processing interval**: 2 seconds
- **Guidance interval**: 3 seconds

### Accessibility Features:
- High contrast UI with large text
- Voice feedback for all actions
- Haptic feedback support
- Emergency repositioning function
- Manual stop/restart navigation

## Usage Instructions

### For End Users:
1. Open the app and grant camera permission
2. Tap "Find My Location" and point camera at surroundings
3. Wait for location confirmation
4. Select destination from available routes
5. Confirm route details and tap "Start Navigation"
6. Follow voice instructions while walking
7. Use "Reorient" button if lost
8. Navigation stops automatically at destination

### For Administrators:
1. Use admin interface to create maps and nodes
2. Record navigation paths between locations using "Record Path"
3. Ensure good CLIP embeddings are captured during recording
4. Test routes before making them available to users

## Technical Requirements

### Dependencies:
- `camera`: Camera access and image capture
- `flutter_tts`: Text-to-speech for voice guidance
- `flutter_compass`: Heading information
- `permission_handler`: Runtime permissions
- CLIP service for embedding generation
- Supabase for database operations

### Performance Considerations:
- CLIP embedding generation: ~1-2 seconds per image
- Frame processing: Limited to every 2 seconds to avoid overload
- Database queries: Optimized with proper indexing
- Memory management: Temporary image files cleaned up automatically

## Error Handling

### Common Scenarios:
- **Camera not available**: Graceful fallback with error message
- **No location match**: Prompt user to try different angle
- **No routes available**: Inform user and suggest relocation
- **Navigation interrupted**: Allow resume or restart
- **Database connection issues**: Retry with user notification

This system provides a complete navigation solution that adapts to the user's visual capabilities while maintaining high accuracy through CLIP-based visual recognition.
