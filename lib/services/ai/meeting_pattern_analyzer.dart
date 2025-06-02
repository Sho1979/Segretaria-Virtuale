// lib/services/ai/meeting_pattern_analyzer.dart

import 'package:flutter/foundation.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:math';

/// Analizza i pattern dei meeting per fornire suggerimenti intelligenti
class MeetingPatternAnalyzer {
  static const String _patternCacheKey = 'meeting_patterns';
  static const String _userPreferencesKey = 'user_preferences';

  // Pattern identificati
  final Map<String, MeetingPattern> _patterns = {};
  final Map<String, UserPreference> _userPreferences = {};

  // Soglie per l'apprendimento
  static const int _minOccurrencesForPattern = 3;
  static const double _confidenceThreshold = 0.7;

  /// Inizializza l'analyzer caricando i pattern salvati
  Future<void> initialize() async {
    await _loadPatterns();
    await _loadUserPreferences();
  }

  /// Analizza gli eventi storici per identificare pattern
  Future<void> analyzeHistoricalData(List<gcal.Event> events) async {
    if (kDebugMode) {
      print('Analizzando ${events.length} eventi storici...');
    }

    // Raggruppa per tipo di meeting
    final Map<String, List<gcal.Event>> groupedEvents = {};

    for (final event in events) {
      if (event.summary == null || event.start?.dateTime == null) continue;

      final key = _generateEventKey(event);
      groupedEvents.putIfAbsent(key, () => []).add(event);
    }

    // Identifica pattern per ogni gruppo
    groupedEvents.forEach((key, eventList) {
      if (eventList.length >= _minOccurrencesForPattern) {
        final pattern = _extractPattern(key, eventList);
        if (pattern != null) {
          _patterns[key] = pattern;
        }
      }
    });

    await _savePatterns();
  }

  /// Genera una chiave unica per raggruppare eventi simili
  String _generateEventKey(gcal.Event event) {
    final summary = event.summary?.toLowerCase() ?? '';

    // Identifica parole chiave comuni
    final keywords = [
      'standup', 'daily', 'weekly', 'monthly', 'review', 'planning',
      'retrospective', 'demo', 'meeting', 'call', 'sync', '1:1',
      'team', 'project', 'client', 'status', 'report'
    ];

    final foundKeywords = keywords.where((k) => summary.contains(k)).toList();

    // Considera anche i partecipanti per meeting ricorrenti
    final attendeeCount = event.attendees?.length ?? 0;
    final attendeeRange = attendeeCount <= 2 ? 'small' :
    attendeeCount <= 5 ? 'medium' : 'large';

    return '${foundKeywords.join('_')}_${attendeeRange}';
  }

  /// Estrae pattern da una lista di eventi simili
  MeetingPattern? _extractPattern(String key, List<gcal.Event> events) {
    if (events.isEmpty) return null;

    // Analizza durate
    final durations = events
        .where((e) => e.start?.dateTime != null && e.end?.dateTime != null)
        .map((e) => e.end!.dateTime!.difference(e.start!.dateTime!).inMinutes)
        .toList();

    if (durations.isEmpty) return null;

    // Analizza orari preferiti
    final startHours = events
        .where((e) => e.start?.dateTime != null)
        .map((e) => e.start!.dateTime!.hour)
        .toList();

    // Analizza giorni della settimana
    final weekdays = events
        .where((e) => e.start?.dateTime != null)
        .map((e) => e.start!.dateTime!.weekday)
        .toList();

    // Calcola statistiche
    final avgDuration = durations.reduce((a, b) => a + b) / durations.length;
    final mostCommonHour = _findMostCommon(startHours);
    final mostCommonWeekday = _findMostCommon(weekdays);

    // Identifica se è un meeting ricorrente
    final isRecurring = _checkIfRecurring(events);

    // Analizza il contenuto per suggerimenti
    final commonTopics = _extractCommonTopics(events);

    return MeetingPattern(
      key: key,
      averageDuration: avgDuration.round(),
      preferredStartHour: mostCommonHour,
      preferredWeekday: mostCommonWeekday,
      isRecurring: isRecurring,
      occurrences: events.length,
      confidence: _calculateConfidence(events),
      commonTopics: commonTopics,
      lastUpdated: DateTime.now(),
    );
  }

