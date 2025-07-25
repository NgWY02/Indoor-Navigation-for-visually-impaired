-- ===================================================================
-- COMPLETE DATABASE SETUP SCRIPT FOR INDOOR NAVIGATION APP
-- ===================================================================
-- This script creates ALL required tables for the indoor navigation system
-- Copy and paste this entire script into your Supabase SQL Editor
-- ===================================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "vector";

-- ===================================================================
-- ENUMS AND TYPES
-- ===================================================================

-- Create turn_type enum for navigation waypoints
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'turn_type') THEN
        CREATE TYPE turn_type AS ENUM ('straight', 'left', 'right', 'uTurn');
        RAISE NOTICE 'Created turn_type enum';
    ELSE
        RAISE NOTICE 'turn_type enum already exists';
    END IF;
END $$;

-- ===================================================================
-- CORE TABLES (Maps and Nodes)
-- ===================================================================

-- 1. Maps table - Stores floor plans and building maps
CREATE TABLE IF NOT EXISTS maps (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    image_url TEXT NOT NULL,
    is_public BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    CONSTRAINT maps_name_check CHECK (char_length(name) > 0),
    CONSTRAINT maps_image_url_check CHECK (char_length(image_url) > 0)
);

-- 2. Map nodes table - Stores location points on maps
CREATE TABLE IF NOT EXISTS map_nodes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    map_id UUID NOT NULL REFERENCES maps(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    x_position DOUBLE PRECISION NOT NULL,
    y_position DOUBLE PRECISION NOT NULL,
    reference_direction DOUBLE PRECISION,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    CONSTRAINT map_nodes_name_check CHECK (char_length(name) > 0),
    CONSTRAINT map_nodes_position_check CHECK (x_position >= 0 AND y_position >= 0),
    CONSTRAINT map_nodes_direction_check CHECK (reference_direction IS NULL OR (reference_direction >= 0 AND reference_direction < 360))
);

-- 3. Place embeddings table - Stores CLIP embeddings for nodes
CREATE TABLE IF NOT EXISTS place_embeddings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    place_name TEXT NOT NULL,
    embedding TEXT NOT NULL,
    node_id UUID REFERENCES map_nodes(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    CONSTRAINT place_embeddings_name_check CHECK (char_length(place_name) > 0)
);

-- ===================================================================
-- CONNECTION TABLES (Node relationships)
-- ===================================================================

