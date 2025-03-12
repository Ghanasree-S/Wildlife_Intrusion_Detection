// main.dart (Flutter Frontend without IDMC Integration)
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:location/location.dart';
import 'package:charts_flutter/flutter.dart' as charts;
import 'package:intl/intl.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wildlife Detection App',
      theme: ThemeData(
        primarySwatch: Colors.green,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.green.shade800,
        ),
      ),
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();
  File? _videoFile;
  String? _processedVideoPath;
  VideoPlayerController? _controller;
  bool _isProcessing = false;
  Map<String, dynamic>? _statistics;
  Map<String, dynamic>? _analyticsData;
  late TabController _tabController;
  String? _cameraId;
  LocationData? _locationData;
  List<Map<String, dynamic>>? _historicalData;
  bool _isLoadingHistory = false;
  String _period = 'month';
  String _metric = 'detections';

  // Server URL
  final String serverUrl = 'http://192.168.1.6:3000'; // Use this for Android emulator
  // Use 'http://localhost:3000' for iOS simulator or 'http://YOUR_COMPUTER_IP:3000' for physical devices

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _getDeviceLocation();
    _getCameraId();
  }

  Future<void> _getDeviceLocation() async {
    final location = Location();
    bool serviceEnabled;
    PermissionStatus permissionGranted;

    serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
      if (!serviceEnabled) {
        return;
      }
    }

    permissionGranted = await location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) {
        return;
      }
    }

    try {
      _locationData = await location.getLocation();
    } catch (e) {
      print('Error getting location: $e');
    }
  }

  void _getCameraId() {
    // Generate a simple camera ID based on device ID or any unique identifier
    setState(() {
      cameraId = 'CAM${DateTime.now().millisecondsSinceEpoch % 10000}';
    });
  }

  Future<void> _pickVideo() async {
    final XFile? pickedVideo = await _picker.pickVideo(source: ImageSource.gallery);
    if (pickedVideo != null) {
      setState(() {
        _videoFile = File(pickedVideo.path);
        _processedVideoPath = null;
        _statistics = null;

        // Initialize video player for the selected video
        _controller = VideoPlayerController.file(_videoFile!)
          ..initialize().then((_) {
            setState(() {});
          });
      });
    }
  }

  Future<void> _captureVideo() async {
    final XFile? capturedVideo = await _picker.pickVideo(source: ImageSource.camera);
    if (capturedVideo != null) {
      setState(() {
        _videoFile = File(capturedVideo.path);
        _processedVideoPath = null;
        _statistics = null;

        // Initialize video player for the selected video
        _controller = VideoPlayerController.file(_videoFile!)
          ..initialize().then((_) {
            setState(() {});
          });
      });
    }
  }

  Future<void> _processVideo() async {
    if (_videoFile == null) return;
    setState(() {
      _isProcessing = true;
    });
    try {
      // Create a multipart request
      var request = http.MultipartRequest('POST', Uri.parse('$serverUrl/process_video'));
      
      // Add the video file to the request
      request.files.add(await http.MultipartFile.fromPath('video', _videoFile!.path));
      
      // Add metadata to the request
      Map<String, dynamic> metadata = {
        'camera_id': _cameraId ?? 'unknown',
        'location': _locationData != null 
          ? '${_locationData!.latitude},${_locationData!.longitude}' 
          : 'unknown',
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      request.fields['metadata'] = json.encode(metadata);
      
      // Send the request
      var response = await request.send();
      if (response.statusCode == 200) {
        // Convert response stream to string
        final respStr = await response.stream.bytesToString();
        final responseData = json.decode(respStr);
        
        // Save the base64 video to a file
        final String videoBase64 = responseData['processed_video'];
        final bytes = base64Decode(videoBase64);
        final tempDir = await getTemporaryDirectory();
        final outputFile = File('${tempDir.path}/processed_video.mp4');
        await outputFile.writeAsBytes(bytes);
        
        setState(() {
          _processedVideoPath = outputFile.path;
          _statistics = responseData['statistics'];
          
          // Initialize video player for the processed video
          _controller = VideoPlayerController.file(outputFile)
            ..initialize().then((_) {
              _controller!.play();
              setState(() {});
            });
        });
        
        // After processing, fetch analytics data
        _fetchAnalytics();
      } else {
        final errorMessage = await response.stream.bytesToString();
        print('Error: ${response.statusCode}, $errorMessage');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error processing video: ${response.statusCode}')),
        );
      }
    } catch (e) {
      print('Exception: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exception: $e')),
      );
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _fetchHistoricalData() async {
    setState(() {
      _isLoadingHistory = true;
    });
    
    try {
      final now = DateTime.now();
      final startDate = now.subtract(Duration(days: 30)).toIso8601String();
      final endDate = now.toIso8601String();
      
      final response = await http.get(
        Uri.parse('$serverUrl/get_historical_data?start_date=$startDate&end_date=$endDate'),
      );
      
      if (response.statusCode == 200) {
        setState(() {
          _historicalData = List<Map<String, dynamic>>.from(json.decode(response.body)['data']);
          _isLoadingHistory = false;
        });
      } else {
        print('Error fetching historical data: ${response.statusCode}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching historical data')),
        );
        setState(() {
          _isLoadingHistory = false;
        });
      }
    } catch (e) {
      print('Exception fetching historical data: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching historical data: $e')),
      );
      setState(() {
        _isLoadingHistory = false;
      });
    }
  }

  Future<void> _fetchAnalytics() async {
    try {
      final response = await http.get(
        Uri.parse('$serverUrl/get_analytics?period=$_period&metric=$_metric'),
      );
      
      if (response.statusCode == 200) {
        setState(() {
          _analyticsData = json.decode(response.body);
        });
      } else {
        print('Error fetching analytics: ${response.statusCode}');
      }
    } catch (e) {
      print('Exception fetching analytics: $e');
    }
  }

  List<charts.Series<DetectionData, String>> _createChartData() {
    if (_analyticsData == null || !_analyticsData!.containsKey('data')) {
      // Return dummy data if no analytics available
      return [
        charts.Series<DetectionData, String>(
          id: 'Detections',
          data: [
            DetectionData('No data', 0),
          ],
          domainFn: (DetectionData data, _) => data.label,
          measureFn: (DetectionData data, _) => data.count,
          colorFn: (_, __) => charts.MaterialPalette.green.shadeDefault,
        )
      ];
    }

    // Process analytics data
    List<dynamic> data = _analyticsData!['data'];
    List<DetectionData> chartData = data.map((item) => 
      DetectionData(item['label'], item['count'])
    ).toList();

    return [
      charts.Series<DetectionData, String>(
        id: 'Detections',
        data: chartData,
        domainFn: (DetectionData data, _) => data.label,
        measureFn: (DetectionData data, _) => data.count,
        colorFn: (_, __) => charts.MaterialPalette.green.shadeDefault,
      )
    ];
  }

  @override
  void dispose() {
    _controller?.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Wildlife Monitoring'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(icon: Icon(Icons.video_library), text: 'Detection'),
            Tab(icon: Icon(Icons.history), text: 'History'),
            Tab(icon: Icon(Icons.analytics), text: 'Analytics'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDetectionTab(),
          _buildHistoryTab(),
          _buildAnalyticsTab(),
        ],
      ),
    );
  }

  Widget _buildDetectionTab() {
    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (_videoFile != null && _controller != null && _controller!.value.isInitialized)
                AspectRatio(
                  aspectRatio: _controller!.value.aspectRatio,
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      VideoPlayer(_controller!),
                      VideoProgressIndicator(_controller!, allowScrubbing: true),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: IconButton(
                          icon: Icon(
                            _controller!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.white,
                          ),
                          onPressed: () {
                            setState(() {
                              _controller!.value.isPlaying
                                ? _controller!.pause()
                                : _controller!.play();
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.videocam_off, size: 50, color: Colors.grey.shade600),
                        SizedBox(height: 10),
                        Text('No video selected', style: TextStyle(color: Colors.grey.shade700)),
                      ],
                    ),
                  ),
                ),
              SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    icon: Icon(Icons.video_library),
                    label: Text('Select Video'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                    ),
                    onPressed: _pickVideo,
                  ),
                  ElevatedButton.icon(
                    icon: Icon(Icons.camera_alt),
                    label: Text('Record Video'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                    ),
                    onPressed: _captureVideo,
                  ),
                ],
              ),
              SizedBox(height: 10),
              ElevatedButton.icon(
                icon: Icon(Icons.analytics),
                label: Text('Process Video'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade700,
                  minimumSize: Size(double.infinity, 50),
                ),
                onPressed: _videoFile != null && !_isProcessing ? _processVideo : null,
              ),
              SizedBox(height: 20),
              if (_isProcessing)
                Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 10),
                    Text('Processing video, please wait...'),
                  ],
                ),
              if (_statistics != null)
                _buildStatisticsCard(),
              
              if (_cameraId != null)
                Padding(
                  padding: const EdgeInsets.only(top: 20.0),
                  child: Text(
                    'Camera ID: $_cameraId',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
              
              if (_locationData != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10.0),
                  child: Text(
                    'Location: ${_locationData!.latitude?.toStringAsFixed(4)}, ${_locationData!.longitude?.toStringAsFixed(4)}',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatisticsCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.assessment, color: Colors.green.shade700),
                SizedBox(width: 8),
                Text(
                  'Detection Statistics',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            Divider(),
            SizedBox(height: 10),
            ..._statistics!.entries.map((entry) {
              // Skip frames_processed or other non-class entries
              if (entry.key == 'frames_processed' || entry.value == 0) {
                return SizedBox.shrink();
              }
              
              IconData iconData;
              Color iconColor;
              
              // Assign appropriate icons
              if (entry.key.toLowerCase() == 'animal') {
                iconData = Icons.pets;
                iconColor = Colors.brown;
              } else if (entry.key.toLowerCase() == 'vehicle') {
                iconData = Icons.directions_car;
                iconColor = Colors.blue;
              } else if (entry.key.toLowerCase() == 'helicopter') {
                iconData = Icons.helicopter;
                iconColor = Colors.red;
              } else if (entry.key.toLowerCase() == 'poacher') {
                iconData = Icons.person;
                iconColor = Colors.red.shade700;
              } else if (entry.key.toLowerCase() == 'ranger') {
                iconData = Icons.security;
                iconColor = Colors.green;
              } else if (entry.key.toLowerCase() == 'fire') {
                iconData = Icons.local_fire_department;
                iconColor = Colors.orange;
              } else if (entry.key.toLowerCase() == 'weapon') {
                iconData = Icons.gps_fixed;
                iconColor = Colors.red.shade900;
              } else if (entry.key.toLowerCase() == 'binocular') {
                iconData = Icons.visibility;
                iconColor = Colors.blue.shade700;
              } else {
                iconData = Icons.category;
                iconColor = Colors.grey;
              }
              
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  children: [
                    Icon(iconData, color: iconColor, size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        entry.key,
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        entry.value.toString(),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).where((widget) => widget != SizedBox.shrink()).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryTab() {
    if (_historicalData == null && !_isLoadingHistory) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 60, color: Colors.grey.shade400),
            SizedBox(height: 20),
            Text(
              'No historical data loaded',
              style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
            ),
            SizedBox(height: 20),
            ElevatedButton.icon(
              icon: Icon(Icons.refresh),
              label: Text('Load Historical Data'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
              ),
              onPressed: _fetchHistoricalData,
            ),
          ],
        ),
      );
    }

    if (_isLoadingHistory) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('Loading historical data...'),
          ],
        ),
      );
    }

    return _historicalData!.isEmpty
        ? Center(
            child: Text('No historical data available'),
          )
        : ListView.builder(
            padding: EdgeInsets.all(16),
            itemCount: _historicalData!.length,
            itemBuilder: (context, index) {
              final item = _historicalData![index];
              final date = DateTime.parse(item['timestamp']);
              final formattedDate = DateFormat('MMM d, yyyy h:mm a').format(date);
              
              return Card(
                margin: EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: _getLeadingIcon(item),
                  title: Text('${item['object_type']}'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(formattedDate),
                      Text('Location: ${item['location'] ?? 'Unknown'}'),
                    ],
                  ),
                  trailing: Text(
                    '${(item['confidence'] * 100).toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade700,
                    ),
                  ),
                ),
              );
            },
          );
  }

  Widget _getLeadingIcon(Map<String, dynamic> item) {
    final objectType = item['object_type'].toString().toLowerCase();
    
    if (objectType.contains('animal')) {
      return CircleAvatar(backgroundColor: Colors.brown, child: Icon(Icons.pets, color: Colors.white));
    } else if (objectType.contains('vehicle')) {
      return CircleAvatar(backgroundColor: Colors.blue, child: Icon(Icons.directions_car, color: Colors.white));
    } else if (objectType.contains('helicopter')) {
      return CircleAvatar(backgroundColor: Colors.red, child: Icon(Icons.helicopter, color: Colors.white));
    } else if (objectType.contains('poacher')) {
      return CircleAvatar(backgroundColor: Colors.red.shade700, child: Icon(Icons.person, color: Colors.white));
    } else if (objectType.contains('ranger')) {
      return CircleAvatar(backgroundColor: Colors.green, child: Icon(Icons.security, color: Colors.white));
    } else if (objectType.contains('fire')) {
      return CircleAvatar(backgroundColor: Colors.orange, child: Icon(Icons.local_fire_department, color: Colors.white));
    } else if (objectType.contains('weapon')) {
      return CircleAvatar(backgroundColor: Colors.red.shade900, child: Icon(Icons.gps_fixed, color: Colors.white));
    } else if (objectType.contains('binocular')) {
      return CircleAvatar(backgroundColor: Colors.blue.shade700, child: Icon(Icons.visibility, color: Colors.white));
    }
    
    return CircleAvatar(backgroundColor: Colors.grey, child: Icon(Icons.category, color: Colors.white));
  }

  Widget _buildAnalyticsTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Analytics Settings',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Time Period'),
                            DropdownButton<String>(
                              value: _period,
                              isExpanded: true,
                              onChanged: (String? newValue) {
                                if (newValue != null) {
                                  setState(() {
                                    _period = newValue;
                                  });
                                  _fetchAnalytics();
                                }
                              },
                              items: <String>['day', 'week', 'month', 'year']
                                  .map<DropdownMenuItem<String>>((String value) {
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(value.capitalize()),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Metric'),
                            DropdownButton<String>(
                              value: _metric,
                              isExpanded: true,
                              onChanged: (String? newValue) {
                                if (newValue != null) {
                                  setState(() {
                                    _metric = newValue;
                                  });
                                  _fetchAnalytics();
                                }
                              },
                              items: <String>['detections', 'confidence', 'objects']
                                  .map<DropdownMenuItem<String>>((String value) {
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(value.capitalize()),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: Icon(Icons.refresh),
                      label: Text('Refresh Data'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                      ),
                      onPressed: _fetchAnalytics,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 16),
          Expanded(
            child: _analyticsData == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.bar_chart, size: 60, color: Colors.grey.shade400),
                        SizedBox(height: 16),
                        Text(
                          'No analytics data available',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  )
                : Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_metric.capitalize()} by ${_period.capitalize()}',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 16),
                          Expanded(
                            child: charts.BarChart(
                              _createChartData(),
                              animate: true,
                              vertical: true,
                              barRendererDecorator: charts.BarLabelDecorator<String>(),
                              domainAxis: charts.OrdinalAxisSpec(
                                renderSpec: charts.SmallTickRendererSpec(
                                  labelRotation: 45,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class DetectionData {
  final String label;
  final int count;

  DetectionData(this.label, this.count);
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${this.substring(1)}";
  }
}