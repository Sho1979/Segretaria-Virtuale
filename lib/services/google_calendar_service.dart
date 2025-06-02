// lib/services/google_calendar_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/google_config.dart';

class GoogleCalendarService {
  static final GoogleCalendarService _instance = GoogleCalendarService._internal();
  factory GoogleCalendarService() => _instance;
  GoogleCalendarService._internal();

  GoogleSignIn? _googleSignIn;
  calendar.CalendarApi? _calendarApi;
  GoogleSignInAccount? _currentUser;

  // Getter per l'API del calendario
  calendar.CalendarApi get calendarApi {
    if (_calendarApi == null) {
      throw Exception('Calendar API non inizializzata. Effettua prima il login.');
    }
    return _calendarApi!;
  }

  // Inizializza Google Sign In
  void initialize() {
    // Usa il Client ID appropriato per la piattaforma
    final String clientId = kIsWeb
        ? GoogleConfig.webClientId
        : GoogleConfig.androidClientId;

    _googleSignIn = GoogleSignIn(
      clientId: clientId,
      scopes: GoogleConfig.scopes,
    );
  }

  // Verifica se l'utente è autenticato
  bool get isSignedIn => _currentUser != null;

  // Ottieni l'utente corrente
  GoogleSignInAccount? get currentUser => _currentUser;

  // Accedi a Google
  Future<bool> signIn() async {
    try {
      // Se non è inizializzato, inizializza
      if (_googleSignIn == null) {
        initialize();
      }

      final GoogleSignInAccount? account = await _googleSignIn!.signIn();
      if (account != null) {
        _currentUser = account;
        await _initializeCalendarApi();

        print('Login Google completato per: ${account.email}');

        // NON fare reload su web, mantieni lo stato
        return true;
      }
      return false;
    } catch (e) {
      print('Errore durante il login Google: $e');
      return false;
    }
  }

  // Salva lo stato dell'utente Google
  Future<void> _saveGoogleUserState() async {
    if (_currentUser != null) {
      final prefs = await SharedPreferences.getInstance();
      final userInfo = {
        'email': _currentUser!.email,
        'displayName': _currentUser!.displayName,
        'id': _currentUser!.id,
        'photoUrl': _currentUser!.photoUrl,
      };
      await prefs.setString('google_user_state', json.encode(userInfo));
    }
  }

