import 'dart:convert';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as path;
import 'dart:math' as math;
import '../models/path_models.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Define user roles
enum UserRole {
  user,
  admin,
}

// Custom wrapper class for signup results
class SignUpResult {
  final AuthResponse authResponse;
  final bool isNewUser;

  SignUpResult({required this.authResponse, required this.isNewUser});
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
      url: dotenv.env['SUPABASE_URL']!,
      anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
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
          if (createError is StorageException &&
              createError.statusCode == '403') {
            print(
                'Warning: No permission to create bucket. Assuming it exists.');
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

      // If not found in metadata, check the profiles table
      final response = await client
          .from('profiles')
          .select('role')
          .eq('id', currentUser!.id)
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

  // Get current user profile info
  Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    final user = currentUser;
    if (user == null) return null;

    try {
      final profileData = await client
          .from('profiles')
          .select('id, role, organization_id, created_at')
          .eq('id', user.id)
          .maybeSingle();

      if (profileData != null) {
        return {
          ...profileData,
          'email': user.email,
        };
      }

      return {
        'id': user.id,
        'email': user.email,
        'role': 'user',
        'organization_id': null,
      };
    } catch (e) {
      print('Error fetching user profile: $e');
      return null;
    }
  }

  // Helper method to check if email already exists using RPC
  Future<bool> checkEmailExists(String email) async {
    try {
      final result = await client.rpc(
        'email_exists',
        params: {'email_to_check': email.trim()},
      );
      print('RPC email_exists check for "$email": $result');
      return result as bool;
    } catch (e) {
      print('Error calling email_exists RPC: $e');
      // If the RPC fails for any reason (e.g., network error, function not found),
      // it's safer to allow the signup attempt to proceed and let Supabase handle it.
      // Returning true here would block all registrations if the function is broken.
      return false;
    }
  }

  Future<SignUpResult> signUpWithCheck({
    required String email,
    required String password,
    required UserRole role,
    Map<String, dynamic>? data,
  }) async {
    return await signUp(
      email: email,
      password: password,
      role: role,
      data: data,
    );
  }