  /// Trova l'elemento più comune in una lista
  T _findMostCommon<T>(List<T> items) {
    final counts = <T, int>{};
    for (final item in items) {
      counts[item] = (counts[item] ?? 0) + 1;
    }

    return counts.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;
  }

  /// Verifica se gli eventi seguono un pattern ricorrente
  bool _checkIfRecurring(List<gcal.Event> events) {
    if (events.length < 3) return false;

    final sortedEvents = events.toList()
      ..sort((a, b) => a.start!.dateTime!.compareTo(b.start!.dateTime!));

    // Calcola gli intervalli tra eventi consecutivi
    final intervals = <int>[];
    for (int i = 1; i < sortedEvents.length; i++) {
      final diff = sortedEvents[i].start!.dateTime!
          .difference(sortedEvents[i - 1].start!.dateTime!)
          .inDays;
      intervals.add(diff);
    }

    // Verifica se gli intervalli sono regolari
    if (intervals.isEmpty) return false;

    final avgInterval = intervals.reduce((a, b) => a + b) / intervals.length;
    final variance = intervals
        .map((i) => pow(i - avgInterval, 2))
        .reduce((a, b) => a + b) / intervals.length;

    // Se la varianza è bassa, è probabilmente ricorrente
    return variance < 4; // Soglia empirica
  }

  /// Estrae argomenti comuni dai meeting
  List<String> _extractCommonTopics(List<gcal.Event> events) {
    final Map<String, int> topicCounts = {};

    // Parole da ignorare
    final stopWords = {
      'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for',
      'of', 'with', 'by', 'from', 'as', 'is', 'was', 'are', 'were',
      'meeting', 'call', 'sync', 'discussion'
    };

    for (final event in events) {
      final words = (event.summary ?? '')
          .toLowerCase()
          .split(RegExp(r'[\s\-_]+'))
          .where((w) => w.length > 3 && !stopWords.contains(w));

      for (final word in words) {
        topicCounts[word] = (topicCounts[word] ?? 0) + 1;
      }
    }

    // Ordina per frequenza e prendi i top 5
    final sortedTopics = topicCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sortedTopics
        .take(5)
        .where((e) => e.value >= events.length * 0.3) // Presente in almeno 30% dei meeting
        .map((e) => e.key)
        .toList();
  }

  /// Calcola la confidenza del pattern
  double _calculateConfidence(List<gcal.Event> events) {
    if (events.length < _minOccurrencesForPattern) return 0.0;

    // Fattori che aumentano la confidenza:
    // 1. Numero di occorrenze
    // 2. Regolarità temporale
    // 3. Consistenza nella durata

    final occurrenceScore = min(events.length / 10.0, 1.0);
    final regularityScore = _checkIfRecurring(events) ? 1.0 : 0.5;

    // Calcola la consistenza della durata
    final durations = events
        .where((e) => e.start?.dateTime != null && e.end?.dateTime != null)
        .map((e) => e.end!.dateTime!.difference(e.start!.dateTime!).inMinutes)
        .toList();

    final durationConsistency = durations.isNotEmpty
        ? 1.0 - (_standardDeviation(durations) / (_average(durations) + 1))
        : 0.0;

    return (occurrenceScore + regularityScore + durationConsistency) / 3.0;
  }

  /// Calcola la deviazione standard
  double _standardDeviation(List<int> values) {
    if (values.isEmpty) return 0.0;
    final avg = _average(values);
    final variance = values
        .map((v) => pow(v - avg, 2))
        .reduce((a, b) => a + b) / values.length;
    return sqrt(variance);
  }

