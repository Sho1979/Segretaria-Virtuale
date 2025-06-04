import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:googleapis/calendar/v3.dart' as google_calendar;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_animate/flutter_animate.dart';

// IMPORT CORRETTI
import '../../services/google_calendar_service.dart';
import '../../services/outlook_calendar_service.dart';
import '../../services/ai/command_service.dart';
// import '../../services/ai/ai_assistant_service.dart'; // Commentato perché non utilizzato
import '../../services/calendar/free_slots_analyzer.dart'
    show FreeSlot, FreeSlotsAnalyzer;
import '../../widgets/voice_input_widget.dart';
import '../../widgets/date_navigation_widget.dart';
import '../../main.dart';

// Enumerazioni
enum CalendarView { day, week, month }

enum CalendarSource { google, outlook }

// Classe wrapper per eventi
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
    if (source == CalendarSource.google) {
      return googleEvent?.id ?? '';
    } else {
      return outlookEvent?['id'] ?? '';
    }
  }

  String get title {
    if (source == CalendarSource.google) {
      return googleEvent?.summary ?? 'Senza titolo';
    } else {
      return outlookEvent?['subject'] ?? 'Senza titolo';
    }
  }

  DateTime get startTime {
    if (source == CalendarSource.google) {
      return googleEvent?.start?.dateTime ?? DateTime.now();
    } else {
      final startStr = outlookEvent?['start']?['dateTime'];
      return startStr != null ? DateTime.parse(startStr) : DateTime.now();
    }
  }

  DateTime get endTime {
    if (source == CalendarSource.google) {
      return googleEvent?.end?.dateTime ?? DateTime.now();
    } else {
      final endStr = outlookEvent?['end']?['dateTime'];
      return endStr != null ? DateTime.parse(endStr) : DateTime.now();
    }
  }

  Duration get duration => endTime.difference(startTime);

  String? get location {
    if (source == CalendarSource.google) {
      return googleEvent?.location;
    } else {
      return outlookEvent?['location']?['displayName'];
    }
  }

  String? get description {
    if (source == CalendarSource.google) {
      return googleEvent?.description;
    } else {
      return outlookEvent?['bodyPreview'];
    }
  }

  Color get color {
    // Assegna colori diversi in base alla sorgente
    if (source == CalendarSource.google) {
      return Colors.blue;
    } else {
      return const Color(0xFF0078D4);
    }
  }

  String get timeText {
    final start = DateFormat('HH:mm').format(startTime);
    final end = DateFormat('HH:mm').format(endTime);
    return '$start - $end';
  }
}

// Costanti per il design
class CalendarTheme {
  static const primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6B5EFF), Color(0xFF4A43EC)],
  );

  static const morningGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFD93D), Color(0xFFFFB344)],
  );

  static const afternoonGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF6BCF7F), Color(0xFF4BA75E)],
  );

  static const eveningGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
  );

  static LinearGradient getTimeBasedGradient() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return morningGradient;
    if (hour >= 12 && hour < 17) return afternoonGradient;
    return eveningGradient;
  }
}

class CalendarDashboard extends StatefulWidget {
  const CalendarDashboard({super.key});

  @override
  State<CalendarDashboard> createState() => _CalendarDashboardState();
}