-- 4. Node connections table - Links between map nodes
CREATE TABLE IF NOT EXISTS node_connections (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    map_id UUID NOT NULL REFERENCES maps(id) ON DELETE CASCADE,
    node_a_id UUID NOT NULL REFERENCES map_nodes(id) ON DELETE CASCADE,
    node_b_id UUID NOT NULL REFERENCES map_nodes(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    distance_meters NUMERIC,
    steps INTEGER,
    average_heading NUMERIC,
    custom_instruction TEXT,
    confirmation_objects JSONB,
    is_bidirectional BOOLEAN DEFAULT TRUE,
    
    CONSTRAINT node_connections_different_nodes CHECK (node_a_id != node_b_id),
    CONSTRAINT node_connections_distance_check CHECK (distance_meters IS NULL OR distance_meters >= 0),
    CONSTRAINT node_connections_steps_check CHECK (steps IS NULL OR steps >= 0),
    CONSTRAINT node_connections_heading_check CHECK (average_heading IS NULL OR (average_heading >= 0 AND average_heading < 360))
);

-- ===================================================================
-- PATH RECORDING TABLES
-- ===================================================================

-- 5. Navigation paths table - Stores recorded paths between nodes
CREATE TABLE IF NOT EXISTS navigation_paths (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    start_location_id UUID NOT NULL, -- Changed from TEXT to UUID
    end_location_id UUID NOT NULL,   -- Changed from TEXT to UUID
    estimated_distance DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    estimated_steps INTEGER NOT NULL DEFAULT 0,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    CONSTRAINT navigation_paths_name_check CHECK (char_length(name) > 0),
    CONSTRAINT navigation_paths_distance_check CHECK (estimated_distance >= 0),
    CONSTRAINT navigation_paths_steps_check CHECK (estimated_steps >= 0)
);

-- 6. Path waypoints table - Individual waypoints with CLIP embeddings
CREATE TABLE IF NOT EXISTS path_waypoints (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    path_id UUID NOT NULL REFERENCES navigation_paths(id) ON DELETE CASCADE,
    sequence_number INTEGER NOT NULL,
    embedding VECTOR(512), -- CLIP embeddings are 512-dimensional
    heading DOUBLE PRECISION NOT NULL,
    heading_change DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    turn_type turn_type NOT NULL DEFAULT 'straight',
    is_decision_point BOOLEAN NOT NULL DEFAULT FALSE,
    landmark_description TEXT,
    distance_from_previous DOUBLE PRECISION,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
    
    UNIQUE(path_id, sequence_number),
    
    CONSTRAINT path_waypoints_sequence_check CHECK (sequence_number >= 0),
    CONSTRAINT path_waypoints_heading_check CHECK (heading >= 0.0 AND heading < 360.0),
    CONSTRAINT path_waypoints_heading_change_check CHECK (heading_change >= -180.0 AND heading_change <= 180.0),
    CONSTRAINT path_waypoints_distance_check CHECK (distance_from_previous IS NULL OR distance_from_previous >= 0.0)
);

-- ===================================================================
-- SESSION TRACKING TABLES
-- ===================================================================

-- 7. Walking sessions table - Training data from "teach by walking"
CREATE TABLE IF NOT EXISTS walking_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    map_id UUID NOT NULL REFERENCES maps(id) ON DELETE CASCADE,
    start_node_id UUID NOT NULL REFERENCES map_nodes(id) ON DELETE CASCADE,
    end_node_id UUID NOT NULL REFERENCES map_nodes(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    distance_meters NUMERIC NOT NULL,
    step_count INTEGER NOT NULL,
    average_heading NUMERIC,
    instruction TEXT,
    detected_objects JSONB,
    sensor_data JSONB,
    session_duration_seconds INTEGER,
    
    CONSTRAINT walking_sessions_distance_check CHECK (distance_meters >= 0),
    CONSTRAINT walking_sessions_steps_check CHECK (step_count >= 0),
    CONSTRAINT walking_sessions_duration_check CHECK (session_duration_seconds IS NULL OR session_duration_seconds >= 0),
    CONSTRAINT walking_sessions_heading_check CHECK (average_heading IS NULL OR (average_heading >= 0 AND average_heading < 360))
);

-- 8. Navigation logs table - Actual navigation session tracking
CREATE TABLE IF NOT EXISTS navigation_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    map_id UUID NOT NULL REFERENCES maps(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    start_node_id UUID NOT NULL REFERENCES map_nodes(id) ON DELETE CASCADE,
    end_node_id UUID NOT NULL REFERENCES map_nodes(id) ON DELETE CASCADE,
    route_steps JSONB NOT NULL,
    completed BOOLEAN DEFAULT FALSE,
    completion_time TIMESTAMP WITH TIME ZONE,
    total_distance_meters NUMERIC,
    total_steps INTEGER,
    navigation_mode TEXT DEFAULT 'enhanced',
    confidence_scores JSONB,
    deviation_events JSONB,
    
    CONSTRAINT navigation_logs_distance_check CHECK (total_distance_meters IS NULL OR total_distance_meters >= 0),
    CONSTRAINT navigation_logs_steps_check CHECK (total_steps IS NULL OR total_steps >= 0)
);

-- ===================================================================
-- INDEXES FOR PERFORMANCE
-- ===================================================================

-- Maps indexes
CREATE INDEX IF NOT EXISTS idx_maps_user_id ON maps(user_id);
CREATE INDEX IF NOT EXISTS idx_maps_is_public ON maps(is_public);
CREATE INDEX IF NOT EXISTS idx_maps_created_at ON maps(created_at);

-- Map nodes indexes
CREATE INDEX IF NOT EXISTS idx_map_nodes_map_id ON map_nodes(map_id);
CREATE INDEX IF NOT EXISTS idx_map_nodes_user_id ON map_nodes(user_id);
CREATE INDEX IF NOT EXISTS idx_map_nodes_position ON map_nodes(map_id, x_position, y_position);

-- Place embeddings indexes
CREATE INDEX IF NOT EXISTS idx_place_embeddings_node_id ON place_embeddings(node_id);
CREATE INDEX IF NOT EXISTS idx_place_embeddings_user_id ON place_embeddings(user_id);

-- Node connections indexes
CREATE INDEX IF NOT EXISTS idx_node_connections_map_id ON node_connections(map_id);
CREATE INDEX IF NOT EXISTS idx_node_connections_node_a ON node_connections(node_a_id);
CREATE INDEX IF NOT EXISTS idx_node_connections_node_b ON node_connections(node_b_id);
CREATE INDEX IF NOT EXISTS idx_node_connections_bidirectional ON node_connections(map_id, is_bidirectional) WHERE is_bidirectional = TRUE;

-- Navigation paths indexes
CREATE INDEX IF NOT EXISTS idx_navigation_paths_user_id ON navigation_paths(user_id);
CREATE INDEX IF NOT EXISTS idx_navigation_paths_start_location ON navigation_paths(start_location_id);
CREATE INDEX IF NOT EXISTS idx_navigation_paths_end_location ON navigation_paths(end_location_id);
CREATE INDEX IF NOT EXISTS idx_navigation_paths_created_at ON navigation_paths(created_at);

-- Path waypoints indexes
CREATE INDEX IF NOT EXISTS idx_path_waypoints_path_id ON path_waypoints(path_id);
CREATE INDEX IF NOT EXISTS idx_path_waypoints_sequence ON path_waypoints(path_id, sequence_number);
CREATE INDEX IF NOT EXISTS idx_path_waypoints_decision_points ON path_waypoints(path_id, is_decision_point) WHERE is_decision_point = TRUE;
CREATE INDEX IF NOT EXISTS idx_path_waypoints_timestamp ON path_waypoints(timestamp);

-- Vector similarity index for CLIP embeddings
CREATE INDEX IF NOT EXISTS idx_path_waypoints_embedding_cosine ON path_waypoints 
USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- Walking sessions indexes
CREATE INDEX IF NOT EXISTS idx_walking_sessions_map_id ON walking_sessions(map_id);
CREATE INDEX IF NOT EXISTS idx_walking_sessions_start_node ON walking_sessions(start_node_id);
CREATE INDEX IF NOT EXISTS idx_walking_sessions_end_node ON walking_sessions(end_node_id);
CREATE INDEX IF NOT EXISTS idx_walking_sessions_created_at ON walking_sessions(created_at DESC);

-- Navigation logs indexes
CREATE INDEX IF NOT EXISTS idx_navigation_logs_map_id ON navigation_logs(map_id);
CREATE INDEX IF NOT EXISTS idx_navigation_logs_user_id ON navigation_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_navigation_logs_start_node ON navigation_logs(start_node_id);
CREATE INDEX IF NOT EXISTS idx_navigation_logs_end_node ON navigation_logs(end_node_id);
CREATE INDEX IF NOT EXISTS idx_navigation_logs_created_at ON navigation_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_navigation_logs_completed ON navigation_logs(completed);

-- ===================================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ===================================================================

-- Enable RLS on all tables
ALTER TABLE maps ENABLE ROW LEVEL SECURITY;
ALTER TABLE map_nodes ENABLE ROW LEVEL SECURITY;
ALTER TABLE place_embeddings ENABLE ROW LEVEL SECURITY;
ALTER TABLE node_connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE navigation_paths ENABLE ROW LEVEL SECURITY;
ALTER TABLE path_waypoints ENABLE ROW LEVEL SECURITY;
ALTER TABLE walking_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE navigation_logs ENABLE ROW LEVEL SECURITY;

-- Maps policies
DROP POLICY IF EXISTS "Users can view public maps or their own maps" ON maps;
CREATE POLICY "Users can view public maps or their own maps" ON maps
    FOR SELECT USING (is_public = TRUE OR auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own maps" ON maps;
CREATE POLICY "Users can insert their own maps" ON maps
    FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own maps" ON maps;
CREATE POLICY "Users can update their own maps" ON maps
    FOR UPDATE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their own maps" ON maps;
CREATE POLICY "Users can delete their own maps" ON maps
    FOR DELETE USING (auth.uid() = user_id);

-- Map nodes policies
DROP POLICY IF EXISTS "Users can view nodes for accessible maps" ON map_nodes;
CREATE POLICY "Users can view nodes for accessible maps" ON map_nodes
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM maps 
            WHERE maps.id = map_nodes.map_id 
            AND (maps.is_public = TRUE OR maps.user_id = auth.uid())
        )
    );