  // Carica lo stato dell'utente Google
  Future<void> _loadGoogleUserState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userStateJson = prefs.getString('google_user_state');
      if (userStateJson != null) {
        // Prova a riconnettersi silenziosamente
        final GoogleSignInAccount? account = await _googleSignIn!.signInSilently();
        if (account != null) {
          _currentUser = account;
          await _initializeCalendarApi();
        }
      }
    } catch (e) {
      print('Errore nel ripristino sessione Google: $e');
    }
  }

  // Prova a fare login silenzioso (senza popup)
  Future<GoogleSignInAccount?> signInSilently() async {
    try {
      if (_googleSignIn == null) {
        initialize();
      }

      final account = await _googleSignIn!.signInSilently();
      if (account != null) {
        _currentUser = account;
        await _initializeCalendarApi();
        return account;
      }
      return null;
    } catch (e) {
      print('Errore durante il login silenzioso Google: $e');
      return null;
    }
  }

  // Disconnetti da Google
  Future<void> signOut() async {
    await _googleSignIn?.signOut();
    _currentUser = null;
    _calendarApi = null;
  }

  // Inizializza l'API Calendar
  Future<void> _initializeCalendarApi() async {
    if (_currentUser == null) return;

    try {
      final GoogleSignInAuthentication auth = await _currentUser!.authentication;
      final _GoogleAuthClient authClient = _GoogleAuthClient(auth.accessToken!);
      _calendarApi = calendar.CalendarApi(authClient);
    } catch (e) {
      print('Errore nell\'inizializzazione Calendar API: $e');
    }
  }

  // Ottieni la lista dei calendari
  Future<List<calendar.CalendarListEntry>> getCalendars() async {
    if (_calendarApi == null) {
      throw Exception('Calendar API non inizializzata');
    }

    try {
      final calendar.CalendarList calendarList = await _calendarApi!.calendarList.list();
      return calendarList.items ?? [];
    } catch (e) {
      print('Errore nel recupero dei calendari: $e');
      rethrow;
    }
  }

  // Ottieni gli eventi di un periodo specifico
  Future<List<calendar.Event>> getEvents({
    String calendarId = 'primary',
    DateTime? timeMin,
    DateTime? timeMax,
    int maxResults = 50,
  }) async {
    if (_calendarApi == null) {
      throw Exception('Calendar API non inizializzata');
    }

    try {
      final calendar.Events events = await _calendarApi!.events.list(
        calendarId,
        timeMin: timeMin,
        timeMax: timeMax,
        maxResults: maxResults,
        singleEvents: true,
        orderBy: 'startTime',
      );
      return events.items ?? [];
    } catch (e) {
      print('Errore nel recupero degli eventi: $e');
      rethrow;
    }
  }

  // Ottieni gli eventi per una data specifica
  Future<List<calendar.Event>> getEventsForDate(DateTime date) async {
    if (_calendarApi == null) {
      throw Exception('Calendar API non inizializzata');
    }

    try {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final calendar.Events events = await _calendarApi!.events.list(
        'primary',
        timeMin: startOfDay.toUtc(),
        timeMax: endOfDay.toUtc(),
        singleEvents: true,
        orderBy: 'startTime',
      );

      return events.items ?? [];
    } catch (e) {
      print('Errore nel recupero eventi per data: $e');
      rethrow;
    }
  }

  // Ottieni gli eventi di oggi
  Future<List<calendar.Event>> getTodayEvents() async {
    final DateTime now = DateTime.now();
    final DateTime startOfDay = DateTime(now.year, now.month, now.day);
    final DateTime endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);

    return getEvents(
      timeMin: startOfDay,
      timeMax: endOfDay,
    );
  }

  // Ottieni gli eventi della settimana
  Future<List<calendar.Event>> getWeekEvents() async {
    final DateTime now = DateTime.now();
    final DateTime startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final DateTime endOfWeek = startOfWeek.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));

    return getEvents(
      timeMin: startOfWeek,
      timeMax: endOfWeek,
    );
  }

  // Crea un nuovo evento
  Future<calendar.Event?> createEvent({
    required String summary,
    String? description,
    required DateTime startTime,
    required DateTime endTime,
    String? location,
    List<String>? attendees,
    String calendarId = 'primary',
  }) async {
    if (_calendarApi == null) {
      throw Exception('Calendar API non inizializzata');
    }

    try {
      final calendar.Event event = calendar.Event(
        summary: summary,
        description: description,
        location: location,
        start: calendar.EventDateTime(
          dateTime: startTime,
          timeZone: 'Europe/Rome',
        ),
        end: calendar.EventDateTime(
          dateTime: endTime,
          timeZone: 'Europe/Rome',
        ),
        attendees: attendees?.map((email) => calendar.EventAttendee(email: email)).toList(),
      );

      final calendar.Event createdEvent = await _calendarApi!.events.insert(event, calendarId);
      return createdEvent;
    } catch (e) {
      print('Errore nella creazione dell\'evento: $e');
      rethrow;
    }
  }

  // Aggiorna un evento esistente
  Future<calendar.Event?> updateEvent({
    required String eventId,
    required String summary,
    String? description,
    required DateTime startTime,
    required DateTime endTime,
    String? location,
    String calendarId = 'primary',
  }) async {
    if (_calendarApi == null) {
      throw Exception('Calendar API non inizializzata');
    }

    try {
      final calendar.Event event = calendar.Event(
        summary: summary,
        description: description,
        location: location,
        start: calendar.EventDateTime(
          dateTime: startTime,
          timeZone: 'Europe/Rome',
        ),
        end: calendar.EventDateTime(
          dateTime: endTime,
          timeZone: 'Europe/Rome',
        ),
      );

      final calendar.Event updatedEvent = await _calendarApi!.events.update(event, calendarId, eventId);
      return updatedEvent;
    } catch (e) {
      print('Errore nell\'aggiornamento dell\'evento: $e');
      rethrow;
    }
  }

  // Elimina un evento
  Future<bool> deleteEvent(String eventId, {String calendarId = 'primary'}) async {
    if (_calendarApi == null) {
      throw Exception('Calendar API non inizializzata');
    }

    try {
      await _calendarApi!.events.delete(calendarId, eventId);
      return true;
    } catch (e) {
      print('Errore nell\'eliminazione dell\'evento: $e');
      return false;
    }
  }

  // Ottieni statistiche intelligenti
  Future<Map<String, dynamic>> getWeeklyStats() async {
    final List<calendar.Event> events = await getWeekEvents();

    int totalEvents = events.length;
    int completedEvents = 0;
    int upcomingEvents = 0;
    Map<String, int> dailyCount = {};
    Duration totalDuration = Duration.zero;

    final DateTime now = DateTime.now();

    for (final event in events) {
      if (event.start?.dateTime != null && event.end?.dateTime != null) {
        final DateTime startTime = event.start!.dateTime!;
        final DateTime endTime = event.end!.dateTime!;

        // Calcola durata
        totalDuration += endTime.difference(startTime);

        // Conta eventi per giorno
        final String dayKey = '${startTime.day}/${startTime.month}';
        dailyCount[dayKey] = (dailyCount[dayKey] ?? 0) + 1;

        // Classifica eventi
        if (endTime.isBefore(now)) {
          completedEvents++;
        } else {
          upcomingEvents++;
        }
      }
    }

    return {
      'totalEvents': totalEvents,
      'completedEvents': completedEvents,
      'upcomingEvents': upcomingEvents,
      'totalHours': totalDuration.inHours,
      'dailyDistribution': dailyCount,
      'averageEventsPerDay': totalEvents / 7,
    };
  }
}

// Client HTTP personalizzato per l'autenticazione Google
class _GoogleAuthClient extends http.BaseClient {
  final String _accessToken;
  final http.Client _client = http.Client();

  _GoogleAuthClient(this._accessToken);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_accessToken';
    return _client.send(request);
  }

  @override
  void close() {
    _client.close();
  }
}