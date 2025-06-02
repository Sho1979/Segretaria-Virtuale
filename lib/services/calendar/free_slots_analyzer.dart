// lib/services/calendar/free_slots_analyzer.dart

import 'package:flutter/material.dart';
import '../google_calendar_service.dart';
import '../outlook_calendar_service.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;

/// Livello di energia per uno slot
enum EnergyLevel {
  high,
  medium,
  low
}

/// Rappresenta uno slot ottimale nel calendario
class OptimalSlot {
  final DateTime start;
  final DateTime end;
  final EnergyLevel energyLevel;
  final String reason;

  OptimalSlot({
    required this.start,
    required this.end,
    required this.energyLevel,
    this.reason = '',
  });
}

/// Rappresenta uno slot libero nel calendario
class FreeSlot {
  final DateTime start;
  final DateTime end;
  final Duration duration;
  final double energyScore; // 0-1, basato su ora del giorno e pattern utente
  final String suggestion;

  FreeSlot({
    required this.start,
    required this.end,
    required this.duration,
    required this.energyScore,
    required this.suggestion,
  });

  bool get isHighEnergy => energyScore > 0.7;
  bool get isMediumEnergy => energyScore > 0.4 && energyScore <= 0.7;
  bool get isLowEnergy => energyScore <= 0.4;
}

/// Servizio per analizzare gli slot liberi nel calendario
class FreeSlotAnalyzerService {
  // Configurazione orario lavorativo (personalizzabile per utente)
  final TimeOfDay workDayStart = const TimeOfDay(hour: 9, minute: 0);
  final TimeOfDay workDayEnd = const TimeOfDay(hour: 18, minute: 0);
  final TimeOfDay lunchStart = const TimeOfDay(hour: 12, minute: 30);
  final TimeOfDay lunchEnd = const TimeOfDay(hour: 13, minute: 30);

  // Pattern energia durante il giorno (personalizzabile con ML)
  final Map<int, double> defaultEnergyPattern = {
    6: 0.3,   // 6:00 - Bassa energia
    7: 0.4,   // 7:00
    8: 0.6,   // 8:00
    9: 0.8,   // 9:00 - Alta energia mattutina
    10: 0.9,  // 10:00 - Picco mattutino
    11: 0.85, // 11:00
    12: 0.5,  // 12:00 - Calo pre-pranzo
    13: 0.4,  // 13:00 - Post pranzo
    14: 0.6,  // 14:00
    15: 0.7,  // 15:00 - Ripresa pomeridiana
    16: 0.75, // 16:00
    17: 0.6,  // 17:00
    18: 0.4,  // 18:00 - Fine giornata
    19: 0.3,  // 19:00
    20: 0.2,  // 20:00 - Energia serale bassa
  };

  /// Trova slot ottimali per attività
  Future<List<OptimalSlot>> findOptimalSlots({
    required DateTime startDate,
    required DateTime endDate,
    required List<gcal.Event> currentEvents,
    Duration minDuration = const Duration(minutes: 30),
  }) async {
    final List<OptimalSlot> optimalSlots = [];

    // Analizza ogni giorno nel periodo
    DateTime currentDay = DateTime(startDate.year, startDate.month, startDate.day);
    final endDay = DateTime(endDate.year, endDate.month, endDate.day);

    while (!currentDay.isAfter(endDay)) {
      final daySlots = await _findDaySlots(currentDay, currentEvents, minDuration);
      optimalSlots.addAll(daySlots);
      currentDay = currentDay.add(const Duration(days: 1));
    }

    // Ordina per energia e orario
    optimalSlots.sort((a, b) {
      // Prima per livello di energia (alto -> basso)
      final energyCompare = _energyLevelToInt(b.energyLevel).compareTo(_energyLevelToInt(a.energyLevel));
      if (energyCompare != 0) return energyCompare;

      // Poi per orario
      return a.start.compareTo(b.start);
    });

    return optimalSlots;
  }

