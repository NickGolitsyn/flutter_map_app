import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;
import 'main.dart';

class PlanRunScreen extends StatefulWidget {
  final LatLng startLocation;

  const PlanRunScreen({
    super.key,
    required this.startLocation,
  });

  @override
  State<PlanRunScreen> createState() => _PlanRunScreenState();
}

class _PlanRunScreenState extends State<PlanRunScreen> {
  double _targetDistanceKm = 5.0;
  List<LatLng> _roundTripPoints = [];
  LatLng? _intermediatePoint;
  bool _isLoading = false;
  final MapController _mapController = MapController();
  String _routeInfo = "";

  @override
  void initState() {
    super.initState();
    _generateRoundTrip();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _adjustDistance(double delta) {
    setState(() {
      _targetDistanceKm = (_targetDistanceKm + delta).clamp(1.0, 50.0);
       _roundTripPoints = [];
       _intermediatePoint = null;
       _routeInfo = "";
    });
    _generateRoundTrip();
  }

  Future<void> _generateRoundTrip() async {
    if (yourORSapiKey == 'api_key') {
      _showErrorSnackBar('Please add your OpenRouteService API key!');
      return;
    }

    setState(() { _isLoading = true; });

    try {
      await _fetchRoundTripRoute(widget.startLocation, widget.startLocation);

    } catch (e) {
      print('Error generating round trip: $e');
      _showErrorSnackBar('Error generating round trip: ${e.toString()}');
    } finally {
       if(mounted){
         setState(() { _isLoading = false; });
       }
    }
  }

  Future<void> _fetchRoundTripRoute(LatLng start, LatLng midpoint) async {
     final String routeUrl = 'https://api.openrouteservice.org/v2/directions/foot-walking/json';

     try {
        final response = await http.post(
           Uri.parse(routeUrl),
            headers: {
              'Authorization': yourORSapiKey,
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json, application/geo+json, application/gpx+xml, img/png; charset=utf-8'
            },
            body: json.encode({
               'coordinates': [[start.longitude, start.latitude]],
               'instructions': true,
               'options': {
                 'round_trip': {
                   'length': _targetDistanceKm * 1000,
                   'points': 15,
                   'seed': 1
                 }
               }
            }),
        );

        if (response.statusCode == 200) {
           final data = json.decode(response.body);
           final String encodedGeometry = data['routes'][0]['geometry'];
           final List<LatLng> decodedPoints = _decodePolyline(encodedGeometry);
           final Map<String, dynamic> summary = data['routes'][0]['summary'];
           final double totalDistance = summary['distance'] ?? 0.0;
           final double totalDurationSec = summary['duration'] ?? 0.0;
           final Duration duration = Duration(seconds: totalDurationSec.toInt());

           if (mounted) {
              setState(() {
                _roundTripPoints = decodedPoints;
                _routeInfo = "Route: ${totalDistance.toStringAsFixed(1)} m, approx ${duration.inMinutes} min";
              });
           }
        } else {
           print('ORS Directions API Error: ${response.statusCode} - ${response.body}');
            String errorMessage = 'Failed to get route (${response.statusCode})';
            try {
              final errorData = json.decode(response.body);
              errorMessage = errorData['error']?['message'] ?? errorMessage;
            } catch (_) {}
            _showErrorSnackBar(errorMessage);
             if (mounted) {
                setState(() {
                   _roundTripPoints = [];
                   _intermediatePoint = null;
                   _routeInfo = "Route calculation failed";
                });
              }
           print('Response body: ${response.body}');
        }
    } catch (e) {
        print('Directions Network/Parsing Error: $e');
        _showErrorSnackBar('Network error during route calculation.');
         if (mounted) {
            setState(() {
              _roundTripPoints = [];
              _intermediatePoint = null;
              _routeInfo = "Route calculation failed";
            });
          }
    }
}

List<LatLng> _decodePolyline(String encoded) {
  List<LatLng> points = [];
  int index = 0;
  int len = encoded.length;
  int lat = 0;
  int lng = 0;

  while (index < len) {
    int b;
    int shift = 0;
    int result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1F) << shift;
      shift += 5;
    } while (b >= 0x20);
    int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
    lat += dlat;

    shift = 0;
    result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1F) << shift;
      shift += 5;
    } while (b >= 0x20);
    int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
    lng += dlng;

    points.add(LatLng(lat / 1E5, lng / 1E5));
  }
  return points;
}

  Future<void> _launchRunNavigation() async {
    if (_roundTripPoints.isEmpty || _intermediatePoint == null) {
      _showErrorSnackBar('No route calculated yet.');
      return;
    }

    final LatLng start = widget.startLocation;
    final LatLng mid = _intermediatePoint!;

    String googleUrl =
        'https://www.google.com/maps/dir/?api=1&origin=${start.latitude},${start.longitude}'
        '&destination=${start.latitude},${start.longitude}'
        '&waypoints=${mid.latitude},${mid.longitude}'
        '&travelmode=walking';

    // Apple Maps URL is less flexible with waypoints for turn-by-turn.
    // Option 1: Route Start -> Midpoint (user needs to manually route back)
    // String appleUrl = 'https://maps.apple.com/?saddr=${start.latitude},${start.longitude}&daddr=${mid.latitude},${mid.longitude}&dirflg=w';
    // Option 2: Route Start -> Start (doesn't make sense)
    // Option 3: Just provide the Start address and let user figure it out?
    // Let's go with Start -> Midpoint for Apple Maps as the most practical compromise.
     String appleUrl = 'https://maps.apple.com/?saddr=${start.latitude},${start.longitude}&daddr=${mid.latitude},${mid.longitude}&dirflg=w';


    Uri? launchUri;

    if (Platform.isIOS) {
      launchUri = Uri.parse(appleUrl);
      _showInfoSnackBar("Launching route Start -> Midpoint in Apple Maps. You'll need to navigate back manually.");

    } else {
      launchUri = Uri.parse(googleUrl);
       _showInfoSnackBar("Launching route Start -> Midpoint -> Start in Google Maps.");
    }

    try {
      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri, mode: LaunchMode.externalApplication);
      } else {
        _showErrorSnackBar('Could not launch ${Platform.isIOS ? "Apple Maps" : "Google Maps"}');
      }
    } catch (e) {
      _showErrorSnackBar('Error launching maps: $e');
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }
   void _showInfoSnackBar(String message) {
     if (!mounted) return;
     ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(content: Text(message), backgroundColor: Colors.blueGrey),
     );
   }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plan Round Trip Run'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: _isLoading ? null : () => _adjustDistance(-1.0),
                  tooltip: 'Decrease distance',
                ),
                Text(
                  '${_targetDistanceKm.toStringAsFixed(1)} km',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: _isLoading ? null : () => _adjustDistance(1.0),
                  tooltip: 'Increase distance',
                ),
              ],
            ),
          ),

           if (_routeInfo.isNotEmpty)
              Padding(
                 padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                 child: Text(_routeInfo, style: Theme.of(context).textTheme.bodyMedium),
              ),

           if (_isLoading)
              const Padding(
                 padding: EdgeInsets.symmetric(vertical: 10.0),
                 child: Column(
                   children: [
                     LinearProgressIndicator(),
                     SizedBox(height: 4),
                     Text("Calculating route...")
                   ],
                 ),
              ),

          Expanded(
            child: FlutterMap(
               mapController: _mapController,
              options: MapOptions(
                initialCenter: widget.startLocation,
                initialZoom: 14.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.flutter_map_app',
                ),

                 MarkerLayer(
                    markers: [
                       Marker(
                          width: 80.0, height: 80.0,
                          point: widget.startLocation,
                          child: const Tooltip(
                             message: "Start/End",
                             child: Icon(Icons.person_pin_circle, color: Colors.green, size: 40.0)),
                       ),
                       if (_intermediatePoint != null)
                           Marker(
                              width: 80.0, height: 80.0,
                              point: _intermediatePoint!,
                              child: const Tooltip(
                                 message: "Turnaround Point",
                                 child: Icon(Icons.flag_circle, color: Colors.orange, size: 35.0)),
                           ),
                    ],
                 ),

                if (_roundTripPoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _roundTripPoints,
                        color: Colors.deepPurple,
                        strokeWidth: 5.0,
                      ),
                    ],
                  ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.share),
                  label: const Text('Share'),
                  onPressed: null,
                  style: ElevatedButton.styleFrom(foregroundColor: Colors.grey),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Save'),
                  onPressed: null,
                   style: ElevatedButton.styleFrom(foregroundColor: Colors.grey),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Run'),
                  onPressed: (_roundTripPoints.isEmpty || _isLoading) ? null : _launchRunNavigation,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}