DROP POLICY IF EXISTS "Users can insert nodes for their own maps" ON map_nodes;
CREATE POLICY "Users can insert nodes for their own maps" ON map_nodes
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM maps 
            WHERE maps.id = map_nodes.map_id 
            AND maps.user_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Users can update nodes for their own maps" ON map_nodes;
CREATE POLICY "Users can update nodes for their own maps" ON map_nodes
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM maps 
            WHERE maps.id = map_nodes.map_id 
            AND maps.user_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Users can delete nodes for their own maps" ON map_nodes;
CREATE POLICY "Users can delete nodes for their own maps" ON map_nodes
    FOR DELETE USING (
        EXISTS (
            SELECT 1 FROM maps 
            WHERE maps.id = map_nodes.map_id 
            AND maps.user_id = auth.uid()
        )
    );

-- Place embeddings policies
DROP POLICY IF EXISTS "Users can view their own embeddings" ON place_embeddings;
CREATE POLICY "Users can view their own embeddings" ON place_embeddings
    FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own embeddings" ON place_embeddings;
CREATE POLICY "Users can insert their own embeddings" ON place_embeddings
    FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own embeddings" ON place_embeddings;
CREATE POLICY "Users can update their own embeddings" ON place_embeddings
    FOR UPDATE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their own embeddings" ON place_embeddings;
