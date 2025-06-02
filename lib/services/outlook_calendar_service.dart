// lib/services/outlook_calendar_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart'; // Per kIsWeb
import 'package:flutter/material.dart'; // Necessario per kIsWeb e potenziali UI
import 'package:http/http.dart' as http;
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:shared_preferences/shared_preferences.dart';
// url_launcher non è usato direttamente qui ma potrebbe servire
// import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'package:googleapis/calendar/v3.dart' as gcal;

// Aggiunto import per dart:html
import 'dart:html' as html;


class OutlookCalendarService {
  static const String clientId = 'a3a43eeb-576e-45a4-bb9d-0551032005a0';
  static String get redirectUri {
    if (kIsWeb) {
      // Per web, usa la pagina auth.html
      // final url = WebUtils.getCurrentUrl(); // Vecchia chiamata
      final url = html.window.location.href; // NUOVA CHIAMATA DIRETTA
      final uri = Uri.parse(url);
      return '${uri.origin}/auth.html';
    }
    return 'http://localhost:8080';
  }
  static const String authority = 'https://login.microsoftonline.com/common';

  static const List<String> scopes = [
    'openid',
    'profile',
    'email',
    'offline_access',
    'https://graph.microsoft.com/Calendars.Read',
    'https://graph.microsoft.com/Calendars.ReadWrite',
    'https://graph.microsoft.com/User.Read',
  ];

  final FlutterAppAuth _appAuth = const FlutterAppAuth();
  String? _accessToken;
  String? _refreshToken;
  Map<String, dynamic>? _userInfo;

  // Setter per il token di accesso
  set accessToken(String? token) {
    _accessToken = token;
  }

  // Getter per verificare se il servizio è configurato
  bool get isConfigured => _accessToken != null;

  Future<bool> signIn() async {
    if (kIsWeb) {
      return _signInWeb();
    } else {
      return _signInMobile();
    }
  }

  Future<bool> _signInWeb() async {
    try {
      // Salva che stiamo facendo login dal calendar
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('oauth_login_in_progress', true);

      // Per il web, utilizziamo il flusso di autorizzazione OAuth2 con redirect
      final authUrl = Uri.https(
        'login.microsoftonline.com',
        '/common/oauth2/v2.0/authorize',
        {
          'client_id': clientId,
          'response_type': 'token',
          'redirect_uri': redirectUri,
          'scope': scopes.join(' '),
          'response_mode': 'fragment',
          'prompt': 'select_account',
          'state': 'outlook_auth', // Aggiungiamo uno state per identificare il callback
        },
      );

      // Invece di aprire una popup, facciamo il redirect diretto
      // WebUtils.navigateTo(authUrl.toString()); // Vecchia chiamata
      if (kIsWeb) { // Controllo esplicito
        html.window.location.assign(authUrl.toString()); // NUOVA CHIAMATA DIRETTA
      } else {
        // Su mobile, questo metodo non dovrebbe essere chiamato, ma per sicurezza
        print("Tentativo di navigazione web su piattaforma non web.");
      }


      // Il risultato verrà gestito quando l'app si ricarica
      return false; // Ritorniamo false perché il processo non è ancora completo
    } catch (e) {
      print('Errore durante il login web Outlook: $e');
      return false;
    }
  }

  // Metodo per gestire il callback OAuth quando l'app si ricarica
  Future<bool> handleWebCallback() async {
    if (!kIsWeb) return false;

    try {
      // Prima controlla localStorage per il token salvato
      // final savedToken = WebUtils.getLocalStorageItem('oauth_access_token'); // Vecchia chiamata
      final savedToken = html.window.localStorage['oauth_access_token']; // NUOVA CHIAMATA DIRETTA
      if (savedToken != null) {
        _accessToken = savedToken;
        // WebUtils.removeLocalStorageItem('oauth_access_token'); // Vecchia chiamata
        html.window.localStorage.remove('oauth_access_token'); // NUOVA CHIAMATA DIRETTA

        // Salva il token nelle SharedPreferences
        await _saveTokens();

        // Ottieni le info utente
        await _getUserInfo();

        return true;
      }

      // Altrimenti controlla l'URL come prima
      // final url = WebUtils.getCurrentUrl(); // Vecchia chiamata
      final url = html.window.location.href; // NUOVA CHIAMATA DIRETTA
      final uri = Uri.parse(url);

      // Se l'URL contiene il fragment con access_token
      if (uri.fragment.contains('access_token')) {
        final params = Uri.splitQueryString(uri.fragment);

        if (params.containsKey('access_token')) {
          _accessToken = params['access_token'];

          print('Token Outlook ricevuto dal callback');

          // Salva il token
          await _saveTokens();

          // Ottieni le info utente
          await _getUserInfo();

          // Pulisci l'URL rimuovendo il fragment
          // WebUtils.replaceHistoryState('${uri.origin}${uri.path}'); // Vecchia chiamata
          if (kIsWeb) { // Controllo esplicito
            html.window.history.replaceState(null, '', '${uri.origin}${uri.path}'); // NUOVA CHIAMATA DIRETTA
          }

          return true;
        }
      }
    } catch (e) {
      print('Errore nel gestire il callback OAuth: $e');
    }

    return false;
  }

