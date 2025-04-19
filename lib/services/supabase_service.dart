import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

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

  // Save embedding to Supabase
  Future<String?> saveEmbedding(String placeName, List<double> embedding) async {
    try {
      final id = uuid.v4();
      
      await client.from('place_embeddings').insert({
        'id': id,
        'place_name': placeName,
        'embedding': jsonEncode(embedding),
        'created_at': DateTime.now().toIso8601String(),
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
      final response = await client
        .from('place_embeddings')
        .select('place_name, embedding');
      
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