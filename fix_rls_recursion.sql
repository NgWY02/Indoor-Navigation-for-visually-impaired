-- Diagnose and fix RLS recursion issues
-- This script will check current RLS policies and fix the infinite recursion

-- First, let's see what policies exist on the user_roles table
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual
FROM pg_policies
WHERE tablename = 'user_roles'
ORDER BY policyname;

-- Check policies on maps table
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual
FROM pg_policies
WHERE tablename = 'maps'
ORDER BY policyname;

-- Check policies on profiles table
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual
FROM pg_policies
WHERE tablename = 'profiles'
ORDER BY policyname;

-- Drop all policies on user_roles table to prevent recursion
DROP POLICY IF EXISTS "Users can view their own roles" ON user_roles;
DROP POLICY IF EXISTS "Admins can view all roles" ON user_roles;
DROP POLICY IF EXISTS "Users can insert their own roles" ON user_roles;
DROP POLICY IF EXISTS "Admins can manage all roles" ON user_roles;

-- Since we're moving to a single-user system, we can disable RLS on user_roles entirely
ALTER TABLE user_roles DISABLE ROW LEVEL SECURITY;

-- Fix maps table policies to use profiles table instead of user_roles
DROP POLICY IF EXISTS "Users can view public maps or their own" ON maps;
DROP POLICY IF EXISTS "Admins can view all maps" ON maps;
DROP POLICY IF EXISTS "Users can insert their own maps" ON maps;
DROP POLICY IF EXISTS "Users can update their own maps" ON maps;
DROP POLICY IF EXISTS "Admins can manage all maps" ON maps;

-- Create new policies for maps table using profiles table
CREATE POLICY "Users can view public maps or their own" ON maps
FOR SELECT USING (
  is_public = true OR
  user_id = auth.uid() OR
  EXISTS (
    SELECT 1 FROM profiles
    WHERE profiles.id = auth.uid() AND profiles.role = 'admin'
  )
);

CREATE POLICY "Users can insert their own maps" ON maps
FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update their own maps" ON maps
FOR UPDATE USING (
  user_id = auth.uid() OR
  EXISTS (
    SELECT 1 FROM profiles
    WHERE profiles.id = auth.uid() AND profiles.role = 'admin'
  )
);

CREATE POLICY "Users can delete their own maps" ON maps
FOR DELETE USING (
  user_id = auth.uid() OR
  EXISTS (
    SELECT 1 FROM profiles
    WHERE profiles.id = auth.uid() AND profiles.role = 'admin'
  )
);

-- Check and fix navigation_paths policies
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual
FROM pg_policies
WHERE tablename = 'navigation_paths'
ORDER BY policyname;

-- Drop old navigation_paths policies
DROP POLICY IF EXISTS "Users can view their own paths" ON navigation_paths;
DROP POLICY IF EXISTS "Admins can view all paths" ON navigation_paths;
DROP POLICY IF EXISTS "Users can insert their own paths" ON navigation_paths;
DROP POLICY IF EXISTS "Users can update their own paths" ON navigation_paths;
DROP POLICY IF EXISTS "Admins can manage all paths" ON navigation_paths;

-- Create new navigation_paths policies
CREATE POLICY "Users can view their own paths" ON navigation_paths
FOR SELECT USING (
  user_id = auth.uid() OR
  EXISTS (
    SELECT 1 FROM profiles
    WHERE profiles.id = auth.uid() AND profiles.role = 'admin'
  )
);

CREATE POLICY "Users can insert their own paths" ON navigation_paths
FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update their own paths" ON navigation_paths
FOR UPDATE USING (
  user_id = auth.uid() OR
  EXISTS (
    SELECT 1 FROM profiles
    WHERE profiles.id = auth.uid() AND profiles.role = 'admin'
  )
);

CREATE POLICY "Users can delete their own paths" ON navigation_paths
FOR DELETE USING (
  user_id = auth.uid() OR
  EXISTS (
    SELECT 1 FROM profiles
    WHERE profiles.id = auth.uid() AND profiles.role = 'admin'
  )
);

-- Check and fix map_nodes policies
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual
FROM pg_policies
WHERE tablename = 'map_nodes'
ORDER BY policyname;

