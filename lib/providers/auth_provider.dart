// lib/providers/auth_provider.dart

import 'package:flutter/foundation.dart';
import '../services/google_calendar_service.dart';
import '../services/outlook_calendar_service.dart';

class AuthProvider with ChangeNotifier {
  final GoogleCalendarService _googleCalendarService = GoogleCalendarService();
  final OutlookCalendarService _outlookCalendarService = OutlookCalendarService();

  bool _isLoading = false;
  String? _errorMessage;

  // Getters
  GoogleCalendarService? get googleCalendarService => _googleCalendarService;
  OutlookCalendarService? get outlookCalendarService => _outlookCalendarService;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  bool get isGoogleSignedIn => _googleCalendarService.isSignedIn;
  bool get isOutlookSignedIn => _outlookCalendarService.isSignedIn;
  bool get isAnyServiceConnected => isGoogleSignedIn || isOutlookSignedIn;

  // Inizializza i servizi
  Future<void> initialize() async {
    _setLoading(true);
    try {
      // Inizializza Google Calendar Service
      _googleCalendarService.initialize();

      // Inizializza Outlook Calendar Service
      await _outlookCalendarService.initialize();

      // Prova il login silenzioso per Google
      await _googleCalendarService.signInSilently();

      // Controlla se c'è un callback OAuth per Outlook
      if (kIsWeb) {
        await _outlookCalendarService.handleWebCallback();
      }

      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Errore durante l\'inizializzazione: $e';
      if (kDebugMode) {
        print(_errorMessage);
      }
    } finally {
      _setLoading(false);
    }
  }

  // Login Google
  Future<bool> signInGoogle() async {
    _setLoading(true);
    _errorMessage = null;

    try {
      final success = await _googleCalendarService.signIn();
      if (success) {
        notifyListeners();
      } else {
        _errorMessage = 'Login Google annullato';
      }
      return success;
    } catch (e) {
      _errorMessage = 'Errore durante il login Google: $e';
      if (kDebugMode) {
        print(_errorMessage);
      }
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // Login Outlook
  Future<bool> signInOutlook() async {
    _setLoading(true);
    _errorMessage = null;

    try {
      final success = await _outlookCalendarService.signIn();
      if (success) {
        notifyListeners();
      } else {
        _errorMessage = 'Login Outlook annullato';
      }
      return success;
    } catch (e) {
      _errorMessage = 'Errore durante il login Outlook: $e';
      if (kDebugMode) {
        print(_errorMessage);
      }
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // Logout Google
  Future<void> signOutGoogle() async {
    _setLoading(true);
    try {
      await _googleCalendarService.signOut();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Errore durante il logout Google: $e';
      if (kDebugMode) {
        print(_errorMessage);
      }
    } finally {
      _setLoading(false);
    }
  }

  // Logout Outlook
  Future<void> signOutOutlook() async {
    _setLoading(true);
    try {
      await _outlookCalendarService.signOut();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Errore durante il logout Outlook: $e';
      if (kDebugMode) {
        print(_errorMessage);
      }
    } finally {
      _setLoading(false);
    }
  }

  // Logout da tutti i servizi
  Future<void> signOutAll() async {
    _setLoading(true);
    try {
      await Future.wait([
        if (isGoogleSignedIn) _googleCalendarService.signOut(),
        if (isOutlookSignedIn) _outlookCalendarService.signOut(),
      ]);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Errore durante il logout: $e';
      if (kDebugMode) {
        print(_errorMessage);
      }
    } finally {
      _setLoading(false);
    }
  }

  // Helper per impostare lo stato di caricamento
  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  // Pulisce i messaggi di errore
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}