  /// Trova slot ottimali per un giorno specifico
  Future<List<OptimalSlot>> _findDaySlots(
      DateTime date,
      List<gcal.Event> allEvents,
      Duration minDuration,
      ) async {
    final List<OptimalSlot> slots = [];

    // Filtra eventi per questo giorno
    final dayEvents = allEvents.where((event) {
      final eventStart = event.start?.dateTime ?? event.start?.date;
      if (eventStart == null) return false;

      return eventStart.year == date.year &&
          eventStart.month == date.month &&
          eventStart.day == date.day;
    }).toList();

    // Ordina eventi per ora di inizio
    dayEvents.sort((a, b) {
      final aStart = a.start?.dateTime ?? a.start?.date ?? date;
      final bStart = b.start?.dateTime ?? b.start?.date ?? date;
      return aStart.compareTo(bStart);
    });

    // Definisci inizio e fine della giornata lavorativa
    final dayStart = DateTime(
      date.year, date.month, date.day,
      workDayStart.hour, workDayStart.minute,
    );
    final dayEnd = DateTime(
      date.year, date.month, date.day,
      workDayEnd.hour, workDayEnd.minute,
    );

    // Se siamo oggi, non considerare slot passati
    final now = DateTime.now();
    final effectiveStart = date.day == now.day && date.month == now.month && date.year == now.year
        ? (now.isAfter(dayStart) ? now.add(const Duration(minutes: 15)) : dayStart)
        : dayStart;

    // Se non ci sono eventi, l'intera giornata è libera
    if (dayEvents.isEmpty) {
      if (effectiveStart.isBefore(dayEnd)) {
        slots.add(_createOptimalSlot(effectiveStart, dayEnd));
      }
    } else {
      // Controlla slot prima del primo evento
      final firstEventStart = dayEvents.first.start?.dateTime ?? dayEvents.first.start?.date ?? date;
      if (firstEventStart.isAfter(effectiveStart) &&
          firstEventStart.difference(effectiveStart) >= minDuration) {
        slots.add(_createOptimalSlot(effectiveStart, firstEventStart));
      }

      // Controlla slot tra eventi
      for (int i = 0; i < dayEvents.length - 1; i++) {
        final currentEnd = dayEvents[i].end?.dateTime ?? dayEvents[i].end?.date ?? date;
        final nextStart = dayEvents[i + 1].start?.dateTime ?? dayEvents[i + 1].start?.date ?? date;

        if (nextStart.isAfter(currentEnd) &&
            nextStart.difference(currentEnd) >= minDuration) {
          slots.add(_createOptimalSlot(currentEnd, nextStart));
        }
      }

      // Controlla slot dopo l'ultimo evento
      final lastEventEnd = dayEvents.last.end?.dateTime ?? dayEvents.last.end?.date ?? date;
      if (lastEventEnd.isBefore(dayEnd) &&
          dayEnd.difference(lastEventEnd) >= minDuration) {
        slots.add(_createOptimalSlot(lastEventEnd, dayEnd));
      }
    }

    return slots;
  }

  /// Crea uno slot ottimale con valutazione energia
  OptimalSlot _createOptimalSlot(DateTime start, DateTime end) {
    final duration = end.difference(start);
    final energyScore = _calculateEnergyScore(start, start);

    EnergyLevel level;
    String reason;

    if (energyScore > 0.7) {
      level = EnergyLevel.high;
      reason = 'Ottimo per attività che richiedono concentrazione';
    } else if (energyScore > 0.4) {
      level = EnergyLevel.medium;
      reason = 'Buono per meeting o lavoro collaborativo';
    } else {
      level = EnergyLevel.low;
      reason = 'Adatto per attività di routine o pausa';
    }

    if (duration >= const Duration(hours: 2)) {
      reason += '. Slot lungo, considera una pausa a metà';
    }

    return OptimalSlot(
      start: start,
      end: end,
      energyLevel: level,
      reason: reason,
    );
  }

  /// Calcola il punteggio energia per un orario
  double _calculateEnergyScore(DateTime time, DateTime slotDate) {
    final hour = time.hour;
    final now = DateTime.now();

    // Se lo slot è già passato o è durante un meeting in corso, energia molto bassa
    if (slotDate.year == now.year &&
        slotDate.month == now.month &&
        slotDate.day == now.day) {
      // Siamo oggi
      if (time.isBefore(now)) {
        return 0.1; // Slot già passato
      }

      // Controlla se c'è un meeting in corso in questo orario
      if (time.hour == now.hour && time.minute <= now.minute) {
        return 0.2; // Slot durante orario corrente
      }
    }

    // Usa il pattern di default
    double baseScore = defaultEnergyPattern[hour] ?? 0.5;

    // Penalizza orari durante pranzo
    if (time.hour == lunchStart.hour ||
        (time.hour == lunchEnd.hour && time.minute < lunchEnd.minute)) {
      baseScore *= 0.5;
    }

    // Penalizza orari serali
    if (time.hour >= 20) {
      baseScore *= 0.3;
    }

    return baseScore.clamp(0.0, 1.0);
  }

  /// Converte EnergyLevel in int per confronto
  int _energyLevelToInt(EnergyLevel level) {
    switch (level) {
      case EnergyLevel.high:
        return 3;
      case EnergyLevel.medium:
        return 2;
      case EnergyLevel.low:
        return 1;
    }
  }
}

