// lib/screens/calendar/calendar_dashboard.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart' as google_calendar;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:html' as html;

// IMPORT CORRETTI
import '../../services/google_calendar_service.dart';
import '../../services/outlook_calendar_service.dart';
import '../../services/ai/command_service.dart';
import '../../services/calendar/free_slots_analyzer.dart';
import '../../widgets/voice_input_widget.dart';
import '../../widgets/date_navigation_widget.dart';
import '../../main.dart'; // Per HomePage
// Percorsi corretti per i widget e utils:
import '../../widgets/free_slots_analyzer_widget.dart';
import '../../widgets/floating_summary_widget.dart';
import '../../widgets/ai_assistant_widget.dart';
import '../../utils/web_utils.dart' // Corretto: ../../utils/
if (dart.library.html) '../../utils/web_utils_web.dart'; // Corretto: ../../utils/

class CalendarDashboard extends StatefulWidget {
  const CalendarDashboard({super.key});

  @override
  State<CalendarDashboard> createState() => _CalendarDashboardState();
}

class _CalendarDashboardState extends State<CalendarDashboard> {
  final GoogleCalendarService _googleCalendarService = GoogleCalendarService();
  final OutlookCalendarService _outlookCalendarService = OutlookCalendarService();
  late final FreeSlotsAnalyzer _slotsAnalyzer;

  bool _isLoading = false;
  bool _isGoogleSignedIn = false;
  bool _isOutlookSignedIn = false;

  // Eventi combinati
  List<CalendarEventWrapper> _todayEvents = [];
  List<CalendarEventWrapper> _weekEvents = [];
  Map<String, dynamic> _weeklyStats = {};

  // Nuove variabili per AI
  List<FreeSlot> _freeSlots = [];
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _googleCalendarService.initialize();
    _slotsAnalyzer = FreeSlotsAnalyzer(_googleCalendarService, _outlookCalendarService);
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    setState(() => _isLoading = true);

