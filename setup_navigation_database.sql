-- Enhanced Navigation System Database Setup
-- Run this script in your Supabase SQL Editor

-- 1. Create node_connections table for pathways between locations
CREATE TABLE IF NOT EXISTS public.node_connections (
    id UUID DEFAULT gen_random_uuid() NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    map_id UUID NOT NULL,
    node_a_id UUID NOT NULL,
    node_b_id UUID NOT NULL,
    user_id UUID NOT NULL,
    distance_meters NUMERIC,
    steps INTEGER,
    average_heading NUMERIC,
    custom_instruction TEXT,
    confirmation_objects JSONB,
    is_bidirectional BOOLEAN DEFAULT true,
    CONSTRAINT node_connections_pkey PRIMARY KEY (id),
    CONSTRAINT node_connections_map_id_fkey FOREIGN KEY (map_id) REFERENCES public.maps(id) ON DELETE CASCADE,
    CONSTRAINT node_connections_node_a_id_fkey FOREIGN KEY (node_a_id) REFERENCES public.map_nodes(id) ON DELETE CASCADE,
    CONSTRAINT node_connections_node_b_id_fkey FOREIGN KEY (node_b_id) REFERENCES public.map_nodes(id) ON DELETE CASCADE,
    CONSTRAINT node_connections_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);

-- 2. Create walking_sessions table for "teach by walking" training data
CREATE TABLE IF NOT EXISTS public.walking_sessions (
    id UUID DEFAULT gen_random_uuid() NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    map_id UUID NOT NULL,
    start_node_id UUID NOT NULL,
    end_node_id UUID NOT NULL,
    user_id UUID NOT NULL,
    distance_meters NUMERIC NOT NULL,
    step_count INTEGER NOT NULL,
    average_heading NUMERIC,
    instruction TEXT,
    detected_objects JSONB,
    sensor_data JSONB,
    session_duration_seconds INTEGER,
    CONSTRAINT walking_sessions_pkey PRIMARY KEY (id),
    CONSTRAINT walking_sessions_map_id_fkey FOREIGN KEY (map_id) REFERENCES public.maps(id) ON DELETE CASCADE,
    CONSTRAINT walking_sessions_start_node_id_fkey FOREIGN KEY (start_node_id) REFERENCES public.map_nodes(id) ON DELETE CASCADE,
    CONSTRAINT walking_sessions_end_node_id_fkey FOREIGN KEY (end_node_id) REFERENCES public.map_nodes(id) ON DELETE CASCADE,
    CONSTRAINT walking_sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);

-- 3. Create navigation_logs table for tracking actual navigation sessions
CREATE TABLE IF NOT EXISTS public.navigation_logs (
    id UUID DEFAULT gen_random_uuid() NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    map_id UUID NOT NULL,
    user_id UUID NOT NULL,
    start_node_id UUID NOT NULL,
    end_node_id UUID NOT NULL,
    route_steps JSONB NOT NULL,
    completed BOOLEAN DEFAULT false,
    completion_time TIMESTAMP WITH TIME ZONE,
    total_distance_meters NUMERIC,
    total_steps INTEGER,
    navigation_mode TEXT DEFAULT 'enhanced',
    confidence_scores JSONB,
    deviation_events JSONB,
    CONSTRAINT navigation_logs_pkey PRIMARY KEY (id),
    CONSTRAINT navigation_logs_map_id_fkey FOREIGN KEY (map_id) REFERENCES public.maps(id) ON DELETE CASCADE,
    CONSTRAINT navigation_logs_start_node_id_fkey FOREIGN KEY (start_node_id) REFERENCES public.map_nodes(id) ON DELETE CASCADE,
    CONSTRAINT navigation_logs_end_node_id_fkey FOREIGN KEY (end_node_id) REFERENCES public.map_nodes(id) ON DELETE CASCADE,
    CONSTRAINT navigation_logs_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);

-- 4. Add indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_node_connections_map_id ON public.node_connections(map_id);
CREATE INDEX IF NOT EXISTS idx_node_connections_node_a ON public.node_connections(node_a_id);
CREATE INDEX IF NOT EXISTS idx_node_connections_node_b ON public.node_connections(node_b_id);
CREATE INDEX IF NOT EXISTS idx_node_connections_bidirectional ON public.node_connections(map_id, is_bidirectional) WHERE is_bidirectional = true;

