import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

// *** LOGIN INIZIO *** //
void main() {
  runApp(const PopPathApp());
}

class PopPathApp extends StatefulWidget {
  const PopPathApp({super.key});

  @override
  State<PopPathApp> createState() => _PopPathAppState();
}

class _PopPathAppState extends State<PopPathApp> {
  String? _loggedEmail;

  @override
  void initState() {
    super.initState();
    _checkLogin();
  }

  Future<void> _checkLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('logged_email');
    setState(() {
      _loggedEmail = email;
    });
  }

  void _onLogin(String email) {
    setState(() {
      _loggedEmail = email;
    });
  }

  void _onLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('logged_email');
    setState(() {
      _loggedEmail = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loggedEmail == null) {
      return MaterialApp(
        title: 'Pop Path - Login',
        theme: ThemeData(primarySwatch: Colors.blue),
        home: LoginPage(onLogin: _onLogin),
      );
    }
    return MaterialApp(
      title: 'Pop Path',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: MapPage(userEmail: _loggedEmail!, onLogout: _onLogout),
      routes: {
        '/history': (context) => HistoryPage(userEmail: _loggedEmail!),
      },
    );
  }
}

// LoginPage
class LoginPage extends StatefulWidget {
  final void Function(String email) onLogin;
  const LoginPage({super.key, required this.onLogin});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _error;

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _error = 'Inserisci email e password';
      });
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final savedPassword = prefs.getString('user_$email');

    if (savedPassword == null) {
      // Registrazione semplice
      await prefs.setString('user_$email', password);
      await prefs.setString('logged_email', email);
      widget.onLogin(email);
    } else if (savedPassword == password) {
      // Login corretto
      await prefs.setString('logged_email', email);
      widget.onLogin(email);
    } else {
      setState(() {
        _error = 'Password errata';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login Pop Path')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _login,
              child: const Text('Accedi / Registrati'),
            ),
          ],
        ),
      ),
    );
  }
}
// *** LOGIN FINE *** //

// PathData class
class PathData {
  final LatLng point1;
  final LatLng point2;
  final double distance;
  final double elevationDiff;

  PathData({
    required this.point1,
    required this.point2,
    required this.distance,
    required this.elevationDiff,
  });

  Map<String, dynamic> toMap() {
    return {
      'point1_lat': point1.latitude,
      'point1_lng': point1.longitude,
      'point2_lat': point2.latitude,
      'point2_lng': point2.longitude,
      'distance': distance,
      'elevationDiff': elevationDiff,
    };
  }

  factory PathData.fromMap(Map<String, dynamic> map) {
    return PathData(
      point1: LatLng(map['point1_lat'], map['point1_lng']),
      point2: LatLng(map['point2_lat'], map['point2_lng']),
      distance: map['distance'],
      elevationDiff: map['elevationDiff'],
    );
  }

  String toJson() => json.encode(toMap());

  factory PathData.fromJson(String source) =>
      PathData.fromMap(json.decode(source));
}

// MapPage
class MapPage extends StatefulWidget {
  final String userEmail;
  final VoidCallback onLogout;