  /// Calcola la media
  double _average(List<int> values) {
    if (values.isEmpty) return 0.0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  /// Suggerisce slot ottimali per un nuovo meeting
  Future<List<SlotSuggestion>> suggestOptimalSlots({
    required String meetingType,
    required int duration,
    required DateTime startDate,
    required DateTime endDate,
    List<gcal.Event>? existingEvents,
  }) async {
    final suggestions = <SlotSuggestion>[];

    // Trova pattern simili
    final relevantPatterns = _patterns.entries
        .where((e) => e.value.confidence >= _confidenceThreshold)
        .where((e) => _isPatternRelevant(e.value, meetingType))
        .toList();

    // Se ci sono pattern rilevanti, usa quelli
    if (relevantPatterns.isNotEmpty) {
      for (final pattern in relevantPatterns) {
        final patternSuggestions = _generateSuggestionsFromPattern(
          pattern.value,
          duration,
          startDate,
          endDate,
          existingEvents ?? [],
        );
        suggestions.addAll(patternSuggestions);
      }
    }

    // Aggiungi suggerimenti basati sulle preferenze generali dell'utente
    final generalSuggestions = _generateGeneralSuggestions(
      duration,
      startDate,
      endDate,
      existingEvents ?? [],
    );
    suggestions.addAll(generalSuggestions);

    // Ordina per punteggio
    suggestions.sort((a, b) => b.score.compareTo(a.score));

    return suggestions.take(5).toList(); // Top 5 suggerimenti
  }

  /// Verifica se un pattern è rilevante per un tipo di meeting
  bool _isPatternRelevant(MeetingPattern pattern, String meetingType) {
    final typeWords = meetingType.toLowerCase().split(' ');
    final patternWords = pattern.key.toLowerCase().split('_');

    // Controlla se ci sono parole in comune
    return typeWords.any((w) => patternWords.contains(w)) ||
        pattern.commonTopics.any((t) => meetingType.toLowerCase().contains(t));
  }

  /// Genera suggerimenti basati su un pattern
  List<SlotSuggestion> _generateSuggestionsFromPattern(
      MeetingPattern pattern,
      int requestedDuration,
      DateTime startDate,
      DateTime endDate,
      List<gcal.Event> existingEvents,
      ) {
    final suggestions = <SlotSuggestion>[];

    // Usa la durata del pattern o quella richiesta
    final duration = requestedDuration > 0 ? requestedDuration : pattern.averageDuration;

    // Genera slot nei giorni preferiti
    DateTime current = startDate;
    while (current.isBefore(endDate)) {
      if (current.weekday == pattern.preferredWeekday) {
        final slotStart = DateTime(
          current.year,
          current.month,
          current.day,
          pattern.preferredStartHour,
        );

        final slotEnd = slotStart.add(Duration(minutes: duration));

        // Verifica disponibilità
        if (!_hasConflict(slotStart, slotEnd, existingEvents)) {
          suggestions.add(SlotSuggestion(
            start: slotStart,
            end: slotEnd,
            score: pattern.confidence,
            reason: 'Basato su pattern ricorrente (${pattern.occurrences} occorrenze)',
            patternKey: pattern.key,
          ));
        }
      }
      current = current.add(const Duration(days: 1));
    }

    return suggestions;
  }

  /// Genera suggerimenti generali basati sulle preferenze utente
  List<SlotSuggestion> _generateGeneralSuggestions(
      int duration,
      DateTime startDate,
      DateTime endDate,
      List<gcal.Event> existingEvents,
      ) {
    final suggestions = <SlotSuggestion>[];

    // Orari preferiti generali (mattina produttiva, pomeriggio per collaborazione)
    final preferredSlots = [
      {'hour': 9, 'score': 0.8, 'reason': 'Inizio giornata produttivo'},
      {'hour': 10, 'score': 0.9, 'reason': 'Orario di punta per focus'},
      {'hour': 11, 'score': 0.85, 'reason': 'Pre-pranzo produttivo'},
      {'hour': 14, 'score': 0.7, 'reason': 'Post-pranzo per collaborazione'},
      {'hour': 15, 'score': 0.75, 'reason': 'Pomeriggio produttivo'},
    ];

    DateTime current = startDate;
    while (current.isBefore(endDate) && suggestions.length < 10) {
      // Evita weekend se non specificato diversamente
      if (current.weekday <= 5) {
        for (final slot in preferredSlots) {
          final slotStart = DateTime(
            current.year,
            current.month,
            current.day,
            slot['hour'] as int,
          );

          final slotEnd = slotStart.add(Duration(minutes: duration));

          if (!_hasConflict(slotStart, slotEnd, existingEvents)) {
            suggestions.add(SlotSuggestion(
              start: slotStart,
              end: slotEnd,
              score: slot['score'] as double,
              reason: slot['reason'] as String,
            ));
          }
        }
      }
      current = current.add(const Duration(days: 1));
    }

    return suggestions;
  }

  /// Verifica se c'è un conflitto con eventi esistenti
  bool _hasConflict(DateTime start, DateTime end, List<gcal.Event> events) {
    for (final event in events) {
      if (event.start?.dateTime == null || event.end?.dateTime == null) continue;

      final eventStart = event.start!.dateTime!;
      final eventEnd = event.end!.dateTime!;

      // Controlla sovrapposizione
      if (start.isBefore(eventEnd) && end.isAfter(eventStart)) {
        return true;
      }
    }
    return false;
  }

  /// Apprende dal feedback dell'utente
  Future<void> learnFromFeedback({
    required String meetingType,
    required DateTime scheduledTime,
    required int duration,
    required FeedbackType feedback,
    String? reason,
  }) async {
    final key = _generateEventKey(gcal.Event(
      summary: meetingType,
      start: gcal.EventDateTime(dateTime: scheduledTime),
      end: gcal.EventDateTime(dateTime: scheduledTime.add(Duration(minutes: duration))),
    ));

    // Aggiorna le preferenze utente
    final preference = _userPreferences[key] ?? UserPreference(
      meetingType: key,
      preferences: {},
    );

    // Registra il feedback
    final feedbackKey = '${scheduledTime.weekday}_${scheduledTime.hour}';
    preference.preferences[feedbackKey] = FeedbackData(
      type: feedback,
      timestamp: DateTime.now(),
      reason: reason,
    );

    _userPreferences[key] = preference;
    await _saveUserPreferences();

    // Se il feedback è positivo, rafforza il pattern
    if (feedback == FeedbackType.positive && _patterns.containsKey(key)) {
      _patterns[key]!.confidence = min(_patterns[key]!.confidence * 1.1, 1.0);
      await _savePatterns();
    }
  }

  /// Ottiene insights sui pattern di meeting
  MeetingInsights getInsights() {
    final totalMeetings = _patterns.values
        .map((p) => p.occurrences)
        .fold(0, (a, b) => a + b);

    final avgDuration = _patterns.values.isNotEmpty
        ? _patterns.values
        .map((p) => p.averageDuration)
        .reduce((a, b) => a + b) / _patterns.values.length
        : 0.0;

    final busiestDay = _patterns.values.isNotEmpty
        ? _findMostCommon(_patterns.values.map((p) => p.preferredWeekday).toList())
        : 1;

    final busiestHour = _patterns.values.isNotEmpty
        ? _findMostCommon(_patterns.values.map((p) => p.preferredStartHour).toList())
        : 9;

    final recurringMeetings = _patterns.values
        .where((p) => p.isRecurring)
        .length;

    final topTopics = <String, int>{};
    for (final pattern in _patterns.values) {
      for (final topic in pattern.commonTopics) {
        topTopics[topic] = (topTopics[topic] ?? 0) + pattern.occurrences;
      }
    }

    final sortedTopics = topTopics.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return MeetingInsights(
      totalAnalyzedMeetings: totalMeetings,
      averageMeetingDuration: avgDuration,
      busiestDay: _weekdayName(busiestDay),
      busiestHour: '$busiestHour:00',
      recurringMeetingsCount: recurringMeetings,
      topDiscussionTopics: sortedTopics.take(5).map((e) => e.key).toList(),
      patterns: _patterns.values.toList(),
    );
  }

  String _weekdayName(int day) {
    const days = ['', 'Lunedì', 'Martedì', 'Mercoledì', 'Giovedì', 'Venerdì', 'Sabato', 'Domenica'];
    return days[day];
  }

  /// Salva i pattern identificati
  Future<void> _savePatterns() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _patterns.map((k, v) => MapEntry(k, v.toJson()));
    await prefs.setString(_patternCacheKey, jsonEncode(data));
  }