CREATE INDEX IF NOT EXISTS idx_walking_sessions_map_id ON public.walking_sessions(map_id);
CREATE INDEX IF NOT EXISTS idx_walking_sessions_start_node ON public.walking_sessions(start_node_id);
CREATE INDEX IF NOT EXISTS idx_walking_sessions_end_node ON public.walking_sessions(end_node_id);
CREATE INDEX IF NOT EXISTS idx_walking_sessions_created_at ON public.walking_sessions(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_navigation_logs_map_id ON public.navigation_logs(map_id);
CREATE INDEX IF NOT EXISTS idx_navigation_logs_user_id ON public.navigation_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_navigation_logs_completed ON public.navigation_logs(completed);
CREATE INDEX IF NOT EXISTS idx_navigation_logs_created_at ON public.navigation_logs(created_at DESC);

-- 5. Enable Row Level Security (RLS)
ALTER TABLE public.node_connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.walking_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.navigation_logs ENABLE ROW LEVEL SECURITY;

-- 6. Create RLS policies

-- node_connections policies
CREATE POLICY "Users can view all connections" ON public.node_connections
    FOR SELECT USING (true);

CREATE POLICY "Users can create connections for their maps" ON public.node_connections
    FOR INSERT WITH CHECK (
        auth.uid() = user_id AND 
        EXISTS (SELECT 1 FROM public.maps WHERE id = map_id AND user_id = auth.uid())
    );

CREATE POLICY "Users can update their own connections" ON public.node_connections
    FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own connections" ON public.node_connections
    FOR DELETE USING (auth.uid() = user_id);

-- walking_sessions policies  
CREATE POLICY "Users can view walking sessions for accessible maps" ON public.walking_sessions
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM public.maps WHERE id = map_id AND (user_id = auth.uid() OR is_public = true))
    );

CREATE POLICY "Users can create walking sessions" ON public.walking_sessions
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own walking sessions" ON public.walking_sessions
    FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own walking sessions" ON public.walking_sessions
    FOR DELETE USING (auth.uid() = user_id);

-- navigation_logs policies
CREATE POLICY "Users can view their own navigation logs" ON public.navigation_logs
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own navigation logs" ON public.navigation_logs
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own navigation logs" ON public.navigation_logs
    FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own navigation logs" ON public.navigation_logs
    FOR DELETE USING (auth.uid() = user_id);

-- 7. Create updated_at trigger for node_connections
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER handle_node_connections_updated_at
    BEFORE UPDATE ON public.node_connections
    FOR EACH ROW
    EXECUTE PROCEDURE public.handle_updated_at();

-- 8. Create helpful views

-- View for bidirectional connections (makes pathfinding queries easier)
CREATE OR REPLACE VIEW public.navigation_graph AS
SELECT 
    id as connection_id,
    map_id,
    node_a_id as from_node_id,
    node_b_id as to_node_id,
    distance_meters,
    steps,
    average_heading,
    custom_instruction,
    confirmation_objects
FROM public.node_connections
WHERE is_bidirectional = true
UNION ALL
SELECT 
    id as connection_id,
    map_id,
    node_b_id as from_node_id,
    node_a_id as to_node_id,
    distance_meters,
    steps,
    CASE 
        WHEN average_heading IS NOT NULL THEN 
            CASE 
                WHEN average_heading + 180 > 360 THEN average_heading - 180
                ELSE average_heading + 180
            END
        ELSE NULL
    END as average_heading,
    custom_instruction,
    confirmation_objects
FROM public.node_connections
WHERE is_bidirectional = true;

-- View for map navigation summary
CREATE OR REPLACE VIEW public.map_navigation_summary AS
SELECT 
    m.id as map_id,
    m.name as map_name,
    COUNT(DISTINCT mn.id) as node_count,
    COUNT(DISTINCT nc.id) as connection_count,
    AVG(nc.distance_meters) as avg_connection_distance,
    COUNT(DISTINCT ws.id) as training_sessions_count
FROM public.maps m
LEFT JOIN public.map_nodes mn ON m.id = mn.map_id
LEFT JOIN public.node_connections nc ON m.id = nc.map_id
LEFT JOIN public.walking_sessions ws ON m.id = ws.map_id
GROUP BY m.id, m.name;

-- 9. Grant necessary permissions for functions and views
GRANT SELECT ON public.navigation_graph TO authenticated;
GRANT SELECT ON public.map_navigation_summary TO authenticated;

-- 10. Verify setup completed successfully
SELECT 'Enhanced Navigation Database Setup Complete!' as status,
       'Tables created: node_connections, walking_sessions, navigation_logs' as tables_created,
       'You can now connect nodes and store navigation data!' as next_step; 