/// Analizza gli slot liberi nel calendario (classe legacy per compatibilità)
class FreeSlotsAnalyzer {
  final GoogleCalendarService _googleService;
  final OutlookCalendarService _outlookService;
  final FreeSlotAnalyzerService _analyzerService = FreeSlotAnalyzerService();

  FreeSlotsAnalyzer(this._googleService, this._outlookService);

  // Configurazione orario lavorativo (personalizzabile per utente)
  TimeOfDay get workDayStart => _analyzerService.workDayStart;
  TimeOfDay get workDayEnd => _analyzerService.workDayEnd;
  TimeOfDay get lunchStart => _analyzerService.lunchStart;
  TimeOfDay get lunchEnd => _analyzerService.lunchEnd;

  // Pattern energia durante il giorno
  Map<int, double> get defaultEnergyPattern => _analyzerService.defaultEnergyPattern;

  /// Trova tutti gli slot liberi per una data specifica
  Future<List<FreeSlot>> findFreeSlots({
    required DateTime date,
    Duration minDuration = const Duration(minutes: 30),
    bool includeEvenings = false,
  }) async {
    // Ottieni tutti gli eventi del giorno
    final allEvents = await _getAllEventsForDate(date);

    // Ordina eventi per ora di inizio
    allEvents.sort((a, b) => a.start.compareTo(b.start));

    // Trova slot liberi
    List<FreeSlot> freeSlots = [];

    // Definisci inizio e fine della giornata lavorativa
    DateTime dayStart = DateTime(
      date.year, date.month, date.day,
      workDayStart.hour, workDayStart.minute,
    );
    DateTime dayEnd = DateTime(
      date.year, date.month, date.day,
      includeEvenings ? 21 : workDayEnd.hour,
      includeEvenings ? 0 : workDayEnd.minute,
    );

    // Se non ci sono eventi, l'intera giornata è libera
    if (allEvents.isEmpty) {
      freeSlots.add(_createFreeSlot(dayStart, dayEnd, date));
    } else {
      // Controlla slot prima del primo evento
      if (allEvents.first.start.isAfter(dayStart)) {
        final slot = _createFreeSlot(dayStart, allEvents.first.start, date);
        if (slot.duration >= minDuration) {
          freeSlots.add(slot);
        }
      }

      // Controlla slot tra eventi
      for (int i = 0; i < allEvents.length - 1; i++) {
        final currentEnd = allEvents[i].end;
        final nextStart = allEvents[i + 1].start;

        if (nextStart.isAfter(currentEnd)) {
          final slot = _createFreeSlot(currentEnd, nextStart, date);
          if (slot.duration >= minDuration) {
            freeSlots.add(slot);
          }
        }
      }

      // Controlla slot dopo l'ultimo evento
      if (allEvents.last.end.isBefore(dayEnd)) {
        final slot = _createFreeSlot(allEvents.last.end, dayEnd, date);
        if (slot.duration >= minDuration) {
          freeSlots.add(slot);
        }
      }
    }

    // Filtra slot già passati se stiamo analizzando oggi
    final now = DateTime.now();
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      freeSlots = freeSlots.where((slot) => slot.end.isAfter(now)).toList();
    }

