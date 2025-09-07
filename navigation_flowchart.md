# Navigation Module Flowchart

## 📋 Navigation Process Overview

The navigation module guides users from their current location to their destination using real-time camera processing and AI-powered waypoint detection.

### 🎯 Key Components:

1. **🧭 Initial Orientation**: Uses compass to guide user to face the correct starting direction
2. **📸 Real-Time Processing**: Captures camera frames every 1 second during navigation
3. **🤖 AI Pipeline**: YOLO person detection + DINOv2 embedding generation
4. **🎯 Waypoint Detection**: Compares current view with target waypoint embeddings
5. **📢 Audio Guidance**: Text-to-speech instructions for visually impaired users
6. **⚠️ Off-Track Recovery**: Automatic detection and repositioning assistance

### 🔄 Main Flow States:
- **Orientation Phase**: Getting user facing the right direction
- **Active Navigation**: Real-time waypoint tracking and guidance
- **Repositioning**: Helping user get back on track when off-course
- **Completion**: Arriving at destination

---

## Detailed Flowchart (Technical Version)

```mermaid
flowchart TD
    A[Route Selected] --> B[Start Navigation]
    B --> C[Initial Orientation Phase]

    C --> D[Initialize Compass]
    D --> E{Compass Available?}

    E -->|No| F[Skip Orientation]
    E -->|Yes| G[Guide User to Face First Waypoint]

    G --> H{User Facing Correct Direction?}
    H -->|No| I[Provide Turn Instructions]
    I --> H

    H -->|Yes| J[Orientation Complete]
    F --> J

    J --> K[Start Real-Time Navigation]
    K --> L[Begin Frame Processing Timer]

    L --> M[Capture Camera Frame]
    M --> N[Send to AI Processing]

    N --> O[YOLO Person Detection]
    O --> P{People Detected?}

    P -->|Yes| Q[Inpainting: Remove People]
    P -->|No| R[Skip Inpainting]

    Q --> S[DINOv2 Embedding Generation]
    R --> S

    S --> T[Compare vs Current Waypoint]
    T --> U{Similarity > Threshold?}

    U -->|Yes| V[Waypoint Reached]
    U -->|No| W[Continue to Next Waypoint]

    V --> X[Update Sequence Number]
    X --> Y{More Waypoints?}

    Y -->|Yes| Z[Load Next Waypoint]
    Y -->|No| AA[Destination Reached]

    Z --> BB[Update Navigation Instruction]
    BB --> CC[Speak Audio Guidance]
    CC --> DD[Update UI Display]

    W --> EE[Continue Current Instruction]
    EE --> BB

    AA --> FF[Stop Navigation Timer]
    FF --> GG[Speak "Destination Reached"]
    GG --> HH[Show Completion Message]

    DD --> II[Wait for Next Frame]
    II --> M

    BB --> JJ[Progress Tracking]
    JJ --> KK[Update Progress Bar]
    KK --> II

    W --> LL{Off-Track Detection}
    LL -->|Yes| MM[Increment Off-Track Counter]
    LL -->|No| NN[Reset Counter]

    MM --> OO{Counter > 3?}
    OO -->|Yes| PP[Request User Repositioning]
    OO -->|No| EE

    PP --> QQ[Pause Navigation]
    QQ --> RR[Guide User to Reorient]
    RR --> SS[Resume Navigation After Timeout]
    SS --> EE
```

---

## Simplified Flowchart (User-Friendly Version)

```mermaid
flowchart TD
    A[Route Selected] --> B[Start Navigation]
    B --> C[🧭 Initial Orientation]

    C --> D{Compass Available?}
    D -->|No| E[Skip to Navigation]
    D -->|Yes| F[Guide User Direction]

    F --> G{Facing Correct Way?}
    G -->|No| H[Audio: "Turn Left/Right"]
    H --> G

    G -->|Yes| I[✅ Orientation Complete]
    E --> I

    I --> J[🚀 Start Navigation]
    J --> K[📸 Capture Frame Every 1s]

    K --> L[🤖 AI Processing]
    L --> M{Similar to Target Waypoint?}

    M -->|Yes| N[🎯 Waypoint Reached!]
    M -->|No| O[📍 Continue Current Path]

    N --> P[Next Waypoint]
    P --> Q{More Waypoints?}

    Q -->|Yes| R[📢 Update Instructions]
    Q -->|No| S[🏁 Destination Reached!]

    R --> T[🎵 Speak Guidance]
    T --> U[📱 Update UI]
    U --> K

    O --> V{User Off-Track?}
    V -->|Yes| W[⚠️ Repositioning Mode]
    V -->|No| K

    W --> X[⏸️ Pause Navigation]
    X --> Y[🔄 Guide User to Reorient]
    Y --> Z[▶️ Resume After 10s]
    Z --> K

    S --> AA[🛑 Stop All Timers]
    AA --> BB[🎉 "You have arrived!"]
```

---

## 🎵 Audio Instructions Flow:
1. **"Navigation started. Let me help you face the right direction first."**
2. **"Turn left/right"** (during orientation)
3. **"Perfect! You are facing the right direction."**
4. **"Starting navigation now."**
5. **"Continue straight/Turn left/Turn right"** (waypoint guidance)
6. **"You have arrived at your destination!"** (completion)

## ⚙️ Technical Details:
- **Frame Rate**: 1 frame per second during navigation
- **AI Processing**: YOLO + DINOv2 on each frame
- **Thresholds**: Dynamic based on scene complexity (0.85 clean, 0.75 people, 0.70 crowded)
- **Off-Track Recovery**: Activates after 3 consecutive off-track detections
- **Repositioning Timeout**: 10 seconds to allow user reorientation