  Future<SignUpResult> signUp({
    required String email,
    required String password,
    required UserRole role,
    Map<String, dynamic>? data,
  }) async {
    data ??= {};
    data['role'] = role == UserRole.admin ? 'admin' : 'user';

    print('Attempting Supabase signup for email: $email');
    AuthResponse response;
    bool isNewUser = false;

    try {
      response = await client.auth.signUp(
        email: email,
        password: password,
        data: data,
        // Add redirect URL specifically for email confirmation
        // This ensures confirmation links go to the correct handler
        emailRedirectTo: 'com.example.indoornavigation://auth/callback',
      );

      print('Supabase signup response received.');
      print('  - User: ${response.user?.id ?? 'null'}');
      print('  - User Email: ${response.user?.email ?? 'null'}');
      print(
          '  - User Email Confirmed: ${response.user?.emailConfirmedAt ?? 'null'}');
      print(
          '  - Session: ${response.session?.accessToken != null ? "exists" : "null"}');

      // Determine if this is a new user
      // For new signups, session is typically null until email confirmation
      isNewUser = response.session == null;

      if (response.user != null && isNewUser) {
        print('New user signup detected - inserting into profiles table.');
        try {
          final String userRoleString = role == UserRole.admin ? 'admin' : 'user';
          final String currentTime = DateTime.now().toIso8601String();

          print(
              'Attempting to insert into profiles: id=${response.user!.id}, role=$userRoleString');

          await client.from('profiles').insert({
            'id': response.user!.id,
            'email': response.user!.email,
            'role': userRoleString,
            'created_at': currentTime,
            'updated_at': currentTime,
          });
          print(
              'User profile inserted into profiles table for ${response.user!.id}');
        } catch (e) {
          print('Error saving user profile to profiles table: $e');
          if (e is PostgrestException) {
            print('Postgrest Error Details: ${e.details}');
            print('Postgrest Error Hint: ${e.hint}');
            print('Postgrest Error Code: ${e.code}');
          }

          // Don't fail the signup if profiles insert fails - user can still use the app
          print(
              'Continuing with signup despite profiles insert failure - user can still use the app');
        }
      } else if (response.user != null && !isNewUser) {
        print('Existing user detected - skipping profiles insert.');
      } else {
        print(
            'Signup response did not contain a user object. Skipping profiles insert.');
      }

      // For debugging: log the final decision
      print(
          'Final signup result: User exists: ${response.user != null}, IsNewUser: $isNewUser');

    } catch (authError) {
      print('Error during client.auth.signUp: $authError');
      // Re-throw the error for UI to handle
      throw authError;
    }

    return SignUpResult(authResponse: response, isNewUser: isNewUser);
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    print(
        'Attempting Supabase sign in for email: $email'); // Log sign-in attempt
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
        print(
            'Sign in successful, user object exists. Ensuring user profile exists.');
        await _ensureUserProfileExists(response.user!.id);
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

  // --- SIMPLIFIED METHOD - Now only ensures profile exists ---
  Future<void> _ensureUserProfileExists(String userId) async {
    try {
      // Check if profile already exists
      final existingProfile = await client
          .from('profiles')
          .select('id')
          .eq('id', userId)
          .maybeSingle();

      if (existingProfile == null) {
        // Profile doesn't exist, it should be auto-created by the database trigger
        // But let's try to create it manually just in case
        print('Profile not found for user $userId. Trigger should have created it.');
        // The database trigger should handle this, so we don't need to manually insert
      } else {
        print('Profile already exists for user $userId.');
      }
    } catch (e) {
      print('Error checking user profile: $e');
      // Don't rethrow - profile creation is handled by database trigger
    }
  }
  // --- END HELPER FUNCTION MODIFICATION ---

  Future<void> signOut() async {
    await client.auth.signOut();
  }

  /// Refresh the current authentication session
  /// This can help resolve RLS policy violations
  Future<bool> refreshSession() async {
    try {
      print('🔄 Attempting to refresh authentication session...');
      final response = await client.auth.refreshSession();

      if (response.session != null) {
        print('✅ Session refreshed successfully');
        print('New session expires at: ${response.session!.expiresAt}');
        return true;
      } else {
        print('❌ Session refresh failed - no session returned');
        return false;
      }
    } catch (e) {
      print('❌ Error refreshing session: $e');
      return false;
    }
  }

  /// Debug method to check user authentication status in database
  Future<Map<String, dynamic>> debugUserAuthStatus() async {
    try {
      final userId = currentUser?.id;
      print('🔍 DEBUG: Checking user auth status for: $userId');

      final result = {
        'client_user_id': userId,
        'is_authenticated': isAuthenticated,
        'session_valid': client.auth.currentSession != null,
        'user_exists_in_auth': false,
        'user_role_exists': false,
        'user_role': null,
      };

      if (userId != null) {
        // Check if user exists in profiles table
        try {
          final profileResponse = await client
              .from('profiles')
              .select('role')
              .eq('id', userId)
              .maybeSingle();

          if (profileResponse != null) {
            result['user_role_exists'] = true;
            result['user_role'] = profileResponse['role'];
            print('✅ User profile found: ${profileResponse['role']}');
          } else {
            print('❌ No user profile found for user: $userId');
          }
        } catch (roleError) {
          print('❌ Error checking user profile: $roleError');
          result['role_check_error'] = roleError.toString();
        }

        // Try to query a table that should be accessible to check auth.uid()
        try {
          final testQuery = await client
              .from('profiles')
              .select('id')
              .eq('id', userId)
              .limit(1);

          result['user_exists_in_auth'] = testQuery.isNotEmpty;
          print('✅ User exists in auth context: ${testQuery.isNotEmpty}');
        } catch (authError) {
          print('❌ Error checking auth context: $authError');
          result['auth_check_error'] = authError.toString();
        }
      }

      print('🔍 DEBUG: Auth status result: $result');
      return result;
    } catch (e) {
      print('❌ Error in debugUserAuthStatus: $e');
      return {'error': e.toString()};
    }
  }

  /// Fix user role if it was incorrectly set during signup
  Future<bool> fixUserRole() async {
    try {
      final userId = currentUser?.id;
      if (userId == null) {
        print('❌ No current user to fix role for');
        return false;
      }

      // Check user metadata for the intended role
      final userMeta = currentUser!.userMetadata;
      String intendedRole = 'user'; // Default

      if (userMeta != null && userMeta.containsKey('role')) {
        intendedRole = userMeta['role'] as String;
        print('🔍 Found intended role in metadata: $intendedRole');
      } else {
        print('⚠️ No role found in user metadata, keeping current role');
        return true; // No change needed
      }

      // Update the profiles table with the correct role
      await client
          .from('profiles')
          .update({'role': intendedRole, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', userId);

      print('✅ User role updated to: $intendedRole');
      return true;
    } catch (e) {
      print('❌ Error fixing user role: $e');
      return false;
    }
  }

  /// Admin method to fix roles for all users who should be admins
  Future<int> fixAllAdminRoles() async {
    try {
      // Only allow if current user is admin
      final currentRole = await getUserRole();
      if (currentRole != 'admin') {
        print('❌ Only admins can fix all user roles');
        return 0;
      }

      // Find all users who have 'admin' in their metadata but 'user' in profiles
      final usersToFix = await client
          .from('profiles')
          .select('id, role')
          .eq('role', 'user');

      int fixedCount = 0;

      for (final user in usersToFix) {
        final userId = user['id'];

        // Check if this user should be admin based on their auth metadata
        try {
          final authUser = await client.auth.admin.getUserById(userId);
          final userMeta = authUser.user?.userMetadata;

          if (userMeta != null && userMeta['role'] == 'admin') {
            // Update the profile to admin
            await client
                .from('profiles')
                .update({'role': 'admin', 'updated_at': DateTime.now().toIso8601String()})
                .eq('id', userId);

            fixedCount++;
            print('✅ Fixed role for user: $userId');
          }
        } catch (e) {
          print('⚠️ Could not check metadata for user $userId: $e');
        }
      }

      print('✅ Fixed roles for $fixedCount users');
      return fixedCount;
    } catch (e) {
      print('❌ Error fixing all admin roles: $e');
      return 0;
    }
  }

  Future<void> resetPassword(String email) async {
    try {
      // Send password reset email with custom redirect URL to our app
      // This will use the deep link scheme for the app
      await client.auth.resetPasswordForEmail(
        email,
  // Use a distinct redirect path for password reset so it doesn't conflict
  // with email confirmation links which use '/auth/callback'.
  redirectTo: 'com.example.indoornavigation://auth/reset',
      );
    } catch (e) {
      print('Reset password error: $e');
      throw Exception('Failed to send reset email. Please try again.');
    }
  }

  Future<void> updatePassword({
    required String newPassword,
    String? accessToken,
    String? refreshToken,
  }) async {
    try {
      // If we have tokens from the reset link, establish a session first
      if (accessToken != null && refreshToken != null) {
        print('Setting session from password reset tokens');

        // Create a session using the tokens from the reset link
        final response = await client.auth.setSession(refreshToken);

        if (response.session != null) {
          print('Session established successfully');

          // Now update the password
          final updateResponse = await client.auth.updateUser(
            UserAttributes(password: newPassword),
          );

          print('Password update response: ${updateResponse.user?.id}');
        } else {
          throw Exception('Could not establish session with reset tokens');
        }
      } else {
        // Fallback: try to update password with current session
        await client.auth.updateUser(
          UserAttributes(password: newPassword),
        );
      }
    } catch (e) {
      print('Password update error: $e');
      throw Exception('Failed to update password. Please try again.');
    }
  }

  Future<Session?> exchangeCodeForSession(String authCode) async {
    try {
      // Use getSessionFromUrl method instead of exchangeCodeForSession
      // The authCode should be processed as a full URL callback
      final callbackUrl =
          'com.example.indoornavigation://auth/callback?code=$authCode';

      final response =
          await client.auth.getSessionFromUrl(Uri.parse(callbackUrl));

      return response.session;
    } catch (e) {
      // Try alternative method - setSession with the authorization code
      try {
        await client.auth.exchangeCodeForSession(authCode);
        final currentSession = client.auth.currentSession;
        if (currentSession != null) {
          return currentSession;
        }
      } catch (e2) {
        // Alternative method also failed
      }
      throw Exception(
          'Failed to process password reset link. Please try again.');
    }
  }

  // Admin specific methods
  Future<List<Map<String, dynamic>>> getAllUsers() async {
    // Only admins should be able to access this
    if (!(await isAdmin())) {
      throw Exception('Unauthorized: Admin access required');
    }

    try {
      // Fetch all users directly from profiles table
      final profilesResponse = await client
          .from('profiles')
          .select('id, email, role, created_at');

      final List<Map<String, dynamic>> profiles =
          List<Map<String, dynamic>>.from(profilesResponse);

      if (profiles.isEmpty) {
        return []; // No users found
      }

      // Format the results to match the expected structure
      final List<Map<String, dynamic>> combinedResults =
          profiles.map((profile) {
        return {
          'user_id': profile['id'],
          'role': profile['role'] ?? 'user',
          'email': profile['email'],
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
      await client.from('profiles').update({
        'role': role == UserRole.admin ? 'admin' : 'user',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);
      return true;
    } catch (e) {
      print('Error updating user role: $e');
      return false;
    }
  }

  // Map Management Methods
  Future<String> uploadMap(String mapName, File mapImage) async {
    // TEMPORARILY DISABLED ADMIN CHECK FOR TESTING
    // if (!(await isAdmin())) {
    //   throw Exception('Unauthorized: Admin access required');
    // }

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
      final imageUrl =
          'data:image/${path.extension(mapImage.path).replaceFirst('.', '')};base64,$base64Image';

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
      final userId = currentUser?.id;
      final isAdminUser = await isAdmin();

      print('🔍 DEBUG: getMaps() called');
      print('🔍 DEBUG: Current user ID: $userId');
      print('🔍 DEBUG: Is admin: $isAdminUser');

      final query = client.from('maps').select('*, map_nodes(count)');

      if (!isAdminUser) {
        // For non-admin users, get only public maps or their own
        if (userId != null) {
          query.or('is_public.eq.true,user_id.eq.$userId');
          print('🔍 DEBUG: Query filter: is_public=true OR user_id=$userId');
        } else {
          query.eq('is_public', true);
          print('🔍 DEBUG: Query filter: is_public=true (no user)');
        }
      } else {
        print('🔍 DEBUG: Admin user - getting all maps');
      }

      final response = await query;
      print('🔍 DEBUG: Query returned ${response.length} maps');

      // Log details of each map for debugging
      for (var map in response) {
        print('🔍 DEBUG: Map ${map['id']}: name=${map['name']}, user_id=${map['user_id']}, is_public=${map['is_public']}');
      }

      // Process the response to get the node count correctly
      return List<Map<String, dynamic>>.from(response.map((map) {
        // --- FIX START ---
        int nodeCount = 0; // Default to 0
        final List<dynamic>? countData =
            map['map_nodes'] as List<dynamic>?; // Cast safely
        if (countData != null && countData.isNotEmpty) {
          final Map<String, dynamic>? countMap =
              countData[0] as Map<String, dynamic>?; // Cast safely
          if (countMap != null && countMap.containsKey('count')) {
            nodeCount = countMap['count'] as int? ??
                0; // Extract count, default to 0 if null
          }
        }

        return {
          'id': map['id'],
          'name': map['name'],
          'image_url': map['image_url'],
          'is_public': map['is_public'] ?? false,
          'created_at': map['created_at'],
          'node_count': nodeCount,
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
          .select(
              '*, map_nodes(*)') // Fetch all map columns and all related map_nodes columns
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
        if (response['user_id'] != currentUser?.id &&
            !(response['is_public'] ?? false)) {
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
      final nodesResponse =
          await client.from('map_nodes').select('id').eq('map_id', mapId);

      final List<String> nodeIds =
          (nodesResponse as List).map((node) => node['id'] as String).toList();

      print(
          'Found ${nodeIds.length} nodes associated with map $mapId: $nodeIds');

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
      await client.from('map_nodes').delete().eq('map_id', mapId);
      print('Deleted nodes associated with the map.');

      // 4. Delete the map itself
      print('Deleting map entry: $mapId');
      await client.from('maps').delete().eq('id', mapId);
      print('Successfully deleted map: $mapId');
    } catch (e) {
      print('Error deleting map $mapId: $e');
      if (e is PostgrestException) {
        print('Postgrest Error Details: ${e.details}');
        print('Postgrest Error Hint: ${e.hint}');
        print('Postgrest Error Code: ${e.code}');
      }
      // Re-throw a more specific error
      throw Exception(
          'Failed to delete map and associated data: ${e.toString()}');
    }
  }

  // Map Node Methods
  Future<String> createMapNode(
      String mapId, String nodeName, double x, double y,
      {double? referenceDirection}) async {
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
        'reference_direction':
            referenceDirection, // Store the entrance direction if provided
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
      final response =
          await client.from('map_nodes').select().eq('id', nodeId).single();
      return response;
    } catch (e) {
      print('Error getting map node details: $e');
      throw Exception('Failed to get map node details: ${e.toString()}');
    }
  }

  // Update an existing map node and related place_embeddings if they exist
  Future<void> updateMapNode(String nodeId, String nodeName, double x, double y,
      {double? referenceDirection}) async {
    try {
      final userId = currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final bool isAdminUser = await isAdmin();
      print(
          'Attempting updateMapNode. User ID: $userId, Is Admin: $isAdminUser');

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
        print(
            'WARNING: Update call returned null. RLS might still be blocking.');
      } else {
        print('Update response data: $updateResponse');
        // Check the name directly from the update response
        final updatedNameInResponse = updateResponse['name'] ?? 'N/A';
        print('Name in update response: "$updatedNameInResponse"');
        if (updatedNameInResponse != nodeName) {
          print(
              'WARNING: Name in update response does not match expected name!');
        }
      }

      // --- UNCOMMENT place_embeddings UPDATE ---
      print('Checking for related place_embeddings to update...');
      try {
        await client.from('place_embeddings').update({
          'place_name': nodeName,
        }).eq('node_id', nodeId);
        print(
            'Attempted to update place_embeddings associated with node: $nodeId');
      } catch (embeddingError) {
        if (embeddingError is PostgrestException &&
            embeddingError.code == 'PGRST204') {
          print(
              'Note: place_embeddings table does not have an updated_at column.');
        } else {
          print(
              'Note: No place_embeddings found for node or other update error: $embeddingError');
        }
      }
      // --- END UNCOMMENT ---

      print(
          'Node update attempt complete. Node ID: $nodeId, Name: "$nodeName"');
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
      await client.from('place_embeddings').delete().eq('node_id', nodeId);

      print('Deleted embedding associated with node: $nodeId (if existed)');

      // Then, delete the map node itself
      // Ensure RLS allows this delete based on user_id or admin role
      await client.from('map_nodes').delete().eq('id', nodeId);

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
  // Modified to always create new embeddings for 360-degree videos
  Future<String?> saveEmbedding(String placeName, List<double> embedding,
      {String? nodeId, bool forceCreate = false}) async {
    try {
      final userId = currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Get user's organization for embedding context
      final userProfile = await getCurrentUserProfile();
      final userOrganizationId = userProfile?['organization_id'];
      print('👤 Saving embedding for user organization: $userOrganizationId');

      // For 360-degree videos, we want multiple embeddings per node, so always create new ones
      // Only try to update if explicitly not forced to create and nodeId is provided
      if (nodeId != null && !forceCreate) {
        try {
          final updateData = {
            'place_name': placeName, // Update name in case it changed
            'embedding': jsonEncode(embedding),
            'user_id': userId, // Update user_id in case ownership changes (optional)
          };

          // Include organization_id in update if available
          if (userOrganizationId != null) {
            updateData['organization_id'] = userOrganizationId;
          }

          final updateResponse = await client
              .from('place_embeddings')
              .update(updateData)
              .eq('node_id', nodeId)
              .select('id') // Select ID to confirm update happened
              .maybeSingle(); // Use maybeSingle as node might not have embedding yet

          if (updateResponse != null && updateResponse['id'] != null) {
            print('Updated embedding for node: $nodeId with organization: $userOrganizationId');
            return updateResponse['id']; // Return the existing embedding ID
          } else {
            print(
                'No existing embedding found for node $nodeId, creating new one.');
            // Fall through to create a new embedding if update failed (no existing record)
          }
        } catch (updateError) {
          print(
              'Error trying to update embedding for node $nodeId: $updateError. Creating new one.');
          // Fall through to create a new embedding if update check failed
        }
      }

      // Create new embedding (default behavior for 360-degree videos)
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

      // Add organization_id if available (for organization-based access control)
      if (userOrganizationId != null) {
        data['organization_id'] = userOrganizationId;
      }

      await client.from('place_embeddings').insert(data);
      print('Created new embedding with ID: $id for node: $nodeId, organization: $userOrganizationId');
      return id;
    } catch (e) {
      print('Error saving/updating embedding: $e');
      return null;
    }
  }

  // Get all embeddings for comparison
  Future<Map<String, List<double>>> getAllEmbeddings() async {
    try {
      // Get user's organization for filtering
      final userProfile = await getCurrentUserProfile();
      final userOrganizationId = userProfile?['organization_id'];
      final isAdminUser = await isAdmin();

      print('👤 getAllEmbeddings() - User organization: $userOrganizationId, Is Admin: $isAdminUser');

      final query = client.from('place_embeddings').select('place_name, embedding, organization_id');

      // Apply organization-based filtering
      if (isAdminUser) {
        // Admin users can see ALL content from their organization (including other admins' content)
        if (userOrganizationId != null) {
          query.or('organization_id.eq.$userOrganizationId,organization_id.is.null');
          print('🔓 Admin user - filtering by organization: $userOrganizationId (including null org for compatibility)');
        } else {
          // Admin with no organization can only see their own content
          final userId = currentUser?.id;
          if (userId != null) {
            query.eq('user_id', userId);
            print('🔓 Admin user (no organization) - filtering by user: $userId');
          } else {
            print('⚠️ No user ID available for admin filtering');
            return {};
          }
        }
      } else {
        // Regular users can see content from their organization OR null organization_id (backward compatibility)
        if (userOrganizationId != null) {
          query.or('organization_id.eq.$userOrganizationId,organization_id.is.null');
          print('🔒 Regular user - filtering by organization: $userOrganizationId (including null org for compatibility)');
        } else {
          // Users without organization can only see their own embeddings
          final userId = currentUser?.id;
          if (userId != null) {
            query.eq('user_id', userId);
            print('🔒 Regular user (no organization) - filtering by user: $userId');
          } else {
            print('⚠️ No user ID available for filtering');
            return {};
          }
        }
      }

      final response = await query;

      // Create a map to store embeddings and counts for each place name
      Map<String, List<List<double>>> embeddingsByPlace = {};

      // Group embeddings by place name
      for (final item in response) {
        final String placeName = item['place_name'];
        final List<dynamic> rawEmbedding = jsonDecode(item['embedding']);
        final List<double> embedding = rawEmbedding
            .map<double>((e) => e is int ? e.toDouble() : e as double)
            .toList();

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
        List<double> averagedEmbedding =
            List<double>.filled(embeddingSize, 0.0);

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
        magnitude = math.sqrt(magnitude);

        if (magnitude > 0) {
          for (int i = 0; i < embeddingSize; i++) {
            averagedEmbedding[i] = averagedEmbedding[i] / magnitude;
          }
        }

        finalEmbeddings[placeName] = averagedEmbedding;
      });

      print('📊 Retrieved ${finalEmbeddings.length} unique place embeddings');
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
        'confirmation_objects': confirmationObjects != null
            ? jsonEncode(confirmationObjects)
            : null,
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
        'confirmation_objects': confirmationObjects != null
            ? jsonEncode(confirmationObjects)
            : null,
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

  Future<void> deleteNavigationPath(String pathId) async {
    try {
      final userId = currentUser?.id;

      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // First delete all waypoints for this path
      await client.from('path_waypoints').delete().eq('path_id', pathId);

      // Then delete the navigation path itself
      await client
          .from('navigation_paths')
          .delete()
          .eq('id', pathId)
          .eq('user_id', userId);
    } catch (e) {
      print('Error deleting navigation path: $e');
      throw Exception('Failed to delete navigation path: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>> getNavigationData(String mapId) async {
    try {
      final nodes =
          await client.from('map_nodes').select('*').eq('map_id', mapId);
      final connections =
          await client.from('node_connections').select('*').eq('map_id', mapId);
      return {'nodes': nodes, 'connections': connections};
    } catch (e) {
      print('Error getting navigation data: $e');
      throw Exception('Failed to get navigation data: ${e.toString()}');
    }
  }

  Future<List<Map<String, dynamic>>> getWalkingSessions(String mapId) async {
    try {
      return await client
          .from('walking_sessions')
          .select('*')
          .eq('map_id', mapId);
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

  // Save NavigationPath model to database
  Future<String> savePath(NavigationPath navigationPath) async {
    try {
      // Ensure user is authenticated and session is valid
      final userId = currentUser?.id;
      print('=== savePath() called ===');
      print('Path name: ${navigationPath.name}');
      print('Start location ID: ${navigationPath.startLocationId}');
      print('End location ID: ${navigationPath.endLocationId}');
      print('Current user ID: $userId');
      print('Is authenticated: $isAuthenticated');

      if (userId == null) {
        throw Exception('User not authenticated. Please sign in again.');
      }

      // Additional check: verify session is still valid
      final session = client.auth.currentSession;
      if (session == null) {
        throw Exception('Session expired. Please sign in again.');
      }

      print('Session access token exists: true');
      print('Session expires at: ${session.expiresAt}');

      // Debug: Check user authentication status in database
      print('🔍 DEBUG: Checking user authentication status before save...');
      final authStatus = await debugUserAuthStatus();
      print('🔍 DEBUG: User auth status: $authStatus');
      print('🔍 DEBUG: Auth status check complete');

      // Ensure user profile exists before attempting to save
      print('🔍 DEBUG: Ensuring user profile exists...');
      await _ensureUserProfileExists(userId);
      print('🔍 DEBUG: User profile check complete');

      // Get user's organization
      final userProfile = await client
          .from('profiles')
          .select('organization_id')
          .eq('id', userId)
          .maybeSingle();

      final userOrganizationId = userProfile?['organization_id'];

      // First, save the navigation path (without waypoints)
      final Map<String, dynamic> pathData = {
        'id': navigationPath.id,
        'name': navigationPath.name,
        'start_location_id': navigationPath.startLocationId,
        'end_location_id': navigationPath.endLocationId,
        'estimated_distance': navigationPath.estimatedDistance,
        'estimated_steps': navigationPath.estimatedSteps,
        'user_id': userId,
        'organization_id': userOrganizationId, // Add organization for sharing
        'created_at': navigationPath.createdAt.toIso8601String(),
        'updated_at': navigationPath.updatedAt.toIso8601String(),
      };

      print('Inserting path data: $pathData');

      // Insert the navigation path with explicit error handling
      try {
        await client.from('navigation_paths').insert(pathData);
        print('✅ Navigation path saved with ID: ${navigationPath.id}');
      } catch (insertError) {
        print('❌ Insert error: $insertError');
        if (insertError.toString().contains('violates row-level security policy')) {
          throw Exception('Authentication error: User ID mismatch with database session. Please sign out and sign in again.');
        }
        rethrow;
      }

      // Then, save all waypoints separately
      if (navigationPath.waypoints.isNotEmpty) {
        final List<Map<String, dynamic>> waypointsData =
            navigationPath.waypoints.map((waypoint) {
          // 🐛 DEBUG: Check waypoint people data before saving
          print(
              '🔍 DEBUG saving waypoint ${waypoint.sequenceNumber}: peopleDetected=${waypoint.peopleDetected}, count=${waypoint.peopleCount}');

          return {
            'id': waypoint.id,
            'path_id': navigationPath.id, // Link to the parent path
            'sequence_number': waypoint.sequenceNumber,
            'embedding': waypoint.embedding,
            'heading': waypoint.heading,
            'heading_change': waypoint.headingChange,
            'turn_type': waypoint.turnType.name,
            'is_decision_point': waypoint.isDecisionPoint,
            'landmark_description': waypoint.landmarkDescription,
            'distance_from_previous': waypoint.distanceFromPrevious,
            'timestamp': waypoint.timestamp.toIso8601String(),
            // Add people detection fields for smart navigation thresholds
            'people_detected': waypoint.peopleDetected,
            'people_count': waypoint.peopleCount,
            'people_confidence_scores': waypoint.peopleConfidenceScores,
          };
        }).toList();

        // Insert all waypoints
        await client.from('path_waypoints').insert(waypointsData);
        print(
            '${navigationPath.waypoints.length} waypoints saved for path ${navigationPath.id}');

        // Debug: Show people detection data being saved
        final peopleWaypoints =
            navigationPath.waypoints.where((w) => w.peopleDetected).length;
        print(
            '📊 People detection: ${peopleWaypoints}/${navigationPath.waypoints.length} waypoints had people');
      }

      return navigationPath.id;
    } catch (e) {
      print('Error saving navigation path: $e');
      throw Exception('Failed to save navigation path: ${e.toString()}');
    }
  }

  // Load NavigationPath from database by ID
  Future<NavigationPath?> loadPath(String pathId) async {
    try {
      final userId = currentUser?.id;

      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // First, load the navigation path
      final pathResponse = await client
          .from('navigation_paths')
          .select()
          .eq('id', pathId)
          .eq('user_id', userId)
          .single();

      // Then, load all waypoints for this path
      final waypointsResponse = await client
          .from('path_waypoints')
          .select()
          .eq('path_id', pathId)
          .order('sequence_number');

      // Convert waypoints data to PathWaypoint objects
      final waypoints =
          (waypointsResponse as List<dynamic>).map((waypointData) {
        return PathWaypoint(
          id: waypointData['id'],
          sequenceNumber: waypointData['sequence_number'],
          embedding: List<double>.from(waypointData['embedding'] ?? []),
          heading: waypointData['heading'].toDouble(),
          headingChange: waypointData['heading_change'].toDouble(),
          turnType: TurnType.values.firstWhere(
            (e) => e.name == waypointData['turn_type'],
            orElse: () => TurnType.straight,
          ),
          isDecisionPoint: waypointData['is_decision_point'],
          landmarkDescription: waypointData['landmark_description'],
          distanceFromPrevious:
              waypointData['distance_from_previous']?.toDouble(),
          timestamp: DateTime.parse(waypointData['timestamp']),
        );
      }).toList();

      // Create NavigationPath object
      return NavigationPath(
        id: pathResponse['id'],
        name: pathResponse['name'],
        startLocationId: pathResponse['start_location_id'],
        endLocationId: pathResponse['end_location_id'],
        waypoints: waypoints,
        estimatedDistance: pathResponse['estimated_distance'].toDouble(),
        estimatedSteps: pathResponse['estimated_steps'],
        createdAt: DateTime.parse(pathResponse['created_at']),
        updatedAt: DateTime.parse(pathResponse['updated_at']),
      );
    } catch (e) {
      print('Error loading navigation path: $e');
      return null;
    }
  }

  // Load all navigation paths for the current user
  Future<List<NavigationPath>> loadAllPaths() async {
    try {
      final userId = currentUser?.id;
      print('=== loadAllPaths() called ===');
      print('Current user ID: $userId');

      if (userId == null) {
        print('❌ User not authenticated');
        throw Exception('User not authenticated');
      }

      // Get user's organization and admin status
      final userProfile = await client
          .from('profiles')
          .select('organization_id')
          .eq('id', userId)
          .maybeSingle();

      final userOrganizationId = userProfile?['organization_id'];
      final isAdminUser = await isAdmin();

      print('User organization ID: $userOrganizationId');
      print('User is admin: $isAdminUser');

      if (userOrganizationId == null && !isAdminUser) {
        print('⚠️ WARNING: User has no organization assigned and is not admin!');
        print('⚠️ This means they can only see paths they created themselves');
      }

      // Load navigation paths based on user role and organization
      print('Querying navigation_paths table...');

      final pathsResponse;
      if (isAdminUser) {
        // Admin users can see ALL paths from their organization (including other admins' paths)
        if (userOrganizationId != null) {
          pathsResponse = await client
              .from('navigation_paths')
              .select()
              .eq('organization_id', userOrganizationId)
              .order('created_at', ascending: false);
          print('🔓 Admin user - filtering by organization: $userOrganizationId');
        } else {
          // Admin with no organization can only see their own paths
          pathsResponse = await client
              .from('navigation_paths')
              .select()
              .eq('user_id', userId)
              .order('created_at', ascending: false);
          print('🔓 Admin user (no organization) - filtering by user: $userId');
        }
      } else {
        // Regular users can see paths from their organization
        if (userOrganizationId != null) {
          pathsResponse = await client
              .from('navigation_paths')
              .select()
              .eq('organization_id', userOrganizationId)
              .order('created_at', ascending: false);
          print('🔒 Regular user - filtering by organization: $userOrganizationId');
        } else {
          // Users without organization can only see their own paths
          pathsResponse = await client
              .from('navigation_paths')
              .select()
              .eq('user_id', userId)
              .order('created_at', ascending: false);
          print('🔒 Regular user (no organization) - filtering by user: $userId');
        }
      }

      print('Raw paths response: $pathsResponse');
      print('Number of paths found: ${pathsResponse.length}');

      // Debug: Check each path's details
      for (var i = 0; i < pathsResponse.length; i++) {
        final path = pathsResponse[i];
        print('Path ${i + 1}: ${path['name']}');
        print('  ID: ${path['id']}');
        print('  Start: ${path['start_location_id']}');
        print('  End: ${path['end_location_id']}');
        print('  Organization: ${path['organization_id']}');
        print('  User: ${path['user_id']}');
      }

      final List<NavigationPath> paths = [];

      for (final pathData in pathsResponse) {
        final pathId = pathData['id'];
        print('Processing path: ${pathData['name']} (ID: $pathId)');
        print('  Start location: ${pathData['start_location_id']}');
        print('  End location: ${pathData['end_location_id']}');

        // Load waypoints for this path
        final waypointsResponse = await client
            .from('path_waypoints')
            .select()
            .eq('path_id', pathId)
            .order('sequence_number');

        print('  Found ${(waypointsResponse as List).length} waypoints');

        // Debug: Print raw waypoint data to see exact structure
        if ((waypointsResponse as List).isNotEmpty) {
          final firstWaypoint = (waypointsResponse as List)[0];
          print('  DEBUG - First waypoint raw data:');
          print(
              '    ID: ${firstWaypoint['id']} (type: ${firstWaypoint['id'].runtimeType})');
          print(
              '    Embedding: ${firstWaypoint['embedding']} (type: ${firstWaypoint['embedding'].runtimeType})');
          print(
              '    Heading: ${firstWaypoint['heading']} (type: ${firstWaypoint['heading'].runtimeType})');
        }

        // Convert waypoints data to PathWaypoint objects
        final waypoints =
            (waypointsResponse as List<dynamic>).map((waypointData) {
          // Handle embedding data - could be String, List, or null
          List<double> embedding = [];
          final embeddingData = waypointData['embedding'];
          if (embeddingData != null) {
            if (embeddingData is String) {
              // If it's a string representation, try to parse it
              try {
                // Remove brackets and split by comma
                final cleanString =
                    embeddingData.replaceAll('[', '').replaceAll(']', '');
                if (cleanString.isNotEmpty) {
                  embedding = cleanString
                      .split(',')
                      .map((e) => double.parse(e.trim()))
                      .toList();
                }
              } catch (e) {
                print('Warning: Could not parse embedding string: $e');
              }
            } else if (embeddingData is List) {
              // If it's already a list, convert to double list
              embedding = List<double>.from(embeddingData);
            }
          }

          return PathWaypoint(
            id: waypointData['id'],
            sequenceNumber: waypointData['sequence_number'],
            embedding: embedding,
            heading: waypointData['heading'].toDouble(),
            headingChange: waypointData['heading_change'].toDouble(),
            turnType: TurnType.values.firstWhere(
              (e) => e.name == waypointData['turn_type'],
              orElse: () => TurnType.straight,
            ),
            isDecisionPoint: waypointData['is_decision_point'],
            landmarkDescription: waypointData['landmark_description'],
            distanceFromPrevious:
                waypointData['distance_from_previous']?.toDouble(),
            timestamp: DateTime.parse(waypointData['timestamp']),
            // Load people detection fields for smart navigation thresholds
            peopleDetected: waypointData['people_detected'] ?? false,
            peopleCount: waypointData['people_count'] ?? 0,
            peopleConfidenceScores: waypointData['people_confidence_scores'] !=
                    null
                ? List<double>.from(waypointData['people_confidence_scores'])
                : [],
          );
        }).toList();

        // Create NavigationPath object
        final navigationPath = NavigationPath(
          id: pathData['id'],
          name: pathData['name'],
          startLocationId: pathData['start_location_id'],
          endLocationId: pathData['end_location_id'],
          waypoints: waypoints,
          estimatedDistance: pathData['estimated_distance'].toDouble(),
          estimatedSteps: pathData['estimated_steps'],
          createdAt: DateTime.parse(pathData['created_at']),
          updatedAt: DateTime.parse(pathData['updated_at']),
        );

        print('  Created NavigationPath: ${navigationPath.name}');
        paths.add(navigationPath);
      }

      print('Total NavigationPath objects created: ${paths.length}');
      return paths;
    } catch (e) {
      print('Error loading navigation paths: $e');
      return [];
    }
  }

  Future<String> saveRecordedPath(Map<String, dynamic> pathData) async {
    try {
      final String pathId = uuid.v4();
      final userId = currentUser?.id;

      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Get user's organization
      final userProfile = await client
          .from('profiles')
          .select('organization_id')
          .eq('id', userId)
          .maybeSingle();

      final userOrganizationId = userProfile?['organization_id'];

      // Prepare the path data with additional fields
      final Map<String, dynamic> completePathData = {
        'id': pathId,
        'user_id': userId,
        'organization_id': userOrganizationId, // Add organization for sharing
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

  // ===================================================================
  // ORGANIZATION MANAGEMENT METHODS
  // ===================================================================

  // Get all organizations
  Future<List<Map<String, dynamic>>> getAllOrganizations() async {
    try {
      // Verify admin permissions
      final isAdmin = await this.isAdmin();
      if (!isAdmin) {
        throw Exception('Admin privileges required');
      }

      final user = currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // 🔒 SECURITY: Only return organizations the current admin can access
      // Admins can see organizations they created
      final response = await client
          .from('organizations')
          .select('*')
          .eq('created_by_admin_id', user.id)
          .order('name');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching organizations: $e');
      throw Exception('Failed to fetch organizations: ${e.toString()}');
    }
  }

  // Get all users with their organization info (Admin-scoped)
  Future<List<Map<String, dynamic>>> getAllUsersWithOrganizations() async {
    try {
      // Verify admin permissions
      final isAdmin = await this.isAdmin();
      if (!isAdmin) {
        throw Exception('Admin privileges required');
      }

      final user = currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // 🔒 SECURITY: Only get organizations this admin can access
      final orgsResponse = await client
          .from('organizations')
          .select('id, name, description')
          .eq('created_by_admin_id', user.id);

      final orgsList = List<Map<String, dynamic>>.from(orgsResponse);
      final accessibleOrgIds = orgsList.map((org) => org['id'] as String).toSet();

      // Get users that either:
      // 1. Belong to organizations this admin can access, OR
      // 2. Have no organization assigned
      final usersResponse = await client
          .from('profiles')
          .select('id, email, role, organization_id, created_at')
          .or('organization_id.is.null,or(organization_id.in.(${accessibleOrgIds.join(",")}))')
          .order('created_at', ascending: false);

      // Convert responses to properly typed lists
      final usersList = List<Map<String, dynamic>>.from(usersResponse);

      // Create a map of organizations for quick lookup
      final organizations = Map<String, Map<String, dynamic>>.fromIterable(
        orgsList,
        key: (org) => org['id'] as String,
        value: (org) => org as Map<String, dynamic>,
      );

      // Combine users with their organization info
      final usersWithOrgs = usersList.map((user) {
        final orgId = user['organization_id'];
        final organization = orgId != null ? organizations[orgId] : null;

        return {
          ...user,
          'organizations': organization,
        };
      }).toList();

      return usersWithOrgs;
    } catch (e) {
      print('Error fetching users with organizations: $e');
      throw Exception('Failed to fetch users: ${e.toString()}');
    }
  }

  // Assign user to organization
  Future<void> assignUserToOrganization(String userEmail, String organizationId) async {
    try {
      // Verify admin permissions
      final isAdmin = await this.isAdmin();
      if (!isAdmin) {
        throw Exception('Admin privileges required');
      }

      final user = currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // 🔒 SECURITY CHECK: Verify the current admin has access to this organization
      final orgResponse = await client
          .from('organizations')
          .select('created_by_admin_id, name')
          .eq('id', organizationId)
          .maybeSingle();

      if (orgResponse == null) {
        throw Exception('Organization not found');
      }

      if (orgResponse['created_by_admin_id'] != user.id) {
        throw Exception('You do not have permission to assign users to this organization');
      }

      // First, get the user ID from email
      final userResponse = await client
          .from('profiles')
          .select('id, organization_id')
          .eq('email', userEmail)
          .maybeSingle();

      if (userResponse == null) {
        throw Exception('User with email "$userEmail" not found. Please check the email address and try again.');
      }

      final userId = userResponse['id'];
      final currentOrgId = userResponse['organization_id'];

      // Check if user is already in another organization
      if (currentOrgId != null && currentOrgId != organizationId) {
        // Get the current organization name for better error message
        final currentOrgResponse = await client
            .from('organizations')
            .select('name')
            .eq('id', currentOrgId)
            .maybeSingle();

        final currentOrgName = currentOrgResponse?['name'] ?? 'another organization';
        throw Exception('User is already assigned to "$currentOrgName". Please remove them from their current organization first.');
      }

      // If user is already in the target organization, no need to do anything
      if (currentOrgId == organizationId) {
        print('User $userEmail is already in organization $organizationId');
        return;
      }

      // Update user's organization
      final response = await client
          .from('profiles')
          .update({'organization_id': organizationId})
          .eq('email', userEmail)
          .select('id')
          .maybeSingle();

      if (response == null) {
        throw Exception('User not found or update failed');
      }

      // 🔧 CRITICAL: Update all existing content for this user
      print('🔧 Updating existing content for user $userEmail with organization $organizationId...');

      // Update place_embeddings
      await client.rpc('exec_sql', params: {
        'sql': '''
          UPDATE place_embeddings
          SET organization_id = '$organizationId'
          WHERE user_id = '$userId'
          AND organization_id IS NULL;
        '''
      });
      print('✅ Updated place_embeddings for user $userId');

      // Update navigation_paths
      await client.rpc('exec_sql', params: {
        'sql': '''
          UPDATE navigation_paths
          SET organization_id = '$organizationId'
          WHERE user_id = '$userId'
          AND organization_id IS NULL;
        '''
      });
      print('✅ Updated navigation_paths for user $userId');

      // NOTE: path_waypoints table doesn't have organization_id column
      // Security is handled through navigation_paths foreign key relationship
      print('📍 Skipping path_waypoints update (no organization_id column)');

      // Update map_nodes
      await client.rpc('exec_sql', params: {
        'sql': '''
          UPDATE map_nodes
          SET organization_id = '$organizationId'
          WHERE user_id = '$userId'
          AND organization_id IS NULL;
        '''
      });
      print('✅ Updated map_nodes for user $userId');

      // Update recorded_paths
      await client.rpc('exec_sql', params: {
        'sql': '''
          UPDATE recorded_paths
          SET organization_id = '$organizationId'
          WHERE user_id = '$userId'
          AND organization_id IS NULL;
        '''
      });
      print('✅ Updated recorded_paths for user $userId');

      print('🎉 Successfully assigned user $userEmail to organization $organizationId and updated all existing content!');
    } catch (e) {
      print('Error assigning user to organization: $e');
      throw Exception('Failed to assign user: ${e.toString()}');
    }
  }

  // Remove user from organization and clear all their content organization_id
  Future<void> removeUserFromOrganization(String userEmail) async {
    try {
      // Verify admin permissions
      final isAdmin = await this.isAdmin();
      if (!isAdmin) {
        throw Exception('Admin privileges required');
      }

      final user = currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // First, get the user and their current organization
      final userResponse = await client
          .from('profiles')
          .select('id, organization_id, email')
          .eq('email', userEmail)
          .maybeSingle();

      if (userResponse == null) {
        throw Exception('User with email "$userEmail" not found. Please check the email address and try again.');
      }

      final userId = userResponse['id'];
      final userOrgId = userResponse['organization_id'];

      // If user is not in any organization, no need to do anything
      if (userOrgId == null) {
        print('User $userEmail is not in any organization');
        return;
      }

      // If user is in an organization, verify admin has access to it
      if (userOrgId != null) {
        final orgResponse = await client
            .from('organizations')
            .select('created_by_admin_id, name')
            .eq('id', userOrgId)
            .maybeSingle();

        if (orgResponse == null) {
          throw Exception('User\'s organization not found');
        }

        if (orgResponse['created_by_admin_id'] != user.id) {
          throw Exception('You do not have permission to manage users in this organization');
        }
      }

      print('🔄 Removing user $userEmail from organization and clearing content...');

      // Clear organization_id from all user's content
      // Update place_embeddings
      await client.rpc('exec_sql', params: {
        'sql': '''
          UPDATE place_embeddings
          SET organization_id = NULL
          WHERE user_id = '$userId';
        '''
      });
      print('✅ Cleared organization_id from place_embeddings for user $userId');

      // Update navigation_paths
      await client.rpc('exec_sql', params: {
        'sql': '''
          UPDATE navigation_paths
          SET organization_id = NULL
          WHERE user_id = '$userId';
        '''
      });
      print('✅ Cleared organization_id from navigation_paths for user $userId');

      // Update map_nodes
      await client.rpc('exec_sql', params: {
        'sql': '''
          UPDATE map_nodes
          SET organization_id = NULL
          WHERE user_id = '$userId';
        '''
      });
      print('✅ Cleared organization_id from map_nodes for user $userId');

      // Update recorded_paths
      await client.rpc('exec_sql', params: {
        'sql': '''
          UPDATE recorded_paths
          SET organization_id = NULL
          WHERE user_id = '$userId';
        '''
      });
      print('✅ Cleared organization_id from recorded_paths for user $userId');

      // Finally, remove organization assignment from user profile
      final response = await client
          .from('profiles')
          .update({'organization_id': null})
          .eq('email', userEmail)
          .select('id')
          .maybeSingle();

      if (response == null) {
        throw Exception('User not found or update failed');
      }

      print('🎉 Successfully removed user $userEmail from organization and cleared all content organization_id');
    } catch (e) {
      print('Error removing user from organization: $e');
      throw Exception('Failed to remove user: ${e.toString()}');
    }
  }

  // Delete entire organization and remove all users/content from it
  Future<void> deleteOrganization(String organizationId) async {
    try {
      // Verify admin permissions
      final isAdmin = await this.isAdmin();
      if (!isAdmin) {
        throw Exception('Admin privileges required');
      }

      final user = currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // 🔒 SECURITY CHECK: Verify the current admin created this organization
      final orgResponse = await client
          .from('organizations')
          .select('created_by_admin_id, name')
          .eq('id', organizationId)
          .maybeSingle();

      if (orgResponse == null) {
        throw Exception('Organization not found');
      }

      final createdByAdminId = orgResponse['created_by_admin_id'];
      final orgName = orgResponse['name'];

      // Only allow deletion if the current admin created this organization
      if (createdByAdminId != user.id) {
        throw Exception('Access denied: You can only delete organizations you created. This organization was created by another admin.');
      }

      print('🗑️ Deleting organization "$orgName" ($organizationId) and cleaning up all associated data...');

      // First, get all users in this organization
      final usersResponse = await client
          .from('profiles')
          .select('id, email')
          .eq('organization_id', organizationId);

      final users = List<Map<String, dynamic>>.from(usersResponse);

      // Remove organization_id from all content for each user
      for (final user in users) {
        final userId = user['id'];
        final userEmail = user['email'];

        print('🔄 Cleaning up content for user $userEmail...');

        // Clear organization_id from all user's content
        await client.rpc('exec_sql', params: {
          'sql': '''
            UPDATE place_embeddings
            SET organization_id = NULL
            WHERE user_id = '$userId';
          '''
        });

        await client.rpc('exec_sql', params: {
          'sql': '''
            UPDATE navigation_paths
            SET organization_id = NULL
            WHERE user_id = '$userId';
          '''
        });

        await client.rpc('exec_sql', params: {
          'sql': '''
            UPDATE map_nodes
            SET organization_id = NULL
            WHERE user_id = '$userId';
          '''
        });

        await client.rpc('exec_sql', params: {
          'sql': '''
            UPDATE recorded_paths
            SET organization_id = NULL
            WHERE user_id = '$userId';
          '''
        });
      }

      // Clear organization_id from all user profiles
      await client.rpc('exec_sql', params: {
        'sql': '''
          UPDATE profiles
          SET organization_id = NULL
          WHERE organization_id = '$organizationId';
        '''
      });
      print('✅ Cleared organization_id from all user profiles');

      // Finally, delete the organization
      final deleteResponse = await client
          .from('organizations')
          .delete()
          .eq('id', organizationId)
          .select('id')
          .maybeSingle();

      if (deleteResponse == null) {
        throw Exception('Organization not found or delete failed');
      }

      print('🎉 Successfully deleted organization $organizationId and cleaned up all associated data');
    } catch (e) {
      print('Error deleting organization: $e');
      throw Exception('Failed to delete organization: ${e.toString()}');
    }
  }

  // Get current user's organization
  Future<Map<String, dynamic>?> getCurrentUserOrganization() async {
    final user = currentUser;
    if (user == null) return null;

    try {
      final response = await client
          .from('profiles')
          .select('''
            organization_id,
            organizations (
              id,
              name,
              description
            )
          ''')
          .eq('id', user.id)
          .single();

      if (response['organizations'] != null) {
        return response['organizations'];
      }

      return null;
    } catch (e) {
      print('Error fetching user organization: $e');
      return null;
    }
  }

  // Create new organization
  Future<Map<String, dynamic>> createOrganization(String name, String description) async {
    try {
      // Verify admin permissions
      final isAdmin = await this.isAdmin();
      if (!isAdmin) {
        throw Exception('Admin privileges required');
      }

      final user = currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final response = await client
          .from('organizations')
          .insert({
            'name': name,
            'description': description,
            'created_by_admin_id': user.id,
          })
          .select()
          .single();

      print('Successfully created organization: $name');
      return response;
    } catch (e) {
      print('Error creating organization: $e');
      throw Exception('Failed to create organization: ${e.toString()}');
    }
  }

  // Get users by organization
  Future<List<Map<String, dynamic>>> getUsersByOrganization(String organizationId) async {
    try {
      // Verify admin permissions
      final isAdmin = await this.isAdmin();
      if (!isAdmin) {
        throw Exception('Admin privileges required');
      }

      final user = currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // 🔒 SECURITY CHECK: Verify the current admin has access to this organization
      final orgResponse = await client
          .from('organizations')
          .select('created_by_admin_id, name')
          .eq('id', organizationId)
          .maybeSingle();

      if (orgResponse == null) {
        throw Exception('Organization not found');
      }

      if (orgResponse['created_by_admin_id'] != user.id) {
        throw Exception('You do not have permission to view users in this organization');
      }

      // Get all users in this organization
      final usersResponse = await client
          .from('profiles')
          .select('id, email, role, created_at')
          .eq('organization_id', organizationId)
          .order('email', ascending: true);

      return List<Map<String, dynamic>>.from(usersResponse);
    } catch (e) {
      print('Error fetching users by organization: $e');
      throw Exception('Failed to fetch users: ${e.toString()}');
    }
  }
}
