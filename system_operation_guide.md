# Chapter 5.4: System Operation

## Indoor Navigation System - Operation Guide

This chapter demonstrates the practical operation of the indoor navigation system through visual documentation and step-by-step workflows.

---

## 5.4.1 System Setup and Configuration

### Category 5.4.1.1: Development Environment Setup

**Screenshots Required:**
1. **Flutter SDK Installation** - Command prompt showing Flutter installation
2. **Android Studio Setup** - Android Studio welcome screen with Flutter plugin
3. **VS Code Flutter Extension** - VS Code with Flutter/Dart extensions installed
4. **Project Structure** - File explorer showing complete project structure
5. **Pub Dependencies** - Terminal output showing `flutter pub get` completion
6. **Device Connection** - Android device/emulator connected and recognized

**Purpose:** Demonstrate the development environment setup process

---

### Category 5.4.1.2: Backend Server Configuration

**Screenshots Required:**
1. **Conda Environment** - Terminal showing conda environment activation
2. **Python Dependencies** - `pip install -r requirements.txt` execution
3. **FastAPI Server Startup** - Server running on specified port
4. **Health Check Endpoint** - Browser showing `/health` endpoint response
5. **Model Loading Process** - Console output showing DINOv2 model loading
6. **Server Logs** - Terminal showing successful server initialization

**Purpose:** Show the backend AI server setup and verification

---

### Category 5.4.1.3: Supabase Database Setup

**Screenshots Required:**
1. **Supabase Dashboard** - Main dashboard showing project overview
2. **Database Schema** - SQL Editor with table creation scripts
3. **Authentication Settings** - Auth configuration in Supabase dashboard
4. **Storage Buckets** - File storage setup for maps and images
5. **API Keys** - Project API keys (partially obscured for security)
6. **Row Level Security** - RLS policies configuration

**Purpose:** Demonstrate database and backend service configuration

---

## 5.4.2 User Interface Operations

### Category 5.4.2.1: Authentication Flow

**Screenshots Required:**
1. **Login Screen** - App login interface
2. **Registration Screen** - User registration form
3. **Password Reset** - Forgot password functionality
4. **Email Verification** - Verification email sent confirmation
5. **Profile Screen** - User profile management
6. **Logout Process** - Logout confirmation dialog

**Purpose:** Show user authentication and account management

---

### Category 5.4.2.2: Map Management

**Screenshots Required:**
1. **Map Upload Interface** - File selection for map images
2. **Map Display** - Interactive map view with zoom/pan controls
3. **Map Properties** - Map metadata editing (name, description, visibility)
4. **Map Sharing** - Public/private map settings
5. **Map Deletion** - Map removal confirmation
6. **Map Gallery** - List of all user's maps

**Purpose:** Demonstrate map creation, management, and sharing

---

### Category 5.4.2.3: Node Creation and Management

**Screenshots Required:**
1. **Node Placement** - Touch interface for placing nodes on map
2. **Node Naming** - Text input for node names
3. **Direction Capture** - Compass interface for reference direction
4. **Video Recording** - 360° video recording interface
5. **Node List** - Display of all nodes on a map
6. **Node Editing** - Modify existing node properties
7. **Node Deletion** - Remove node confirmation

**Purpose:** Show the complete node creation workflow

---

### Category 5.4.2.4: Path Recording and Navigation

**Screenshots Required:**
1. **Path Selection** - Choose start and end nodes for navigation
2. **Recording Interface** - Real-time path recording screen
3. **Waypoint Capture** - Automatic waypoint creation during movement
4. **Navigation Start** - Begin navigation from current location
5. **Turn Instructions** - Audio/text navigation guidance
6. **Destination Reached** - Completion confirmation
7. **Navigation History** - Previous navigation sessions

**Purpose:** Demonstrate the core navigation functionality

---

## 5.4.3 Backend Operations

### Category 5.4.3.1: AI Processing Operations

**Screenshots Required:**
1. **Model Inference** - Console output showing DINOv2 processing
2. **Embedding Generation** - Vector generation logs
3. **Similarity Calculation** - Matching algorithm execution
4. **Batch Processing** - Multiple image processing queue
5. **Processing Results** - Successful embedding generation
6. **Error Handling** - Failed processing recovery

