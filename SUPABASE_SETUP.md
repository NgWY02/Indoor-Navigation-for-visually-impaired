# Supabase Setup Guide for Indoor Navigation App

## 🚀 Quick Setup

### 1. Create New Supabase Project
1. Go to [supabase.com](https://supabase.com)
2. Create a new project
3. Wait for it to be fully provisioned

### 2. Get Your Credentials
1. Go to **Settings** → **API**
2. Copy your **Project URL** and **anon/public key**
3. Update your `.env` file:
```env
SUPABASE_URL=https://your-project-id.supabase.co
SUPABASE_ANON_KEY=your-anon-key-here
```

### 3. Run Database Setup Script
1. Go to **SQL Editor** in your Supabase dashboard
2. Copy and paste the entire script below
3. Click **Run**

## 📋 Complete Database Schema

```sql
-- ===================================================================
-- COMPLETE DATABASE SETUP SCRIPT FOR INDOOR NAVIGATION APP
-- ===================================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "vector";

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
-- CORE TABLES
-- ===================================================================

-- User profiles table
CREATE TABLE IF NOT EXISTS profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT,
    name TEXT,
    role TEXT DEFAULT 'user',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Maps table
CREATE TABLE IF NOT EXISTS maps (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    image_url TEXT NOT NULL,
    is_public BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE
);

-- Map nodes table
CREATE TABLE IF NOT EXISTS map_nodes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    map_id UUID NOT NULL REFERENCES maps(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    x_position DOUBLE PRECISION NOT NULL,
    y_position DOUBLE PRECISION NOT NULL,
    reference_direction DOUBLE PRECISION,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE
);

-- Place embeddings table
CREATE TABLE IF NOT EXISTS place_embeddings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    place_name TEXT NOT NULL,
    embedding TEXT NOT NULL,
    node_id UUID REFERENCES map_nodes(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE
);

-- Node connections table
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
    is_bidirectional BOOLEAN DEFAULT TRUE
);

-- Navigation paths table
CREATE TABLE IF NOT EXISTS navigation_paths (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    start_location_id UUID NOT NULL,
    end_location_id UUID NOT NULL,
    estimated_distance DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    estimated_steps INTEGER NOT NULL DEFAULT 0,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    is_published BOOLEAN DEFAULT TRUE,
    map_id UUID REFERENCES maps(id)
);

-- Path waypoints table
CREATE TABLE IF NOT EXISTS path_waypoints (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    path_id UUID NOT NULL REFERENCES navigation_paths(id) ON DELETE CASCADE,
    sequence_number INTEGER NOT NULL,
    embedding VECTOR(512),
    heading DOUBLE PRECISION NOT NULL,
    heading_change DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    turn_type turn_type NOT NULL DEFAULT 'straight',
    is_decision_point BOOLEAN NOT NULL DEFAULT FALSE,
    landmark_description TEXT,
    distance_from_previous DOUBLE PRECISION,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
    UNIQUE(path_id, sequence_number)
);

-- Walking sessions table
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
    session_duration_seconds INTEGER
);

-- Navigation logs table
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
    deviation_events JSONB
);

-- ===================================================================
-- INDEXES FOR PERFORMANCE
-- ===================================================================

CREATE INDEX IF NOT EXISTS idx_maps_user_id ON maps(user_id);
CREATE INDEX IF NOT EXISTS idx_maps_is_public ON maps(is_public);
CREATE INDEX IF NOT EXISTS idx_map_nodes_map_id ON map_nodes(map_id);
CREATE INDEX IF NOT EXISTS idx_navigation_paths_user_id ON navigation_paths(user_id);
CREATE INDEX IF NOT EXISTS idx_path_waypoints_path_id ON path_waypoints(path_id);
CREATE INDEX IF NOT EXISTS idx_path_waypoints_embedding_cosine ON path_waypoints
USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- ===================================================================
-- ROW LEVEL SECURITY POLICIES
-- ===================================================================

-- Enable RLS
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE maps ENABLE ROW LEVEL SECURITY;
ALTER TABLE map_nodes ENABLE ROW LEVEL SECURITY;
ALTER TABLE navigation_paths ENABLE ROW LEVEL SECURITY;
ALTER TABLE path_waypoints ENABLE ROW LEVEL SECURITY;

-- Profiles policies
CREATE POLICY "Users can view their own profile" ON profiles
    FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update their own profile" ON profiles
    FOR UPDATE USING (auth.uid() = id);

-- Maps policies
CREATE POLICY "Users can view public maps or their own maps" ON maps
    FOR SELECT USING (is_public = TRUE OR auth.uid() = user_id);
CREATE POLICY "Users can insert their own maps" ON maps
    FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their own maps" ON maps
    FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete their own maps" ON maps
    FOR DELETE USING (auth.uid() = user_id);

-- Map nodes policies
CREATE POLICY "Users can view nodes for accessible maps" ON map_nodes
    FOR SELECT USING (EXISTS (SELECT 1 FROM maps WHERE maps.id = map_nodes.map_id AND (maps.is_public = TRUE OR maps.user_id = auth.uid())));
CREATE POLICY "Users can insert nodes for their own maps" ON map_nodes
    FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM maps WHERE maps.id = map_nodes.map_id AND maps.user_id = auth.uid()));

-- Navigation paths policies
CREATE POLICY "Users can view their own navigation paths" ON navigation_paths
    FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert their own navigation paths" ON navigation_paths
    FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their own navigation paths" ON navigation_paths
    FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete their own navigation paths" ON navigation_paths
    FOR DELETE USING (auth.uid() = user_id);

-- Path waypoints policies
CREATE POLICY "Users can view waypoints for their own paths" ON path_waypoints
    FOR SELECT USING (EXISTS (SELECT 1 FROM navigation_paths WHERE navigation_paths.id = path_waypoints.path_id AND navigation_paths.user_id = auth.uid()));
CREATE POLICY "Users can insert waypoints for their own paths" ON path_waypoints
    FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM navigation_paths WHERE navigation_paths.id = path_waypoints.path_id AND navigation_paths.user_id = auth.uid()));

-- ===================================================================
-- AUTO PROFILE CREATION TRIGGER
-- ===================================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, email, role)
  VALUES (new.id, new.email, 'user');
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- ===================================================================
-- STORAGE BUCKETS
-- ===================================================================

-- Create storage buckets
INSERT INTO storage.buckets (id, name, public)
VALUES ('maps', 'maps', true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public)
VALUES ('place_images', 'place_images', true)
ON CONFLICT (id) DO NOTHING;

-- Storage policies
CREATE POLICY "Users can upload their own map images" ON storage.objects
  FOR INSERT WITH CHECK (bucket_id = 'maps' AND auth.uid()::text = (storage.foldername(name))[1]);

CREATE POLICY "Anyone can view map images" ON storage.objects
  FOR SELECT USING (bucket_id = 'maps');

CREATE POLICY "Users can upload their own place images" ON storage.objects
  FOR INSERT WITH CHECK (bucket_id = 'place_images' AND auth.uid()::text = (storage.foldername(name))[1]);

CREATE POLICY "Anyone can view place images" ON storage.objects
  FOR SELECT USING (bucket_id = 'place_images');

-- ===================================================================
-- PERMISSIONS
-- ===================================================================

GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;
```

## 🔧 Testing Your Setup

### 1. Test the Database Connection
```bash
cd "c:\FlutterProjects\Indoor-Navigation-for-visually-impaired"
flutter run --debug
```

### 2. Check for Errors
- If you see "Failed host lookup" errors, your Supabase URL is incorrect
- If you see authentication errors, check your anon key
- If you see permission errors, the RLS policies may not be set up correctly

### 3. Verify Storage Buckets
1. Go to **Storage** in your Supabase dashboard
2. Ensure you have `maps` and `place_images` buckets
3. Check that the buckets are public

## 🎯 Next Steps

1. **Test Authentication**: Try signing up/in in your app
2. **Create a Map**: Upload a floor plan image
3. **Add Nodes**: Create location points on your map
4. **Record Paths**: Test the navigation path recording feature
5. **Test Navigation**: Try navigating between locations

## 🆘 Troubleshooting

### Common Issues:

1. **"Failed host lookup"**
   - Check your Supabase URL in `.env`
   - Ensure your project is not paused

2. **Authentication Errors**
   - Verify your anon key is correct
   - Check that RLS policies are enabled

3. **Storage Upload Errors**
   - Ensure storage buckets exist and are public
   - Check storage policies are correctly configured

4. **Permission Errors**
   - Re-run the database setup script
   - Check that all tables and policies were created

### Need Help?
- Check the Supabase dashboard for error logs
- Verify all environment variables are set correctly
- Ensure your Flutter app has internet permission

---

**Your app should now be fully functional with a fresh Supabase project!** 🎉