class _CalendarDashboardState extends State<CalendarDashboard>
    with TickerProviderStateMixin {
  // Servizi
  final GoogleCalendarService _googleCalendarService = GoogleCalendarService();
  final OutlookCalendarService _outlookCalendarService =
      OutlookCalendarService();
  late final FreeSlotsAnalyzer _slotsAnalyzer;

  // Stati
  bool _isLoading = false;
  bool _isGoogleSignedIn = false;
  bool _isOutlookSignedIn = false;

  // Dati
  List<CalendarEventWrapper> _todayEvents = [];
  List<CalendarEventWrapper> _weekEvents = [];
  Map<String, dynamic> _weeklyStats = {};
  List<FreeSlot> _freeSlots = [];
  DateTime _selectedDate = DateTime.now();

  // Sistema pausa
  bool _shouldShowPauseReminder = false;
  int _minutesWorkedWithoutBreak = 0;
  Timer? _workTimeTracker;

  // Animazioni
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _pulseAnimation;

  // Vista corrente
  CalendarView _currentView = CalendarView.day;

  // Statistiche avanzate
  Map<String, dynamic> _advancedStats = {};
  List<FlSpot> _weeklyTrendData = [];

  // Preferenze utente
  bool _smartSuggestionsEnabled = true;
  bool _autoSchedulingEnabled = false;
  bool _focusModeEnabled = false;
  Timer? _focusTimer;
  int _focusMinutesRemaining = 0;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _googleCalendarService.initialize();
    _slotsAnalyzer =
        FreeSlotsAnalyzer(_googleCalendarService, _outlookCalendarService);
    _initializeServices();
    _startWorkTimeTracking();
    _loadUserPreferences();
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.1,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    _fadeController.forward();
    _slideController.forward();
  }

  Future<void> _loadUserPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _smartSuggestionsEnabled = prefs.getBool('smart_suggestions') ?? true;
      _autoSchedulingEnabled = prefs.getBool('auto_scheduling') ?? false;
      _focusModeEnabled = prefs.getBool('focus_mode') ?? false;
    });
  }

  void _startWorkTimeTracking() {
    _workTimeTracker = Timer.periodic(const Duration(minutes: 1), (timer) {
      setState(() {
        _minutesWorkedWithoutBreak++;

        // Sistema intelligente di pause
        if (_minutesWorkedWithoutBreak >= 90 && !_shouldShowPauseReminder) {
          _shouldShowPauseReminder = true;
          HapticFeedback.mediumImpact();
        }
      });
    });
  }

  Future<void> _initializeServices() async {
    setState(() => _isLoading = true);

    try {
      if (kIsWeb) {
        final hasCallback = await _outlookCalendarService.handleWebCallback();
        if (hasCallback) {
          print('Outlook login completato tramite callback');
        }
      }

      await _outlookCalendarService.initialize();

      setState(() {
        _isGoogleSignedIn = _googleCalendarService.isSignedIn;
        _isOutlookSignedIn = _outlookCalendarService.hasValidToken;
      });

      if (_isGoogleSignedIn || _isOutlookSignedIn) {
        await _loadCalendarData();
        await _loadAdvancedAnalytics();
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

  @override
  void dispose() {
    _workTimeTracker?.cancel();
    _focusTimer?.cancel();
    _fadeController.dispose();
    _slideController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _signInToGoogle() async {
    setState(() => _isLoading = true);
    HapticFeedback.selectionClick();

    try {
      final bool success = await _googleCalendarService.signIn();
      if (mounted && success) {
        setState(() => _isGoogleSignedIn = true);
        await _loadCalendarData();

        _showSuccessWithAnimation('Google Calendar connesso!');
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
    HapticFeedback.selectionClick();

    try {
      final bool success = await _outlookCalendarService.signIn();
      if (mounted && success) {
        setState(() => _isOutlookSignedIn = true);
        await _loadCalendarData();

        _showSuccessWithAnimation('Outlook Calendar connesso!');
      } else {
        _showError('Impossibile accedere a Outlook Calendar');
      }
    } catch (e) {
      _showError('Errore durante l\'accesso Outlook: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _connectAllCalendars() async {
    setState(() => _isLoading = true);
    HapticFeedback.mediumImpact();

    try {
      bool allSuccess = true;

      if (!_isGoogleSignedIn) {
        final googleSuccess = await _googleCalendarService.signIn();
        if (googleSuccess) {
          setState(() => _isGoogleSignedIn = true);
        } else {
          allSuccess = false;
        }
      }

      if (!_isOutlookSignedIn) {
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

      if (_isGoogleSignedIn || _isOutlookSignedIn) {
        await _loadCalendarData();
        await _loadAdvancedAnalytics();

        if (allSuccess && _isGoogleSignedIn && _isOutlookSignedIn) {
          _showSuccessWithAnimation('Tutti i calendari sincronizzati! 🎉');
        } else if (_isGoogleSignedIn || _isOutlookSignedIn) {
          _showInfo('Alcuni calendari connessi con successo');
        }
      } else {
        _showError('Impossibile connettere i calendari');
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

      // Carica eventi Google
      if (_isGoogleSignedIn) {
        try {
          final googleTodayEvents =
              await _googleCalendarService.getEventsForDate(_selectedDate);
          final googleWeekEvents = await _googleCalendarService.getWeekEvents();

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
          final outlookTodayEvents =
              await _outlookCalendarService.getEventsForDate(_selectedDate);
          final outlookWeekEvents =
              await _outlookCalendarService.getWeekEvents();

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
          if (e.toString().contains('401')) {
            setState(() => _isOutlookSignedIn = false);
            _showError('Sessione Outlook scaduta. Riconnettiti.');
          }
        }
      }

      // Ordina eventi
      todayEvents.sort((a, b) => a.startTime.compareTo(b.startTime));
      weekEvents.sort((a, b) => a.startTime.compareTo(b.startTime));

      // Calcola statistiche
      double totalHours = 0;
      for (var event in weekEvents) {
        totalHours += event.duration.inMinutes / 60.0;
      }

      // Analizza slot liberi
      await _analyzeFreeSlots();

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

      // Genera suggerimenti intelligenti
      if (_smartSuggestionsEnabled) {
        _generateSmartSuggestions();
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

      // Filtra solo gli slot VERAMENTE liberi
      final freeSlots = <FreeSlot>[];
      for (var slot in slots) {
        bool hasConflict = false;

        for (var event in _todayEvents) {
          if (slot.start.isBefore(event.endTime) &&
              slot.end.isAfter(event.startTime)) {
            hasConflict = true;
            break;
          }
        }

        if (!hasConflict && slot.end.isAfter(DateTime.now())) {
          freeSlots.add(slot);
        }
      }

      setState(() => _freeSlots = freeSlots);
    } catch (e) {
      print('Errore analisi slot: $e');
    }
  }

  Future<void> _loadAdvancedAnalytics() async {
    try {
      // Calcola trend settimanale
      final weeklyData = <String, int>{};
      for (var event in _weekEvents) {
        final dayKey = DateFormat('E').format(event.startTime);
        weeklyData[dayKey] = (weeklyData[dayKey] ?? 0) + 1;
      }

      // Genera dati per il grafico
      _weeklyTrendData = [
        FlSpot(0, weeklyData['Mon']?.toDouble() ?? 0),
        FlSpot(1, weeklyData['Tue']?.toDouble() ?? 0),
        FlSpot(2, weeklyData['Wed']?.toDouble() ?? 0),
        FlSpot(3, weeklyData['Thu']?.toDouble() ?? 0),
        FlSpot(4, weeklyData['Fri']?.toDouble() ?? 0),
      ];

      // Calcola metriche avanzate
      final meetingTypes = <String, int>{};
      final meetingDurations = <int>[];

      for (var event in _weekEvents) {
        // Categorizza per tipo
        final type = _categorizeEvent(event.title);
        meetingTypes[type] = (meetingTypes[type] ?? 0) + 1;

        // Raccogli durate
        meetingDurations.add(event.duration.inMinutes);
      }

      // Calcola statistiche
      final avgDuration = meetingDurations.isEmpty
          ? 0
          : meetingDurations.reduce((a, b) => a + b) / meetingDurations.length;

      setState(() {
        _advancedStats = {
          'meetingTypes': meetingTypes,
          'avgDuration': avgDuration,
          'productivityScore': _calculateProductivityScore(),
          'suggestions': _generateAdvancedSuggestions(),
        };
      });
    } catch (e) {
      print('Errore caricamento analytics: $e');
    }
  }

  String _categorizeEvent(String title) {
    final lower = title.toLowerCase();
    if (lower.contains('meeting') || lower.contains('incontro'))
      return 'Meeting';
    if (lower.contains('call') || lower.contains('chiamata')) return 'Call';
    if (lower.contains('review') || lower.contains('revisione'))
      return 'Review';
    if (lower.contains('1:1') || lower.contains('one on one'))
      return 'One-on-One';
    if (lower.contains('standup') || lower.contains('daily')) return 'Standup';
    return 'Altri';
  }

  double _calculateProductivityScore() {
    // Algoritmo per calcolare un punteggio di produttività
    double score = 100.0;

    // Penalizza troppi meeting
    if (_todayEvents.length > 6) {
      score -= 20;
    } else if (_todayEvents.length > 4) score -= 10;

    // Premia tempo libero per focus
    final freeHours =
        _freeSlots.fold(0, (sum, slot) => sum + slot.duration.inMinutes) / 60;
    if (freeHours > 4) score += 10;

    // Penalizza meeting back-to-back
    for (int i = 0; i < _todayEvents.length - 1; i++) {
      final gap =
          _todayEvents[i + 1].startTime.difference(_todayEvents[i].endTime);
      if (gap.inMinutes < 15) score -= 5;
    }

    return score.clamp(0, 100);
  }

  List<String> _generateAdvancedSuggestions() {
    final suggestions = <String>[];

    final productivity = _calculateProductivityScore();
    if (productivity < 50) {
      suggestions.add(
          '🔴 Giornata molto intensa. Considera di riprogrammare alcuni meeting.');
    } else if (productivity < 70) {
      suggestions
          .add('🟡 Carico di lavoro elevato. Proteggi del tempo per il focus.');
    } else {
      suggestions.add('🟢 Buon bilanciamento! Hai tempo per lavoro profondo.');
    }

    // Suggerimenti basati sui pattern
    if (_todayEvents.length > 5) {
      suggestions
          .add('💡 Prova a raggruppare meeting simili per risparmiare tempo.');
    }

    if (_freeSlots.any((slot) => slot.duration.inHours >= 2)) {
      suggestions
          .add('🎯 Hai blocchi di tempo perfetti per attività importanti.');
    }

    return suggestions;
  }

  void _generateSmartSuggestions() {
    // Implementazione suggerimenti AI
    if (_todayEvents.length > 4 && _freeSlots.length < 2) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          _showSmartSuggestion(
            'La tua giornata sembra molto piena. Vuoi che ottimizzi il tuo calendario?',
            action: () => _optimizeSchedule(),
          );
        }
      });
    }
  }

  void _showSmartSuggestion(String message, {VoidCallback? action}) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: CalendarTheme.primaryGradient,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lightbulb, color: Colors.white, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Suggerimento Smart',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Dopo',
                        style: TextStyle(color: Colors.white70)),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      action?.call();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF6B5EFF),
                    ),
                    child: const Text('Ottimizza'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _optimizeSchedule() {
    // Implementazione ottimizzazione calendario
    _showInfo('Ottimizzazione in corso...');
    // TODO: Implementare logica di ottimizzazione
  }

  void _onDateChanged(DateTime newDate) {
    setState(() {
      _selectedDate = newDate;
    });
    _loadCalendarData();

    // Animazione cambio data
    _slideController.reset();
    _slideController.forward();
  }

  @override
  Widget build(BuildContext context) {
    final bool fromHome =
        (ModalRoute.of(context)?.settings.arguments as Map?)?['fromHome'] ??
            false;

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
        backgroundColor: Colors.grey.shade50,
        body: CustomScrollView(
          slivers: [
            _buildModernAppBar(fromHome),
            SliverToBoxAdapter(
              child: _buildBody(),
            ),
          ],
        ),
        floatingActionButton: _buildFloatingActionButton(),
        bottomNavigationBar: _buildBottomBar(),
      ),
    );
  }

  Widget _buildModernAppBar(bool fromHome) {
    return SliverAppBar(
      expandedHeight: 120,
      floating: false,
      pinned: true,
      elevation: 0,
      backgroundColor: Colors.transparent,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: CalendarTheme.getTimeBasedGradient(),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text(
                    'Calendar Dashboard',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                      .animate()
                      .fadeIn(duration: 500.ms)
                      .slideX(begin: -0.2, end: 0),
                  const SizedBox(height: 4),
                  Text(
                    _formatDate(DateTime.now()),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                    ),
                  )
                      .animate()
                      .fadeIn(duration: 500.ms, delay: 100.ms)
                      .slideX(begin: -0.2, end: 0),
                ],
              ),
            ),
          ),
        ),
      ),
      leading: fromHome
          ? IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () {
                HapticFeedback.selectionClick();
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const HomePage()),
                );
              },
            )
          : null,
      actions: [
        if (_isGoogleSignedIn || _isOutlookSignedIn) ...[
          IconButton(
            icon: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) => Transform.scale(
                scale: _pulseAnimation.value,
                child: const Icon(Icons.refresh, color: Colors.white),
              ),
            ),
            onPressed: _isLoading
                ? null
                : () {
                    HapticFeedback.lightImpact();
                    _loadCalendarData();
                    _loadAdvancedAnalytics();
                  },
            tooltip: 'Aggiorna',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (value) async {
              HapticFeedback.selectionClick();
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
                case 'settings':
                  _showSettingsDialog();
                  break;
                case 'focus_mode':
                  _toggleFocusMode();
                  break;
              }
            },
            itemBuilder: (context) => [
              if (_isGoogleSignedIn)
                const PopupMenuItem(
                  value: 'google_logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout, size: 20),
                      SizedBox(width: 12),
                      Text('Disconnetti Google'),
                    ],
                  ),
                ),
              if (_isOutlookSignedIn)
                const PopupMenuItem(
                  value: 'outlook_logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout, size: 20),
                      SizedBox(width: 12),
                      Text('Disconnetti Outlook'),
                    ],
                  ),
                ),
              const PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.settings, size: 20),
                    SizedBox(width: 12),
                    Text('Impostazioni'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'focus_mode',
                child: Row(
                  children: [
                    Icon(Icons.psychology, size: 20),
                    SizedBox(width: 12),
                    Text('Modalità Focus'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildBody() {
    return Stack(
      children: [
        AnimatedBuilder(
          animation: _fadeAnimation,
          builder: (context, child) => Opacity(
            opacity: _fadeAnimation.value,
            child: _isLoading && _todayEvents.isEmpty
                ? _buildLoadingState()
                : (!_isGoogleSignedIn && !_isOutlookSignedIn)
                    ? _buildSignInPrompt()
                    : _buildDashboard(),
          ),
        ),
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
        if (_focusModeEnabled)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildFocusModeBar(),
          ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 80,
              height: 80,
              child: const CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Color(0xFF6B5EFF),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Caricamento in corso...',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Sincronizzazione calendari',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignInPrompt() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 40),
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              gradient: CalendarTheme.primaryGradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6B5EFF).withOpacity(0.3),
                  blurRadius: 30,
                  offset: const Offset(0, 15),
                ),
              ],
            ),
            child: const Icon(
              Icons.calendar_today,
              size: 60,
              color: Colors.white,
            ),
          )
              .animate()
              .scale(duration: 600.ms, curve: Curves.elasticOut)
              .fadeIn(),
          const SizedBox(height: 32),
          const Text(
            'Connetti i tuoi Calendari',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          )
              .animate()
              .fadeIn(duration: 500.ms, delay: 200.ms)
              .slideY(begin: 0.2, end: 0),
          const SizedBox(height: 16),
          Text(
            'Accedi ai tuoi account per sincronizzare i calendari\ne gestire tutti i tuoi appuntamenti in un unico posto',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade600,
              height: 1.5,
            ),
          )
              .animate()
              .fadeIn(duration: 500.ms, delay: 300.ms)
              .slideY(begin: 0.2, end: 0),
          const SizedBox(height: 48),
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _connectAllCalendars,
            icon: const Icon(Icons.sync, size: 24),
            label: const Text(
              'Connetti Tutti i Calendari',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6B5EFF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
              elevation: 8,
              shadowColor: const Color(0xFF6B5EFF).withOpacity(0.4),
            ),
          )
              .animate()
              .fadeIn(duration: 500.ms, delay: 400.ms)
              .scaleXY(begin: 0.9, end: 1.0),
          const SizedBox(height: 24),
          Text(
            'oppure connetti singolarmente',
            style: TextStyle(color: Colors.grey.shade500),
          ).animate().fadeIn(duration: 500.ms, delay: 500.ms),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!_isGoogleSignedIn)
                _buildProviderButton(
                  'Google',
                  Icons.g_mobiledata,
                  Colors.blue,
                  _signInToGoogle,
                ).animate().fadeIn(duration: 500.ms, delay: 600.ms).slideX(
                    begin: -0.2, end: 0),
              if (!_isGoogleSignedIn && !_isOutlookSignedIn)
                const SizedBox(width: 16),
              if (!_isOutlookSignedIn)
                _buildProviderButton(
                  'Outlook',
                  Icons.mail_outline,
                  const Color(0xFF0078D4),
                  _signInToOutlook,
                )
                    .animate()
                    .fadeIn(duration: 500.ms, delay: 700.ms)
                    .slideX(begin: 0.2, end: 0),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProviderButton(
    String provider,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return OutlinedButton.icon(
      onPressed: _isLoading ? null : onPressed,
      icon: Icon(icon, color: color),
      label: Text(provider),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withOpacity(0.5)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(25),
        ),
      ),
    );
  }

  Widget _buildDashboard() {
    return RefreshIndicator(
      onRefresh: () async {
        await _loadCalendarData();
        await _loadAdvancedAnalytics();
      },
      color: const Color(0xFF6B5EFF),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            _buildQuickActionsSection(),
            const SizedBox(height: 24),
            _buildVoiceAssistantSection(),
            const SizedBox(height: 24),
            _buildDateNavigationSection(),
            const SizedBox(height: 24),
            _buildWelcomeSection(),
            const SizedBox(height: 24),
            _buildAdvancedStatsSection(),
            const SizedBox(height: 24),
            _buildTimelineView(),
            const SizedBox(height: 24),
            _buildConnectedAccountsSection(),
            const SizedBox(height: 24),
            _buildUpcomingEventsSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsSection() {
    final quickActions = [
      {
        'icon': Icons.event_available,
        'label': 'Slot liberi',
        'color': Colors.green,
        'action': CommandType.showFreeSlots
      },
      {
        'icon': Icons.today,
        'label': 'Oggi',
        'color': Colors.blue,
        'action': CommandType.dailySummary
      },
      {
        'icon': Icons.note_add,
        'label': 'Promemoria',
        'color': Colors.purple,
        'action': CommandType.createReminder
      },
      {
        'icon': Icons.event,
        'label': 'Evento',
        'color': Colors.pink,
        'action': CommandType.scheduleEvent
      },
      {
        'icon': Icons.analytics,
        'label': 'Analisi',
        'color': Colors.indigo,
        'action': CommandType.workloadAnalysis
      },
      {
        'icon': Icons.block,
        'label': 'Focus Time',
        'color': Colors.orange,
        'action': CommandType.blockTime
      },
      {
        'icon': Icons.people,
        'label': 'Delega',
        'color': Colors.teal,
        'action': CommandType.delegateTask
      },
      {
        'icon': Icons.coffee,
        'label': 'Pausa',
        'color': Colors.brown,
        'action': CommandType.pauseReminder
      },
    ];

    final suggestions = [
      'Vuoi il riepilogo della giornata?',
      'Vuoi vedere i tuoi slot liberi per oggi?',
      'È ora di fare una pausa',
      'Rivedi le scadenze in arrivo',
      'Posso aiutarti con qualcosa?',
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Azioni Rapide',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 90,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: quickActions.length,
              itemBuilder: (context, index) {
                final action = quickActions[index];
                return Container(
                  margin: EdgeInsets.only(
                    right: 12,
                    left: index == 0 ? 0 : 0,
                  ),
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _handleCommand(ParsedCommand(
                        originalText: action['label'] as String,
                        type: action['action'] as CommandType,
                        parameters: {},
                        confidence: 1.0,
                        timestamp: DateTime.now(),
                      ));
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 80,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            (action['color'] as Color).withOpacity(0.1),
                            (action['color'] as Color).withOpacity(0.2),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: (action['color'] as Color).withOpacity(0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            action['icon'] as IconData,
                            color: action['color'] as Color,
                            size: 28,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            action['label'] as String,
                            style: TextStyle(
                              color:
                                  (action['color'] as Color).withOpacity(0.7),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                    .animate()
                    .fadeIn(duration: 300.ms, delay: (index * 50).ms)
                    .scaleXY(
                        begin: 0.8,
                        end: 1.0,
                        duration: 300.ms,
                        delay: (index * 50).ms);
              },
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: suggestions.length,
              itemBuilder: (context, index) {
                return Container(
                  margin: EdgeInsets.only(
                    right: 8,
                    left: index == 0 ? 0 : 0,
                  ),
                  child: ActionChip(
                    label: Text(suggestions[index]),
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      // TODO: Handle suggestion tap
                    },
                    backgroundColor: Colors.white,
                    side: BorderSide(color: Colors.grey.shade300),
                    labelStyle: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 13,
                    ),
                  ),
                )
                    .animate()
                    .fadeIn(duration: 300.ms, delay: (index * 50 + 400).ms)
                    .slideX(
                        begin: 0.2,
                        end: 0,
                        duration: 300.ms,
                        delay: (index * 50 + 400).ms);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceAssistantSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: VoiceInputWidget(
        onCommandReceived: _handleCommand,
      ),
    );
  }

  Widget _buildDateNavigationSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: DateNavigationWidget(
        selectedDate: _selectedDate,
        onDateChanged: _onDateChanged,
      ),
    );
  }

  Widget _buildWelcomeSection() {
    String userName = 'Utente';
    String? photoUrl;

    if (_isGoogleSignedIn && _googleCalendarService.currentUser != null) {
      userName = _googleCalendarService.currentUser!.displayName ?? userName;
      photoUrl = _googleCalendarService.currentUser!.photoUrl;
    } else if (_isOutlookSignedIn &&
        _outlookCalendarService.currentUser != null) {
      userName =
          _outlookCalendarService.currentUser!['displayName'] ?? userName;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: CalendarTheme.getTimeBasedGradient(),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.2),
              border:
                  Border.all(color: Colors.white.withOpacity(0.3), width: 2),
            ),
            child: photoUrl != null
                ? ClipOval(
                    child: Image.network(
                      photoUrl,
                      fit: BoxFit.cover,
                    ),
                  )
                : Center(
                    child: Text(
                      userName.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        fontSize: 24,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Benvenuto, $userName!',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _getGreeting(),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.2, end: 0);
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    final productivity = _calculateProductivityScore();

    if (hour < 12) {
      return 'Buongiorno! Pronto per una giornata produttiva?';
    } else if (hour < 17) {
      if (productivity < 50) {
        return 'Giornata intensa! Ricorda di fare una pausa.';
      }
      return 'Buon pomeriggio! Come procede la giornata?';
    } else {
      return 'Buonasera! È ora di rilassarsi un po\'.';
    }
  }

  Widget _buildAdvancedStatsSection() {
    if (_weeklyStats.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Panoramica',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton(
                onPressed: () => _showWorkloadAnalysis(),
                child: const Text('Vedi dettagli'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildModernStatCard(
                  'Eventi Oggi',
                  _todayEvents.length.toString(),
                  Icons.today,
                  Colors.blue,
                  subtitle: _todayEvents.isEmpty ? 'Giornata libera!' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildModernStatCard(
                  'Settimana',
                  _weeklyStats['totalEvents']?.toString() ?? '0',
                  Icons.calendar_view_week,
                  Colors.green,
                  subtitle: '${_weeklyStats['totalHours']} ore',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildModernStatCard(
                  'Produttività',
                  '${_calculateProductivityScore().toInt()}%',
                  Icons.trending_up,
                  _getProductivityColor(_calculateProductivityScore()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getProductivityColor(double score) {
    if (score >= 70) return Colors.green;
    if (score >= 50) return Colors.orange;
    return Colors.red;
  }

  Widget _buildModernStatCard(
    String title,
    String value,
    IconData icon,
    Color color, {
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
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
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).scaleXY(begin: 0.9, end: 1.0);
  }

  Widget _buildTimelineView() {
    if (_todayEvents.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Timeline Oggi',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 120,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _todayEvents.length,
              itemBuilder: (context, index) {
                final event = _todayEvents[index];
                final isOngoing = event.startTime.isBefore(DateTime.now()) &&
                    event.endTime.isAfter(DateTime.now());
                final isPast = event.endTime.isBefore(DateTime.now());

                return Container(
                  width: 200,
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isPast
                          ? [Colors.grey.shade300, Colors.grey.shade400]
                          : isOngoing
                              ? [event.color.withOpacity(0.8), event.color]
                              : [
                                  event.color.withOpacity(0.6),
                                  event.color.withOpacity(0.8)
                                ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: event.color.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            event.source == CalendarSource.google
                                ? Icons.g_mobiledata
                                : Icons.mail_outline,
                            color: Colors.white,
                            size: 16,
                          ),
                          const Spacer(),
                          if (isOngoing)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                  )
                                      .animate(
                                        onPlay: (controller) =>
                                            controller.repeat(),
                                      )
                                      .scaleXY(
                                        begin: 0.8,
                                        end: 1.2,
                                        duration: const Duration(seconds: 1),
                                      ),
                                  const SizedBox(width: 4),
                                  const Text(
                                    'In corso',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              event.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (event.location != null) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.location_on,
                                    color: Colors.white70,
                                    size: 12,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      event.location!,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          const Icon(
                            Icons.access_time,
                            color: Colors.white70,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            event.timeText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
                    .animate()
                    .fadeIn(duration: 300.ms, delay: (index * 100).ms)
                    .slideX(
                        begin: 0.2,
                        end: 0,
                        duration: 300.ms,
                        delay: (index * 100).ms);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectedAccountsSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Account Connessi',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          if (_isGoogleSignedIn)
            _buildAccountTile(
              'Google Calendar',
              Icons.g_mobiledata,
              Colors.blue,
              _googleCalendarService.currentUser?.email ?? 'Connesso',
              onTap: () => _showAccountMenu('google'),
            ),
          if (_isGoogleSignedIn && _isOutlookSignedIn)
            const SizedBox(height: 12),
          if (_isOutlookSignedIn)
            _buildAccountTile(
              'Outlook Calendar',
              Icons.mail_outline,
              const Color(0xFF0078D4),
              _outlookCalendarService.currentUser?['userPrincipalName'] ??
                  'Connesso',
              onTap: () => _showAccountMenu('outlook'),
            ),
          if (!_isGoogleSignedIn || !_isOutlookSignedIn) ...[
            const SizedBox(height: 16),
            Center(
              child: TextButton.icon(
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Aggiungi altro calendario'),
                onPressed: _connectAllCalendars,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAccountTile(
    String title,
    IconData icon,
    Color color,
    String subtitle, {
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: color.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.check_circle,
                color: color,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUpcomingEventsSection() {
    if (_weekEvents.isEmpty) return const SizedBox.shrink();

    final upcomingEvents = _weekEvents
        .where((e) => e.startTime.isAfter(DateTime.now()))
        .take(5)
        .toList();

    if (upcomingEvents.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Prossimi Eventi',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _currentView = CalendarView.week;
                  });
                },
                child: const Text('Vedi tutti'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...upcomingEvents.map((event) {
            final daysUntil = event.startTime.difference(DateTime.now()).inDays;
            final hoursUntil =
                event.startTime.difference(DateTime.now()).inHours;

            String timeUntil = '';
            if (daysUntil > 0) {
              timeUntil =
                  'tra $daysUntil ${daysUntil == 1 ? 'giorno' : 'giorni'}';
            } else if (hoursUntil > 0) {
              timeUntil = 'tra $hoursUntil ${hoursUntil == 1 ? 'ora' : 'ore'}';
            } else {
              final minutesUntil =
                  event.startTime.difference(DateTime.now()).inMinutes;
              timeUntil = 'tra $minutesUntil minuti';
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _showEventDetails(event),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 4,
                          height: 60,
                          decoration: BoxDecoration(
                            color: event.color,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                event.title,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.access_time,
                                    size: 14,
                                    color: Colors.grey.shade600,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    DateFormat('dd MMM • HH:mm')
                                        .format(event.startTime),
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: event.color.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      timeUntil,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: event.color,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (event.location != null) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.location_on,
                                      size: 14,
                                      color: Colors.grey.shade500,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        event.location!,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade500,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: Colors.grey.shade400,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFloatingActionButton() {
    if (!_isGoogleSignedIn && !_isOutlookSignedIn)
      return const SizedBox.shrink();

    return ScaleTransition(
      scale: _pulseAnimation,
      child: FloatingActionButton.extended(
        onPressed: () {
          HapticFeedback.mediumImpact();
          _showCreateEventDialog();
        },
        backgroundColor: const Color(0xFF6B5EFF),
        icon: const Icon(Icons.add),
        label: const Text('Nuovo Evento'),
        elevation: 8,
      ),
    );
  }

  Widget _buildBottomBar() {
    if (!_isGoogleSignedIn && !_isOutlookSignedIn)
      return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildBottomBarItem(
                Icons.calendar_today,
                'Giorno',
                _currentView == CalendarView.day,
                () => setState(() => _currentView = CalendarView.day),
              ),
              _buildBottomBarItem(
                Icons.calendar_view_week,
                'Settimana',
                _currentView == CalendarView.week,
                () => setState(() => _currentView = CalendarView.week),
              ),
              _buildBottomBarItem(
                Icons.calendar_month,
                'Mese',
                _currentView == CalendarView.month,
                () => setState(() => _currentView = CalendarView.month),
              ),
              _buildBottomBarItem(
                Icons.insights,
                'Insights',
                false,
                () => _showWorkloadAnalysis(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBarItem(
    IconData icon,
    String label,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? const Color(0xFF6B5EFF) : Colors.grey,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF6B5EFF) : Colors.grey,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFocusModeBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.purple,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.psychology, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Modalità Focus attiva - $_focusMinutesRemaining min rimanenti',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          TextButton(
            onPressed: _toggleFocusMode,
            child: const Text(
              'Termina',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // Helper methods
  void _showAccountMenu(String provider) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('Sincronizza ora'),
              onTap: () {
                Navigator.pop(context);
                _loadCalendarData();
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Disconnetti',
                  style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(context);
                if (provider == 'google') {
                  await _googleCalendarService.signOut();
                  setState(() => _isGoogleSignedIn = false);
                } else {
                  await _outlookCalendarService.signOut();
                  setState(() => _isOutlookSignedIn = false);
                }
                _loadCalendarData();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showEventDetails(CalendarEventWrapper event) {
    showDialog(
      context: context,
      builder: (context) => _buildModernDialog(
        title: event.title,
        gradient: LinearGradient(
          colors: [event.color.withOpacity(0.8), event.color],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow(
                Icons.calendar_today, 'Data', _formatDate(event.startTime)),
            _buildInfoRow(Icons.access_time, 'Orario', event.timeText),
            _buildInfoRow(
                Icons.timer, 'Durata', _formatDuration(event.duration)),
            if (event.location != null)
              _buildInfoRow(Icons.location_on, 'Luogo', event.location!),
            if (event.description != null && event.description!.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Descrizione',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                event.description!,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade700,
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

  void _showCreateEventDialog() {
    final titleController = TextEditingController();
    DateTime selectedDate = _selectedDate;
    TimeOfDay selectedTime = TimeOfDay.now();
    int duration = 60;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => _buildModernDialog(
          title: 'Nuovo Evento',
          gradient: CalendarTheme.primaryGradient,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: InputDecoration(
                  labelText: 'Titolo evento',
                  prefixIcon: const Icon(Icons.event),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.calendar_today),
                      title: Text('Data: ${_formatDate(selectedDate)}'),
                      trailing: const Icon(Icons.edit),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime.now(),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setState(() => selectedDate = picked);
                        }
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.access_time),
                      title: Text('Ora: ${selectedTime.format(context)}'),
                      trailing: const Icon(Icons.edit),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: selectedTime,
                        );
                        if (picked != null) {
                          setState(() => selectedTime = picked);
                        }
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.timer),
                      title: Text('Durata: $duration minuti'),
                      trailing: const Icon(Icons.edit),
                      onTap: () {
                        // TODO: Show duration picker
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annulla'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.check),
              label: const Text('Crea'),
              onPressed: () async {
                Navigator.pop(dialogContext);

                final startDateTime = DateTime(
                  selectedDate.year,
                  selectedDate.month,
                  selectedDate.day,
                  selectedTime.hour,
                  selectedTime.minute,
                );

                await _createEvent({
                  'title': titleController.text.isEmpty
                      ? 'Nuovo evento'
                      : titleController.text,
                  'date': selectedDate,
                  'startTime': startDateTime,
                  'endTime': startDateTime.add(Duration(minutes: duration)),
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF6B5EFF),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => _buildModernDialog(
        title: 'Impostazioni',
        gradient: LinearGradient(
          colors: [Colors.grey.shade700, Colors.grey.shade900],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              title: const Text('Suggerimenti intelligenti'),
              subtitle: const Text(
                  'Ricevi suggerimenti AI per ottimizzare il calendario'),
              value: _smartSuggestionsEnabled,
              onChanged: (value) async {
                setState(() => _smartSuggestionsEnabled = value);
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('smart_suggestions', value);
              },
            ),
            SwitchListTile(
              title: const Text('Auto-scheduling'),
              subtitle:
                  const Text('Permetti all\'AI di programmare automaticamente'),
              value: _autoSchedulingEnabled,
              onChanged: (value) async {
                setState(() => _autoSchedulingEnabled = value);
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('auto_scheduling', value);
              },
            ),
            SwitchListTile(
              title: const Text('Modalità Focus'),
              subtitle:
                  const Text('Blocca notifiche durante il tempo di focus'),
              value: _focusModeEnabled,
              onChanged: (value) {
                _toggleFocusMode();
              },
            ),
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

  void _toggleFocusMode() async {
    setState(() {
      _focusModeEnabled = !_focusModeEnabled;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('focus_mode', _focusModeEnabled);

    if (_focusModeEnabled) {
      _focusMinutesRemaining = 25; // Pomodoro timer
      _focusTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
        setState(() {
          _focusMinutesRemaining--;
          if (_focusMinutesRemaining <= 0) {
            _focusTimer?.cancel();
            _focusModeEnabled = false;
            _showInfo('Sessione focus completata!');
          }
        });
      });
      _showSuccess('Modalità focus attivata per 25 minuti');
    } else {
      _focusTimer?.cancel();
      _showInfo('Modalità focus disattivata');
    }
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernDialog({
    required String title,
    required Gradient gradient,
    required Widget content,
    required List<Widget> actions,
  }) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: content,
            ),
            Padding(
              padding: const EdgeInsets.only(right: 20, bottom: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: actions,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Additional helper methods
  void _schedulePause() async {
    try {
      final now = DateTime.now();
      final pauseEnd = now.add(const Duration(minutes: 15));

      await _googleCalendarService.createEvent(
        summary: '☕ Pausa rigenerante',
        description: 'Momento di relax e ricarica energia',
        startTime: now,
        endTime: pauseEnd,
      );

      setState(() {
        _minutesWorkedWithoutBreak = 0;
        _shouldShowPauseReminder = false;
      });

      _showSuccessWithAnimation(
          'Pausa programmata! Goditi il tuo momento di relax 😊');
      await _loadCalendarData();
    } catch (e) {
      print('Errore creazione pausa: $e');
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _showSuccess(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showSuccessWithAnimation(String message) {
    HapticFeedback.mediumImpact();
    _showSuccess(message);
  }

  void _showInfo(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.orange.shade600,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  String _getTotalMeetingTime() {
    final totalMinutes = _todayEvents.fold(
      0,
      (sum, event) => sum + event.duration.inMinutes,
    );
    final hours = totalMinutes / 60;
    return hours.toStringAsFixed(1);
  }

  String _getTotalFreeTime() {
    if (_freeSlots.isEmpty) return '0 ore';

    final totalMinutes = _freeSlots.fold(
      0,
      (sum, slot) => sum + slot.duration.inMinutes,
    );

    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;

    if (hours > 0 && minutes > 0) {
      return '$hours h $minutes min';
    } else if (hours > 0) {
      return '$hours ore';
    } else {
      return '$minutes minuti';
    }
  }

  void _showErrorWithAnimation(String message) {
    HapticFeedback.heavyImpact();
    _showError(message);
  }
  // ===== METODI AGGIUNTIVI PER COMMAND HANDLING =====

  void _handleCommand(ParsedCommand command) async {
    HapticFeedback.lightImpact();

    print('=== COMANDO RICEVUTO ===');
    print('Tipo: ${command.type}');
    print('Parametri: ${command.parameters}');

    if (command.parameters['shouldShowPauseReminder'] == true &&
        command.type != CommandType.pauseReminder) {
      setState(() {
        _shouldShowPauseReminder = true;
      });
    }

    if (command.parameters['date'] != null) {
      setState(() {
        _selectedDate = command.parameters['date'] as DateTime;
      });
      await _loadCalendarData();
    }

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
        _showErrorWithAnimation('Non ho capito. Prova a riformulare.');
    }
  }

  void _showPauseDialog() {
    HapticFeedback.mediumImpact();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.orange.withOpacity(0.7), Colors.orange],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.coffee,
                  color: Colors.white,
                  size: 48,
                ),
              )
                  .animate()
                  .scale(duration: 600.ms, curve: Curves.elasticOut)
                  .then()
                  .shake(duration: 300.ms, hz: 3),
              const SizedBox(height: 24),
              const Text(
                'È ora di una pausa!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Hai lavorato per $_minutesWorkedWithoutBreak minuti.\nUna pausa ti aiuterà a rimanere produttivo!',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Dopo',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Programma pausa'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      _schedulePause();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.orange.shade600,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
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

  void _showProcessingCommand(ParsedCommand command) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: const CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            Text('Eseguo: ${_getCommandName(command.type)}...'),
          ],
        ),
        duration: const Duration(seconds: 1),
        backgroundColor: const Color(0xFF6B5EFF),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  String _getCommandName(CommandType type) {
    switch (type) {
      case CommandType.showFreeSlots:
        return 'Analisi slot liberi';
      case CommandType.dailySummary:
        return 'Riepilogo giornaliero';
      case CommandType.workloadAnalysis:
        return 'Analisi carico di lavoro';
      case CommandType.scheduleEvent:
        return 'Creazione evento';
      case CommandType.createReminder:
        return 'Creazione promemoria';
      case CommandType.blockTime:
        return 'Blocco tempo';
      case CommandType.delegateTask:
        return 'Delega task';
      case CommandType.pauseReminder:
        return 'Promemoria pausa';
      default:
        return 'Comando';
    }
  }

  void _handleScheduleEvent(ParsedCommand command) async {
    final params = command.parameters;

    showDialog(
      context: context,
      builder: (context) => _buildModernDialog(
        title: 'Nuovo Evento',
        gradient: CalendarTheme.primaryGradient,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildInfoRow(
                Icons.title, 'Titolo', params['title'] ?? 'Nuovo evento'),
            if (params['date'] != null)
              _buildInfoRow(Icons.calendar_today, 'Data',
                  _formatDate(params['date'] as DateTime)),
            if (params['time'] != null)
              _buildInfoRow(Icons.access_time, 'Ora',
                  (params['time'] as TimeOfDay).format(context)),
            _buildInfoRow(
                Icons.timer, 'Durata', '${params['duration'] ?? 60} minuti'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.check),
            label: const Text('Crea'),
            onPressed: () async {
              Navigator.pop(context);
              await _createEvent(params);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF6B5EFF),
            ),
          ),
        ],
      ),
    );
  }

  void _handleCreateReminder(ParsedCommand command) {
    final params = command.parameters;
    final TextEditingController titleController =
        TextEditingController(text: params['content']?.toString() ?? '');

    DateTime selectedDate = params['date'] ?? DateTime.now();
    TimeOfDay selectedTime = params['time'] ?? TimeOfDay.now();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => _buildModernDialog(
          title: 'Nuovo Promemoria',
          gradient: LinearGradient(
            colors: [Colors.purple.withOpacity(0.7), Colors.purple],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: InputDecoration(
                  labelText: 'Nome promemoria',
                  prefixIcon: const Icon(Icons.note, color: Colors.purple),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.calendar_today,
                          color: Colors.purple),
                      title: Text('Data: ${_formatDate(selectedDate)}'),
                      trailing: const Icon(Icons.edit),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime.now(),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setState(() => selectedDate = picked);
                        }
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading:
                          const Icon(Icons.access_time, color: Colors.purple),
                      title: Text('Ora: ${selectedTime.format(context)}'),
                      trailing: const Icon(Icons.edit),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: selectedTime,
                        );
                        if (picked != null) {
                          setState(() => selectedTime = picked);
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildPrioritySelector(params['priority'] ?? 'normale'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.alarm_add),
              label: const Text('Crea'),
              onPressed: () async {
                Navigator.pop(context);

                final reminderDate = DateTime(
                  selectedDate.year,
                  selectedDate.month,
                  selectedDate.day,
                  selectedTime.hour,
                  selectedTime.minute,
                );

                await _createEvent({
                  'title': '🔔 ${titleController.text}',
                  'date': selectedDate,
                  'startTime': reminderDate,
                  'endTime': reminderDate.add(const Duration(minutes: 15)),
                  'description': 'Promemoria creato da SVP',
                });

                _showSuccessWithAnimation('Promemoria creato!');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.purple,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrioritySelector(String currentPriority) {
    final priorities = ['bassa', 'normale', 'alta'];
    final colors = [Colors.green, Colors.orange, Colors.red];
    final icons = [Icons.arrow_downward, Icons.remove, Icons.arrow_upward];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(priorities.length, (index) {
        final isSelected = currentPriority == priorities[index];
        return InkWell(
          onTap: () {
            // TODO: Update priority
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? colors[index].withOpacity(0.2)
                  : Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? colors[index] : Colors.transparent,
                width: 2,
              ),
            ),
            child: Row(
              children: [
                Icon(icons[index], color: colors[index], size: 20),
                const SizedBox(width: 4),
                Text(
                  priorities[index].substring(0, 1).toUpperCase() +
                      priorities[index].substring(1),
                  style: TextStyle(
                    color: isSelected ? colors[index] : Colors.grey,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  void _handleBlockTime(ParsedCommand command) async {
    final params = command.parameters;
    final reason = params['reason'] ?? 'blocked';

    String reasonText = 'Tempo bloccato';
    IconData reasonIcon = Icons.block;
    Color reasonColor = Colors.grey;

    switch (reason) {
      case 'focus_time':
        reasonText = 'Tempo per focus';
        reasonIcon = Icons.psychology;
        reasonColor = Colors.blue;
        break;
      case 'lunch':
        reasonText = 'Pausa pranzo';
        reasonIcon = Icons.restaurant;
        reasonColor = Colors.orange;
        break;
      case 'break':
        reasonText = 'Pausa';
        reasonIcon = Icons.coffee;
        reasonColor = Colors.brown;
        break;
      case 'personal':
        reasonText = 'Tempo personale';
        reasonIcon = Icons.person;
        reasonColor = Colors.purple;
        break;
    }

    showDialog(
      context: context,
      builder: (context) => _buildModernDialog(
        title: 'Blocca $reasonText',
        gradient: LinearGradient(
          colors: [reasonColor.withOpacity(0.7), reasonColor],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: reasonColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(reasonIcon, size: 48, color: reasonColor),
            ).animate().scale(duration: 400.ms),
            const SizedBox(height: 24),
            if (params['date'] != null)
              _buildInfoRow(Icons.calendar_today, 'Data',
                  _formatDate(params['date'] as DateTime)),
            if (params['time'] != null)
              _buildInfoRow(Icons.access_time, 'Dalle',
                  (params['time'] as TimeOfDay).format(context)),
            if (params['endTime'] != null)
              _buildInfoRow(Icons.access_time_filled, 'Alle',
                  (params['endTime'] as TimeOfDay).format(context)),
            if (params['recurring'] == true)
              Chip(
                label: const Text('Ricorrente'),
                avatar: const Icon(Icons.repeat, size: 18),
                backgroundColor: reasonColor.withOpacity(0.2),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          ElevatedButton.icon(
            icon: Icon(reasonIcon),
            label: const Text('Blocca'),
            onPressed: () async {
              Navigator.pop(context);
              await _createBlockedTime(params, reasonText);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: reasonColor,
            ),
          ),
        ],
      ),
    );
  }

  void _handleDelegateTask(ParsedCommand command) {
    final params = command.parameters;

    showDialog(
      context: context,
      builder: (context) => _buildModernDialog(
        title: 'Delega Task',
        gradient: LinearGradient(
          colors: [Colors.pink.withOpacity(0.7), Colors.pink],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildInfoRow(Icons.task, 'Task', params['task'] ?? 'Da definire'),
            _buildInfoRow(Icons.person, 'Assegnato a',
                params['assignee'] ?? 'Da definire'),
            if (params['date'] != null)
              _buildInfoRow(Icons.calendar_today, 'Entro',
                  _formatDate(params['date'] as DateTime)),
            if (params['instructions'] != null)
              Card(
                color: const Color(0xFFFCE4EC),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.note, color: Color(0xFFEC407A)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          params['instructions'],
                          style: const TextStyle(color: Color(0xFFAD1457)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.send),
            label: const Text('Delega'),
            onPressed: () {
              Navigator.pop(context);
              _showSuccessWithAnimation('Task delegato con successo!');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.pink,
            ),
          ),
        ],
      ),
    );
  }

  void _handleCancelEvent(ParsedCommand command) {
    _showInfo('Seleziona l\'evento da cancellare dalla lista');
    // TODO: Implementare selezione e cancellazione evento
  }

  void _handleRescheduleEvent(ParsedCommand command) {
    _showInfo('Seleziona l\'evento da riprogrammare');
    // TODO: Implementare riprogrammazione evento
  }

  void _handleEmailSuggestions(ParsedCommand command) {
    _showInfo('Analisi email in corso...');
    // TODO: Implementare suggerimenti email
  }

  void _handleContactReminder(ParsedCommand command) {
    final params = command.parameters;

    showDialog(
      context: context,
      builder: (context) => _buildModernDialog(
        title: 'Promemoria Contatto',
        gradient: LinearGradient(
          colors: [Colors.teal.withOpacity(0.7), Colors.teal],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildInfoRow(
                Icons.person, 'Contattare', params['contact'] ?? 'Contatto'),
            _buildInfoRow(
                Icons.phone, 'Metodo', params['method'] ?? 'da definire'),
            if (params['reason'] != null)
              _buildInfoRow(Icons.info, 'Motivo', params['reason']),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.alarm),
            label: const Text('Crea'),
            onPressed: () {
              Navigator.pop(context);
              _showSuccessWithAnimation('Promemoria contatto creato!');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.teal,
            ),
          ),
        ],
      ),
    );
  }

  void _handleMultiCommand(ParsedCommand command) {
    _showInfo('Elaborazione comando multiplo...');
  }

  Future<void> _createEvent(Map<String, dynamic> params) async {
    try {
      setState(() => _isLoading = true);
      HapticFeedback.mediumImpact();

      DateTime startTime;
      DateTime endTime;

      if (params['startTime'] != null && params['startTime'] is DateTime) {
        startTime = params['startTime'];
      } else {
        final DateTime date = params['date'] ?? DateTime.now();
        final TimeOfDay? time = params['time'];

        if (time != null) {
          startTime =
              DateTime(date.year, date.month, date.day, time.hour, time.minute);
        } else {
          startTime = date;
        }
      }

      if (params['endTime'] != null && params['endTime'] is DateTime) {
        endTime = params['endTime'];
      } else {
        final int duration = params['duration'] ?? 60;
        endTime = startTime.add(Duration(minutes: duration));
      }

      if (_isGoogleSignedIn) {
        await _googleCalendarService.createEvent(
          summary: params['title'] ?? 'Nuovo evento',
          startTime: startTime,
          endTime: endTime,
          description: params['description'],
          location: params['location'],
          attendees: params['attendees'] as List<String>?,
        );
      }

      await _loadCalendarData();
      _showSuccessWithAnimation('Evento creato con successo! ✨');
    } catch (e) {
      _showError('Errore nella creazione dell\'evento: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _createBlockedTime(
      Map<String, dynamic> params, String title) async {
    try {
      setState(() => _isLoading = true);
      HapticFeedback.mediumImpact();

      final DateTime date = params['date'] ?? DateTime.now();
      final TimeOfDay time =
          params['time'] ?? const TimeOfDay(hour: 9, minute: 0);
      final TimeOfDay endTime = params['endTime'] ??
          TimeOfDay(hour: (time.hour + 2) % 24, minute: time.minute);

      final startDateTime =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
      final endDateTime = DateTime(
          date.year, date.month, date.day, endTime.hour, endTime.minute);

      if (_isGoogleSignedIn) {
        await _googleCalendarService.createEvent(
          summary: title,
          startTime: startDateTime,
          endTime: endDateTime,
          description: 'Tempo bloccato automaticamente da SVP',
        );
      }

      await _loadCalendarData();
      _showSuccessWithAnimation('Tempo bloccato con successo! 🔒');
    } catch (e) {
      _showError('Errore nel bloccare il tempo: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }
  // ===== METODI ANALISI FREE SLOTS E DAILY SUMMARY =====

  void _showFreeSlotsDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  gradient: CalendarTheme.primaryGradient,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.event_available,
                        color: Colors.white, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Slot liberi',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _formatDate(_selectedDate),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _freeSlots.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.event_busy,
                                size: 80, color: Colors.grey[300]),
                            const SizedBox(height: 16),
                            Text(
                              'Nessuno slot libero disponibile',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'La tua giornata è completamente occupata',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _freeSlots.length,
                        itemBuilder: (context, index) {
                          final slot = _freeSlots[index];
                          const greenColor = Colors.green;
                          const orangeColor = Colors.orange;
                          const redColor = Colors.red;
                          const greyColor = Colors.grey;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: slot.isHighEnergy
                                    ? [
                                        Color.fromARGB(20, greenColor.red,
                                            greenColor.green, greenColor.blue),
                                        Color.fromARGB(40, greenColor.red,
                                            greenColor.green, greenColor.blue)
                                      ]
                                    : slot.isMediumEnergy
                                        ? [
                                            Color.fromARGB(
                                                20,
                                                orangeColor.red,
                                                orangeColor.green,
                                                orangeColor.blue),
                                            Color.fromARGB(
                                                40,
                                                orangeColor.red,
                                                orangeColor.green,
                                                orangeColor.blue)
                                          ]
                                        : [
                                            Color.fromARGB(20, redColor.red,
                                                redColor.green, redColor.blue),
                                            Color.fromARGB(40, redColor.red,
                                                redColor.green, redColor.blue)
                                          ],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  _showCreateEventInSlot(slot);
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 60,
                                        height: 60,
                                        decoration: BoxDecoration(
                                          color: slot.isHighEnergy
                                              ? greenColor
                                              : slot.isMediumEnergy
                                                  ? orangeColor
                                                  : redColor,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              '${(slot.energyScore * 100).toInt()}%',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const Text(
                                              'energia',
                                              style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${_formatTime(slot.start)} - ${_formatTime(slot.end)}',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Durata: ${_formatDuration(slot.duration)}',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: Color.fromARGB(
                                                    255,
                                                    greyColor.red ~/ 2,
                                                    greyColor.green ~/ 2,
                                                    greyColor.blue ~/ 2),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              slot.suggestion,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[600],
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Icon(
                                          Icons.add,
                                          color: slot.isHighEnergy
                                              ? Colors.green
                                              : slot.isMediumEnergy
                                                  ? Colors.orange
                                                  : Colors.red,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          )
                              .animate()
                              .fadeIn(duration: 300.ms, delay: (index * 50).ms)
                              .slideX(
                                  begin: 0.2,
                                  end: 0,
                                  duration: 300.ms,
                                  delay: (index * 50).ms);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateEventInSlot(FreeSlot slot) {
    final TextEditingController titleController = TextEditingController();
    final TextEditingController attendeeController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => _buildModernDialog(
        title: 'Crea Evento',
        gradient: CalendarTheme.primaryGradient,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: InputDecoration(
                labelText: 'Titolo evento',
                prefixIcon: const Icon(Icons.event),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: attendeeController,
              decoration: InputDecoration(
                labelText: 'Partecipante (email)',
                prefixIcon: const Icon(Icons.person),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.access_time, color: Colors.blue[700]),
                  const SizedBox(width: 8),
                  Text(
                    '${_formatTime(slot.start)} - ${_formatTime(slot.end)}',
                    style: TextStyle(
                      color: Colors.blue[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annulla'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.check),
            label: const Text('Crea'),
            onPressed: () async {
              Navigator.pop(dialogContext);
              Navigator.pop(context);

              await _createEvent({
                'title': titleController.text.isEmpty
                    ? 'Nuovo meeting'
                    : titleController.text,
                'date': _selectedDate,
                'startTime': slot.start,
                'endTime': slot.end,
                'attendees': attendeeController.text.isNotEmpty
                    ? [attendeeController.text]
                    : null,
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF6B5EFF),
            ),
          ),
        ],
      ),
    );
  }

  void _showDailySummary() async {
    final workload = await _slotsAnalyzer.analyzeWeeklyWorkload();

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: CalendarTheme.getTimeBasedGradient(),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today,
                        color: Colors.white, size: 28),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Riepilogo Giornaliero',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSummaryHeader(),
                      const SizedBox(height: 20),
                      _buildEventsList(),
                      const SizedBox(height: 20),
                      _buildStatsSection(workload),
                      const SizedBox(height: 20),
                      _buildProductivityScore(),
                      if (_advancedStats['suggestions'] != null) ...[
                        const SizedBox(height: 20),
                        _buildSuggestionsSection(),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue[50]!, Colors.blue[100]!],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child:
                Icon(Icons.calendar_month, color: Colors.blue[700], size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatDate(_selectedDate),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Produttività: ${_calculateProductivityScore().toInt()}%',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.2, end: 0);
  }

  Widget _buildEventsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'I tuoi appuntamenti (${_todayEvents.length})',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue[100],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_getTotalMeetingTime()} ore totali',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.blue[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_todayEvents.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.event_available, color: Colors.green[700]),
                const SizedBox(width: 12),
                Text(
                  'Nessun meeting oggi - Ottimo per il focus!',
                  style: TextStyle(color: Colors.green[700]),
                ),
              ],
            ),
          )
        else
          ..._todayEvents.asMap().entries.map((entry) {
            final index = entry.key;
            final event = entry.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 40,
                    decoration: BoxDecoration(
                      color: event.color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.access_time,
                                size: 14, color: Colors.grey[600]),
                            const SizedBox(width: 4),
                            Text(
                              event.timeText,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '${event.duration.inMinutes} min',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    event.source == CalendarSource.google
                        ? Icons.g_mobiledata
                        : Icons.mail_outline,
                    size: 16,
                    color: Colors.grey[400],
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 300.ms, delay: (index * 50).ms).slideX(
                begin: -0.1, end: 0, duration: 300.ms, delay: (index * 50).ms);
          }),
      ],
    );
  }

  Widget _buildStatsSection(Map<String, dynamic> workload) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.purple[50]!, Colors.purple[100]!],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Statistiche',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Slot liberi',
                  '${_freeSlots.length}',
                  Icons.event_available,
                  Colors.green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Tempo libero',
                  _getTotalFreeTime(),
                  Icons.timer,
                  Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Media sett.',
                  '${workload['averageDailyMeetings']?.toStringAsFixed(1) ?? "0"} ore',
                  Icons.trending_up,
                  Colors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Energia media',
                  '${(_freeSlots.isEmpty ? 0 : _freeSlots.map((s) => s.energyScore).reduce((a, b) => a + b) / _freeSlots.length * 100).toInt()}%',
                  Icons.battery_charging_full,
                  Colors.purple,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductivityScore() {
    final score = _calculateProductivityScore();
    final color = score >= 70
        ? Colors.green
        : score >= 50
            ? Colors.orange
            : Colors.red;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color[50],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 60,
                height: 60,
                child: CircularProgressIndicator(
                  value: score / 100,
                  strokeWidth: 6,
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
              Text(
                '${score.toInt()}',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Punteggio Produttività',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  score >= 70
                      ? 'Ottimo bilanciamento tra meeting e focus time!'
                      : score >= 50
                          ? 'Buono, ma potresti ottimizzare meglio il tempo'
                          : 'Attenzione: troppi meeting, poco tempo per il focus',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().scale(duration: 500.ms, curve: Curves.elasticOut);
  }

  Widget _buildSuggestionsSection() {
    final suggestions = _advancedStats['suggestions'] as List<String>;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Suggerimenti AI',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...suggestions.map((suggestion) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline,
                      color: Colors.blue, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      suggestion,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.blue[900],
                      ),
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }
  // ===== METODI WORKLOAD ANALYSIS =====

  void _showWorkloadAnalysis() async {
    setState(() => _isLoading = true);

    try {
      final analysis = await _slotsAnalyzer.analyzeWeeklyWorkload();

      showDialog(
        context: context,
        builder: (context) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.95,
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.indigo.withOpacity(0.7), Colors.indigo],
                    ),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.analytics,
                          color: Colors.white, size: 28),
                      const SizedBox(width: 12),
                      const Text(
                        'Analisi Carico di Lavoro',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildWeeklyChart(),
                        const SizedBox(height: 24),
                        _buildWorkloadMetrics(analysis),
                        const SizedBox(height: 24),
                        _buildMeetingTypesBreakdown(),
                        const SizedBox(height: 24),
                        _buildOptimizationSuggestions(analysis),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildWeeklyChart() {
    return Container(
      height: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Trend Settimanale',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: Colors.grey.shade200,
                      strokeWidth: 1,
                    );
                  },
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toInt().toString(),
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        );
                      },
                      reservedSize: 30,
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        const days = ['Lun', 'Mar', 'Mer', 'Gio', 'Ven'];
                        if (value.toInt() < days.length) {
                          return Text(
                            days[value.toInt()],
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          );
                        }
                        return const Text('');
                      },
                      reservedSize: 30,
                    ),
                  ),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: _weeklyTrendData,
                    isCurved: true,
                    color: Colors.indigo,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) {
                        return FlDotCirclePainter(
                          radius: 4,
                          color: Colors.white,
                          strokeWidth: 2,
                          strokeColor: Colors.indigo,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.indigo.withOpacity(0.1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 500.ms).scaleXY(begin: 0.95, end: 1.0);
  }

  Widget _buildWorkloadMetrics(Map<String, dynamic> analysis) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Metriche Chiave',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                '📊 Ore totali',
                '${analysis['totalMeetingHours']?.toStringAsFixed(1) ?? "0"}',
                Colors.blue,
                'questa settimana',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                '📈 Media',
                '${analysis['averageDailyMeetings']?.toStringAsFixed(1) ?? "0"}',
                Colors.green,
                'ore/giorno',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                '🔥 Più impegnato',
                analysis['busiestDay'] ?? '-',
                Colors.orange,
                'giorno critico',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                '😌 Più leggero',
                analysis['lightestDay'] ?? '-',
                Colors.purple,
                'per focus time',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricCard(
      String icon, String value, Color color, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color.fromARGB(20, color.red, color.green, color.blue),
            Color.fromARGB(40, color.red, color.green, color.blue)
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            icon,
            style: const TextStyle(fontSize: 24),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(
                  255, color.red ~/ 3, color.green ~/ 3, color.blue ~/ 3),
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: Color.fromARGB(
                  255, color.red ~/ 2, color.green ~/ 2, color.blue ~/ 2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMeetingTypesBreakdown() {
    final types = _advancedStats['meetingTypes'] as Map<String, int>? ?? {};
    if (types.isEmpty) return const SizedBox.shrink();

    final total = types.values.reduce((a, b) => a + b);
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.pink,
      Colors.teal,
    ];

    const greyColor = Colors.grey;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:
            Color.fromARGB(20, greyColor.red, greyColor.green, greyColor.blue),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Distribuzione Meeting',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ...types.entries.toList().asMap().entries.map((entry) {
            final index = entry.key;
            final type = entry.value;
            final percentage = (type.value / total * 100).toInt();
            final color = colors[index % colors.length];

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            type.key,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                      Text(
                        '${type.value} ($percentage%)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: percentage / 100,
                    backgroundColor: Color.fromARGB(
                        50, greyColor.red, greyColor.green, greyColor.blue),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                    minHeight: 6,
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildOptimizationSuggestions(Map<String, dynamic> analysis) {
    final suggestions = analysis['suggestedBreaks'] as List? ?? [];
    if (suggestions.isEmpty) return const SizedBox.shrink();

    const amberColor = Colors.amber;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color.fromARGB(
                20, amberColor.red, amberColor.green, amberColor.blue),
            Color.fromARGB(
                40, amberColor.red, amberColor.green, amberColor.blue)
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tips_and_updates,
                  color: Color.fromARGB(255, amberColor.red ~/ 2,
                      amberColor.green ~/ 2, amberColor.blue ~/ 2)),
              const SizedBox(width: 8),
              Text(
                'Suggerimenti Ottimizzazione',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color.fromARGB(255, amberColor.red ~/ 3,
                      amberColor.green ~/ 3, amberColor.blue ~/ 3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...suggestions.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('💡', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s.toString(),
                        style: TextStyle(
                          fontSize: 14,
                          color: Color.fromARGB(255, amberColor.red ~/ 3,
                              amberColor.green ~/ 3, amberColor.blue ~/ 3),
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

// Widget per il reminder pausa
class PauseReminderWidget extends StatelessWidget {
  final int minutesWorked;
  final VoidCallback onPauseTaken;
  final VoidCallback onDismiss;

  const PauseReminderWidget({
    super.key,
    required this.minutesWorked,
    required this.onPauseTaken,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    const orangeColor = Colors.orange;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color.fromARGB(255, orangeColor.red, orangeColor.green ~/ 1.5,
                orangeColor.blue ~/ 2),
            Color.fromARGB(255, orangeColor.red, orangeColor.green ~/ 2,
                orangeColor.blue ~/ 3)
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: orangeColor.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.coffee, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'È ora di una pausa!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Hai lavorato per $minutesWorked minuti',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onPauseTaken,
            child: const Text(
              'Pausa',
              style: TextStyle(color: Colors.white),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70, size: 20),
            onPressed: onDismiss,
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 300.ms)
        .slideY(begin: -0.5, end: 0)
        .then()
        .shake(duration: 300.ms, hz: 3, offset: const Offset(2, 0));
  }
}