  Future<bool> _signInMobile() async {
    try {
      final AuthorizationTokenResponse? result = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          clientId,
          redirectUri,
          issuer: authority,
          scopes: scopes,
          promptValues: ['login'],
          additionalParameters: {
            'prompt': 'select_account',
          },
        ),
      );

      if (result != null) {
        _accessToken = result.accessToken;
        _refreshToken = result.refreshToken;

        await _saveTokens();
        await _getUserInfo();

        return true;
      }
      return false;
    } catch (e) {
      print('Errore durante il login mobile Outlook: $e');
      return false;
    }
  }

  Future<void> _saveTokens() async {
    if (_accessToken != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('outlook_access_token', _accessToken!);
      if (_refreshToken != null) {
        await prefs.setString('outlook_refresh_token', _refreshToken!);
      }
    }
  }

  Future<void> _loadTokens() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString('outlook_access_token');
    _refreshToken = prefs.getString('outlook_refresh_token');
  }

  Future<void> checkAndRefreshToken() async {
    await _loadTokens();

    if (_accessToken != null) {
      // Prova a fare una richiesta di test
      try {
        final response = await http.get(
          Uri.parse('https://graph.microsoft.com/v1.0/me'),
          headers: {
            'Authorization': 'Bearer $_accessToken',
            'Content-Type': 'application/json',
          },
        );

        if (response.statusCode == 401) {
          // Token scaduto, pulisci tutto
          print('Token Outlook scaduto, pulizia in corso...');
          await signOut();
        } else if (response.statusCode == 200) {
          // Token valido, aggiorna info utente
          _userInfo = json.decode(response.body);
        }
      } catch (e) {
        print('Errore verifica token: $e');
        await signOut();
      }
    }
  }

  Future<void> initialize() async {
    await checkAndRefreshToken();
  }

  Future<void> _getUserInfo() async {
    if (_accessToken == null) return;

    try {
      final response = await http.get(
        Uri.parse('https://graph.microsoft.com/v1.0/me'),
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        _userInfo = json.decode(response.body);
        print('User info: $_userInfo');
      } else {
        print('Errore nel recupero info utente: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Errore nel recupero info utente: $e');
    }
  }

  // Ottieni eventi per una data specifica
  Future<List<OutlookEvent>> getEventsForDate(DateTime date) async {
    if (_accessToken == null) {
      await _loadTokens();
      if (_accessToken == null) {
        print('Nessun token Outlook disponibile');
        return [];
      }
    }

    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    // Formatta le date in ISO 8601 con timezone UTC
    final startTime = startOfDay.toUtc().toIso8601String();
    final endTime = endOfDay.toUtc().toIso8601String();

    try {
      final url = Uri.parse('https://graph.microsoft.com/v1.0/me/calendarview')
          .replace(queryParameters: {
        'startDateTime': startTime,
        'endDateTime': endTime,
        '\$orderby': 'start/dateTime',
        '\$top': '50',
      });

      print('Richiesta eventi Outlook per: ${date.toString()}');

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Prefer': 'outlook.timezone="Europe/Rome"',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final events = data['value'] as List;

        print('Eventi Outlook trovati: ${events.length}');

        return events.map((e) => OutlookEvent.fromJson(e)).toList();
      } else if (response.statusCode == 401) {
        // Token scaduto
        print('Token Outlook scaduto durante recupero eventi');
        await signOut();
        return [];
      }

      print('Errore nel recupero eventi Outlook: ${response.statusCode} - ${response.body}');
      return [];
    } catch (e) {
      print('Errore nel recupero eventi Outlook per data: $e');
      return [];
    }
  }

  Future<List<OutlookEvent>> getTodayEvents() async {
    if (_accessToken == null) {
      await _loadTokens();
      if (_accessToken == null) return [];
    }

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return _getEvents(startOfDay, endOfDay);
  }

  Future<List<OutlookEvent>> getWeekEvents() async {
    if (_accessToken == null) {
      await _loadTokens();
      if (_accessToken == null) return [];
    }

    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 7));

    return _getEvents(startOfWeek, endOfWeek);
  }

  Future<List<OutlookEvent>> _getEvents(DateTime start, DateTime end) async {
    try {
      final url = Uri.parse('https://graph.microsoft.com/v1.0/me/calendarview')
          .replace(queryParameters: {
        'startDateTime': start.toUtc().toIso8601String(),
        'endDateTime': end.toUtc().toIso8601String(),
        '\$orderby': 'start/dateTime',
        '\$top': '50',
        '\$select': 'subject,body,bodyPreview,start,end,location,isAllDay,categories,id',
      });

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Prefer': 'outlook.timezone="Europe/Rome"',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final events = data['value'] as List;

        return events.map((e) => OutlookEvent.fromJson(e)).toList();
      } else if (response.statusCode == 401) {
        // Token scaduto
        if (!kIsWeb && _refreshToken != null) {
          await _refreshAccessToken();
          if (_accessToken != null) {
            return _getEvents(start, end);
          }
        } else {
          await signOut();
        }
      }

      print('Errore nel recupero eventi: ${response.statusCode} - ${response.body}');
      return [];
    } catch (e) {
      print('Errore nel recupero eventi Outlook: $e');
      return [];
    }
  }

  /// Ottiene eventi dal calendario Outlook in formato Google Calendar
  Future<List<gcal.Event>> getEvents({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final outlookEvents = await _getEvents(startDate, endDate);

      // Converti eventi Outlook in formato Google Calendar
      return outlookEvents.map((event) => _convertToGoogleEvent(event)).toList();
    } catch (e) {
      if (kDebugMode) {
        print('Errore conversione eventi: $e');
      }
      return [];
    }
  }

  /// Converte un evento Outlook in formato Google Calendar
  gcal.Event _convertToGoogleEvent(OutlookEvent outlookEvent) {
    final event = gcal.Event();

    // Mappatura campi base
    event.summary = outlookEvent.subject ?? '';
    event.description = outlookEvent.bodyPreview ?? '';
    event.location = outlookEvent.location ?? '';
    event.id = outlookEvent.id;

    // Mappatura date
    if (outlookEvent.start != null) {
      event.start = gcal.EventDateTime(
        dateTime: outlookEvent.start,
        timeZone: 'Europe/Rome',
      );
    }

    if (outlookEvent.end != null) {
      event.end = gcal.EventDateTime(
        dateTime: outlookEvent.end,
        timeZone: 'Europe/Rome',
      );
    }

    // Status
    event.status = 'confirmed';

    return event;
  }

  Future<void> _refreshAccessToken() async {
    if (kIsWeb || _refreshToken == null) return;

    try {
      final result = await _appAuth.token(
        TokenRequest(
          clientId,
          redirectUri,
          issuer: authority,
          refreshToken: _refreshToken,
          scopes: scopes,
        ),
      );

      if (result != null) {
        _accessToken = result.accessToken;
        _refreshToken = result.refreshToken ?? _refreshToken;
        await _saveTokens();
      }
    } catch (e) {
      print('Errore nel refresh del token: $e');
    }
  }

  Future<Map<String, dynamic>> getWeeklyStats() async {
    final weekEvents = await getWeekEvents();

    double totalHours = 0;
    for (var event in weekEvents) {
      if (event.start != null && event.end != null) {
        totalHours += event.end!.difference(event.start!).inMinutes / 60.0;
      }
    }

    return {
      'totalEvents': weekEvents.length,
      'totalHours': totalHours.toStringAsFixed(1),
    };
  }

  bool get isSignedIn => _accessToken != null;
  bool get hasValidToken => _accessToken != null && _accessToken!.isNotEmpty;

  Map<String, dynamic>? get currentUser => _userInfo;

  Future<void> signOut() async {
    _accessToken = null;
    _refreshToken = null;
    _userInfo = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('outlook_access_token');
    await prefs.remove('outlook_refresh_token');
  }
}

class OutlookEvent {
  final String? id;
  final String? subject;
  final DateTime? start;
  final DateTime? end;
  final String? location;
  final String? body;
  final String? bodyPreview;
  final bool isAllDay;
  final List<String> categories;

  OutlookEvent({
    this.id,
    this.subject,
    this.start,
    this.end,
    this.location,
    this.body,
    this.bodyPreview,
    this.isAllDay = false,
    this.categories = const [],
  });

  factory OutlookEvent.fromJson(Map<String, dynamic> json) {
    DateTime? parseDateTime(Map<String, dynamic>? dateTimeJson) {
      if (dateTimeJson == null || dateTimeJson['dateTime'] == null) return null;
      return DateTime.parse(dateTimeJson['dateTime'] + 'Z').toLocal();
    }

    return OutlookEvent(
      id: json['id'],
      subject: json['subject'],
      start: parseDateTime(json['start']),
      end: parseDateTime(json['end']),
      location: json['location']?['displayName'],
      body: json['body']?['content'],
      bodyPreview: json['bodyPreview'],
      isAllDay: json['isAllDay'] ?? false,
      categories: json['categories'] != null
          ? List<String>.from(json['categories'])
          : [],
    );
  }
}