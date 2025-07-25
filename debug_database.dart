#!/usr/bin/env dart

// Simple script to check database content
// Run with: dart run debug_database.dart

import 'dart:io';
import 'lib/services/supabase_service.dart';

Future<void> main() async {
  print('=== Database Debug Script ===');
  
  try {
    final service = SupabaseService();
    
    print('\n1. Checking authentication...');
    final user = service.currentUser;
    if (user == null) {
      print('❌ No user authenticated. Please sign in through the app first.');
      exit(1);
    }
    print('✅ User authenticated: ${user.id}');
    
    print('\n2. Checking navigation_paths table...');
    final paths = await service.loadAllPaths();
    print('Found ${paths.length} navigation paths:');
    
    for (int i = 0; i < paths.length; i++) {
      final path = paths[i];
      print('  Path $i:');
      print('    Name: ${path.name}');
      print('    ID: ${path.id}');
      print('    Start: ${path.startLocationId}');
      print('    End: ${path.endLocationId}');
      print('    Distance: ${path.estimatedDistance}m');
      print('    Steps: ${path.estimatedSteps}');
      print('    Created: ${path.createdAt}');
      print('    Waypoints: ${path.waypoints.length}');
      print('');
    }
    
    print('\n3. Checking maps table...');
    // Note: We'd need to add a method to get all maps, but for now let's use a known map ID
    // You can replace this with your actual map ID
    const testMapId = 'your-map-id-here'; // Replace with actual map ID
    
    print('\n4. Done!');
    
  } catch (e) {
    print('❌ Error: $e');
    exit(1);
  }
}
