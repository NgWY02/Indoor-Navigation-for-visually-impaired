import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

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
      
      if (response != null && response.containsKey('role')) {
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

  // Save embedding to Supabase
  Future<String?> saveEmbedding(String placeName, List<double> embedding) async {
    try {
      final id = uuid.v4();
      final userId = currentUser?.id;
      
      if (userId == null) {
        throw Exception('User not authenticated');
      }
      
      await client.from('place_embeddings').insert({
        'id': id,
        'place_name': placeName,
        'embedding': jsonEncode(embedding),
        'created_at': DateTime.now().toIso8601String(),
        'user_id': userId, // Associate with current user
      });
      
      return id;
    } catch (e) {
      print('Error saving embedding: $e');
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