  /// Carica i pattern salvati
  Future<void> _loadPatterns() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_patternCacheKey);
    if (data != null) {
      final Map<String, dynamic> decoded = jsonDecode(data);
      _patterns.clear();
      decoded.forEach((k, v) {
        _patterns[k] = MeetingPattern.fromJson(v);
      });
    }
  }

  /// Salva le preferenze utente
  Future<void> _saveUserPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _userPreferences.map((k, v) => MapEntry(k, v.toJson()));
    await prefs.setString(_userPreferencesKey, jsonEncode(data));
  }

  /// Carica le preferenze utente
  Future<void> _loadUserPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_userPreferencesKey);
    if (data != null) {
      final Map<String, dynamic> decoded = jsonDecode(data);
      _userPreferences.clear();
      decoded.forEach((k, v) {
        _userPreferences[k] = UserPreference.fromJson(v);
      });
    }
  }
}

/// Rappresenta un pattern di meeting identificato
class MeetingPattern {
  final String key;
  final int averageDuration; // in minuti
  final int preferredStartHour;
  final int preferredWeekday;
  final bool isRecurring;
  final int occurrences;
  double confidence;
  final List<String> commonTopics;
  final DateTime lastUpdated;

  MeetingPattern({
    required this.key,
    required this.averageDuration,
    required this.preferredStartHour,
    required this.preferredWeekday,
    required this.isRecurring,
    required this.occurrences,
    required this.confidence,
    required this.commonTopics,
    required this.lastUpdated,
  });

