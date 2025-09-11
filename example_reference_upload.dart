// Example: How to upload reference images for VLM verification
// Run this once to set up your reference images

import 'dart:io';
import 'lib/services/reference_image_helper.dart';

Future<void> setupReferenceImages() async {
  print('📸 Setting up reference images for VLM verification...');
  
  // Method 1: Upload individual reference images
  await ReferenceImageHelper.uploadReferenceImage(
    placeName: "University Main Entrance", 
    imageFile: File('path/to/entrance_photo.jpg'),
  );
  
  await ReferenceImageHelper.uploadReferenceImage(
    placeName: "Library Ground Floor",
    imageFile: File('path/to/library_photo.jpg'), 
  );
  
  // Method 2: Batch upload (more efficient)
  await ReferenceImageHelper.uploadBatchReferenceImages({
    "Cafeteria": File('path/to/cafeteria.jpg'),
    "Computer Lab": File('path/to/lab.jpg'),
    "Lecture Hall A": File('path/to/hall_a.jpg'),
    "Student Lounge": File('path/to/lounge.jpg'),
  });
  
  print('✅ Reference images setup complete!');
  
  // Verify what was uploaded
  final availableImages = await ReferenceImageHelper.listReferenceImages();
  print('📋 Available reference images: $availableImages');
}

// Call this function once to set up your reference images
// Then you can use the enhanced localization system!