    return freeSlots;
  }

  /// Suggerisce i migliori slot per un'attività
  Future<List<FreeSlot>> suggestBestSlots({
    required DateTime date,
    required Duration activityDuration,
    required String activityType,
  }) async {
    final allSlots = await findFreeSlots(date: date, minDuration: activityDuration);

    // Filtra slot che possono contenere l'attività
    final viableSlots = allSlots.where((slot) =>
    slot.duration >= activityDuration
    ).toList();

    // Assegna punteggi basati sul tipo di attività
    for (var slot in viableSlots) {
      _scoreSlotForActivity(slot, activityType);
    }

    // Ordina per punteggio energia
    viableSlots.sort((a, b) => b.energyScore.compareTo(a.energyScore));

    // Ritorna i migliori 3 slot
    return viableSlots.take(3).toList();
  }

  /// Analizza il carico di lavoro per la settimana
  Future<Map<String, dynamic>> analyzeWeeklyWorkload() async {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));

    Map<String, dynamic> analysis = {
      'totalMeetingHours': 0.0,
      'averageDailyMeetings': 0.0,
      'busiestDay': '',
      'lightestDay': '',
      'suggestedBreaks': <String>[],
    };

    double maxHours = 0;
    double minHours = 24;
    String busiestDay = '';
    String lightestDay = '';

    for (int i = 0; i < 7; i++) {
      final date = weekStart.add(Duration(days: i));
      final events = await _getAllEventsForDate(date);

      double dayHours = 0;
      for (var event in events) {
        dayHours += event.duration.inMinutes / 60.0;
      }

      analysis['totalMeetingHours'] =
          (analysis['totalMeetingHours'] as double) + dayHours;

      if (dayHours > maxHours) {
        maxHours = dayHours;
        busiestDay = _getDayName(date.weekday);
      }

      if (dayHours < minHours && date.weekday <= 5) { // Solo giorni lavorativi
        minHours = dayHours;
        lightestDay = _getDayName(date.weekday);
      }
    }

    analysis['averageDailyMeetings'] =
        (analysis['totalMeetingHours'] as double) / 5; // Media su giorni lavorativi
    analysis['busiestDay'] = busiestDay;
    analysis['lightestDay'] = lightestDay;

    // Suggerimenti basati sull'analisi
    if ((analysis['averageDailyMeetings'] as double) > 6) {
      analysis['suggestedBreaks'].add(
          'Il tuo carico di meeting è alto. Considera di bloccare slot per lavoro concentrato.'
      );
    }

    return analysis;
  }

  /// Crea uno slot libero con calcolo energia
  FreeSlot _createFreeSlot(DateTime start, DateTime end, DateTime slotDate) {
    final duration = end.difference(start);
    final energyScore = _calculateEnergyScore(start, slotDate);
    final suggestion = _generateSlotSuggestion(start, duration, energyScore);

    return FreeSlot(
      start: start,
      end: end,
      duration: duration,
      energyScore: energyScore,
      suggestion: suggestion,
    );
  }

  /// Calcola il punteggio energia per un orario
  double _calculateEnergyScore(DateTime time, DateTime slotDate) {
    return _analyzerService._calculateEnergyScore(time, slotDate);
  }

  /// Genera suggerimento per uno slot
  String _generateSlotSuggestion(DateTime start, Duration duration, double energy) {
    String timeSuggestion = '';

    if (energy > 0.8) {
      timeSuggestion = 'Ottimo per attività che richiedono concentrazione';
    } else if (energy > 0.6) {
      timeSuggestion = 'Buono per meeting o lavoro collaborativo';
    } else if (energy > 0.4) {
      timeSuggestion = 'Adatto per attività di routine o email';
    } else {
      timeSuggestion = 'Meglio per attività leggere o pausa';
    }

    if (duration >= const Duration(hours: 2)) {
      timeSuggestion += '. Slot lungo, considera una pausa a metà';
    }

    return timeSuggestion;
  }

  /// Assegna punteggio a uno slot per tipo di attività
  void _scoreSlotForActivity(FreeSlot slot, String activityType) {
    // Implementazione vuota per ora
    // In un'app reale, modificherebbe il punteggio basandosi sul tipo di attività
  }

  /// Ottieni tutti gli eventi per una data
  Future<List<CalendarEvent>> _getAllEventsForDate(DateTime date) async {
    List<CalendarEvent> allEvents = [];

    // Eventi Google
    try {
      final googleEvents = await _googleService.getEventsForDate(date);
      allEvents.addAll(googleEvents.map((e) => CalendarEvent(
        id: e.id ?? '',
        title: e.summary ?? 'Senza titolo',
        start: e.start?.dateTime ?? e.start?.date ?? date,
        end: e.end?.dateTime ?? e.end?.date ?? date,
        isAllDay: e.start?.dateTime == null,
        source: 'google',
      )));
    } catch (e) {
      print('Errore caricamento eventi Google: $e');
    }

    // Eventi Outlook
    try {
      final outlookEvents = await _outlookService.getEventsForDate(date);
      allEvents.addAll(outlookEvents.map((e) => CalendarEvent(
        id: e.id ?? '',
        title: e.subject ?? 'Senza titolo',
        start: e.start ?? date,
        end: e.end ?? date,
        isAllDay: e.isAllDay,
        source: 'outlook',
      )));
    } catch (e) {
      print('Errore caricamento eventi Outlook: $e');
    }

    return allEvents;
  }

  /// Ottieni nome del giorno
  String _getDayName(int weekday) {
    const days = [
      'Lunedì', 'Martedì', 'Mercoledì', 'Giovedì',
      'Venerdì', 'Sabato', 'Domenica'
    ];
    return days[weekday - 1];
  }
}

/// Rappresenta un evento calendario unificato
class CalendarEvent {
  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final bool isAllDay;
  final String source;

  CalendarEvent({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    required this.isAllDay,
    required this.source,
  });

  Duration get duration => end.difference(start);
}

// Alias per compatibilità
typedef FreeSlotAnalyzer = FreeSlotAnalyzerService;