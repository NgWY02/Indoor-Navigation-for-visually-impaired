/// Demo/Test file showing how SmolVLM works
/// This demonstrates the difference between real VLM comparison vs fake embeddings

import 'dart:typed_data';
import 'smolvlm_service.dart';

class SmolVLMDemo {
  final SmolVLMService _service;
  
  SmolVLMDemo(String serverUrl) : _service = SmolVLMService(baseUrl: serverUrl);
  
  /// Example workflow: Admin creates a location
  Future<void> demoLocationCreation(Uint8List imageBytes) async {
    print("=== ADMIN: Creating Location ===");
    
    // Method 1: Get direct text description (RECOMMENDED)
    try {
      final description = await _service.generateDescription(imageBytes);
      print("✅ SmolVLM Description: $description");
      
      // This description gets stored in database for comparison
      print("💾 Storing description in database...");
      
    } catch (e) {
      print("❌ Error: $e");
    }
    
    // Method 2: Legacy embedding method (for compatibility)
    try {
      final fakeEmbedding = await _service.generateEmbedding(imageBytes);
      print("⚠️  Fake embedding (${fakeEmbedding.length} dimensions): ${fakeEmbedding.take(5).toList()}...");
      print("   Note: This is NOT a real neural embedding, just a hash of the text description!");
      
    } catch (e) {
      print("❌ Embedding error: $e");
    }
  }
  
  /// Example workflow: User navigation recognition
  Future<void> demoLocationRecognition(Uint8List liveImageBytes, String storedDescription) async {
    print("\n=== USER: Navigation Recognition ===");
    
    // Method 1: Direct VLM comparison (RECOMMENDED)
    try {
      final similarity = await _service.compareImageWithDescription(liveImageBytes, storedDescription);
      print("✅ SmolVLM Similarity Score: $similarity");
      
      if (similarity > 0.7) {
        print("🎯 LOCATION IDENTIFIED! (${(similarity * 100).toStringAsFixed(1)}% match)");
      } else if (similarity > 0.4) {
        print("🤔 Possible match (${(similarity * 100).toStringAsFixed(1)}% similarity)");
      } else {
        print("❌ No match (${(similarity * 100).toStringAsFixed(1)}% similarity)");
      }
      
    } catch (e) {
      print("❌ Comparison error: $e");
    }
  }
  
  /// Show the difference between approaches
  void explainApproaches() {
    print("\n=== COMPARISON OF APPROACHES ===");
    print("📊 Traditional Computer Vision:");
    print("   • Extract feature vectors (embeddings) from images");
    print("   • Compare vectors using cosine similarity");
    print("   • Works well for objects, but struggles with complex scenes");
    print("");
    print("🧠 SmolVLM Vision-Language Model:");
    print("   • Understands images like humans do");
    print("   • Generates rich text descriptions");
    print("   • Compares images semantically, not just visually");
    print("   • Better for indoor navigation with furniture, signs, layout");
    print("");
    print("⚡ Your Implementation:");
    print("   • Uses SmolVLM for location understanding");
    print("   • Stores text descriptions (not real embeddings)");
    print("   • Direct image-to-description comparison");
    print("   • Fake embeddings only for database compatibility");
  }
}

/// Usage example
void main() async {
  final demo = SmolVLMDemo('http://localhost:8080');
  
  // Demo explanation
  demo.explainApproaches();
  
  // Would normally load real image bytes here
  // final imageBytes = await loadImageFromCamera();
  // await demo.demoLocationCreation(imageBytes);
  // await demo.demoLocationRecognition(imageBytes, "A library room with wooden tables...");
}
