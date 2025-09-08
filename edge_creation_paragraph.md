# Node Connection (Edge Creation) Process - Final Year Project Documentation

## 4.3.2 Node Connection Process

### Recording and Processing Workflow

The core recording workflow begins with the administrator selecting start and end nodes, after which the system enters a continuous capture loop that executes every three seconds. At each interval, the system performs a comprehensive data acquisition sequence: first capturing the current compass heading, then normalizing it to a 0-360° range, and calculating the heading change relative to the previous waypoint using sophisticated wraparound handling. The heading difference calculation employs circular arithmetic to ensure values remain within the -180° to +180° range, preventing discontinuities at the 0°/360° boundary.

The system then classifies the turn type based on the magnitude and direction of the heading change. Changes less than 30° are classified as straight movements, while larger deviations are categorized as left turns (negative values) or right turns (positive values). Each waypoint is marked as either a regular path point or a decision point based on whether the heading change exceeds the 30° threshold, enabling the system to identify critical navigation junctions.

Following directional analysis, the camera captures a frame which is temporarily stored on the device along with comprehensive metadata including the image file path, normalized heading, heading change magnitude, detected turn type, decision point flag, timestamp, and sequential numbering. Critically, the computationally intensive CLIP embedding generation is deferred during this real-time phase to maintain responsive performance. The raw waypoint data is accumulated in memory, and the capture loop continues until the administrator reaches the destination or manually terminates the recording session.

### Post-Recording Batch Processing

Upon recording completion, the system transitions to intensive batch processing of the accumulated waypoint data. Each stored image is loaded from disk and processed through the CLIP model to generate 768-dimensional embedding vectors that capture the visual characteristics of the location. The embeddings are combined with the previously calculated directional metadata to create complete waypoint objects, after which the original image files are removed to conserve storage resources.

The system then applies intelligent optimization through similarity filtering, comparing adjacent waypoints using cosine similarity calculations on their embedding vectors. Waypoints exhibiting greater than 95% visual similarity and less than 10° heading difference are identified as redundant and removed from the path. This filtering process eliminates unnecessary waypoints while preserving critical decision points and maintaining navigation accuracy. The remaining waypoints are renumbered sequentially to maintain proper path ordering.

### Database Integration and System Updates

The optimized waypoint collection is packaged into a NavigationPath object containing comprehensive metadata including start/end node references, distance calculations, and temporal information. This path data, along with all associated waypoints, is persisted to the Supabase database through batch insertion operations that ensure data consistency and referential integrity.

Finally, a node connection record is created linking the selected nodes while referencing the navigation path, establishing the formal edge in the navigation graph. The system updates all dependent components: the map display renders the new connection with directional arrows, the navigation graph incorporates the pathway for routing algorithms, and the real-time navigation service becomes aware of the additional route option, ensuring immediate availability for user navigation.

### Performance and Error Resilience

The two-phase architecture achieves optimal performance by separating lightweight real-time operations from computationally intensive processing. Recording phase operations complete in under 500 milliseconds per waypoint, ensuring responsive user interaction, while batch processing operates invisibly in the background at 1-2 seconds per frame. Error handling is integrated throughout both phases, with graceful degradation strategies for hardware failures, permission issues, and processing errors that maintain system stability and user experience.
