import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart' as geo;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';

// 🔹 Páginas
import 'login_page.dart';
import 'rutas_page.dart';
import 'mensajeros_page.dart';
import 'envios_page.dart';
import 'entregados_page.dart';
import 'envios_pendientes_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final storage = const FlutterSecureStorage();
  Map<String, dynamic>? usuario;
  Map<String, dynamic>? dashboardData;
  bool _loading = true;
  bool _compartiendoUbicacion = false;

  final String baseUrl = "http://192.168.3.159:8000"; // Cambia la URL por la de tu backend

  @override
  void initState() {
    super.initState();
    _cargarUsuario();
  }

  // Cargar los datos del usuario desde almacenamiento seguro
  Future<void> _cargarUsuario() async {
    final data = await storage.readAll();
    if (data.containsKey('id')) {
      usuario = {
        'id': int.tryParse(data['id'] ?? '0') ?? 0,
        'nombre': data['nombre'],
        'email': data['email'],
        'rol': data['rol'],
        'is_active': data['is_active'] == 'true',
      };

      if (usuario?['rol'] == 'Administrador') {
        await _fetchDashboardData();
      } else {
        setState(() => _loading = false);
      }
    } else {
      setState(() => _loading = false);
    }
  }

  // Obtener los datos del dashboard desde el backend
  Future<void> _fetchDashboardData() async {
    try {
      final url = Uri.parse('$baseUrl/usuarios/home_data/');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          dashboardData = jsonDecode(response.body);
          _loading = false;
        });
      } else {
        debugPrint('Error al cargar dashboard: ${response.statusCode}');
        setState(() => _loading = false);
      }
    } catch (e) {
      debugPrint('⚠️ Error al cargar dashboard: $e');
      setState(() => _loading = false);
    }
  }

  // =====================================================
  // 📍 SERVICIO DE UBICACIÓN EN SEGUNDO PLANO
  // =====================================================

  // Iniciar el seguimiento de ubicación
  Future<void> _iniciarTracking() async {
    bool serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Activa la ubicación en tu dispositivo.')),
      );
      return;
    }

    geo.LocationPermission permission = await geo.Geolocator.requestPermission();
    if (permission == geo.LocationPermission.denied ||
        permission == geo.LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permiso de ubicación denegado')),
      );
      return;
    }

    await _iniciarServicio();

    setState(() => _compartiendoUbicacion = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('🟢 Compartiendo ubicación en segundo plano')),
    );
  }

  // Configurar el servicio para ejecutar en segundo plano
  Future<void> _iniciarServicio() async {
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,  // Función que maneja el servicio en segundo plano
        autoStart: true,  // El servicio se inicia automáticamente
        isForegroundMode: true,  // Mantén el servicio en primer plano
        notificationChannelId: 'ubicacion_courier_channel',  // Canal de notificación
        initialNotificationTitle: 'Courier Bolivian Express',
        initialNotificationContent: 'Compartiendo ubicación...',
        foregroundServiceNotificationId: 999,  // ID de la notificación para primer plano
      ),
      iosConfiguration: IosConfiguration(),
    );

    await service.startService();  // Inicia el servicio en primer plano
    service.invoke('setUserId', {'id': usuario?['id']});  // Establece el ID del usuario
  }

  // Detener el seguimiento de ubicación
  Future<void> _detenerTracking() async {
    final service = FlutterBackgroundService();
    service.invoke('stopService');
    setState(() => _compartiendoUbicacion = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('🔴 Se detuvo el envío de ubicación')),
    );
  }

  // Cambiar entre iniciar y detener el seguimiento
  void _toggleTracking() {
    if (_compartiendoUbicacion) {
      _detenerTracking();
    } else {
      _iniciarTracking();
    }
  }

  // =====================================================
  // 🔹 INTERFAZ (UI)
  // =====================================================

  @override
  Widget build(BuildContext context) {
    final rol = usuario?['rol'] ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFD47B2C),
        title: Text(
          rol == 'Administrador'
              ? 'Dashboard - Courier Bolivian Express'
              : 'Panel del Mensajero',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await storage.deleteAll();
              if (_compartiendoUbicacion) await _detenerTracking();
              if (!context.mounted) return;
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginPage()),
              );
            },
          )
        ],
      ),
      drawer: _buildDrawer(context, rol),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : rol == 'Administrador'
              ? _buildDashboard()
              : _buildMensajero(),
    );
  }

  // Construir el menú lateral (Drawer)
  Drawer _buildDrawer(BuildContext context, String rol) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          DrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFFD47B2C)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(
                  backgroundColor: Colors.white,
                  radius: 28,
                  child: Icon(Icons.person, color: Color(0xFFD47B2C), size: 40),
                ),
                const SizedBox(height: 10),
                Text(
                  usuario?['nombre'] ?? 'Usuario',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
                Text(
                  usuario?['email'] ?? '',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          if (rol == 'Administrador') ...[
            _menuItem(Icons.dashboard, 'Dashboard',
                () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomePage()))),
            _menuItem(Icons.route, 'Rutas',
                () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const RutasPage()))),
            _menuItem(Icons.person_pin_circle, 'Mensajeros',
                () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MensajerosPage()))),
            _menuItem(Icons.local_shipping, 'Envíos',
                () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const EnviosPage()))),
            _menuItem(Icons.check_circle_outline, 'Entregados',
                () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const EntregadosPage()))),
            _menuItem(Icons.pending_actions, 'Envíos Pendientes',
                () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const EnviosPendientesPage()))),
          ] else ...[
            _menuItem(
              _compartiendoUbicacion
                  ? Icons.stop_circle
                  : Icons.play_circle_fill,
              _compartiendoUbicacion
                  ? 'Dejar de compartir ubicación'
                  : 'Compartir ubicación',
              _toggleTracking,
            ),
          ],
        ],
      ),
    );
  }

  // Elementos del menú lateral
  Widget _menuItem(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFFD47B2C)),
      title: Text(title),
      onTap: onTap,
    );
  }

  // Construir la interfaz del mensajero
  Widget _buildMensajero() {
    return Center(
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor:
              _compartiendoUbicacion ? Colors.redAccent : Colors.orange,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: _toggleTracking,
        icon: Icon(
          _compartiendoUbicacion ? Icons.stop_circle : Icons.my_location,
          color: Colors.white,
        ),
        label: Text(
          _compartiendoUbicacion
              ? 'Dejar de compartir ubicación'
              : 'Compartir ubicación',
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
      ),
    );
  }

  // Construir el dashboard para el administrador
  Widget _buildDashboard() {
    return RefreshIndicator(
      onRefresh: _fetchDashboardData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Resumen general',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              children: [
                _buildCard('Usuarios',
                    dashboardData?['usuarios_count']?.toString() ?? '0',
                    Icons.people, Colors.blueAccent),
                _buildCard('Envíos Pendientes',
                    dashboardData?['envios_pendientes']?.toString() ?? '0',
                    Icons.local_shipping, Colors.orangeAccent),
                _buildCard('Mensajeros Activos',
                    dashboardData?['mensajeros_activos']?.toString() ?? '0',
                    Icons.delivery_dining, Colors.green),
                _buildCard('% Entregados',
                    '${dashboardData?['porcentaje_entregados'] ?? 0}%',
                    Icons.check_circle, Colors.teal),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Crear tarjeta para el dashboard
  Widget _buildCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 40),
            const SizedBox(height: 10),
            Text(value,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

// =====================================================
// 🛰️ FUNCIÓN GLOBAL DE SERVICIO EN SEGUNDO PLANO
// =====================================================
@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.on('stopService').listen((event) => service.stopSelf());
  }

  int userId = 0;
  service.on('setUserId').listen((event) {
    userId = event?['id'] ?? 0;
  });

  bool serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) return;

  geo.LocationPermission permission = await geo.Geolocator.checkPermission();
  if (permission == geo.LocationPermission.denied ||
      permission == geo.LocationPermission.deniedForever) {
    permission = await geo.Geolocator.requestPermission();
    if (permission == geo.LocationPermission.denied ||
        permission == geo.LocationPermission.deniedForever) {
      return;
    }
  }

  Timer.periodic(const Duration(seconds: 10), (timer) async {
    try {
      geo.Position position = await geo.Geolocator.getCurrentPosition(
          desiredAccuracy: geo.LocationAccuracy.high);

      const String apiUrl =
          "http://192.168.3.159:8000/usuarios/actualizar_ubicacion/";

      await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'usuario_id': userId > 0 ? userId : 1,
          'latitud': position.latitude,
          'longitud': position.longitude,
        }),
      );
      debugPrint("✅ Ubicación enviada: (${position.latitude}, ${position.longitude})");
    } catch (e) {
      debugPrint("⚠️ Error enviando ubicación: $e");
    }
  });
}