  const MapPage({super.key, required this.userEmail, required this.onLogout});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  LatLng? _point1;
  LatLng? _point2;
  double _distance = 0;
  double _elevationDiff = 0;
  LatLng _center = LatLng(45.4642, 9.19); // Milano
  final MapController _mapController = MapController();
  final Random _random = Random();

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return;
      }
    }

    final Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
    _mapController.move(LatLng(pos.latitude, pos.longitude), 15.0);
  }

  void _onTapMap(TapPosition tapPosition, LatLng point) async {
    setState(() {
      if (_point1 == null) {
        _point1 = point;
      } else if (_point2 == null) {
        _point2 = point;
      } else {
        _point1 = point;
        _point2 = null;
        _distance = 0;
        _elevationDiff = 0;
        return;
      }

      if (_point1 != null && _point2 != null) {
        _calculateDistanceAndElevation();
      }
    });
  }

  Future<void> _calculateDistanceAndElevation() async {
    final Distance distance = const Distance();
    _distance = distance.as(LengthUnit.Meter, _point1!, _point2!);

    double elevation1 = 1 + _random.nextInt(100).toDouble();
    double elevation2 = 1 + _random.nextInt(100).toDouble();
    _elevationDiff = (elevation2 - elevation1).abs();

    setState(() {});
  }

  void _shareData() {
    if (_point1 == null || _point2 == null) return;

    final text = '''
Punto 1: ${_point1!.latitude}, ${_point1!.longitude}
Punto 2: ${_point2!.latitude}, ${_point2!.longitude}
Distanza: ${_distance.toStringAsFixed(2)} metri
Dislivello: ${_elevationDiff.toStringAsFixed(2)} metri
''';
    Share.share(text);
  }

  Future<void> _saveCurrentPath() async {
    if (_point1 == null || _point2 == null) return;
    final prefs = await SharedPreferences.getInstance();

    List<String> savedPaths =
        prefs.getStringList('paths_${widget.userEmail}') ?? [];

    final newPath = PathData(
      point1: _point1!,
      point2: _point2!,
      distance: _distance,
      elevationDiff: _elevationDiff,
    );

    savedPaths.add(newPath.toJson());
    await prefs.setStringList('paths_${widget.userEmail}', savedPaths);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Percorso salvato!')),
    );
  }

  Future<void> _centerMapOnMilano() async {
    _mapController.move(_center, 13.0);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Mappa centrata su Milano')),
    );
  }

  void _resetPoints() {
    setState(() {
      _point1 = null;
      _point2 = null;
      _distance = 0;
      _elevationDiff = 0;
    });
  }

  Future<void> _showSavedPathsCount() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> savedPaths = prefs.getStringList('paths_${widget.userEmail}') ?? [];
    final count = savedPaths.length;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Totale percorsi salvati: $count')),
    );
  }

  Future<void> _clearAllPaths() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Conferma cancellazione'),
        content: const Text('Sei sicuro di voler cancellare tutti i percorsi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Conferma'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('paths_${widget.userEmail}');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tutti i percorsi sono stati cancellati.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    List<Marker> markers = [];
    if (_point1 != null) {
      markers.add(
        Marker(
          point: _point1!,
          width: 30,
          height: 30,
          child: const Icon(Icons.location_on, color: Colors.red, size: 30),
        ),
      );
    }
    if (_point2 != null) {
      markers.add(
        Marker(
          point: _point2!,
          width: 30,
          height: 30,
          child: const Icon(Icons.location_on, color: Colors.blue, size: 30),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pop Path'),
        actions: [
          IconButton(
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
          ),
          IconButton(
            onPressed: () => Navigator.pushNamed(context, '/history'),
            icon: const Icon(Icons.history),
            tooltip: 'Storico percorsi',
          ),
        ],
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          center: _center,
          zoom: 13.0,
          onTap: _onTapMap,
        ),
        children: [
          TileLayer(
            urlTemplate:
            'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
            subdomains: const ['a', 'b', 'c'],
            userAgentPackageName: 'com.example.pop_path',
          ),
          MarkerLayer(markers: markers),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            onPressed: _getCurrentLocation,
            heroTag: 'btn1',
            tooltip: 'Posizione attuale',
            child: const Icon(Icons.my_location),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            onPressed: _centerMapOnMilano,
            heroTag: 'btn2',
            tooltip: 'Centra su Milano',
            child: const Icon(Icons.location_city),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            onPressed: _shareData,
            heroTag: 'btn3',
            tooltip: 'Condividi dati',
            child: const Icon(Icons.share),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            onPressed: _saveCurrentPath,
            heroTag: 'btn4',
            tooltip: 'Salva percorso',
            child: const Icon(Icons.save),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            onPressed: _showSavedPathsCount,
            heroTag: 'btn5',
            tooltip: 'Mostra tot. percorsi salvati',
            child: const Icon(Icons.info),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            onPressed: _resetPoints,
            heroTag: 'btn6',
            tooltip: 'Reset punti',
            child: const Icon(Icons.refresh),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            onPressed: _clearAllPaths,
            heroTag: 'btn7',
            tooltip: 'Cancella tutti i percorsi',
            child: const Icon(Icons.delete_forever),
          ),
        ],
      ),
    );
  }
}

// HistoryPage
class HistoryPage extends StatefulWidget {
  final String userEmail;
  const HistoryPage({super.key, required this.userEmail});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<PathData> _savedPaths = [];

  @override
  void initState() {
    super.initState();
    _loadSavedPaths();
  }

  Future<void> _loadSavedPaths() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPaths = prefs.getStringList('paths_${widget.userEmail}') ?? [];
    setState(() {
      _savedPaths = savedPaths.map((e) => PathData.fromJson(e)).toList();
    });
  }

  Future<void> _deletePath(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final savedPaths = prefs.getStringList('paths_${widget.userEmail}') ?? [];
    savedPaths.removeAt(index);
    await prefs.setStringList('paths_${widget.userEmail}', savedPaths);
    _loadSavedPaths();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Storico Percorsi'),
      ),
      body: ListView.builder(
        itemCount: _savedPaths.length,
        itemBuilder: (context, index) {
          final path = _savedPaths[index];
          return ListTile(
            title: Text(
                'P1: ${path.point1.latitude.toStringAsFixed(5)}, ${path.point1.longitude.toStringAsFixed(5)} - P2: ${path.point2.latitude.toStringAsFixed(5)}, ${path.point2.longitude.toStringAsFixed(5)}'),
            subtitle: Text(
                'Distanza: ${path.distance.toStringAsFixed(2)} m, Dislivello: ${path.elevationDiff.toStringAsFixed(2)} m'),
            trailing: IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () => _deletePath(index),
              tooltip: 'Elimina percorso',
            ),
          );
        },
      ),
    );
  }
}