CREATE POLICY "Users can delete their own embeddings" ON place_embeddings
    FOR DELETE USING (auth.uid() = user_id);

-- Node connections policies
DROP POLICY IF EXISTS "Users can view connections for accessible maps" ON node_connections;
CREATE POLICY "Users can view connections for accessible maps" ON node_connections
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM maps 
            WHERE maps.id = node_connections.map_id 
            AND (maps.is_public = TRUE OR maps.user_id = auth.uid())
        )
    );

DROP POLICY IF EXISTS "Users can insert connections for their own maps" ON node_connections;
CREATE POLICY "Users can insert connections for their own maps" ON node_connections
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM maps 
            WHERE maps.id = node_connections.map_id 
            AND maps.user_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Users can update connections for their own maps" ON node_connections;
CREATE POLICY "Users can update connections for their own maps" ON node_connections
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM maps 
            WHERE maps.id = node_connections.map_id 
            AND maps.user_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Users can delete connections for their own maps" ON node_connections;
CREATE POLICY "Users can delete connections for their own maps" ON node_connections
    FOR DELETE USING (
        EXISTS (
            SELECT 1 FROM maps 
            WHERE maps.id = node_connections.map_id 
            AND maps.user_id = auth.uid()
        )
    );

-- Navigation paths policies
DROP POLICY IF EXISTS "Users can view their own navigation paths" ON navigation_paths;
CREATE POLICY "Users can view their own navigation paths" ON navigation_paths
    FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own navigation paths" ON navigation_paths;
CREATE POLICY "Users can insert their own navigation paths" ON navigation_paths
    FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own navigation paths" ON navigation_paths;
CREATE POLICY "Users can update their own navigation paths" ON navigation_paths
    FOR UPDATE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their own navigation paths" ON navigation_paths;
CREATE POLICY "Users can delete their own navigation paths" ON navigation_paths
    FOR DELETE USING (auth.uid() = user_id);

-- Path waypoints policies
DROP POLICY IF EXISTS "Users can view waypoints for their own paths" ON path_waypoints;
CREATE POLICY "Users can view waypoints for their own paths" ON path_waypoints
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM navigation_paths 
            WHERE navigation_paths.id = path_waypoints.path_id 
            AND navigation_paths.user_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Users can insert waypoints for their own paths" ON path_waypoints;