  Map<String, dynamic> toJson() => {
    'key': key,
    'averageDuration': averageDuration,
    'preferredStartHour': preferredStartHour,
    'preferredWeekday': preferredWeekday,
    'isRecurring': isRecurring,
    'occurrences': occurrences,
    'confidence': confidence,
    'commonTopics': commonTopics,
    'lastUpdated': lastUpdated.toIso8601String(),
  };

  factory MeetingPattern.fromJson(Map<String, dynamic> json) => MeetingPattern(
    key: json['key'],
    averageDuration: json['averageDuration'],
    preferredStartHour: json['preferredStartHour'],
    preferredWeekday: json['preferredWeekday'],
    isRecurring: json['isRecurring'],
    occurrences: json['occurrences'],
    confidence: json['confidence'],
    commonTopics: List<String>.from(json['commonTopics']),
    lastUpdated: DateTime.parse(json['lastUpdated']),
  );
}

/// Suggerimento di slot per meeting
class SlotSuggestion {
  final DateTime start;
  final DateTime end;
  final double score;
  final String reason;
  final String? patternKey;

  SlotSuggestion({
    required this.start,
    required this.end,
    required this.score,
    required this.reason,
    this.patternKey,
  });
}

/// Tipo di feedback dell'utente
enum FeedbackType {
  positive,
  negative,
  neutral,
}

/// Dati di feedback
class FeedbackData {
  final FeedbackType type;
  final DateTime timestamp;
  final String? reason;

  FeedbackData({
    required this.type,
    required this.timestamp,
    this.reason,
  });

  Map<String, dynamic> toJson() => {
    'type': type.index,
    'timestamp': timestamp.toIso8601String(),
    'reason': reason,
  };

  factory FeedbackData.fromJson(Map<String, dynamic> json) => FeedbackData(
    type: FeedbackType.values[json['type']],
    timestamp: DateTime.parse(json['timestamp']),
    reason: json['reason'],
  );
}

/// Preferenze utente per tipo di meeting
class UserPreference {
  final String meetingType;
  final Map<String, FeedbackData> preferences;

  UserPreference({
    required this.meetingType,
    required this.preferences,
  });

  Map<String, dynamic> toJson() => {
    'meetingType': meetingType,
    'preferences': preferences.map((k, v) => MapEntry(k, v.toJson())),
  };

  factory UserPreference.fromJson(Map<String, dynamic> json) => UserPreference(
    meetingType: json['meetingType'],
    preferences: (json['preferences'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, FeedbackData.fromJson(v)),
    ),
  );
}

/// Insights sui meeting
class MeetingInsights {
  final int totalAnalyzedMeetings;
  final double averageMeetingDuration;
  final String busiestDay;
  final String busiestHour;
  final int recurringMeetingsCount;
  final List<String> topDiscussionTopics;
  final List<MeetingPattern> patterns;

  MeetingInsights({
    required this.totalAnalyzedMeetings,
    required this.averageMeetingDuration,
    required this.busiestDay,
    required this.busiestHour,
    required this.recurringMeetingsCount,
    required this.topDiscussionTopics,
    required this.patterns,
  });
}