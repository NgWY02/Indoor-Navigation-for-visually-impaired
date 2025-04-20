import 'dart:convert';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as path;

// Define user roles
enum UserRole {
  user,
  admin,
}

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  final uuid = Uuid();

  factory SupabaseService() {
    return _instance;
  }

  SupabaseService._internal();

  Future<void> initialize() async {
    await Supabase.initialize(
      url: 'https://cemfdjiuqjmmxedpnbds.supabase.co',  
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNlbWZkaml1cWptbXhlZHBuYmRzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDQ2MDY1NTQsImV4cCI6MjA2MDE4MjU1NH0.vqw1BYIBmw9-S5Eyy5aXpCKvc0jlBLrTnMYdZF8n00A', 
    );
    
    // Initialize required storage buckets
    await _initializeStorage();
  }
  
  Future<void> _initializeStorage() async {
    try {
      // Check if the user is authenticated before attempting to create buckets
      if (client.auth.currentUser != null) {
        await _createBucketIfNotExists('maps');
        await _createBucketIfNotExists('place_images');
      }
    } catch (e) {
      print('Error initializing storage buckets: $e');
    }
  }
  
  Future<bool> _createBucketIfNotExists(String bucketName) async {
    try {
      // Try to get the bucket to check if it exists
      await client.storage.getBucket(bucketName);
      print('Bucket $bucketName already exists');
      return true;
    } catch (e) {
      // If bucket doesn't exist (404 error), try to create it
      if (e is StorageException && e.statusCode == '404') {
        try {
          await client.storage.createBucket(
            bucketName,
            const BucketOptions(
              public: true, // Make the bucket public
              fileSizeLimit: '52428800', // 50MB limit
            ),
          );
          print('Bucket $bucketName created successfully');
          return true;
        } catch (createError) {
          print('Error creating bucket $bucketName: $createError');
          // If we get a 403 Unauthorized error for bucket creation, 
          // the user doesn't have permission to create buckets
          // We will still try to upload files assuming the bucket already exists
          if (createError is StorageException && createError.statusCode == '403') {
            print('Warning: No permission to create bucket. Assuming it exists.');
            return true; // Assume bucket exists and continue
          }
          return false;
        }
      } else if (e is StorageException && e.statusCode == '403') {
        // If we get a 403 error checking the bucket, we don't have permission to check
        // but the bucket might still exist, so we'll try to continue
        print('Warning: No permission to check bucket. Assuming it exists.');
        return true; // Assume bucket exists and continue
      } else {
        print('Error checking bucket $bucketName: $e');
        return false;
      }
    }
  }

  SupabaseClient get client => Supabase.instance.client;
  User? get currentUser => client.auth.currentUser;
  bool get isAuthenticated => currentUser != null;
  Stream<AuthState> get authStateChanges => client.auth.onAuthStateChange;

  // User role methods
  Future<UserRole> getUserRole() async {
    if (currentUser == null) {
      return UserRole.user; // Default role for unauthenticated users
    }
    
    try {
      // First, check if the role is in the user metadata
      final userMeta = currentUser!.userMetadata;
      if (userMeta != null && userMeta.containsKey('role')) {
        return userMeta['role'] == 'admin' ? UserRole.admin : UserRole.user;
      }
      
      // If not found in metadata, check the user_roles table
      final response = await client
          .from('user_roles')
          .select('role')
          .eq('user_id', currentUser!.id)
          .single();
      
      if (response.containsKey('role')) {
        return response['role'] == 'admin' ? UserRole.admin : UserRole.user;
      }
      
      // Default to regular user if no role is found
      return UserRole.user;
    } catch (e) {
      print('Error fetching user role: $e');
      return UserRole.user; // Default to regular user on error
    }
  }
  
  Future<bool> isAdmin() async {
    return await getUserRole() == UserRole.admin;
  }

  // Authentication Methods
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required UserRole role,
    Map<String, dynamic>? data,
  }) async {
    // Ensure data is initialized
    data ??= {};
    
    // Add role to user metadata
    data['role'] = role == UserRole.admin ? 'admin' : 'user';
    
    final response = await client.auth.signUp(
      email: email,
      password: password,
      data: data,
    );
    
    // If signup successful and user created, also store role in separate table
    if (response.user != null) {
      try {
        await client.from('user_roles').insert({
          'user_id': response.user!.id,
          'role': role == UserRole.admin ? 'admin' : 'user',
          'created_at': DateTime.now().toIso8601String(),
        });
      } catch (e) {
        print('Error saving user role: $e');
      }
    }
    
    return response;
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    await client.auth.signOut();
  }

  Future<void> resetPassword(String email) async {
    await client.auth.resetPasswordForEmail(
      email,
      redirectTo: 'io.supabase.flutterquickstart://login/',
    );
  }
  
  // Admin specific methods
  Future<List<Map<String, dynamic>>> getAllUsers() async {
    // Only admins should be able to access this
    if (!(await isAdmin())) {
      throw Exception('Unauthorized: Admin access required');
    }
    
    try {
      final response = await client
          .from('user_roles')
          .select('user_id, role, profiles(email, name)');
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching users: $e');
      return [];
    }
  }
  
  Future<bool> updateUserRole(String userId, UserRole role) async {
    // Only admins should be able to modify roles
    if (!(await isAdmin())) {
      throw Exception('Unauthorized: Admin access required');
    }
    
    try {
      await client
          .from('user_roles')
          .update({
            'role': role == UserRole.admin ? 'admin' : 'user',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('user_id', userId);
      return true;
    } catch (e) {
      print('Error updating user role: $e');
      return false;
    }
  }

  // Map Management Methods
  Future<String> uploadMap(String mapName, File mapImage) async {
    // Only admins should be able to upload maps
    if (!(await isAdmin())) {
      throw Exception('Unauthorized: Admin access required');
    }
    
    try {
      final String mapId = uuid.v4();
      final userId = currentUser?.id;
      
      if (userId == null) {
        throw Exception('User not authenticated');
      }
      
      // Instead of using Storage, we'll store the image directly in the database
      // using Base64 encoding (for small images this is fine)
      final bytes = await mapImage.readAsBytes();
      final base64Image = base64Encode(bytes);
      final imageUrl = 'data:image/${path.extension(mapImage.path).replaceFirst('.', '')};base64,$base64Image';
      
      try {
        // Try direct insertion first
        await client.from('maps').insert({
          'id': mapId,
          'name': mapName,
          'image_url': imageUrl,
          'is_public': true, // Setting to public by default for easier testing
          'created_at': DateTime.now().toIso8601String(),
          'user_id': userId,
        });
        
        print('Map uploaded successfully with ID: $mapId');
        return mapId;
      } catch (insertError) {
        print('Direct insert error: $insertError');
        throw Exception('Failed to save map data: $insertError');
      }
    } catch (e) {
      print('Error uploading map: $e');
      throw Exception('Failed to upload map: ${e.toString()}');
    }
  }
  
  Future<List<Map<String, dynamic>>> getMaps() async {
    try {
      // For admin, get all maps
      // For regular user, get only public maps or their own maps
      final query = client.from('maps').select('*, map_nodes(count)');
      
      if (!(await isAdmin())) {
        // For non-admin users, get only public maps or their own
        // Adjust this based on your requirements
        final userId = currentUser?.id;
        if (userId != null) {
          query.or('is_public.eq.true,user_id.eq.$userId');
        } else {
          query.eq('is_public', true);
        }
      }
      
      final response = await query;
      
      // Process the response to get the node count
      return List<Map<String, dynamic>>.from(response.map((map) {
        final List mapNodes = map['map_nodes'] ?? [];
        return {
          'id': map['id'],
          'name': map['name'],
          'image_url': map['image_url'],
          'is_public': map['is_public'] ?? false,
          'created_at': map['created_at'],
          'node_count': mapNodes.length,
        };
      }));
    } catch (e) {
      print('Error getting maps: $e');
      return [];
    }
  }
  
  Future<Map<String, dynamic>> getMapDetails(String mapId) async {
    try {
      final response = await client
          .from('maps')
          .select('*, map_nodes(*)')
          .eq('id', mapId)
          .single();
      
      // Check access rights for non-admin users
      if (!(await isAdmin())) {
        if (response['user_id'] != currentUser?.id && !(response['is_public'] ?? false)) {
          throw Exception('Access denied. This map is private.');
        }
      }
      
      return response;
    } catch (e) {
      print('Error getting map details: $e');
      throw Exception('Failed to get map details: ${e.toString()}');
    }
  }
  
  // Map Node Methods
  Future<String> createMapNode(String mapId, String nodeName, double x, double y) async {
    try {
      final String nodeId = uuid.v4();
      final userId = currentUser?.id;
      
      if (userId == null) {
        throw Exception('User not authenticated');
      }
      
      await client.from('map_nodes').insert({
        'id': nodeId,
        'map_id': mapId,
        'name': nodeName,
        'x_position': x,
        'y_position': y,
        'created_at': DateTime.now().toIso8601String(),
        'user_id': userId,
      });
      
      return nodeId;
    } catch (e) {
      print('Error creating map node: $e');
      throw Exception('Failed to create map node: ${e.toString()}');
    }
  }

  // NEW: Get details for a single map node
  Future<Map<String, dynamic>> getMapNodeDetails(String nodeId) async {
    try {
      final response = await client
          .from('map_nodes')
          .select()
          .eq('id', nodeId)
          .single();
      return response;
    } catch (e) {
      print('Error getting map node details: $e');
      throw Exception('Failed to get map node details: ${e.toString()}');
    }
  }

  // NEW: Update an existing map node
  Future<void> updateMapNode(String nodeId, String nodeName, double x, double y) async {
    try {
      final userId = currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      await client
          .from('map_nodes')
          .update({
            'name': nodeName,
            'x_position': x,
            'y_position': y,
          })
          .eq('id', nodeId);
    } catch (e) {
      print('Error updating map node: $e');
      throw Exception('Failed to update map node: ${e.toString()}');
    }
  }

  // NEW: Delete a map node and its associated embedding
  Future<void> deleteMapNode(String nodeId) async {
    try {
      // First, delete the associated embedding (if it exists)
      // Use maybeSingle() in case there's no embedding for the node
      await client
          .from('place_embeddings')
          .delete()
          .eq('node_id', nodeId)
          .maybeSingle(); 
          
      print('Deleted embedding associated with node: $nodeId (if existed)');

      // Then, delete the map node itself
      await client
          .from('map_nodes')
          .delete()
          .eq('id', nodeId);
          
      print('Deleted map node: $nodeId');

    } catch (e) {
      print('Error deleting map node $nodeId: $e');
      throw Exception('Failed to delete map node: ${e.toString()}');
    }
  }

  // Save embedding to Supabase
  // Modify to handle updates if nodeId is provided
  Future<String?> saveEmbedding(String placeName, List<double> embedding, {String? nodeId}) async {
    try {
      final userId = currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // If nodeId is provided, try to update existing embedding first
      if (nodeId != null) {
        try {
          final updateResponse = await client
              .from('place_embeddings')
              .update({
                'place_name': placeName, // Update name in case it changed
                'embedding': jsonEncode(embedding),
                'updated_at': DateTime.now().toIso8601String(),
                'user_id': userId, // Update user_id in case ownership changes (optional)
              })
              .eq('node_id', nodeId)
              .select('id') // Select ID to confirm update happened
              .maybeSingle(); // Use maybeSingle as node might not have embedding yet

          if (updateResponse != null && updateResponse['id'] != null) {
            print('Updated embedding for node: $nodeId');
            return updateResponse['id']; // Return the existing embedding ID
          } else {
             print('No existing embedding found for node $nodeId, creating new one.');
             // Fall through to create a new embedding if update failed (no existing record)
          }
        } catch (updateError) {
          print('Error trying to update embedding for node $nodeId: $updateError. Creating new one.');
          // Fall through to create a new embedding if update check failed
        }
      }

      // Create new embedding if nodeId is null or update failed/not found
      final id = uuid.v4();
      Map<String, dynamic> data = {
        'id': id,
        'place_name': placeName,
        'embedding': jsonEncode(embedding),
        'created_at': DateTime.now().toIso8601String(),
        'user_id': userId,
      };
      
      // Add node reference if provided (for new embeddings)
      if (nodeId != null) {
        data['node_id'] = nodeId;
      }
      
      await client.from('place_embeddings').insert(data);
      print('Created new embedding with ID: $id for node: $nodeId');
      return id;

    } catch (e) {
      print('Error saving/updating embedding: $e');
      return null;
    }
  }

  // Get all embeddings for comparison
  Future<Map<String, List<double>>> getAllEmbeddings() async {
    try {
      final query = client.from('place_embeddings').select('place_name, embedding');
      
      // Admin can see all embeddings, regular users only see public ones or their own
      if (!(await isAdmin())) {
        // For non-admin users, either get only their embeddings or public ones
        // This is just an example - adjust based on your requirements
        query.or('is_public.eq.true,user_id.eq.${currentUser?.id}');
      }
      
      final response = await query;
      
      Map<String, List<double>> embeddings = {};
      
      for (final item in response) {
        final String placeName = item['place_name'];
        final List<dynamic> rawEmbedding = jsonDecode(item['embedding']);
        final List<double> embedding = rawEmbedding.map<double>((e) => e is int ? e.toDouble() : e as double).toList();
        
        embeddings[placeName] = embedding;
      }
      
      return embeddings;
    } catch (e) {
      print('Error loading embeddings: $e');
      return {};
    }
  }
}