-- Drop old map_nodes policies
DROP POLICY IF EXISTS "Users can view nodes from accessible maps" ON map_nodes;
DROP POLICY IF EXISTS "Admins can view all nodes" ON map_nodes;
DROP POLICY IF EXISTS "Users can insert nodes to their maps" ON map_nodes;
DROP POLICY IF EXISTS "Users can update nodes in their maps" ON map_nodes;
DROP POLICY IF EXISTS "Admins can manage all nodes" ON map_nodes;

-- Create new map_nodes policies
CREATE POLICY "Users can view nodes from accessible maps" ON map_nodes
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM maps
    WHERE maps.id = map_nodes.map_id
    AND (
      maps.is_public = true OR
      maps.user_id = auth.uid() OR
      EXISTS (
        SELECT 1 FROM profiles
        WHERE profiles.id = auth.uid() AND profiles.role = 'admin'
      )
    )
  )
);

CREATE POLICY "Users can insert nodes to their maps" ON map_nodes
FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM maps
    WHERE maps.id = map_nodes.map_id
    AND (
      maps.user_id = auth.uid() OR
      EXISTS (
        SELECT 1 FROM profiles
        WHERE profiles.id = auth.uid() AND profiles.role = 'admin'
      )
    )
  )
);

CREATE POLICY "Users can update nodes in their maps" ON map_nodes
FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM maps
    WHERE maps.id = map_nodes.map_id
    AND (
      maps.user_id = auth.uid() OR
      EXISTS (
        SELECT 1 FROM profiles
        WHERE profiles.id = auth.uid() AND profiles.role = 'admin'
      )
    )
  )
);

CREATE POLICY "Users can delete nodes from their maps" ON map_nodes
FOR DELETE USING (
  EXISTS (
    SELECT 1 FROM maps
    WHERE maps.id = map_nodes.map_id
    AND (
      maps.user_id = auth.uid() OR
      EXISTS (
        SELECT 1 FROM profiles
        WHERE profiles.id = auth.uid() AND profiles.role = 'admin'
      )
    )
  )
);

-- Check and fix path_waypoints policies
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual
FROM pg_policies
WHERE tablename = 'path_waypoints'
ORDER BY policyname;

-- Drop old path_waypoints policies
DROP POLICY IF EXISTS "Users can view waypoints from their paths" ON path_waypoints;
DROP POLICY IF EXISTS "Admins can view all waypoints" ON path_waypoints;
DROP POLICY IF EXISTS "Users can insert waypoints to their paths" ON path_waypoints;
DROP POLICY IF EXISTS "Users can update waypoints in their paths" ON path_waypoints;
DROP POLICY IF EXISTS "Admins can manage all waypoints" ON path_waypoints;

-- Create new path_waypoints policies
CREATE POLICY "Users can view waypoints from their paths" ON path_waypoints
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM navigation_paths
    WHERE navigation_paths.id = path_waypoints.path_id
    AND (
      navigation_paths.user_id = auth.uid() OR
      EXISTS (
        SELECT 1 FROM profiles
        WHERE profiles.id = auth.uid() AND profiles.role = 'admin'
      )
    )
  )
);

CREATE POLICY "Users can insert waypoints to their paths" ON path_waypoints
FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM navigation_paths
    WHERE navigation_paths.id = path_waypoints.path_id
    AND (
      navigation_paths.user_id = auth.uid() OR
      EXISTS (
        SELECT 1 FROM profiles
        WHERE profiles.id = auth.uid() AND profiles.role = 'admin'
      )
    )
  )
);

CREATE POLICY "Users can update waypoints in their paths" ON path_waypoints
FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM navigation_paths
    WHERE navigation_paths.id = path_waypoints.path_id
    AND (
      navigation_paths.user_id = auth.uid() OR
      EXISTS (
        SELECT 1 FROM profiles
        WHERE profiles.id = auth.uid() AND profiles.role = 'admin'
      )
    )
  )
);

CREATE POLICY "Users can delete waypoints from their paths" ON path_waypoints
FOR DELETE USING (
  EXISTS (
    SELECT 1 FROM navigation_paths
    WHERE navigation_paths.id = path_waypoints.path_id
    AND (
      navigation_paths.user_id = auth.uid() OR
      EXISTS (
        SELECT 1 FROM profiles
        WHERE profiles.id = auth.uid() AND profiles.role = 'admin'
      )
    )
  )
);

-- Verify all policies are created correctly
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual
FROM pg_policies
WHERE tablename IN ('maps', 'navigation_paths', 'map_nodes', 'path_waypoints', 'profiles')
ORDER BY tablename, policyname;
