import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'dart:html' as html;
import 'config/supabase_config.dart';
import 'screens/auth/login_screen.dart';
import 'screens/calendar/calendar_dashboard.dart';

void main() async {
  // Assicura l'inizializzazione dei binding Flutter
  WidgetsFlutterBinding.ensureInitialized();

  // Inizializza la localizzazione italiana
  await initializeDateFormatting('it_IT', null);
  Intl.defaultLocale = 'it_IT';

  // Inizializza Supabase
  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    anonKey: SupabaseConfig.supabaseAnonKey,
  );

  runApp(const MyApp());
}

// Ottieni l'istanza di Supabase
final supabase = Supabase.instance.client;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Segretaria Virtuale',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
      debugShowCheckedModeBanner: false,
      locale: const Locale('it', 'IT'),
      supportedLocales: const [
        Locale('it', 'IT'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}

// Widget che gestisce lo stato di autenticazione
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  User? _user;
  bool _shouldNavigateToCalendar = false;

  @override
  void initState() {
    super.initState();
    _checkNavigationState();
    _getInitialSession();
    _listenToAuthChanges();
  }

  // Controlla lo stato di navigazione da localStorage
  void _checkNavigationState() {
    if (kIsWeb) {
      // Controlla localStorage per vedere se dobbiamo navigare al calendar
      final shouldRedirect = html.window.localStorage['oauth_redirect_to_calendar'];
      if (shouldRedirect == 'true') {
        _shouldNavigateToCalendar = true;
        // Pulisci il flag
        html.window.localStorage.remove('oauth_redirect_to_calendar');

        // Se c'è un callback URL salvato, gestiscilo
        final callbackUrl = html.window.localStorage['oauth_callback_url'];
        if (callbackUrl != null) {
          html.window.localStorage.remove('oauth_callback_url');
          // Puoi processare il callback URL se necessario
        }
      }
    }
  }

  // Ottieni la sessione iniziale
  Future<void> _getInitialSession() async {
    final session = supabase.auth.currentSession;
    setState(() {
      _user = session?.user;
    });
  }

  // Ascolta i cambiamenti di autenticazione
  void _listenToAuthChanges() {
    supabase.auth.onAuthStateChange.listen((data) {
      if (mounted) {
        setState(() {
          _user = data.session?.user;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Se l'utente è autenticato
    if (_user != null) {
      if (_shouldNavigateToCalendar) {
        // Naviga al calendar dopo il build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const CalendarDashboard(),
              settings: const RouteSettings(arguments: {'fromOAuth': true}),
            ),
          );
        });
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      }
      return const HomePage();
    }
    return const LoginScreen();
  }
}

// Schermata principale per utenti autenticati
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isConnected = false;
  String _connectionMessage = 'Verificando connessione...';
  List<String> _tablesFound = [];
  User? _currentUser;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentUser = supabase.auth.currentUser;
    _checkConnection();
  }

  // Verifica la connessione e le tabelle create
  Future<void> _checkConnection() async {
    List<String> tablesFound = [];

    try {
      // Test delle tabelle principali
      final tables = ['profiles', 'appuntamenti', 'note', 'contatti', 'conversazioni'];

      for (String table in tables) {
        try {
          await supabase.from(table).select('*').limit(1);
          tablesFound.add('✅ $table');
        } catch (e) {
          // Anche se c'è un errore (es. RLS), la tabella esiste
          if (e.toString().contains('row-level security') ||
              e.toString().contains('permission denied') ||
              e.toString().contains('JWT')) {
            tablesFound.add('✅ $table (protetta)');
          } else {
            tablesFound.add('❌ $table');
          }
        }
      }

      setState(() {
        _isConnected = true;
        _tablesFound = tablesFound;
        _connectionMessage = 'Database configurato e utente autenticato!';
      });
    } catch (e) {
      setState(() {
        _isConnected = false;
        _connectionMessage = 'Errore di connessione: ${e.toString()}';
      });
    }
  }

  // Logout dell'utente
  Future<void> _signOut() async {
    try {
      await supabase.auth.signOut();

      // Pulisci anche eventuali token OAuth salvati
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('outlook_access_token');
      await prefs.remove('outlook_refresh_token');
      await prefs.remove('outlook_login_from_calendar');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Logout effettuato con successo!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore durante il logout: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onItemTapped(int index) {
    if (index == 2) { // Calendar
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const CalendarDashboard(),
          settings: const RouteSettings(arguments: {'fromHome': true}),
        ),
      );
    } else {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Segretaria Virtuale'),
        centerTitle: true,
        actions: [
          // Menu utente
          PopupMenuButton<String>(
            icon: CircleAvatar(
              backgroundColor: Colors.blue.shade100,
              child: Text(
                _currentUser?.email?.substring(0, 1).toUpperCase() ?? 'U',
                style: TextStyle(
                  color: Colors.blue.shade700,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            onSelected: (value) {
              if (value == 'logout') {
                _signOut();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Benvenuto!',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    Text(
                      _currentUser?.email ?? 'Utente',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Logout'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.note),
            label: 'Note',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: 'Calendar',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.contacts),
            label: 'Contatti',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        onTap: _onItemTapped,
      ),
    );
  }

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0:
        return _buildHomeContent();
      case 1:
        return const Center(child: Text('Note - In costruzione'));
      case 3:
        return const Center(child: Text('Contatti - In costruzione'));
      default:
        return _buildHomeContent();
    }
  }

  Widget _buildHomeContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: <Widget>[
          const SizedBox(height: 20),
          const Icon(
            Icons.assistant,
            size: 80,
            color: Colors.blue,
          ),
          const SizedBox(height: 20),
          const Text(
            'Segretaria Virtuale App',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'La tua assistente personale',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 30),

          // Card con informazioni utente
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.person, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text(
                        'Utente Autenticato',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Email: ${_currentUser?.email ?? 'N/A'}'),
                  Text('ID: ${_currentUser?.id.substring(0, 8) ?? 'N/A'}...'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Card con stato connessione
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _isConnected ? Icons.cloud_done : Icons.cloud_off,
                        color: _isConnected ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _connectionMessage,
                          style: TextStyle(
                            color: _isConnected ? Colors.green : Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),

                  if (_tablesFound.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Tabelle Database:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._tablesFound.map((table) => Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: Text(
                        table,
                        style: const TextStyle(fontSize: 14),
                      ),
                    )),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 30),

          // Pulsanti di azione
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                onPressed: _checkConnection,
                icon: const Icon(Icons.refresh),
                label: const Text('Ricontrolla'),
              ),
              ElevatedButton.icon(
                onPressed: _isConnected
                    ? () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const CalendarDashboard()),
                  );
                }
                    : null,
                icon: const Icon(Icons.calendar_today),
                label: const Text('Calendar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}