CREATE POLICY "Users can insert waypoints for their own paths" ON path_waypoints
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM navigation_paths 
            WHERE navigation_paths.id = path_waypoints.path_id 
            AND navigation_paths.user_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Users can update waypoints for their own paths" ON path_waypoints;
CREATE POLICY "Users can update waypoints for their own paths" ON path_waypoints
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM navigation_paths 
            WHERE navigation_paths.id = path_waypoints.path_id 
            AND navigation_paths.user_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Users can delete waypoints for their own paths" ON path_waypoints;
CREATE POLICY "Users can delete waypoints for their own paths" ON path_waypoints
    FOR DELETE USING (
        EXISTS (
            SELECT 1 FROM navigation_paths 
            WHERE navigation_paths.id = path_waypoints.path_id 
            AND navigation_paths.user_id = auth.uid()
        )
    );

-- Walking sessions policies
DROP POLICY IF EXISTS "Users can view walking sessions for accessible maps" ON walking_sessions;
CREATE POLICY "Users can view walking sessions for accessible maps" ON walking_sessions
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM maps 
            WHERE maps.id = walking_sessions.map_id 
            AND (maps.is_public = TRUE OR maps.user_id = auth.uid())
        )
    );

DROP POLICY IF EXISTS "Users can insert walking sessions for accessible maps" ON walking_sessions;
CREATE POLICY "Users can insert walking sessions for accessible maps" ON walking_sessions
    FOR INSERT WITH CHECK (
        auth.uid() = user_id AND
        EXISTS (
            SELECT 1 FROM maps 
            WHERE maps.id = walking_sessions.map_id 
            AND (maps.is_public = TRUE OR maps.user_id = auth.uid())
        )
    );

DROP POLICY IF EXISTS "Users can update their own walking sessions" ON walking_sessions;
CREATE POLICY "Users can update their own walking sessions" ON walking_sessions
    FOR UPDATE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their own walking sessions" ON walking_sessions;
CREATE POLICY "Users can delete their own walking sessions" ON walking_sessions
    FOR DELETE USING (auth.uid() = user_id);

-- Navigation logs policies
DROP POLICY IF EXISTS "Users can view their own navigation logs" ON navigation_logs;
CREATE POLICY "Users can view their own navigation logs" ON navigation_logs
    FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own navigation logs" ON navigation_logs;
CREATE POLICY "Users can insert their own navigation logs" ON navigation_logs
    FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own navigation logs" ON navigation_logs;
CREATE POLICY "Users can update their own navigation logs" ON navigation_logs
    FOR UPDATE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their own navigation logs" ON navigation_logs;
CREATE POLICY "Users can delete their own navigation logs" ON navigation_logs
    FOR DELETE USING (auth.uid() = user_id);

-- ===================================================================
-- TRIGGERS FOR AUTOMATIC UPDATES
-- ===================================================================

-- Function to update updated_at column
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE 'plpgsql';

-- Create triggers for tables with updated_at columns
DROP TRIGGER IF EXISTS update_node_connections_updated_at ON node_connections;
CREATE TRIGGER update_node_connections_updated_at 
    BEFORE UPDATE ON node_connections 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_navigation_paths_updated_at ON navigation_paths;
CREATE TRIGGER update_navigation_paths_updated_at 
    BEFORE UPDATE ON navigation_paths 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ===================================================================
-- HELPFUL VIEWS
-- ===================================================================

-- View for navigation paths with statistics
CREATE OR REPLACE VIEW navigation_paths_with_stats AS
SELECT 
    np.*,
    COUNT(pw.id) as waypoint_count,
    MIN(pw.timestamp) as first_waypoint_time,
    MAX(pw.timestamp) as last_waypoint_time
FROM navigation_paths np
LEFT JOIN path_waypoints pw ON np.id = pw.path_id
GROUP BY np.id, np.name, np.start_location_id, np.end_location_id, 
         np.estimated_distance, np.estimated_steps, np.user_id, 
         np.created_at, np.updated_at;

-- View for map summary with node and connection counts
CREATE OR REPLACE VIEW maps_summary AS
SELECT 
    m.*,
    COALESCE(node_counts.node_count, 0) as node_count,
    COALESCE(connection_counts.connection_count, 0) as connection_count
