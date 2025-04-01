import 'package:flutter/material.dart';
// import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_app/plan_run_screen.dart';
import 'package:geolocator_android/geolocator_android.dart';
import 'package:geolocator_apple/geolocator_apple.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:geolocator/geolocator.dart';

const String ORSapiKey = 'api_key';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isAndroid) {
    GeolocatorAndroid.registerWith();
  } else if (Platform.isIOS) {
    GeolocatorApple.registerWith();
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Running Route Planner',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      home: const MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  
  LatLng? _currentLocation;
  LatLng? _endPoint;
  
  List<LatLng> _routePoints = [];
  bool _isLoadingRoute = false;
  bool _isSearching = false;
  List<PlaceSearchResult> _searchResults = [];
  
  final MapController _mapController = MapController();
  
  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }
  
  Future<void> _getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permissions are denied')),
          );
          return;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(
            'Location permissions are permanently denied, we cannot request permissions.')),
        );
        return;
      }
      
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      );
      
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });
      
      if (_currentLocation != null) {
        _mapController.move(_currentLocation!, 15.0);
      }
      
    } catch (e) {
      print('Error getting location: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error getting location: $e')),
      );
    }
  }
  
  Future<void> _searchPlaces(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }
    
    setState(() {
      _isSearching = true;
    });
    
    try {
      final response = await http.get(
        Uri.parse(
          'https://nominatim.openstreetmap.org/search?format=json&q=$query&limit=5'
        ),
        headers: {'User-Agent': 'RunningRouteApp'}
      );
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          _searchResults = data.map((item) => PlaceSearchResult(
            displayName: item['display_name'],
            lat: double.parse(item['lat']),
            lon: double.parse(item['lon']),
          )).toList();
          _isSearching = false;
        });
      } else {
        print('Nominatim API Error: ${response.statusCode} - ${response.body}');
        setState(() {
          _isSearching = false;
        });
      }
    } catch (e) {
      print('Error searching places: $e');
      setState(() {
        _isSearching = false;
      });
    }
  }
  
  void _selectLocation(PlaceSearchResult place) {
    setState(() {
      _endPoint = LatLng(place.lat, place.lon);
      _searchResults = [];
      _searchController.text = place.displayName.split(',')[0];
      _searchFocusNode.unfocus();
    });
    
    if (_currentLocation != null && _endPoint != null) {
      _getRoute();
    }
  }
  
  Future<void> _getRoute() async {
    if (ORSapiKey == 'api_key') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add your OpenRouteService API key!')),
      );
      return;
    }
    
    if (_currentLocation == null || _endPoint == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Start and end points are required!')),
      );
      return;
    }

    setState(() {
      _isLoadingRoute = true;
      _routePoints = [];
    });

    final String url =
        'https://api.openrouteservice.org/v2/directions/foot-walking?api_key=$ORSapiKey'
        '&start=${_currentLocation!.longitude},${_currentLocation!.latitude}'
        '&end=${_endPoint!.longitude},${_endPoint!.latitude}';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> points = data['features'][0]['geometry']['coordinates'];
        setState(() {
          _routePoints = points
              .map((p) => LatLng(p[1].toDouble(), p[0].toDouble()))
              .toList();
        });
        
        if (_routePoints.isNotEmpty) {
          final bounds = LatLngBounds.fromPoints(_routePoints);
          _mapController.move(
            bounds.center,
            14.0,
          );
        }
        
      } else {
        print('ORS API Error: ${response.statusCode} - ${response.body}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching route: ${response.statusCode}')),
        );
      }
    } catch (e) {
      print('Error fetching route: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching route: $e')),
      );
    } finally {
      setState(() {
        _isLoadingRoute = false;
      });
    }
  }

  Future<void> _launchMaps() async {
    if (_routePoints.isEmpty || _currentLocation == null || _endPoint == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Calculate a route first!')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.directions_rounded),
                title: const Text('Google Maps'),
                onTap: () async {
                  Navigator.pop(context);

                  final String googleUrl =
                      'https://www.google.com/maps/dir/?api=1'
                      '&origin=${_currentLocation!.latitude},${_currentLocation!.longitude}'
                      '&destination=${_endPoint!.latitude},${_endPoint!.longitude}'
                      '&travelmode=walking';
                  
                  final launchUri = Uri.parse(googleUrl);

                  try {
                    if (await canLaunchUrl(launchUri)) {
                      await launchUrl(launchUri, mode: LaunchMode.externalApplication);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Launching route in Google Maps')),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Could not launch Google Maps')),
                      );
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error launching Google Maps: $e')),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.apple),
                title: const Text('Apple Maps'),
                enabled: Platform.isIOS,
                onTap: Platform.isIOS ? () async {
                  Navigator.pop(context);

                  final String appleUrl =
                      'https://maps.apple.com/?saddr=${_currentLocation!.latitude},${_currentLocation!.longitude}'
                      '&daddr=${_endPoint!.latitude},${_endPoint!.longitude}'
                      '&dirflg=w';
                  
                  final launchUri = Uri.parse(appleUrl);

                  try {
                    if (await canLaunchUrl(launchUri)) {
                      await launchUrl(launchUri, mode: LaunchMode.externalApplication);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Launching route in Apple Maps')),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Could not launch Apple Maps')),
                      );
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error launching Apple Maps: $e')),
                    );
                  }
                } : null,
              ),
              if (!Platform.isIOS)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    "Apple Maps is only available on iOS devices.",
                    style: TextStyle(color: Colors.grey)
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
  
  void _resetRoute() {
    setState(() {
      _endPoint = null;
      _routePoints = [];
      _searchController.clear();
    });
    
    if (_currentLocation != null) {
      _mapController.move(_currentLocation!, 15.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Running Route Planner'),
        actions: [
          IconButton(
            icon: const Icon(Icons.directions_run),
            onPressed: () {
              if (_currentLocation != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PlanRunScreen(
                      startLocation: _currentLocation!,
                    ),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please get current location first.')),
                );
              }
            },
            tooltip: 'Plan a Run',
          ),
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: _getCurrentLocation,
            tooltip: 'Get Current Location',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _resetRoute,
            tooltip: 'Reset Route',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.my_location, color: Colors.blue),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _currentLocation == null 
                              ? 'Getting your location...' 
                              : 'Current Location',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 8),
                
                TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  decoration: InputDecoration(
                    hintText: 'Search destination...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchResults = [];
                              });
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Theme.of(context).cardColor,
                  ),
                  onChanged: (value) {
                    if (value.length > 2) {
                      _searchPlaces(value);
                    } else if (value.isEmpty) {
                      setState(() {
                        _searchResults = [];
                      });
                    }
                  },
                ),
                
                if (_searchResults.isNotEmpty)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final result = _searchResults[index];
                        return ListTile(
                          title: Text(
                            result.displayName.split(',')[0],
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            result.displayName.split(',').skip(1).join(','),
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _selectLocation(result),
                        );
                      },
                    ),
                  ),
                
                if (_isSearching)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: CircularProgressIndicator(),
                  ),
              ],
            ),
          ),
          
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _currentLocation ?? const LatLng(51.5, -0.09), // Default to London
                    initialZoom: 14.0,
                    onTap: (tapPosition, point) {
                      setState(() {
                        _endPoint = point;
                        _searchController.text = "Selected Location";
                        _searchResults = [];
                        _searchFocusNode.unfocus();
                      });
                      
                      if (_currentLocation != null) {
                        _getRoute();
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.flutter_map_app',
                    ),
                    
                    CurrentLocationLayer(
                      alignPositionOnUpdate: AlignOnUpdate.always,
                      alignDirectionOnUpdate: AlignOnUpdate.never,
                      style: LocationMarkerStyle(
                        marker: const DefaultLocationMarker(
                          child: Icon(
                            Icons.circle,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                        markerSize: const Size(24, 24),
                        markerDirection: MarkerDirection.heading,
                      ),
                    ),
                    
                    if (_routePoints.isNotEmpty)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _routePoints,
                            color: Colors.blue,
                            strokeWidth: 5.0,
                          ),
                        ],
                      ),
                    
                    if (_endPoint != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            width: 80.0,
                            height: 80.0,
                            point: _endPoint!,
                            child: const Tooltip(
                              message: "Destination",
                              child: Icon(Icons.location_on, color: Colors.red, size: 40.0)),
                          ),
                        ],
                      ),
                  ],
                ),
                
                if (_isLoadingRoute)
                  const Center(
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 8),
                            Text('Calculating route...'),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          if (_routePoints.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(10.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.map),
                    label: const Text('Open Maps'),
                    onPressed: _launchMaps,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class PlaceSearchResult {
  final String displayName;
  final double lat;
  final double lon;
  
  PlaceSearchResult({
    required this.displayName,
    required this.lat,
    required this.lon,
  });
}