    try {
      // Prima controlla se c'è un callback OAuth in corso (solo per web)
      if (kIsWeb) {
        final hasCallback = await _outlookCalendarService.handleWebCallback();
        if (hasCallback) {
          print('Outlook login completato tramite callback');
        }
      }

      // Inizializza i servizi
      await _outlookCalendarService.initialize();

      // IMPORTANTE: Usa hasValidToken invece di isSignedIn per Outlook
      setState(() {
        _isGoogleSignedIn = _googleCalendarService.isSignedIn;
        _isOutlookSignedIn = _outlookCalendarService.hasValidToken;
      });

      print('Google signed in: $_isGoogleSignedIn');
      print('Outlook signed in: $_isOutlookSignedIn');

      // Se almeno un servizio è connesso, carica i dati
      if (_isGoogleSignedIn || _isOutlookSignedIn) {
        await _loadCalendarData();
      }
    } catch (e) {
      print('Errore inizializzazione servizi: $e');
      _showError('Errore durante l\'inizializzazione: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signInToGoogle() async {
    setState(() => _isLoading = true);

    try {
      final bool success = await _googleCalendarService.signIn();
      if (mounted && success) {
        setState(() => _isGoogleSignedIn = true);
        await _loadCalendarData();

        // Se entrambi sono connessi, mostra messaggio di successo
        if (_isGoogleSignedIn && _isOutlookSignedIn) {
          _showSuccess('Tutti i calendari sono ora sincronizzati!');
        }
      } else {
        _showError('Impossibile accedere a Google Calendar');
      }
    } catch (e) {
      _showError('Errore durante l\'accesso Google: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signInToOutlook() async {
    setState(() => _isLoading = true);

    try {
      final bool success = await _outlookCalendarService.signIn();
      if (mounted && success) {
        setState(() => _isOutlookSignedIn = true);
        await _loadCalendarData();

        // Se entrambi sono connessi, mostra messaggio di successo
        if (_isGoogleSignedIn && _isOutlookSignedIn) {
          _showSuccess('Tutti i calendari sono ora sincronizzati!');
        }
      } else {
        _showError('Impossibile accedere a Outlook Calendar. Verifica la configurazione.');
      }
    } catch (e) {
      _showError('Errore durante l\'accesso Outlook: $e');
      print('Errore dettagliato Outlook: $e'); // Per debug
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _connectAllCalendars() async {
    setState(() => _isLoading = true);

    try {
      bool allSuccess = true;

      // Prova a connettere Google se non connesso
      if (!_isGoogleSignedIn) {
        final googleSuccess = await _googleCalendarService.signIn();
        if (googleSuccess) {
          setState(() => _isGoogleSignedIn = true);
        } else {
          allSuccess = false;
        }
      }

      // Prova a connettere Outlook se non connesso
      if (!_isOutlookSignedIn) {
        // Su web, salva che stiamo facendo login dal calendar
        if (kIsWeb) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('outlook_login_from_calendar', true);
        }

        final outlookSuccess = await _outlookCalendarService.signIn();
        if (outlookSuccess) {
          setState(() => _isOutlookSignedIn = true);
        } else {
          allSuccess = false;
        }
      }

      // Carica i dati se almeno uno è connesso
      if (_isGoogleSignedIn || _isOutlookSignedIn) {
        await _loadCalendarData();

        if (allSuccess && _isGoogleSignedIn && _isOutlookSignedIn) {
          _showSuccess('Tutti i calendari sono stati sincronizzati con successo!');
        } else if (_isGoogleSignedIn || _isOutlookSignedIn) {
          _showInfo('Alcuni calendari sono stati connessi. Controlla gli account non connessi.');
        }
      } else {
        _showError('Impossibile connettere i calendari. Riprova.');
      }
    } catch (e) {
      _showError('Errore durante la connessione: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadCalendarData() async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      List<CalendarEventWrapper> todayEvents = [];
      List<CalendarEventWrapper> weekEvents = [];

      print('Caricamento eventi per data: $_selectedDate');

      // Carica eventi Google
      if (_isGoogleSignedIn) {
        try {
          print('Caricamento eventi Google...');
          final googleTodayEvents = await _googleCalendarService.getEventsForDate(_selectedDate);
          final googleWeekEvents = await _googleCalendarService.getWeekEvents();

          print('Eventi Google oggi: ${googleTodayEvents.length}');
          print('Eventi Google settimana: ${googleWeekEvents.length}');

          todayEvents.addAll(
            googleTodayEvents.map((e) => CalendarEventWrapper(
              source: CalendarSource.google,
              googleEvent: e,
            )),
          );

          weekEvents.addAll(
            googleWeekEvents.map((e) => CalendarEventWrapper(
              source: CalendarSource.google,
              googleEvent: e,
            )),
          );
        } catch (e) {
          print('Errore caricamento eventi Google: $e');
        }
      }

      // Carica eventi Outlook
      if (_isOutlookSignedIn) {
        try {
          print('Caricamento eventi Outlook...');
          final outlookTodayEvents = await _outlookCalendarService.getEventsForDate(_selectedDate);
          final outlookWeekEvents = await _outlookCalendarService.getWeekEvents();

          print('Eventi Outlook oggi: ${outlookTodayEvents.length}');
          print('Eventi Outlook settimana: ${outlookWeekEvents.length}');

          todayEvents.addAll(
            outlookTodayEvents.map((e) => CalendarEventWrapper(
              source: CalendarSource.outlook,
              outlookEvent: e,
            )),
          );

          weekEvents.addAll(
            outlookWeekEvents.map((e) => CalendarEventWrapper(
              source: CalendarSource.outlook,
              outlookEvent: e,
            )),
          );
        } catch (e) {
          print('Errore caricamento eventi Outlook: $e');
          // Se l'errore è 401, disconnetti Outlook
          if (e.toString().contains('401')) {
            setState(() => _isOutlookSignedIn = false);
            _showError('Sessione Outlook scaduta. Riconnettiti.');
          }
        }
      }

      // Ordina eventi per orario
      todayEvents.sort((a, b) => a.startTime.compareTo(b.startTime));
      weekEvents.sort((a, b) => a.startTime.compareTo(b.startTime));

      print('Totale eventi oggi: ${todayEvents.length}');
      print('Totale eventi settimana: ${weekEvents.length}');

      // Debug eventi
      for (var event in todayEvents) {
        print(event.debugInfo);
      }

      // Calcola statistiche
      double totalHours = 0;
      for (var event in weekEvents) {
        totalHours += event.duration.inMinutes / 60.0;
      }

      // Analizza slot liberi
      try {
        await _analyzeFreeSlots();
      } catch (e) {
        print('Errore analisi slot: $e');
      }

      if (mounted) {
        setState(() {
          _todayEvents = todayEvents;
          _weekEvents = weekEvents;
          _weeklyStats = {
            'totalEvents': weekEvents.length,
            'totalHours': totalHours.toStringAsFixed(1),
          };
        });
      }
    } catch (e) {
      print('Errore nel caricamento dei dati: $e');
      _showError('Errore nel caricamento dei dati: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _analyzeFreeSlots() async {
    try {
      final slots = await _slotsAnalyzer.findFreeSlots(
        date: _selectedDate,
        minDuration: const Duration(minutes: 30),
      );
      setState(() => _freeSlots = slots);
    } catch (e) {
      print('Errore analisi slot: $e');
    }
  }

  void _onDateChanged(DateTime newDate) {
    setState(() {
      _selectedDate = newDate;
    });
    _loadCalendarData();
  }

  void _handleCommand(ParsedCommand command) async {
    // Se il comando ha una data specifica, aggiorna la data selezionata
    if (command.parameters['date'] != null) {
      setState(() {
        _selectedDate = command.parameters['date'] as DateTime;
      });
      await _loadCalendarData(); // Ricarica i dati per la nuova data
    }

    switch (command.type) {
      case CommandType.showFreeSlots:
        await _analyzeFreeSlots();
        _showFreeSlotsDialog();
        break;

      case CommandType.dailySummary:
        _showDailySummary();
        break;

      case CommandType.workloadAnalysis:
        _showWorkloadAnalysis();
        break;

      default:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Comando non ancora implementato')),
        );
    }
  }

  void _showFreeSlotsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Slot liberi - ${_formatDate(_selectedDate)}'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListView.builder(
            itemCount: _freeSlots.length,
            itemBuilder: (context, index) {
              final slot = _freeSlots[index];
              return Card(
                color: slot.isHighEnergy
                    ? Colors.green[50]
                    : slot.isMediumEnergy
                    ? Colors.orange[50]
                    : Colors.red[50],
                child: ListTile(
                  leading: Icon(
                    Icons.access_time,
                    color: slot.isHighEnergy
                        ? Colors.green
                        : slot.isMediumEnergy
                        ? Colors.orange
                        : Colors.red,
                  ),
                  title: Text(
                    '${_formatTime(slot.start)} - ${_formatTime(slot.end)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Durata: ${_formatDuration(slot.duration)}'),
                      Text(
                        slot.suggestion,
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: slot.isHighEnergy
                          ? Colors.green
                          : slot.isMediumEnergy
                          ? Colors.orange
                          : Colors.red,
                    ),
                    child: Text(
                      '${(slot.energyScore * 100).toInt()}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Chiudi'),
          ),
        ],
      ),
    );
  }

  void _showDailySummary() async {
    final workload = await _slotsAnalyzer.analyzeWeeklyWorkload();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Riepilogo Giornaliero'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📅 ${_formatDate(_selectedDate)}'),
            const SizedBox(height: 16),
            Text('Eventi oggi: ${_getTodayEventsCount()}'),
            Text('Slot liberi: ${_freeSlots.length}'),
            Text('Tempo libero totale: ${_getTotalFreeTime()}'),
            const Divider(),
            Text('Media settimanale: ${workload['averageDailyMeetings']?.toStringAsFixed(1) ?? "0"} ore/giorno'),
            if (workload['suggestedBreaks'] != null &&
                (workload['suggestedBreaks'] as List).isNotEmpty)
              ...((workload['suggestedBreaks'] as List).map((s) =>
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('💡 $s', style: TextStyle(color: Colors.orange[700])),
                  )
              )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showWorkloadAnalysis() async {
    setState(() => _isLoading = true);

    try {
      final analysis = await _slotsAnalyzer.analyzeWeeklyWorkload();

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Analisi Carico di Lavoro'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('📊 Ore meeting questa settimana: ${analysis['totalMeetingHours']?.toStringAsFixed(1)}'),
              Text('📈 Media giornaliera: ${analysis['averageDailyMeetings']?.toStringAsFixed(1)} ore'),
              Text('🔥 Giorno più impegnato: ${analysis['busiestDay']}'),
              Text('😌 Giorno più leggero: ${analysis['lightestDay']}'),
              const Divider(),
              if (analysis['suggestedBreaks'] != null)
                ...((analysis['suggestedBreaks'] as List).map((s) =>
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('💡 $s', style: TextStyle(color: Colors.blue[700])),
                    )
                )),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Chiudi'),
            ),
          ],
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Helper methods
  int _getTodayEventsCount() {
    return _todayEvents.length;
  }

  String _getTotalFreeTime() {
    if (_freeSlots.isEmpty) return '0 ore';

    final totalMinutes = _freeSlots.fold(
        0,
            (sum, slot) => sum + slot.duration.inMinutes
    );

    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;

    if (hours > 0 && minutes > 0) {
      return '$hours ore e $minutes minuti';
    } else if (hours > 0) {
      return '$hours ore';
    } else {
      return '$minutes minuti';
    }
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;

    if (hours > 0 && minutes > 0) {
      return '$hours h $minutes min';
    } else if (hours > 0) {
      return '$hours ore';
    } else {
      return '$minutes minuti';
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _showSuccess(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showInfo(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  String _formatDate(DateTime date) {
    try {
      return DateFormat('EEEE, dd MMMM yyyy', 'it_IT').format(date);
    } catch (e) {
      try {
        final formatter = DateFormat('EEEE, dd MMMM yyyy');
        return formatter.format(date);
      } catch (e) {
        return '${date.day}/${date.month}/${date.year}';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Controlla se siamo arrivati dalla HomePage
    final bool fromHome = (ModalRoute.of(context)?.settings.arguments as Map?)?['fromHome'] ?? false;

    return WillPopScope(
      onWillPop: () async {
        if (fromHome) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const HomePage()),
          );
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Calendar Dashboard'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          leading: fromHome ? IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const HomePage()),
              );
            },
          ) : null,
          actions: [
            if (_isGoogleSignedIn || _isOutlookSignedIn) ...[
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _isLoading ? null : _loadCalendarData,
                tooltip: 'Aggiorna',
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (value) async {
                  switch (value) {
                    case 'google_logout':
                      await _googleCalendarService.signOut();
                      setState(() => _isGoogleSignedIn = false);
                      _loadCalendarData();
                      break;
                    case 'outlook_logout':
                      await _outlookCalendarService.signOut();
                      setState(() => _isOutlookSignedIn = false);
                      _loadCalendarData();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  if (_isGoogleSignedIn)
                    const PopupMenuItem(
                      value: 'google_logout',
                      child: Text('Disconnetti Google'),
                    ),
                  if (_isOutlookSignedIn)
                    const PopupMenuItem(
                      value: 'outlook_logout',
                      child: Text('Disconnetti Outlook'),
                    ),
                ],
              ),
            ],
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : (!_isGoogleSignedIn && !_isOutlookSignedIn)
            ? _buildSignInPrompt()
            : _buildDashboard(),
      ),
    );
  }

  Widget _buildSignInPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.calendar_today,
              size: 100,
              color: Colors.blue,
            ),
            const SizedBox(height: 24),
            const Text(
              'Connetti i tuoi Calendari',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Accedi ai tuoi account per sincronizzare i calendari e visualizzare tutti i tuoi appuntamenti in un unico posto.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 32),

            // Pulsante per connettere tutti i calendari
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _connectAllCalendars,
              icon: const Icon(Icons.sync),
              label: const Text('Connetti Tutti i Calendari'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),

            const SizedBox(height: 24),
            const Text(
              'oppure connetti singolarmente:',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),

            // Google Sign In
            if (!_isGoogleSignedIn)
              OutlinedButton.icon(
                onPressed: _isLoading ? null : _signInToGoogle,
                icon: const Icon(Icons.g_mobiledata),
                label: const Text('Google Calendar'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),

            if (!_isGoogleSignedIn && !_isOutlookSignedIn)
              const SizedBox(height: 12),

            // Outlook Sign In
            if (!_isOutlookSignedIn)
              OutlinedButton.icon(
                onPressed: _isLoading ? null : _signInToOutlook,
                icon: const Icon(Icons.mail_outline),
                label: const Text('Outlook Calendar'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0078D4),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboard() {
    return RefreshIndicator(
      onRefresh: _loadCalendarData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Voice Input Widget
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              child: VoiceInputWidget(
                onCommandReceived: _handleCommand,
              ),
            ),
            // Date Navigation Widget
            DateNavigationWidget(
              selectedDate: _selectedDate,
              onDateChanged: _onDateChanged,
            ),
            const SizedBox(height: 16),
            _buildWelcomeCard(),
            const SizedBox(height: 16),
            _buildConnectedAccountsCard(),
            const SizedBox(height: 16),
            _buildStatsCards(),
            const SizedBox(height: 16),
            _buildTodayEvents(),
            const SizedBox(height: 16),
            _buildWeekOverview(),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeCard() {
    String userName = 'Utente';
    String? photoUrl;

    if (_isGoogleSignedIn && _googleCalendarService.currentUser != null) {
      userName = _googleCalendarService.currentUser!.displayName ?? userName;
      photoUrl = _googleCalendarService.currentUser!.photoUrl;
    } else if (_isOutlookSignedIn && _outlookCalendarService.currentUser != null) {
      userName = _outlookCalendarService.currentUser!['displayName'] ?? userName;
    }

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
              child: photoUrl == null
                  ? Text(
                userName.substring(0, 1).toUpperCase(),
                style: const TextStyle(fontSize: 20),
              )
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Benvenuto, $userName!',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _formatDate(DateTime.now()),
                    style: TextStyle(
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectedAccountsCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Account Connessi',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            // Google Account
            Row(
              children: [
                const Icon(Icons.g_mobiledata, color: Colors.blue),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _isGoogleSignedIn
                        ? _googleCalendarService.currentUser?.email ?? 'Google Calendar'
                        : 'Non connesso',
                    style: TextStyle(
                      color: _isGoogleSignedIn ? Colors.green : Colors.grey,
                    ),
                  ),
                ),
                if (!_isGoogleSignedIn)
                  TextButton(
                    onPressed: _signInToGoogle,
                    child: const Text('Connetti'),
                  ),
              ],
            ),

            const SizedBox(height: 8),

            // Outlook Account
            Row(
              children: [
                const Icon(Icons.mail_outline, color: Color(0xFF0078D4)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _isOutlookSignedIn
                        ? (_outlookCalendarService.currentUser?['mail'] ?? 'Outlook Calendar')
                        : 'Non connesso',
                    style: TextStyle(
                      color: _isOutlookSignedIn ? Colors.green : Colors.grey,
                    ),
                  ),
                ),
                if (!_isOutlookSignedIn)
                  TextButton(
                    onPressed: _signInToOutlook,
                    child: const Text('Connetti'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCards() {
    if (_weeklyStats.isEmpty) return const SizedBox.shrink();

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Eventi Oggi',
            _todayEvents.length.toString(),
            Icons.today,
            Colors.blue,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'Questa Settimana',
            _weeklyStats['totalEvents']?.toString() ?? '0',
            Icons.calendar_view_week,
            Colors.green,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'Ore Totali',
            _weeklyStats['totalHours']?.toString() ?? '0',
            Icons.access_time,
            Colors.orange,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTodayEvents() {
    final isToday = _selectedDate.day == DateTime.now().day &&
        _selectedDate.month == DateTime.now().month &&
        _selectedDate.year == DateTime.now().year;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isToday ? 'Eventi di Oggi' : 'Eventi del ${_formatDate(_selectedDate)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_todayEvents.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_todayEvents.length}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_todayEvents.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 32),
                alignment: Alignment.center,
                child: Column(
                  children: [
                    Icon(Icons.event_available, color: Colors.grey.shade400, size: 48),
                    const SizedBox(height: 8),
                    Text(
                      isToday ? 'Nessun evento programmato per oggi' : 'Nessun evento per questa data',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _todayEvents.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) => _buildEventTile(_todayEvents[index]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeekOverview() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Panoramica Settimanale',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_weekEvents.length > 5)
                  TextButton(
                    onPressed: () {
                      // TODO: Navigare alla vista completa degli eventi
                    },
                    child: const Text('Vedi tutti'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_weekEvents.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 32),
                alignment: Alignment.center,
                child: Column(
                  children: [
                    Icon(Icons.event_busy, color: Colors.grey.shade400, size: 48),
                    const SizedBox(height: 8),
                    Text(
                      'Nessun evento questa settimana',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _weekEvents.length > 5 ? 5 : _weekEvents.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) => _buildEventTile(_weekEvents[index]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventTile(CalendarEventWrapper event) {
    final bool isPastEvent = event.endTime.isBefore(DateTime.now());
    final bool isOngoing = event.startTime.isBefore(DateTime.now()) && event.endTime.isAfter(DateTime.now());

    return Material(
      color: Colors.transparent,
      child: Opacity(
        opacity: isPastEvent ? 0.5 : 1.0, // Trasparenza per eventi passati
        child: InkWell(
          onTap: isPastEvent ? null : () => _showEventDetails(event),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isPastEvent ? Colors.grey.shade100 : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isPastEvent ? Colors.grey.shade300 : Colors.grey.shade200,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isPastEvent
                        ? Colors.grey
                        : isOngoing
                        ? Colors.green
                        : event.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              event.title,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: isPastEvent ? Colors.grey : null,
                                decoration: isPastEvent ? TextDecoration.lineThrough : null,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (isOngoing)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'In corso',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          const SizedBox(width: 4),
                          Icon(
                            event.source == CalendarSource.google
                                ? Icons.g_mobiledata
                                : Icons.mail_outline,
                            size: 16,
                            color: isPastEvent ? Colors.grey.shade400 : Colors.grey,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            event.isAllDay ? Icons.wb_sunny : Icons.access_time,
                            size: 14,
                            color: isPastEvent ? Colors.grey.shade400 : Colors.grey.shade600,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            event.timeText,
                            style: TextStyle(
                              color: isPastEvent ? Colors.grey.shade400 : Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                          if (event.location != null) ...[
                            const SizedBox(width: 12),
                            Icon(
                              Icons.location_on,
                              size: 14,
                              color: isPastEvent ? Colors.grey.shade400 : Colors.grey.shade600,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                event.location!,
                                style: TextStyle(
                                  color: isPastEvent ? Colors.grey.shade400 : Colors.grey.shade600,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showEventDetails(CalendarEventWrapper event) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(event.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  event.source == CalendarSource.google
                      ? Icons.g_mobiledata
                      : Icons.mail_outline,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  event.source == CalendarSource.google ? 'Google Calendar' : 'Outlook Calendar',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (event.location != null) ...[
              const Text(
                'Luogo:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(event.location!),
              const SizedBox(height: 12),
            ],
            const Text(
              'Orario:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(event.getEventTimeString()),
            if (event.description != null && event.description!.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Descrizione:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Text(event.description!),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Chiudi'),
          ),
        ],
      ),
    );
  }
}

// Wrapper per gestire eventi da fonti diverse
enum CalendarSource { google, outlook }

class CalendarEventWrapper {
  final CalendarSource source;
  final google_calendar.Event? googleEvent;
  final OutlookEvent? outlookEvent;

  CalendarEventWrapper({
    required this.source,
    this.googleEvent,
    this.outlookEvent,
  });

  String get title {
    if (source == CalendarSource.google) {
      return googleEvent?.summary ?? 'Evento senza titolo';
    } else {
      return outlookEvent?.subject ?? 'Evento senza titolo';
    }
  }

  DateTime get startTime {
    if (source == CalendarSource.google) {
      // Google può avere dateTime o date
      final dateTime = googleEvent?.start?.dateTime;
      final date = googleEvent?.start?.date;

      if (dateTime != null) {
        return dateTime.toLocal();
      } else if (date != null) {
        // Eventi tutto il giorno - assicurati che sia nella timezone locale
        return DateTime.parse(date.toString()).toLocal();
      }

      print('WARN: Evento Google senza data di inizio');
      return DateTime.now();
    } else {
      // Outlook
      final start = outlookEvent?.start;
      if (start != null) {
        return start.toLocal();
      }

      print('WARN: Evento Outlook senza data di inizio');
      return DateTime.now();
    }
  }

  DateTime get endTime {
    if (source == CalendarSource.google) {
      final dateTime = googleEvent?.end?.dateTime;
      final date = googleEvent?.end?.date;

      if (dateTime != null) {
        return dateTime.toLocal();
      } else if (date != null) {
        return DateTime.parse(date.toString()).toLocal();
      }

      return DateTime.now();
    } else {
      final end = outlookEvent?.end;
      if (end != null) {
        return end.toLocal();
      }

      return DateTime.now();
    }
  }

  Duration get duration => endTime.difference(startTime);

  bool get isAllDay {
    if (source == CalendarSource.google) {
      return googleEvent?.start?.dateTime == null;
    } else {
      return outlookEvent?.isAllDay ?? false;
    }
  }

  String? get location {
    if (source == CalendarSource.google) {
      return googleEvent?.location;
    } else {
      return outlookEvent?.location;
    }
  }

  String? get description {
    if (source == CalendarSource.google) {
      return googleEvent?.description;
    } else {
      return outlookEvent?.bodyPreview ?? outlookEvent?.body;
    }
  }

  String get timeText {
    if (isAllDay) return 'Tutto il giorno';

    String start = DateFormat('HH:mm').format(startTime);
    String end = DateFormat('HH:mm').format(endTime);

    return '$start - $end';
  }

  String getEventTimeString() {
    if (isAllDay) {
      return 'Tutto il giorno';
    }

    String result = DateFormat('dd/MM/yyyy HH:mm').format(startTime);
    result += ' - ${DateFormat('HH:mm').format(endTime)}';

    return result;
  }

  String get debugInfo {
    return 'Event: $title, Start: ${startTime.toString()}, End: ${endTime.toString()}, Source: $source';
  }

  Color get color {
    if (source == CalendarSource.google) {
      // Usa i colori di Google Calendar
      switch (googleEvent?.colorId) {
        case '1': return Colors.blue;
        case '2': return Colors.green;
        case '3': return Colors.purple;
        case '4': return Colors.red;
        case '5': return Colors.yellow.shade700;
        case '6': return Colors.orange;
        case '7': return Colors.cyan;
        case '8': return Colors.grey;
        case '9': return Colors.blue.shade900;
        case '10': return Colors.green.shade900;
        case '11': return Colors.red.shade900;
        default: return Colors.blue;
      }
    } else {
      // Colori per categorie Outlook
      if (outlookEvent?.categories.isNotEmpty ?? false) {
        // Puoi personalizzare i colori in base alle categorie
        return const Color(0xFF0078D4);
      }
      return const Color(0xFF0078D4);
    }
  }
}