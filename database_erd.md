# 4.6 Database Design

## Database Schema Overview

The indoor navigation system utilizes a PostgreSQL database hosted on Supabase with a multi-tenant architecture. The database consists of 11 main entities designed to support AI-powered navigation for visually impaired users.

## Entity-Relationship Diagram

```mermaid
erDiagram
    %% ENTITIES
    profiles {
        string id PK
        string email
        string role
        string organization_id FK
        datetime created_at
        datetime updated_at
    }

    organizations {
        string id PK
        string name
        string description
        string created_by_admin_id FK
        datetime created_at
        datetime updated_at
    }

    maps {
        string id PK
        string name
        string description
        string organization_id FK
        datetime created_at
        datetime updated_at
    }

    map_nodes {
        string id PK
        string map_id FK
        string name
        float x_position
        float y_position
        float reference_direction
        string organization_id FK
        string user_id FK
        datetime created_at
    }

    place_embeddings {
        string id PK
        string node_id FK
        string place_name
        float[] embedding
        string organization_id FK
        string user_id FK
        datetime created_at
        datetime updated_at
    }

    node_connections {
        string id PK
        string map_id FK
        string node_a_id FK
        string node_b_id FK
        float distance_meters
        int steps
        float average_heading
        string custom_instruction
        json confirmation_objects
        string user_id FK
        datetime created_at
    }

    navigation_paths {
        string id PK
        string name
        string start_location_id FK
        string end_location_id FK
        float estimated_distance
        int estimated_steps
        string organization_id FK
        string user_id FK
        datetime created_at
        datetime updated_at
    }

    path_waypoints {
        string id PK
        string path_id FK
        int sequence_number
        float[] embedding
        float heading
        float heading_change
        string turn_type
        boolean is_decision_point
        string landmark_description
        float distance_from_previous
        boolean people_detected
        int people_count
        float[] people_confidence_scores
        datetime timestamp
    }

    walking_sessions {
        string id PK
        string map_id FK
        string start_node_id FK
        string end_node_id FK
        float distance_meters
        int step_count
        float average_heading
        string instruction
        json detected_objects
        string user_id FK
        datetime created_at
    }

    recorded_paths {
        string id PK
        string name
        string description
        json segments
        json suggested_checkpoints
        float total_distance
        int total_steps
        string organization_id FK
        string user_id FK
        datetime created_at
        datetime updated_at
    }

    %% RELATIONSHIPS
    profiles ||--o{ organizations : belongs_to
    organizations ||--o{ profiles : has_many
    organizations ||--o{ maps : owns
    organizations ||--o{ map_nodes : owns
    organizations ||--o{ place_embeddings : owns
    organizations ||--o{ navigation_paths : owns
    organizations ||--o{ recorded_paths : owns

    maps ||--o{ map_nodes : contains
    maps ||--o{ node_connections : defines
    maps ||--o{ walking_sessions : records

    map_nodes ||--o{ place_embeddings : has
    map_nodes ||--o{ node_connections : connects_from
    map_nodes ||--o{ node_connections : connects_to
    map_nodes ||--o{ navigation_paths : starts_at
    map_nodes ||--o{ navigation_paths : ends_at
    map_nodes ||--o{ walking_sessions : starts_at
    map_nodes ||--o{ walking_sessions : ends_at

    navigation_paths ||--o{ path_waypoints : consists_of

    profiles ||--o{ maps : creates
    profiles ||--o{ map_nodes : creates
    profiles ||--o{ place_embeddings : creates
    profiles ||--o{ node_connections : creates
    profiles ||--o{ navigation_paths : creates
    profiles ||--o{ path_waypoints : creates
    profiles ||--o{ walking_sessions : creates
    profiles ||--o{ recorded_paths : creates
```

## Key Entities Description

### Core Entities
- **profiles**: User accounts with organization membership
- **organizations**: Multi-tenant data isolation containers
- **maps**: Indoor environment representations
- **map_nodes**: Physical locations (rooms, corridors, landmarks)

### AI Integration
- **place_embeddings**: DINOv2/CLIP visual signatures (768-dim vectors)
- **path_waypoints**: Sequential embeddings for navigation guidance

### Navigation Data
- **node_connections**: Pathways between locations with distance and instructions
- **navigation_paths**: Pre-recorded routes between destinations
- **walking_sessions**: User movement data for path optimization
- **recorded_paths**: User-created navigation routes

## Database Architecture Features

### Multi-Tenant Design
- Organization-based data isolation using Row-Level Security (RLS)
- Users can only access data within their organization
- Admins manage users and data within their organizations

### AI-Powered Navigation
- 768-dimensional embeddings for visual place recognition
- Dynamic similarity thresholds based on scene complexity
- Majority voting system for reliable localization

### Performance Optimizations
- Optimized float array storage for embeddings
- Cosine similarity calculations for fast matching
- Sequential waypoint processing for real-time guidance

This database design supports the complete indoor navigation workflow from user management through AI-powered localization to real-time navigation guidance.