**Purpose:** Show AI model operations and processing pipeline

---

### Category 5.4.3.2: Database Operations

**Screenshots Required:**
1. **Data Insertion** - New records being added to database
2. **Query Execution** - Database queries in Supabase dashboard
3. **Data Retrieval** - API responses showing data fetching
4. **Real-time Updates** - Live data synchronization
5. **Backup Operations** - Database backup process
6. **Performance Metrics** - Query execution times and optimization

**Purpose:** Demonstrate database operations and performance

---

### Category 5.4.3.3: API Communications

**Screenshots Required:**
1. **API Requests** - Network requests in browser dev tools
2. **Response Handling** - Successful API response parsing
3. **Error Responses** - API error handling and user feedback
4. **Real-time Sync** - WebSocket connections for live updates
5. **Authentication Headers** - Secure API communication
6. **Rate Limiting** - API throttling and queue management

**Purpose:** Show system communication and data exchange

---

## 5.4.4 Testing and Validation

### Category 5.4.4.1: Unit Testing

**Screenshots Required:**
1. **Test Execution** - Running Flutter/Dart unit tests
2. **Test Results** - Test pass/fail reports
3. **Code Coverage** - Test coverage analysis
4. **Mock Services** - Simulated backend responses
5. **Integration Tests** - Full system component testing
6. **Performance Tests** - Load testing results

**Purpose:** Demonstrate software testing procedures

---

### Category 5.4.4.2: User Acceptance Testing

**Screenshots Required:**
1. **Test Scenarios** - Defined test cases and expected outcomes
2. **User Feedback** - Testing session recordings
3. **Bug Reports** - Issue tracking and resolution
4. **Performance Metrics** - System response times
5. **Accessibility Testing** - Screen reader compatibility
6. **Cross-device Testing** - Different device compatibility

**Purpose:** Show testing methodologies and validation

---

## 5.4.5 System Maintenance

### Category 5.4.5.1: Monitoring and Logging

**Screenshots Required:**
1. **System Logs** - Application and server log files
2. **Performance Monitoring** - System resource usage
3. **Error Tracking** - Exception logging and alerts
4. **User Analytics** - Usage statistics and patterns
5. **Database Monitoring** - Query performance and optimization
6. **API Monitoring** - Endpoint usage and response times

**Purpose:** Demonstrate system monitoring capabilities

---

### Category 5.4.5.2: Backup and Recovery

**Screenshots Required:**
1. **Automated Backups** - Scheduled backup processes
2. **Manual Backup** - On-demand backup creation
3. **Data Export** - Export functionality for data migration
4. **Recovery Testing** - Backup restoration verification
5. **Disaster Recovery** - System recovery procedures
6. **Data Integrity** - Validation after recovery operations

**Purpose:** Show data protection and recovery procedures

---

## Implementation Guidelines

### Screenshot Standards:
1. **Resolution**: High resolution (1920x1080 or higher)
2. **Format**: PNG format for quality
3. **Annotations**: Use arrows/circles to highlight key elements
4. **Context**: Include relevant UI elements and system status
5. **Consistency**: Maintain similar styling across screenshots

### Caption Format:
```
Figure 5.4.1.1: Flutter SDK Installation Process
Command prompt showing successful Flutter installation with version details.
```

### Documentation Structure:
```
5.4.1 System Setup and Configuration
├── 5.4.1.1 Development Environment Setup
├── 5.4.1.2 Backend Server Configuration
└── 5.4.1.3 Supabase Database Setup

5.4.2 User Interface Operations
├── 5.4.2.1 Authentication Flow
├── 5.4.2.2 Map Management
├── 5.4.2.3 Node Creation and Management
└── 5.4.2.4 Path Recording and Navigation

5.4.3 Backend Operations
├── 5.4.3.1 AI Processing Operations
├── 5.4.3.2 Database Operations
└── 5.4.3.3 API Communications

5.4.4 Testing and Validation
├── 5.4.4.1 Unit Testing
└── 5.4.4.2 User Acceptance Testing

5.4.5 System Maintenance
├── 5.4.5.1 Monitoring and Logging
└── 5.4.5.2 Backup and Recovery
```

This structure provides comprehensive coverage of system operations suitable for final year project evaluation.