FROM maps m
LEFT JOIN (
    SELECT map_id, COUNT(*) as node_count
    FROM map_nodes
    GROUP BY map_id
) node_counts ON m.id = node_counts.map_id
LEFT JOIN (
    SELECT map_id, COUNT(*) as connection_count
    FROM node_connections
    GROUP BY map_id
) connection_counts ON m.id = connection_counts.map_id;

-- ===================================================================
-- PERMISSIONS
-- ===================================================================

-- Grant permissions to authenticated users
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- Grant permissions on specific views
GRANT SELECT ON navigation_paths_with_stats TO authenticated;
GRANT SELECT ON maps_summary TO authenticated;

-- ===================================================================
-- TABLE COMMENTS FOR DOCUMENTATION
-- ===================================================================

COMMENT ON TABLE maps IS 'Stores floor plans and building maps with image data';
COMMENT ON TABLE map_nodes IS 'Location points on maps with coordinates and reference directions';
COMMENT ON TABLE place_embeddings IS 'CLIP embeddings for visual recognition of locations';
COMMENT ON TABLE node_connections IS 'Connections between map nodes with navigation metadata';
COMMENT ON TABLE navigation_paths IS 'Recorded navigation paths between locations';
COMMENT ON TABLE path_waypoints IS 'Individual waypoints with CLIP embeddings for navigation paths';
COMMENT ON TABLE walking_sessions IS 'Training data from teach-by-walking sessions';
COMMENT ON TABLE navigation_logs IS 'Logs of actual navigation sessions for analytics';

COMMENT ON COLUMN path_waypoints.embedding IS 'CLIP visual embedding vector (512 dimensions)';
COMMENT ON COLUMN path_waypoints.turn_type IS 'Type of turn at this waypoint (straight, left, right, uTurn)';
COMMENT ON COLUMN path_waypoints.is_decision_point IS 'Whether this waypoint requires a navigation decision';
COMMENT ON COLUMN path_waypoints.heading IS 'Compass heading in degrees (0-360)';
COMMENT ON COLUMN path_waypoints.heading_change IS 'Change in heading from previous waypoint (-180 to +180)';

-- ===================================================================
-- SETUP VERIFICATION
-- ===================================================================

DO $$
DECLARE
    table_count INTEGER;
    missing_tables TEXT[];
    required_tables TEXT[] := ARRAY[
        'maps', 'map_nodes', 'place_embeddings', 'node_connections',
        'navigation_paths', 'path_waypoints', 'walking_sessions', 'navigation_logs'
    ];
    current_table TEXT;
BEGIN
    -- Check if all required tables exist
    missing_tables := ARRAY[]::TEXT[];
    
    FOREACH current_table IN ARRAY required_tables
    LOOP
        IF NOT EXISTS (
            SELECT FROM information_schema.tables 
            WHERE table_schema = 'public' AND table_name = current_table
        ) THEN
            missing_tables := array_append(missing_tables, current_table);
        END IF;
    END LOOP;
    
    IF array_length(missing_tables, 1) IS NULL THEN
        RAISE NOTICE '✅ SUCCESS: All indoor navigation tables are ready!';
        RAISE NOTICE '✅ Tables created: %', array_to_string(required_tables, ', ');
        RAISE NOTICE '✅ Vector extension enabled for CLIP embeddings';
        RAISE NOTICE '✅ Row Level Security (RLS) policies configured';
        RAISE NOTICE '✅ Indexes created for optimal performance';
        RAISE NOTICE '✅ Your indoor navigation app is ready to use!';
        RAISE NOTICE '';
        RAISE NOTICE '📱 Next steps:';
        RAISE NOTICE '   1. Run your Flutter app: flutter run';
        RAISE NOTICE '   2. Create maps and nodes through the admin interface';
        RAISE NOTICE '   3. Start recording navigation paths between nodes';
        RAISE NOTICE '   4. Test the visual recognition system with CLIP';
    ELSE
        RAISE NOTICE '❌ ERROR: Missing tables: %', array_to_string(missing_tables, ', ');
        RAISE NOTICE '❌ Please review the errors above and re-run the script';
    END IF;
END $$;
