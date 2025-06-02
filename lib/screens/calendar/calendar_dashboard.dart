// lib/screens/calendar/calendar_dashboard.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart' as google_calendar;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

// IMPORT CORRETTI
import '../../services/google_calendar_service.dart';
import '../../services/outlook_calendar_service.dart';
import '../../services/ai/command_service.dart';
import '../../services/ai/ai_assistant_service.dart'; // Per AIAction
import '../../services/calendar/free_slots_analyzer.dart';
import '../../widgets/voice_input_widget.dart';
import '../../widgets/date_navigation_widget.dart';
import '../../widgets/pause_reminder_widget.dart';
import '../../main.dart'; // Per HomePage

// Import condizionale per web
import '../../utils/web_utils.dart'
if (dart.library.html) '../../utils/web_utils_web.dart';

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

  // Variabili per il sistema di pausa
  bool _shouldShowPauseReminder = false;
  int _minutesWorkedWithoutBreak = 0;
  Timer? _workTimeTracker;

  @override
  void initState() {
    super.initState();
    _googleCalendarService.initialize();
    _slotsAnalyzer = FreeSlotsAnalyzer(_googleCalendarService, _outlookCalendarService);
    _initializeServices();
    _startWorkTimeTracking();
  }

  void _startWorkTimeTracking() {
    _workTimeTracker = Timer.periodic(const Duration(minutes: 1), (timer) {
      setState(() {
        _minutesWorkedWithoutBreak++;

        // Mostra reminder ogni 90 minuti
        if (_minutesWorkedWithoutBreak >= 90 && !_shouldShowPauseReminder) {
          _shouldShowPauseReminder = true;
        }
      });
    });
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
              outlookEvent: {
                'id': e.id,
                'subject': e.subject,
                'start': {
                  'dateTime': e.start?.toIso8601String(),
                },
                'end': {
                  'dateTime': e.end?.toIso8601String(),
                },
                'location': {
                  'displayName': e.location,
                },
                'body': {
                  'content': e.body,
                },
                'bodyPreview': e.bodyPreview,
                'isAllDay': e.isAllDay,
                'attendees': [],
              },
            )),
          );

          weekEvents.addAll(
            outlookWeekEvents.map((e) => CalendarEventWrapper(
              source: CalendarSource.outlook,
              outlookEvent: {
                'id': e.id,
                'subject': e.subject,
                'start': {
                  'dateTime': e.start?.toIso8601String(),
                },
                'end': {
                  'dateTime': e.end?.toIso8601String(),
                },
                'location': {
                  'displayName': e.location,
                },
                'body': {
                  'content': e.body,
                },
                'bodyPreview': e.bodyPreview,
                'isAllDay': e.isAllDay,
                'attendees': [],
              },
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
    // DEBUG: Log del comando ricevuto
    print('=== CALENDAR DASHBOARD - COMANDO RICEVUTO ===');
    print('Tipo comando: ${command.type}');
    print('Parametri: ${command.parameters}');

    // Controlla se c'è un suggerimento pausa nei parametri
    if (command.parameters['shouldShowPauseReminder'] == true &&
        command.type != CommandType.pauseReminder) {
      // Mostra il reminder non invasivo
      setState(() {
        _shouldShowPauseReminder = true;
      });
    }

    // Se il comando ha una data specifica, aggiorna la data selezionata
    if (command.parameters['date'] != null) {
      setState(() {
        _selectedDate = command.parameters['date'] as DateTime;
      });
      await _loadCalendarData(); // Ricarica i dati per la nuova data
    }

    // Mostra feedback immediato
    _showProcessingCommand(command);

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

      case CommandType.scheduleEvent:
        _handleScheduleEvent(command);
        break;

      case CommandType.createReminder:
        _handleCreateReminder(command);
        break;

      case CommandType.blockTime:
        _handleBlockTime(command);
        break;

      case CommandType.delegateTask:
        _handleDelegateTask(command);
        break;

      case CommandType.pauseReminder:
        _showPauseDialog();
        break;

      case CommandType.cancelEvent:
        _handleCancelEvent(command);
        break;

      case CommandType.rescheduleEvent:
        _handleRescheduleEvent(command);
        break;

      case CommandType.emailSuggestions:
        _handleEmailSuggestions(command);
        break;

      case CommandType.contactReminder:
        _handleContactReminder(command);
        break;

      case CommandType.multiCommand:
        _handleMultiCommand(command);
        break;

      case CommandType.unknown:
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Non ho capito il comando. Prova a riformulare.'),
            backgroundColor: Colors.orange,
          ),
        );
    }
  }

  void _showPauseDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.pause, color: Colors.orange),
            SizedBox(width: 8),
            Text('È ora di una pausa!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Hai lavorato per più di 90 minuti consecutivi. '
                  'Ti consiglio di fare una pausa di 10-15 minuti per ricaricarti.',
            ),
            const SizedBox(height: 16),
            const Text(
              'Vuoi che programmi una pausa ora?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Dopo'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.coffee),
            label: const Text('Sì, programma pausa'),
            onPressed: () {
              Navigator.of(context).pop();
              _schedulePause();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
          ),
        ],
      ),
    );
  }

  void _schedulePause() async {
    // Crea evento pausa nel calendario
    try {
      final now = DateTime.now();
      final pauseEnd = now.add(const Duration(minutes: 15));

      await _googleCalendarService.createEvent(
        summary: '☕ Pausa',
        description: 'Momento di relax e ricarica',
        startTime: now,
        endTime: pauseEnd,
      );

      // Reset timer
      setState(() {
        _minutesWorkedWithoutBreak = 0;
        _shouldShowPauseReminder = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pausa programmata! Goditi il tuo momento di relax 😊'),
          backgroundColor: Colors.green,
        ),
      );

      // Ricarica eventi
      await _loadCalendarData();
    } catch (e) {
      print('Errore creazione pausa: $e');
    }
  }

  // Mostra che stiamo processando un comando
  void _showProcessingCommand(ParsedCommand command) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            Text('Eseguo: ${command.type.toString().split('.').last}...'),
          ],
        ),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  // Handler per schedulare un evento
  void _handleScheduleEvent(ParsedCommand command) async {
    final params = command.parameters;

    // Mostra dialog per confermare/completare i dettagli
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuovo Evento'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Titolo: ${params['title'] ?? 'Nuovo evento'}'),
            if (params['date'] != null)
              Text('Data: ${_formatDate(params['date'] as DateTime)}'),
            if (params['time'] != null)
              Text('Ora: ${(params['time'] as TimeOfDay).format(context)}'),
            Text('Durata: ${params['duration'] ?? 60} minuti'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              // Implementa la creazione dell'evento
              await _createEvent(params);
            },
            child: const Text('Crea'),
          ),
        ],
      ),
    );
  }

  // Handler per creare un promemoria
  void _handleCreateReminder(ParsedCommand command) {
    final params = command.parameters;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuovo Promemoria'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${params['content'] ?? 'Promemoria'}'),
            if (params['date'] != null)
              Text('Quando: ${_formatDate(params['date'] as DateTime)}'),
            Text('Priorità: ${params['priority'] ?? 'normale'}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showSuccess('Promemoria creato con successo!');
            },
            child: const Text('Crea'),
          ),
        ],
      ),
    );
  }

  // Handler per bloccare tempo
  void _handleBlockTime(ParsedCommand command) async {
    final params = command.parameters;
    final reason = params['reason'] ?? 'blocked';

    String reasonText = 'Tempo bloccato';
    if (reason == 'focus_time') reasonText = 'Tempo per focus';
    else if (reason == 'lunch') reasonText = 'Pausa pranzo';
    else if (reason == 'break') reasonText = 'Pausa';
    else if (reason == 'personal') reasonText = 'Tempo personale';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Blocca $reasonText'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (params['date'] != null)
              Text('Data: ${_formatDate(params['date'] as DateTime)}'),
            if (params['time'] != null)
              Text('Dalle: ${(params['time'] as TimeOfDay).format(context)}'),
            if (params['endTime'] != null)
              Text('Alle: ${(params['endTime'] as TimeOfDay).format(context)}'),
            if (params['recurring'] == true)
              const Text('⚡ Ricorrente'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _createBlockedTime(params, reasonText);
            },
            child: const Text('Blocca'),
          ),
        ],
      ),
    );
  }

  // Handler per delegare task
  void _handleDelegateTask(ParsedCommand command) {
    final params = command.parameters;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delega Task'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Task: ${params['task'] ?? 'Da definire'}'),
            Text('A: ${params['assignee'] ?? 'Da definire'}'),
            if (params['date'] != null)
              Text('Entro: ${_formatDate(params['date'] as DateTime)}'),
            if (params['instructions'] != null)
              Text('Note: ${params['instructions']}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showSuccess('Task delegato con successo!');
            },
            child: const Text('Delega'),
          ),
        ],
      ),
    );
  }

  // Handler per cancellare evento
  void _handleCancelEvent(ParsedCommand command) {
    _showInfo('Funzione di cancellazione eventi in arrivo!');
  }

  // Handler per riprogrammare evento
  void _handleRescheduleEvent(ParsedCommand command) {
    _showInfo('Funzione di riprogrammazione eventi in arrivo!');
  }

  // Handler per suggerimenti email
  void _handleEmailSuggestions(ParsedCommand command) {
    _showInfo('Suggerimenti email in arrivo!');
  }

  // Handler per promemoria contatti
  void _handleContactReminder(ParsedCommand command) {
    final params = command.parameters;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Promemoria Contatto'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Contattare: ${params['contact'] ?? 'Contatto'}'),
            Text('Metodo: ${params['method'] ?? 'da definire'}'),
            if (params['reason'] != null)
              Text('Motivo: ${params['reason']}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showSuccess('Promemoria contatto creato!');
            },
            child: const Text('Crea'),
          ),
        ],
      ),
    );
  }

  // Handler per multi-comando
  void _handleMultiCommand(ParsedCommand command) {
    _showInfo('Elaborazione comando multiplo...');
  }

  // Crea un evento nel calendario
  Future<void> _createEvent(Map<String, dynamic> params) async {
    try {
      setState(() => _isLoading = true);

      // Prepara i parametri dell'evento
      final DateTime date = params['date'] ?? DateTime.now();
      final TimeOfDay? time = params['time'];
      final int duration = params['duration'] ?? 60;

      DateTime startTime;
      if (time != null) {
        startTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      } else {
        startTime = date;
      }

      final endTime = startTime.add(Duration(minutes: duration));

      // Crea l'evento su Google Calendar
      if (_isGoogleSignedIn) {
        await _googleCalendarService.createEvent(
          summary: params['title'] ?? 'Nuovo evento',
          startTime: startTime,
          endTime: endTime,
          description: params['description'],
          location: params['location'],
        );
      }

      // Ricarica i dati
      await _loadCalendarData();

      _showSuccess('Evento creato con successo!');
    } catch (e) {
      _showError('Errore nella creazione dell\'evento: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Crea tempo bloccato
  Future<void> _createBlockedTime(Map<String, dynamic> params, String title) async {
    try {
      setState(() => _isLoading = true);

      final DateTime date = params['date'] ?? DateTime.now();
      final TimeOfDay time = params['time'] ?? const TimeOfDay(hour: 9, minute: 0);
      final TimeOfDay endTime = params['endTime'] ??
          TimeOfDay(hour: (time.hour + 2) % 24, minute: time.minute);

      final startDateTime = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute
      );
      final endDateTime = DateTime(
          date.year,
          date.month,
          date.day,
          endTime.hour,
          endTime.minute
      );

      if (_isGoogleSignedIn) {
        await _googleCalendarService.createEvent(
          summary: title,
          startTime: startDateTime,
          endTime: endDateTime,
          description: 'Tempo bloccato automaticamente da SVP',
        );
      }

      await _loadCalendarData();
      _showSuccess('Tempo bloccato con successo!');

    } catch (e) {
      _showError('Errore nel bloccare il tempo: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Crea una pausa veloce
  void _createQuickBreak() async {
    final now = DateTime.now();
    final startTime = now.add(const Duration(minutes: 5));
    final endTime = startTime.add(const Duration(minutes: 15));

    try {
      if (_isGoogleSignedIn) {
        await _googleCalendarService.createEvent(
          summary: '☕ Pausa',
          startTime: startTime,
          endTime: endTime,
          description: 'Pausa consigliata da SVP',
        );
      }

      await _loadCalendarData();
      _showSuccess('Pausa programmata tra 5 minuti!');
    } catch (e) {
      _showError('Errore nella creazione della pausa: $e');
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

  void _showCreateEventDialog(Map<String, dynamic> params) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Conferma Creazione Meeting'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Inizio: ${DateFormat('dd/MM HH:mm').format(params['start'])}'),
            Text('Fine: ${DateFormat('dd/MM HH:mm').format(params['end'])}'),
            if (params['summary'] != null)
              Text('Titolo: ${params['summary']}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Crea l'evento direttamente
              _createEvent(params);
            },
            child: const Text('Conferma'),
          ),
        ],
      ),
    );
  }

  void _showOptimizationDialog(AIAction action) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Applica Ottimizzazione'),
        content: Text(action.label),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showSuccess('Ottimizzazione applicata!');
            },
            child: const Text('Applica'),
          ),
        ],
      ),
    );
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
  void dispose() {
    _workTimeTracker?.cancel();
    super.dispose();
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
        body: Stack(
          children: [
            // Il tuo body esistente
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : (!_isGoogleSignedIn && !_isOutlookSignedIn)
                ? _buildSignInPrompt()
                : _buildDashboard(),

            // Reminder pausa non invasivo
            if (_shouldShowPauseReminder)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: PauseReminderWidget(
                    minutesWorked: _minutesWorkedWithoutBreak,
                    onPauseTaken: _schedulePause,
                    onDismiss: () {
                      setState(() {
                        _shouldShowPauseReminder = false;
                      });
                    },
                  ),
                ),
              ),
          ],
        ),
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
      builder: (context) => Dialog(
        child: Container(
          padding: const EdgeInsets.all(24.0),
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    event.source == CalendarSource.google
                        ? Icons.g_mobiledata
                        : Icons.mail_outline,
                    color: event.color,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      event.title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Orario
              Row(
                children: [
                  const Icon(Icons.access_time, size: 20),
                  const SizedBox(width: 8),
                  Text(event.timeText),
                ],
              ),

              // Durata
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.timelapse, size: 20),
                  const SizedBox(width: 8),
                  Text('Durata: ${_formatDuration(event.duration)}'),
                ],
              ),

              // Luogo
              if (event.location != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.location_on, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(event.location!),
                    ),
                  ],
                ),
              ],

              // Descrizione
              if (event.description != null) ...[
                const SizedBox(height: 16),
                const Text(
                  'Descrizione:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(event.description!),
              ],

              // Partecipanti
              if (event.attendees.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Partecipanti:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                ...event.attendees.map((attendee) => Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: [
                      Icon(
                        Icons.person,
                        size: 16,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(attendee),
                    ],
                  ),
                )),
              ],

              const SizedBox(height: 24),

              // Azioni
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      // TODO: Implementare modifica evento
                    },
                    child: const Text('Modifica'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      // TODO: Implementare cancellazione evento
                    },
                    child: const Text(
                      'Cancella',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Wrapper per gestire eventi da diverse fonti
class CalendarEventWrapper {
  final CalendarSource source;
  final google_calendar.Event? googleEvent;
  final Map<String, dynamic>? outlookEvent;

  CalendarEventWrapper({
    required this.source,
    this.googleEvent,
    this.outlookEvent,
  });

  String get id {
    switch (source) {
      case CalendarSource.google:
        return googleEvent?.id ?? '';
      case CalendarSource.outlook:
        return outlookEvent?['id'] ?? '';
    }
  }

  String get title {
    switch (source) {
      case CalendarSource.google:
        return googleEvent?.summary ?? 'Senza titolo';
      case CalendarSource.outlook:
        return outlookEvent?['subject'] ?? 'Senza titolo';
    }
  }

  String? get description {
    switch (source) {
      case CalendarSource.google:
        return googleEvent?.description;
      case CalendarSource.outlook:
        return outlookEvent?['body']?['content'];
    }
  }

  String? get location {
    switch (source) {
      case CalendarSource.google:
        return googleEvent?.location;
      case CalendarSource.outlook:
        return outlookEvent?['location']?['displayName'];
    }
  }

  DateTime get startTime {
    switch (source) {
      case CalendarSource.google:
        if (googleEvent?.start?.dateTime != null) {
          return googleEvent!.start!.dateTime!.toLocal();
        } else if (googleEvent?.start?.date != null) {
          return googleEvent!.start!.date!;
        }
        return DateTime.now();
      case CalendarSource.outlook:
        final startStr = outlookEvent?['start']?['dateTime'];
        if (startStr != null) {
          return DateTime.parse(startStr).toLocal();
        }
        return DateTime.now();
    }
  }

  DateTime get endTime {
    switch (source) {
      case CalendarSource.google:
        if (googleEvent?.end?.dateTime != null) {
          return googleEvent!.end!.dateTime!.toLocal();
        } else if (googleEvent?.end?.date != null) {
          return googleEvent!.end!.date!;
        }
        return DateTime.now();
      case CalendarSource.outlook:
        final endStr = outlookEvent?['end']?['dateTime'];
        if (endStr != null) {
          return DateTime.parse(endStr).toLocal();
        }
        return DateTime.now();
    }
  }

  Duration get duration => endTime.difference(startTime);

  bool get isAllDay {
    switch (source) {
      case CalendarSource.google:
        return googleEvent?.start?.date != null;
      case CalendarSource.outlook:
        return outlookEvent?['isAllDay'] ?? false;
    }
  }

  List<String> get attendees {
    switch (source) {
      case CalendarSource.google:
        return googleEvent?.attendees
            ?.map((a) => a.displayName ?? a.email ?? 'Partecipante')
            .toList() ?? [];
      case CalendarSource.outlook:
        final attendeesList = outlookEvent?['attendees'] as List?;
        return attendeesList
            ?.map((a) => a['emailAddress']?['name'] ?? a['emailAddress']?['address'] ?? 'Partecipante')
            .cast<String>()
            .toList() ?? [];
    }
  }

  String get timeText {
    if (isAllDay) {
      return 'Tutto il giorno';
    }

    final now = DateTime.now();
    final isToday = startTime.day == now.day &&
        startTime.month == now.month &&
        startTime.year == now.year;

    String datePrefix = '';
    if (!isToday) {
      datePrefix = '${startTime.day}/${startTime.month} ';
    }

    return '$datePrefix${_formatTime(startTime)} - ${_formatTime(endTime)}';
  }

  static String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  Color get color {
    switch (source) {
      case CalendarSource.google:
      // Usa colore predefinito per Google
        return Colors.blue;
      case CalendarSource.outlook:
      // Usa colore predefinito per Outlook
        return const Color(0xFF0078D4);
    }
  }

  String get debugInfo {
    return '''
    === EVENTO ===
    Fonte: $source
    ID: $id
    Titolo: $title
    Inizio: $startTime
    Fine: $endTime
    Tutto il giorno: $isAllDay
    Luogo: $location
    Partecipanti: ${attendees.length}
    ''';
  }
}

enum CalendarSource {
  google,
  outlook,
}