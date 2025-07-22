import 'dart:convert';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as path;
import 'dart:math';

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
    data ??= {};
    data['role'] = role == UserRole.admin ? 'admin' : 'user';

    print('Attempting Supabase signup for email: $email'); // Log before signup call
    AuthResponse response;
    try {
       response = await client.auth.signUp(
        email: email,
        password: password,
        data: data,
      );
      // Log the response details
      print('Supabase signup response received.');
      print('  - User: ${response.user?.id ?? 'null'}');
      print('  - Session: ${response.session?.accessToken ?? 'null'}');
    } catch (authError) {
       print('Error during client.auth.signUp: $authError');
       // Re-throw the error or handle it appropriately
       throw authError;
    }


    if (response.user != null) {
      print('Signup successful, user object exists. Attempting to insert role into user_roles table.'); // Log entering the if block
      try {
        // Generate a UUID for the 'id' column
        final String newRoleId = uuid.v4();
        final String userRoleString = role == UserRole.admin ? 'admin' : 'user';
        final String currentTime = DateTime.now().toIso8601String();

        print('Attempting to insert into user_roles: id=$newRoleId, user_id=${response.user!.id}, role=$userRoleString, created_at=$currentTime');

        await client.from('user_roles').insert({
          'id': newRoleId,
          'user_id': response.user!.id,
          'role': userRoleString,
          'created_at': currentTime,
        });
        print('User role inserted into user_roles table for ${response.user!.id}');
      } catch (e) {
        print('Error saving user role to user_roles table: $e');
        if (e is PostgrestException) {
          print('Postgrest Error Details: ${e.details}');
          print('Postgrest Error Hint: ${e.hint}');
          print('Postgrest Error Code: ${e.code}');
        }
      }
    } else {
        print('Signup response did not contain a user object. Skipping user_roles insert.'); // Log if user is null
    }

    return response;
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    print('Attempting Supabase sign in for email: $email'); // Log sign-in attempt
    AuthResponse response;
    try {
      response = await client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      print('Supabase sign in response received.');
      print('  - User: ${response.user?.id ?? 'null'}');
      print('  - Session: ${response.session?.accessToken ?? 'null'}');

      // --- ADD ROLE CHECK/INSERT LOGIC HERE ---
      if (response.user != null) {
        print('Sign in successful, user object exists. Ensuring user role exists.');
        await _ensureUserRoleExists(response.user!.id);
      } else {
        print('Sign in response did not contain a user object.');
      }
      // --- END ROLE CHECK/INSERT LOGIC ---

    } catch (authError) {
      print('Error during client.auth.signInWithPassword: $authError');
      // Re-throw the error or handle it appropriately
      throw authError;
    }
    return response;
  }

  // --- MODIFY HELPER FUNCTION HERE ---
  Future<void> _ensureUserRoleExists(String userId) async {
    try {
      // Check if a role already exists for this user
      final existingRoleResponse = await client
          .from('user_roles')
          .select('user_id') // Select any column just to check existence
          .eq('user_id', userId)
          .maybeSingle(); // Use maybeSingle to handle 0 or 1 result

      if (existingRoleResponse == null) {
        // No role found, determine role from metadata and insert
        print('No role found for user $userId. Determining role from metadata and inserting.');

        // Get the current user's metadata
        final userMetaData = client.auth.currentUser?.userMetadata;
        String roleToInsert = 'user'; // Default to 'user'

        if (userMetaData != null && userMetaData.containsKey('role')) {
          final metadataRole = userMetaData['role'] as String?;
          if (metadataRole == 'admin') {
            roleToInsert = 'admin';
          }
          // Add other role checks here if needed
        }
        print('Role determined from metadata (or default): $roleToInsert');

        final String newRoleId = uuid.v4(); // Generate ID for the new role entry
        final String currentTime = DateTime.now().toIso8601String();

        await client.from('user_roles').insert({
          'id': newRoleId,
          'user_id': userId,
          'role': roleToInsert, // Use the determined role
          'created_at': currentTime,
        });
        print('Role ($roleToInsert) inserted for user $userId.');
      } else {
        // Role already exists
        print('Role already exists for user $userId.');
      }
    } catch (e) {
      print('Error ensuring user role exists for user $userId: $e');
      if (e is PostgrestException) {
        print('Postgrest Error Details: ${e.details}');
        print('Postgrest Error Hint: ${e.hint}');
        print('Postgrest Error Code: ${e.code}');
      }
    }
  }
  // --- END HELPER FUNCTION MODIFICATION ---

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
      // 1. Fetch user roles
      final rolesResponse = await client
          .from('user_roles')
          .select('user_id, role'); // Select only columns from user_roles

      final List<Map<String, dynamic>> userRoles = List<Map<String, dynamic>>.from(rolesResponse);

      if (userRoles.isEmpty) {
        return []; // No users found
      }

      // 2. Extract user IDs
      final List<String> userIds = userRoles.map((roleData) => roleData['user_id'] as String).toList();

      // 3. Fetch corresponding profiles
      // Assuming the 'profiles' table has an 'id' column matching user_id
      final profilesResponse = await client
          .from('profiles')
          .select('id, email, name') // Select relevant profile columns
          .inFilter('id', userIds); // Filter by the list of user IDs

      final List<Map<String, dynamic>> profiles = List<Map<String, dynamic>>.from(profilesResponse);

      // 4. Combine the results
      // Create a map for quick profile lookup
      final Map<String, Map<String, dynamic>> profileMap = {
        for (var profile in profiles) profile['id'] as String: profile
      };

      // Merge roles with profiles
      final List<Map<String, dynamic>> combinedResults = userRoles.map((roleData) {
        final String userId = roleData['user_id'];
        final profileData = profileMap[userId];
        return {
          'user_id': userId,
          'role': roleData['role'],
          'email': profileData?['email'], // Use null-aware access
          'name': profileData?['name'],   // Use null-aware access
          // Add other profile fields if needed
        };
      }).toList();

      return combinedResults;

    } catch (e) {
      print('Error fetching users: $e');
       if (e is PostgrestException) {
        print('Postgrest Error Details: ${e.details}');
        print('Postgrest Error Hint: ${e.hint}');
        print('Postgrest Error Code: ${e.code}');
      }
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

      // Process the response to get the node count correctly
      return List<Map<String, dynamic>>.from(response.map((map) {
        // --- FIX START ---
        int nodeCount = 0; // Default to 0
        final List<dynamic>? countData = map['map_nodes'] as List<dynamic>?; // Cast safely
        if (countData != null && countData.isNotEmpty) {
          final Map<String, dynamic>? countMap = countData[0] as Map<String, dynamic>?; // Cast safely
          if (countMap != null && countMap.containsKey('count')) {
            nodeCount = countMap['count'] as int? ?? 0; // Extract count, default to 0 if null
          }
        }
        // --- FIX END ---

        return {
          'id': map['id'],
          'name': map['name'],
          'image_url': map['image_url'],
          'is_public': map['is_public'] ?? false,
          'created_at': map['created_at'],
          'node_count': nodeCount, // Use the correctly extracted count
        };
      }));
    } catch (e) {
      print('Error getting maps: $e');
      return [];
    }
  }
  
  Future<Map<String, dynamic>> getMapDetails(String mapId) async {
    try {
      print('Fetching fresh map details for map ID: $mapId');
      
      // Use .select() with explicit columns and foreign table query
      final response = await client
          .from('maps')
          .select('*, map_nodes(*)') // Fetch all map columns and all related map_nodes columns
          .eq('id', mapId)
          .single(); // Expecting a single map result
      
      // --- DETAILED LOGGING ---
      print('Map details raw response: $response'); 
      
      if (response['map_nodes'] != null) {
        final nodes = response['map_nodes'] as List;
        print('Fetched ${nodes.length} nodes from DB:');
        for (var node in nodes) {
          // Log ID and Name specifically
          print('  - DB Node ID: ${node['id']}, Name: "${node['name']}"'); 
        }
      } else {
        print('No map_nodes found in the response for map $mapId.');
      }
      // --- END LOGGING ---

      // Check access rights for non-admin users
      if (!(await isAdmin())) {
        if (response['user_id'] != currentUser?.id && !(response['is_public'] ?? false)) {
          throw Exception('Access denied. This map is private.');
        }
      }
      
      return response;
    } catch (e) {
      print('Error getting map details: $e');
      // Log the specific error type
      print('Error type: ${e.runtimeType}'); 
      if (e is PostgrestException) {
        print('Postgrest Error Details: ${e.details}');
        print('Postgrest Error Hint: ${e.hint}');
        print('Postgrest Error Code: ${e.code}');
      }
      throw Exception('Failed to get map details: ${e.toString()}');
    }
  }
  
  // NEW: Delete a map and all its associated nodes and embeddings
  Future<void> deleteMap(String mapId) async {
    // Only admins should be able to delete maps
    if (!(await isAdmin())) {
      throw Exception('Unauthorized: Admin access required to delete maps');
    }

    print('Attempting to delete map: $mapId');

    try {
      // 1. Get all node IDs associated with the map
      final nodesResponse = await client
          .from('map_nodes')
          .select('id')
          .eq('map_id', mapId);

      final List<String> nodeIds = (nodesResponse as List)
          .map((node) => node['id'] as String)
          .toList();

      print('Found ${nodeIds.length} nodes associated with map $mapId: $nodeIds');

      // 2. Delete associated place_embeddings (if any nodes exist)
      if (nodeIds.isNotEmpty) {
        print('Deleting place_embeddings for nodes: $nodeIds');
        await client
            .from('place_embeddings')
            .delete()
            .inFilter('node_id', nodeIds);
        print('Deleted embeddings associated with the map\'s nodes.');
      } else {
        print('No nodes found for map $mapId, skipping embedding deletion.');
      }

      // 3. Delete associated map_nodes
      print('Deleting map_nodes for map: $mapId');
      await client
          .from('map_nodes')
          .delete()
          .eq('map_id', mapId);
      print('Deleted nodes associated with the map.');

      // 4. Delete the map itself
      print('Deleting map entry: $mapId');
      await client
          .from('maps')
          .delete()
          .eq('id', mapId);
      print('Successfully deleted map: $mapId');

    } catch (e) {
      print('Error deleting map $mapId: $e');
      if (e is PostgrestException) {
        print('Postgrest Error Details: ${e.details}');
        print('Postgrest Error Hint: ${e.hint}');
        print('Postgrest Error Code: ${e.code}');
      }
      // Re-throw a more specific error
      throw Exception('Failed to delete map and associated data: ${e.toString()}');
    }
  }

  // Map Node Methods
  Future<String> createMapNode(String mapId, String nodeName, double x, double y, {double? referenceDirection}) async {
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
        'reference_direction': referenceDirection, // Store the entrance direction if provided
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

  // Update an existing map node and related place_embeddings if they exist
  Future<void> updateMapNode(String nodeId, String nodeName, double x, double y, {double? referenceDirection}) async {
    try {
      final userId = currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final bool isAdminUser = await isAdmin();
      print('Attempting updateMapNode. User ID: $userId, Is Admin: $isAdminUser');

      // Prepare update data
      final Map<String, dynamic> updateData = {
        'name': nodeName,
        'x_position': x,
        'y_position': y,
      };
      
      // Only add reference_direction if it's provided
      if (referenceDirection != null) {
        updateData['reference_direction'] = referenceDirection;
      }

      print('Updating node in map_nodes table: $nodeId, name: "$nodeName"');
      // Modify the update call to select the result
      final updateResponse = await client
          .from('map_nodes')
          .update(updateData)
          .eq('id', nodeId)
          .select() // Add .select() here
          .maybeSingle(); // Use maybeSingle in case RLS *still* blocks it

      // Log the response from the update itself
      if (updateResponse == null) {
        print('WARNING: Update call returned null. RLS might still be blocking.');
      } else {
        print('Update response data: $updateResponse');
        // Check the name directly from the update response
        final updatedNameInResponse = updateResponse['name'] ?? 'N/A';
        print('Name in update response: "$updatedNameInResponse"');
        if (updatedNameInResponse != nodeName) {
           print('WARNING: Name in update response does not match expected name!');
        }
      }


      // --- UNCOMMENT place_embeddings UPDATE ---
      print('Checking for related place_embeddings to update...');
      try {
        await client
            .from('place_embeddings')
            .update({
              'place_name': nodeName,
            })
            .eq('node_id', nodeId);
        print('Attempted to update place_embeddings associated with node: $nodeId');
      } catch (embeddingError) {
        if (embeddingError is PostgrestException && embeddingError.code == 'PGRST204') {
             print('Note: place_embeddings table does not have an updated_at column.');
        } else {
            print('Note: No place_embeddings found for node or other update error: $embeddingError');
        }
      }
      // --- END UNCOMMENT ---

      print('Node update attempt complete. Node ID: $nodeId, Name: "$nodeName"');
    } catch (e) {
      print('Error updating map node: $e');
      throw Exception('Failed to update map node: ${e.toString()}');
    }
  }

  // NEW: Delete a map node and its associated embedding
  Future<void> deleteMapNode(String nodeId) async {
    try {
      // First, delete the associated embedding (if it exists)
      // Remove .maybeSingle() from the delete operation
      await client
          .from('place_embeddings')
          .delete()
          .eq('node_id', nodeId);

      print('Deleted embedding associated with node: $nodeId (if existed)');

      // Then, delete the map node itself
      // Ensure RLS allows this delete based on user_id or admin role
      await client
          .from('map_nodes')
          .delete()
          .eq('id', nodeId);

      print('Deleted map node: $nodeId');

    } catch (e) {
      print('Error deleting map node $nodeId: $e');
      // Add more detailed error logging if needed
      if (e is PostgrestException) {
        print('Postgrest Error Details: ${e.details}');
        print('Postgrest Error Hint: ${e.hint}');
        print('Postgrest Error Code: ${e.code}');
      }
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
      
      // Create a map to store embeddings and counts for each place name
      Map<String, List<List<double>>> embeddingsByPlace = {};
      
      // Group embeddings by place name
      for (final item in response) {
        final String placeName = item['place_name'];
        final List<dynamic> rawEmbedding = jsonDecode(item['embedding']);
        final List<double> embedding = rawEmbedding.map<double>((e) => e is int ? e.toDouble() : e as double).toList();
        
        // Add to list of embeddings for this place
        if (!embeddingsByPlace.containsKey(placeName)) {
          embeddingsByPlace[placeName] = [];
        }
        embeddingsByPlace[placeName]!.add(embedding);
      }
      
      // Average the embeddings for each place
      Map<String, List<double>> finalEmbeddings = {};
      embeddingsByPlace.forEach((placeName, embeddings) {
        // If only one embedding, use it directly
        if (embeddings.length == 1) {
          finalEmbeddings[placeName] = embeddings[0];
          return;
        }
        
        // Average multiple embeddings
        final int embeddingSize = embeddings[0].length;
        List<double> averagedEmbedding = List<double>.filled(embeddingSize, 0.0);
        
        // Sum all embeddings
        for (final List<double> embedding in embeddings) {
          for (int i = 0; i < embeddingSize; i++) {
            averagedEmbedding[i] += embedding[i];
          }
        }
        
        // Divide by count to get average
        for (int i = 0; i < embeddingSize; i++) {
          averagedEmbedding[i] = averagedEmbedding[i] / embeddings.length;
        }
        
        // Normalize the averaged embedding (ensure it's a unit vector)
        double magnitude = 0.0;
        for (int i = 0; i < embeddingSize; i++) {
          magnitude += averagedEmbedding[i] * averagedEmbedding[i];
        }
        magnitude = sqrt(magnitude);
        
        if (magnitude > 0) {
          for (int i = 0; i < embeddingSize; i++) {
            averagedEmbedding[i] = averagedEmbedding[i] / magnitude;
          }
        }
        
        finalEmbeddings[placeName] = averagedEmbedding;
      });
      
      return finalEmbeddings;
    } catch (e) {
      print('Error loading embeddings: $e');
      return {};
    }
  }

  // Navigation Connection Methods
  Future<String> createNodeConnection({
    required String mapId,
    required String nodeAId,
    required String nodeBId,
    double? distanceMeters,
    int? steps,
    double? averageHeading,
    String? customInstruction,
    List<Map<String, dynamic>>? confirmationObjects,
  }) async {
    try {
      final String connectionId = uuid.v4();
      final userId = currentUser?.id;
      
      if (userId == null) {
        throw Exception('User not authenticated');
      }
      
      await client.from('node_connections').insert({
        'id': connectionId,
        'map_id': mapId,
        'node_a_id': nodeAId,
        'node_b_id': nodeBId,
        'distance_meters': distanceMeters,
        'steps': steps,
        'average_heading': averageHeading,
        'custom_instruction': customInstruction,
        'confirmation_objects': confirmationObjects != null ? jsonEncode(confirmationObjects) : null,
        'created_at': DateTime.now().toIso8601String(),
        'user_id': userId,
      });
      return connectionId;
    } catch (e) {
      print('Error creating node connection: $e');
      throw Exception('Failed to create node connection: ${e.toString()}');
    }
  }

  Future<bool> updateNodeConnection({
    required String connectionId,
    int? steps,
    double? distanceMeters,
    double? averageHeading,
    List<Map<String, dynamic>>? confirmationObjects,
  }) async {
    try {
      await client.from('node_connections').update({
        'steps': steps,
        'distance_meters': distanceMeters,
        'average_heading': averageHeading,
        'confirmation_objects': confirmationObjects != null ? jsonEncode(confirmationObjects) : null,
      }).eq('id', connectionId);
      return true;
    } catch (e) {
      print('Error updating node connection: $e');
      return false;
    }
  }

  Future<void> deleteNodeConnection(String connectionId) async {
    try {
      await client.from('node_connections').delete().eq('id', connectionId);
    } catch (e) {
      print('Error deleting node connection: $e');
      throw Exception('Failed to delete node connection: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>> getNavigationData(String mapId) async {
    try {
      final nodes = await client.from('map_nodes').select('*').eq('map_id', mapId);
      final connections = await client.from('node_connections').select('*').eq('map_id', mapId);
      return {'nodes': nodes, 'connections': connections};
    } catch (e) {
      print('Error getting navigation data: $e');
      throw Exception('Failed to get navigation data: ${e.toString()}');
    }
  }

  Future<List<Map<String, dynamic>>> getWalkingSessions(String mapId) async {
    try {
      return await client.from('walking_sessions').select('*').eq('map_id', mapId);
    } catch (e) {
      print('Error getting walking sessions: $e');
      throw Exception('Failed to get walking sessions: ${e.toString()}');
    }
  }

  Future<String> saveWalkingSession({
    required String mapId,
    required String startNodeId,
    required String endNodeId,
    required double distanceMeters,
    required int stepCount,
    required double averageHeading,
    required String instruction,
    required List<Map<String, dynamic>> detectedObjects,
  }) async {
    try {
      final String sessionId = uuid.v4();
      final userId = currentUser?.id;
      
      if (userId == null) {
        throw Exception('User not authenticated');
      }
      
      await client.from('walking_sessions').insert({
        'id': sessionId,
        'map_id': mapId,
        'start_node_id': startNodeId,
        'end_node_id': endNodeId,
        'distance_meters': distanceMeters,
        'step_count': stepCount,
        'average_heading': averageHeading,
        'instruction': instruction,
        'detected_objects': jsonEncode(detectedObjects),
        'created_at': DateTime.now().toIso8601String(),
        'user_id': userId,
      });
      return sessionId;
    } catch (e) {
      print('Error saving walking session: $e');
      throw Exception('Failed to save walking session: ${e.toString()}');
    }
  }

  // Path Recording Methods
  Future<String> saveRecordedPath(Map<String, dynamic> pathData) async {
    try {
      final String pathId = uuid.v4();
      final userId = currentUser?.id;
      
      if (userId == null) {
        throw Exception('User not authenticated');
      }
      
      // Prepare the path data with additional fields
      final Map<String, dynamic> completePathData = {
        'id': pathId,
        'user_id': userId,
        'created_at': DateTime.now().toIso8601String(),
        ...pathData, // Spread the provided path data
      };
      
      await client.from('recorded_paths').insert(completePathData);
      print('Recorded path saved with ID: $pathId');
      return pathId;
    } catch (e) {
      print('Error saving recorded path: $e');
      throw Exception('Failed to save recorded path: ${e.toString()}');
    }
  }
}