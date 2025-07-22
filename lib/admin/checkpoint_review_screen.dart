import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/path_models.dart';
import 'services/path_recording_service.dart';
import '../services/supabase_service.dart';

class CheckpointReviewScreen extends StatefulWidget {
  final String mapId;
  final String startNodeId;
  final String endNodeId;
  final String startNodeName;
  final String endNodeName;

  const CheckpointReviewScreen({
    Key? key,
    required this.mapId,
    required this.startNodeId,
    required this.endNodeId,
    required this.startNodeName,
    required this.endNodeName,
  }) : super(key: key);

  @override
  _CheckpointReviewScreenState createState() => _CheckpointReviewScreenState();
}

class _CheckpointReviewScreenState extends State<CheckpointReviewScreen> {
  final PathRecordingService _recordingService = PathRecordingService();
  final SupabaseService _supabaseService = SupabaseService();
  
  List<Landmark> _suggestedCheckpoints = [];
  bool _isSaving = false;
  
  // Form controllers for final path details
  final TextEditingController _pathNameController = TextEditingController();
  final TextEditingController _pathDescriptionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSuggestedCheckpoints();
    _initializePathName();
  }

  @override
  void dispose() {
    _pathNameController.dispose();
    _pathDescriptionController.dispose();
    super.dispose();
  }

  void _loadSuggestedCheckpoints() {
    setState(() {
      _suggestedCheckpoints = _recordingService.getSuggestedCheckpoints();
    });
  }

  void _initializePathName() {
    _pathNameController.text = 'Path from ${widget.startNodeName} to ${widget.endNodeName}';
    _pathDescriptionController.text = 'Recorded navigation path with ${_recordingService.currentSession?.segments.length ?? 0} checkpoints';
  }

  void _toggleCheckpointSelection(int index) {
    setState(() {
      _suggestedCheckpoints[index] = _suggestedCheckpoints[index].copyWith(
        isSelected: !_suggestedCheckpoints[index].isSelected,
      );
    });

    // Haptic feedback
    HapticFeedback.selectionClick();
  }

  void _selectAllCheckpoints() {
    setState(() {
      _suggestedCheckpoints = _suggestedCheckpoints
          .map((checkpoint) => checkpoint.copyWith(isSelected: true))
          .toList();
    });
  }

  void _deselectAllCheckpoints() {
    setState(() {
      _suggestedCheckpoints = _suggestedCheckpoints
          .map((checkpoint) => checkpoint.copyWith(isSelected: false))
          .toList();
    });
  }

  void _removeCheckpoint(int index) {
    setState(() {
      _suggestedCheckpoints.removeAt(index);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Checkpoint removed'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            // Simple undo - reload from service
            _loadSuggestedCheckpoints();
          },
        ),
      ),
    );
  }

  Future<void> _savePathWithReview() async {
    if (_pathNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please enter a path name'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      // Get selected checkpoints
      final selectedCheckpoints = _suggestedCheckpoints
          .where((checkpoint) => checkpoint.isSelected)
          .toList();

      // Create the recorded path
      final recordedPath = _recordingService.createRecordedPath(
        name: _pathNameController.text.trim(),
        description: _pathDescriptionController.text.trim(),
        selectedSuggestions: selectedCheckpoints,
      );

      // Save to database
      await _saveToDatabase(recordedPath);

      // Clear the recording session
      _recordingService.cancelRecording();

      // Show success and navigate back
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Path saved successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      // Navigate back to map management (pop multiple screens)
      Navigator.of(context).popUntil((route) => route.isFirst);

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving path: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<void> _saveToDatabase(RecordedPath recordedPath) async {
    // Create the path record in database
    final pathData = {
      'map_id': widget.mapId,
      'start_node_id': widget.startNodeId,
      'end_node_id': widget.endNodeId,
      'name': recordedPath.name,
      'description': recordedPath.description,
      'total_distance': recordedPath.totalDistance,
      'total_steps': recordedPath.totalSteps,
      'segments': recordedPath.segments.map((s) => s.toJson()).toList(),
      'suggested_checkpoints': recordedPath.suggestedCheckpoints.map((c) => c.toJson()).toList(),
      'created_at': recordedPath.createdAt.toIso8601String(),
    };

    // Save to Supabase (you might need to add this method to SupabaseService)
    await _supabaseService.saveRecordedPath(pathData);
  }

  void _discardPath() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Discard Path'),
        content: Text('Are you sure you want to discard this recorded path? All data will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              _recordingService.cancelRecording();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Discard'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = _recordingService.currentSession;
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Review Path'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            onPressed: _discardPath,
            icon: Icon(Icons.delete),
            tooltip: 'Discard Path',
          ),
        ],
      ),
      body: _isSaving
          ? _buildSavingView()
          : SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPathSummary(session),
                  SizedBox(height: 24),
                  _buildPathDetailsForm(),
                  SizedBox(height: 24),
                  _buildSuggestedCheckpointsSection(),
                  SizedBox(height: 32),
                  _buildSaveButton(),
                ],
              ),
            ),
    );
  }

  Widget _buildSavingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 20),
          Text(
            'Saving path...',
            style: TextStyle(fontSize: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildPathSummary(RecordingSession? session) {
    if (session == null) return Container();

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Path Summary',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryItem(
                    icon: Icons.route,
                    label: 'Checkpoints',
                    value: '${session.segments.length}',
                  ),
                ),
                Expanded(
                  child: _buildSummaryItem(
                    icon: Icons.directions_walk,
                    label: 'Steps',
                    value: '${session.relativeStepCount}',
                  ),
                ),
                Expanded(
                  child: _buildSummaryItem(
                    icon: Icons.straighten,
                    label: 'Distance',
                    value: _recordingService.formatDistance(session.currentDistance),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            Text(
              'From: ${widget.startNodeName}',
              style: TextStyle(color: Colors.grey[600]),
            ),
            Text(
              'To: ${widget.endNodeName}',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, size: 32, color: Colors.blue),
        SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildPathDetailsForm() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Path Details',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 16),
            TextField(
              controller: _pathNameController,
              decoration: InputDecoration(
                labelText: 'Path Name',
                border: OutlineInputBorder(),
                hintText: 'Enter a descriptive name for this path',
              ),
            ),
            SizedBox(height: 16),
            TextField(
              controller: _pathDescriptionController,
              decoration: InputDecoration(
                labelText: 'Description (Optional)',
                border: OutlineInputBorder(),
                hintText: 'Add notes about this path',
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestedCheckpointsSection() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Suggested Checkpoints',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: _selectAllCheckpoints,
                      child: Text('Select All'),
                    ),
                    TextButton(
                      onPressed: _deselectAllCheckpoints,
                      child: Text('Deselect All'),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: 8),
            Text(
              'Review objects detected during recording. Keep useful landmarks for navigation.',
              style: TextStyle(color: Colors.grey[600]),
            ),
            SizedBox(height: 16),
            if (_suggestedCheckpoints.isEmpty)
              _buildEmptyCheckpoints()
            else
              ..._suggestedCheckpoints.asMap().entries.map((entry) {
                final index = entry.key;
                final checkpoint = entry.value;
                return _buildCheckpointCard(checkpoint, index);
              }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyCheckpoints() {
    return Container(
      padding: EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(
            Icons.visibility_off,
            size: 64,
            color: Colors.grey[400],
          ),
          SizedBox(height: 16),
          Text(
            'No Objects Detected',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: 8),
          Text(
            'YOLO didn\'t detect any high-confidence objects during recording. The path will be saved with manual checkpoints only.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckpointCard(Landmark checkpoint, int index) {
    return Card(
      margin: EdgeInsets.only(bottom: 12),
      elevation: checkpoint.isSelected ? 4 : 1,
      color: checkpoint.isSelected ? Colors.blue[50] : null,
      child: ListTile(
        leading: Checkbox(
          value: checkpoint.isSelected,
          onChanged: (_) => _toggleCheckpointSelection(index),
          activeColor: Colors.blue,
        ),
        title: Text(
          checkpoint.label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: checkpoint.isSelected ? Colors.blue[800] : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Confidence: ${(checkpoint.confidence * 100).toStringAsFixed(1)}%'),
            Text('At step ${checkpoint.stepCount} (${_recordingService.formatDistance(checkpoint.distance)})'),
            Text('Type: ${checkpoint.type == LandmarkType.yolo ? 'YOLO Detection' : 'Custom'}'),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              checkpoint.type == LandmarkType.yolo ? Icons.smart_toy : Icons.edit,
              color: checkpoint.type == LandmarkType.yolo ? Colors.green : Colors.orange,
            ),
            SizedBox(width: 8),
            IconButton(
              onPressed: () => _removeCheckpoint(index),
              icon: Icon(Icons.delete, color: Colors.red),
              tooltip: 'Remove checkpoint',
            ),
          ],
        ),
        onTap: () => _toggleCheckpointSelection(index),
      ),
    );
  }

  Widget _buildSaveButton() {
    final selectedCount = _suggestedCheckpoints.where((c) => c.isSelected).length;
    
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isSaving ? null : _savePathWithReview,
        icon: Icon(Icons.save),
        label: Text(
          'Save Path${selectedCount > 0 ? ' with $selectedCount suggestions' : ''}',
          style: TextStyle(fontSize: 16),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
} 