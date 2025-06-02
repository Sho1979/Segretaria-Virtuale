// lib/services/ai/ai_assistant_service.dart

import 'package:flutter/foundation.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'meeting_pattern_analyzer.dart';
import '../google_calendar_service.dart';
import '../outlook_calendar_service.dart';
import '../calendar/free_slots_analyzer.dart';
import 'command_service.dart';
import 'package:intl/intl.dart';
import 'dart:math';

/// Servizio AI avanzato per assistenza intelligente al calendario
class AIAssistantService {
  final MeetingPatternAnalyzer _patternAnalyzer = MeetingPatternAnalyzer();
  final GoogleCalendarService _googleService;
  final OutlookCalendarService _outlookService;
  final FreeSlotAnalyzerService _slotAnalyzer = FreeSlotAnalyzerService();

  // Contesto della conversazione
  final List<ConversationContext> _conversationHistory = [];

  // Cache delle previsioni
  final Map<String, PredictionResult> _predictionCache = {};

  AIAssistantService({
    required GoogleCalendarService googleService,
    required OutlookCalendarService outlookService,
  })  : _googleService = googleService,
        _outlookService = outlookService;

  /// Inizializza il servizio AI
  Future<void> initialize() async {
    await _patternAnalyzer.initialize();

    // Carica dati storici per l'apprendimento
    await _loadHistoricalData();
  }

  /// Carica e analizza i dati storici
  Future<void> _loadHistoricalData() async {
    try {
      // Carica eventi degli ultimi 6 mesi
      final now = DateTime.now();
      final sixMonthsAgo = now.subtract(const Duration(days: 180));

      final googleEvents = await _googleService.getEvents(
        timeMin: sixMonthsAgo,
        timeMax: now,
      );

      final outlookEvents = await _outlookService.getEvents(
        startDate: sixMonthsAgo,
        endDate: now,
      );

      // Combina tutti gli eventi
      final allEvents = [...googleEvents, ...outlookEvents];

      // Analizza i pattern
      await _patternAnalyzer.analyzeHistoricalData(allEvents);

      if (kDebugMode) {
        print('AI: Analizzati ${allEvents.length} eventi storici');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Errore nel caricamento dati storici: $e');
      }
    }
  }

  /// Processa un comando in linguaggio naturale
  Future<AIResponse> processCommand(String command, {InputType inputType = InputType.text}) async {
    // Aggiungi al contesto
    _conversationHistory.add(ConversationContext(
      input: command,
      inputType: inputType,
      timestamp: DateTime.now(),
    ));

    // Analizza l'intento
    final intent = _analyzeIntent(command);

    switch (intent.type) {
      case IntentType.scheduleOptimal:
        return await _handleScheduleOptimal(intent);

      case IntentType.analyzeFreeTime:
        return await _handleAnalyzeFreeTime(intent);

      case IntentType.predictWorkload:
        return await _handlePredictWorkload(intent);

      case IntentType.suggestOptimization:
        return await _handleSuggestOptimization(intent);

      case IntentType.provideSummary:
        return await _handleProvideSummary(intent);

      case IntentType.unknown:
      default:
        return AIResponse(
          success: false,
          message: 'Non ho capito la richiesta. Posso aiutarti a:\n'
              '• Trovare il momento migliore per un meeting\n'
              '• Analizzare il tuo tempo libero\n'
              '• Prevedere il carico di lavoro\n'
              '• Ottimizzare il tuo calendario',
          suggestions: _getContextualSuggestions(),
        );
    }
  }

  /// Analizza l'intento del comando
  UserIntent _analyzeIntent(String command) {
    final lowerCommand = command.toLowerCase();

    // Pattern per scheduling ottimale
    if (lowerCommand.contains('schedula') ||
        lowerCommand.contains('prenota') ||
        lowerCommand.contains('organizza') ||
        lowerCommand.contains('miglior momento') ||
        lowerCommand.contains('quando posso')) {

      // Estrai dettagli
      final duration = _extractDuration(lowerCommand);
      final meetingType = _extractMeetingType(lowerCommand);
      final urgency = _extractUrgency(lowerCommand);
      final participants = _extractParticipants(lowerCommand);

      return UserIntent(
        type: IntentType.scheduleOptimal,
        parameters: {
          'duration': duration,
          'meetingType': meetingType,
          'urgency': urgency,
          'participants': participants,
        },
      );
    }

    // Pattern per analisi tempo libero
    if (lowerCommand.contains('tempo libero') ||
        lowerCommand.contains('quando sono libero') ||
        lowerCommand.contains('slot disponibili')) {

      final timeframe = _extractTimeframe(lowerCommand);

      return UserIntent(
        type: IntentType.analyzeFreeTime,
        parameters: {'timeframe': timeframe},
      );
    }

    // Pattern per previsione carico di lavoro
    if (lowerCommand.contains('carico di lavoro') ||
        lowerCommand.contains('quanto sarò impegnato') ||
        lowerCommand.contains('previsione')) {

      final period = _extractPeriod(lowerCommand);

      return UserIntent(
        type: IntentType.predictWorkload,
        parameters: {'period': period},
      );
    }

    // Pattern per ottimizzazione
    if (lowerCommand.contains('ottimizza') ||
        lowerCommand.contains('migliora') ||
        lowerCommand.contains('riorganizza')) {

      return UserIntent(
        type: IntentType.suggestOptimization,
        parameters: {},
      );
    }

    // Pattern per riassunto
    if (lowerCommand.contains('riassumi') ||
        lowerCommand.contains('sommario') ||
        lowerCommand.contains('riepilogo')) {

      return UserIntent(
        type: IntentType.provideSummary,
        parameters: {},
      );
    }

    return UserIntent(type: IntentType.unknown);
  }

  /// Gestisce la richiesta di scheduling ottimale
  Future<AIResponse> _handleScheduleOptimal(UserIntent intent) async {
    final duration = intent.parameters['duration'] ?? 60;
    final meetingType = intent.parameters['meetingType'] ?? 'meeting';
    final urgency = intent.parameters['urgency'] ?? 'normal';

    // Determina il periodo di ricerca basato sull'urgenza
    final now = DateTime.now();
    final searchEnd = urgency == 'urgent'
        ? now.add(const Duration(days: 3))
        : now.add(const Duration(days: 14));

    // Ottieni eventi esistenti
    final existingEvents = await _getAllEvents(now, searchEnd);

    // Usa il pattern analyzer per suggerimenti intelligenti
    final suggestions = await _patternAnalyzer.suggestOptimalSlots(
      meetingType: meetingType,
      duration: duration,
      startDate: now,
      endDate: searchEnd,
      existingEvents: existingEvents,
    );

    if (suggestions.isEmpty) {
      return AIResponse(
        success: false,
        message: 'Non riesco a trovare slot disponibili nel periodo richiesto. '
            'Il tuo calendario sembra molto pieno.',
        suggestions: [
          'Prova ad estendere il periodo di ricerca',
          'Considera meeting più brevi',
          'Valuta se alcuni meeting possono essere riprogrammati',
        ],
      );
    }

    // Arricchisci i suggerimenti con analisi contestuale
    final enrichedSuggestions = await _enrichSuggestions(suggestions, existingEvents);

    if (enrichedSuggestions.isEmpty) { // Controllo aggiunto
      return AIResponse(
          success: false,
          message: 'Non sono riuscito a trovare suggerimenti validi dopo l\'analisi contestuale.',
          suggestions: ['Prova a modificare i parametri della richiesta.']
      );
    }

    // Prepara la risposta
    final topSuggestion = enrichedSuggestions.first;
    final alternativeSuggestions = enrichedSuggestions.skip(1).take(2).toList();

    return AIResponse(
      success: true,
      message: _generateSmartSchedulingMessage(topSuggestion, meetingType),
      data: {
        'primarySlot': topSuggestion,
        'alternatives': alternativeSuggestions,
      },
      suggestions: _generateSchedulingTips(topSuggestion, meetingType),
      actions: [
        AIAction(
          type: ActionType.createEvent,
          label: 'Prenota questo slot',
          parameters: {
            'start': topSuggestion.base.start, // CORRETTO
            'end': topSuggestion.base.end,     // CORRETTO
            'summary': meetingType,
          },
        ),
        if (alternativeSuggestions.isNotEmpty)
          AIAction(
            type: ActionType.showAlternatives,
            label: 'Mostra alternative',
          ),
      ],
    );
  }

  /// Arricchisce i suggerimenti con analisi contestuale
  Future<List<EnrichedSlotSuggestion>> _enrichSuggestions(
      List<SlotSuggestion> suggestions,
      List<gcal.Event> existingEvents,
      ) async {
    final enriched = <EnrichedSlotSuggestion>[];

    for (final suggestion in suggestions) {
      // Analizza il contesto temporale
      final dayContext = _analyzeDayContext(suggestion.start, existingEvents);

      // Analizza l'energia prevista
      final energyLevel = await _predictEnergyLevel(suggestion.start, existingEvents);

      // Calcola il punteggio finale
      final finalScore = _calculateFinalScore(
        suggestion.score,
        dayContext,
        energyLevel,
      );

      enriched.add(EnrichedSlotSuggestion(
        base: suggestion,
        dayContext: dayContext,
        energyLevel: energyLevel,
        finalScore: finalScore,
      ));
    }

    // Ordina per punteggio finale
    enriched.sort((a, b) => b.finalScore.compareTo(a.finalScore));

    return enriched;
  }

  /// Analizza il contesto della giornata
  DayContext _analyzeDayContext(DateTime slot, List<gcal.Event> events) {
    final dayStart = DateTime(slot.year, slot.month, slot.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    // Eventi del giorno
    final dayEvents = events.where((e) {
      final start = e.start?.dateTime;
      return start != null &&
          start.isAfter(dayStart) &&
          start.isBefore(dayEnd);
    }).toList();

    // Calcola metriche
    final totalMeetingMinutes = dayEvents.fold(0, (sum, event) {
      if (event.start?.dateTime != null && event.end?.dateTime != null) {
        return sum + event.end!.dateTime!.difference(event.start!.dateTime!).inMinutes;
      }
      return sum;
    });

    final meetingDensity = totalMeetingMinutes / (8 * 60); // Assumendo 8 ore lavorative

    // Identifica blocchi di tempo libero
    final freeBlocks = _identifyFreeBlocks(dayEvents, dayStart, dayEnd);

    // Controlla se è prima/dopo altri meeting
    final hasEarlierMeetings = dayEvents.any((e) =>
    e.start?.dateTime != null && e.start!.dateTime!.isBefore(slot)
    );

    final hasLaterMeetings = dayEvents.any((e) =>
    e.start?.dateTime != null && e.start!.dateTime!.isAfter(slot)
    );

    return DayContext(
      totalMeetings: dayEvents.length,
      meetingDensity: meetingDensity,
      largestFreeBlock: freeBlocks.isEmpty ? 0 : freeBlocks.map((b) => b.duration).reduce(max),
      isBackToBack: _checkIfBackToBack(slot, dayEvents),
      hasEarlierMeetings: hasEarlierMeetings,
      hasLaterMeetings: hasLaterMeetings,
    );
  }

  /// Prevede il livello di energia per uno slot
  Future<double> _predictEnergyLevel(DateTime slot, List<gcal.Event> events) async {
    // Fattori che influenzano l'energia
    double energyScore = 1.0;

    // Ora del giorno
    final hour = slot.hour;
    if (hour >= 9 && hour <= 11) {
      energyScore *= 1.2; // Mattina produttiva
    } else if (hour >= 14 && hour <= 15) {
      energyScore *= 0.8; // Post-pranzo
    } else if (hour >= 16 && hour <= 17) {
      energyScore *= 0.9; // Tardo pomeriggio
    }

    // Giorno della settimana
    final weekday = slot.weekday;
    if (weekday == 1) {
      energyScore *= 1.1; // Lunedì fresh
    } else if (weekday == 5) {
      energyScore *= 0.85; // Venerdì stanco
    }

    // Densità di meeting nel giorno
    final dayContext = _analyzeDayContext(slot, events);
    if (dayContext.meetingDensity > 0.7) {
      energyScore *= 0.7; // Giornata molto piena
    }

    // Meeting back-to-back
    if (dayContext.isBackToBack) {
      energyScore *= 0.8;
    }

    return max(0.1, min(1.0, energyScore));
  }

  /// Calcola il punteggio finale per uno slot
  double _calculateFinalScore(
      double baseScore,
      DayContext dayContext,
      double energyLevel,
      ) {
    // Peso dei vari fattori
    const patternWeight = 0.4;
    const contextWeight = 0.3;
    const energyWeight = 0.3;

    // Calcola context score
    double contextScore = 1.0;

    if (dayContext.meetingDensity > 0.8) {
      contextScore *= 0.5; // Penalizza giorni troppo pieni
    } else if (dayContext.meetingDensity < 0.3) {
      contextScore *= 1.2; // Premia giorni con spazio
    }

    if (!dayContext.isBackToBack) {
      contextScore *= 1.1; // Premia slot con buffer
    }

    return (baseScore * patternWeight) +
        (contextScore * contextWeight) +
        (energyLevel * energyWeight);
  }

  /// Genera un messaggio intelligente per lo scheduling
  String _generateSmartSchedulingMessage(
      EnrichedSlotSuggestion suggestion,
      String meetingType,
      ) {
    final buffer = StringBuffer();

    // Messaggio principale
    buffer.write('Ho trovato il momento ottimale per il tuo $meetingType: ');
    buffer.write('${_formatDateTime(suggestion.base.start)}. ');

    // Aggiungi contesto
    if (suggestion.finalScore > 0.8) {
      buffer.write('Questo slot è eccellente! ');
    } else if (suggestion.finalScore > 0.6) {
      buffer.write('È un buon momento. ');
    }

    // Spiega il perché
    if (suggestion.base.reason.isNotEmpty) {
      buffer.write(suggestion.base.reason);
      buffer.write(' ');
    }

    // Aggiungi insights sul contesto
    if (suggestion.energyLevel > 0.8) {
      buffer.write('Dovresti avere buona energia in questo momento. ');
    }

    if (suggestion.dayContext.meetingDensity < 0.5) {
      buffer.write('La giornata non è troppo piena. ');
    }

    if (!suggestion.dayContext.isBackToBack) {
      buffer.write('Hai tempo per prepararti prima e dopo. ');
    }

    return buffer.toString();
  }

  /// Genera suggerimenti per lo scheduling
  List<String> _generateSchedulingTips(
      EnrichedSlotSuggestion suggestion,
      String meetingType,
      ) {
    final tips = <String>[];

    // Suggerimenti basati sul contesto
    if (suggestion.dayContext.meetingDensity > 0.7) {
      tips.add('Considera di preparare i materiali in anticipo, la giornata sarà intensa');
    }

    if (suggestion.base.start.hour < 10) {
      tips.add('Meeting mattutino: ottimo per discussioni che richiedono focus');
    } else if (suggestion.base.start.hour > 15) {
      tips.add('Meeting pomeridiano: ideale per brainstorming e collaborazione');
    }

    // Suggerimenti basati sui pattern
    if (suggestion.base.patternKey != null) {
      tips.add('Questo orario è simile ad altri tuoi meeting ricorrenti di successo');
    }

    return tips;
  }

  /// Gestisce l'analisi del tempo libero
  Future<AIResponse> _handleAnalyzeFreeTime(UserIntent intent) async {
    final timeframe = intent.parameters['timeframe'] ?? 'week';

    final now = DateTime.now();
    final endDate = _getEndDateForTimeframe(now, timeframe);

    // Ottieni tutti gli eventi
    final events = await _getAllEvents(now, endDate);

    // Analizza con FreeSlotAnalyzerService
    final analyzer = FreeSlotAnalyzerService();
    final freeSlots = await analyzer.findOptimalSlots(
      startDate: now,
      endDate: endDate,
      currentEvents: events,
    );

    // Raggruppa per giorno
    final slotsByDay = <DateTime, List<OptimalSlot>>{};
    for (final slot in freeSlots) {
      final day = DateTime(slot.start.year, slot.start.month, slot.start.day);
      slotsByDay.putIfAbsent(day, () => []).add(slot);
    }

    // Calcola statistiche
    final totalFreeMinutes = freeSlots.fold(0, (sum, slot) =>
    sum + slot.end.difference(slot.start).inMinutes
    );

    final avgFreePerDay = slotsByDay.isNotEmpty ? totalFreeMinutes / slotsByDay.length : 0.0;

    // Identifica i giorni migliori
    final bestDays = slotsByDay.entries
        .where((e) => e.value.any((s) => s.energyLevel == EnergyLevel.high))
        .map((e) => e.key)
        .toList();

    return AIResponse(
      success: true,
      message: _generateFreeTimeAnalysis(totalFreeMinutes, avgFreePerDay, bestDays),
      data: {
        'freeSlots': freeSlots,
        'slotsByDay': slotsByDay,
        'totalFreeMinutes': totalFreeMinutes,
        'bestDays': bestDays,
      },
      suggestions: _generateFreeTimeSuggestions(slotsByDay, freeSlots),
    );
  }

  /// Genera analisi del tempo libero
  String _generateFreeTimeAnalysis(
      int totalMinutes,
      double avgPerDay,
      List<DateTime> bestDays,
      ) {
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;

    final buffer = StringBuffer();
    buffer.write('Nei prossimi giorni hai ');

    if (hours > 0) {
      buffer.write('$hours ore');
      if (minutes > 0) buffer.write(' e $minutes minuti');
    } else {
      buffer.write('$minutes minuti');
    }

    buffer.write(' di tempo libero utilizzabile. ');

    if (avgPerDay > 120) {
      buffer.write('Hai una buona disponibilità, circa ${avgPerDay.round()} minuti al giorno. ');
    } else if (avgPerDay > 60) {
      buffer.write('La disponibilità è moderata, circa ${avgPerDay.round()} minuti al giorno. ');
    } else {
      buffer.write('Il tempo libero è limitato, solo ${avgPerDay.round()} minuti al giorno in media. ');
    }

    if (bestDays.isNotEmpty) {
      buffer.write('I giorni migliori per attività importanti sono: ');
      buffer.write(bestDays.map((d) => DateFormat('EEEE d', 'it').format(d)).join(', '));
      buffer.write('.');
    }

    return buffer.toString();
  }

  /// Gestisce la previsione del carico di lavoro
  Future<AIResponse> _handlePredictWorkload(UserIntent intent) async {
    final period = intent.parameters['period'] ?? 'week';

    final now = DateTime.now();
    final endDate = _getEndDateForTimeframe(now, period);

    // Ottieni eventi futuri
    final futureEvents = await _getAllEvents(now, endDate);

    // Ottieni pattern storici per confronto
    final insights = _patternAnalyzer.getInsights();

    // Calcola metriche per il periodo
    final workloadMetrics = _calculateWorkloadMetrics(futureEvents, now, endDate);

    // Confronta con media storica
    final comparison = _compareWithHistorical(workloadMetrics, insights);

    // Genera previsione
    final prediction = _generateWorkloadPrediction(workloadMetrics, comparison);

    return AIResponse(
      success: true,
      message: prediction.summary,
      data: {
        'metrics': workloadMetrics,
        'comparison': comparison,
        'prediction': prediction,
      },
      suggestions: prediction.recommendations,
      visualizations: [
        AIVisualization(
          type: VisualizationType.workloadChart,
          data: workloadMetrics.dailyLoad,
        ),
      ],
    );
  }

  /// Calcola metriche del carico di lavoro
  WorkloadMetrics _calculateWorkloadMetrics(
      List<gcal.Event> events,
      DateTime start,
      DateTime end,
      ) {
    final dailyLoad = <DateTime, double>{};
    final hoursByType = <String, int>{};

    // Calcola carico giornaliero
    DateTime current = start;
    while (current.isBefore(end)) {
      final dayEvents = events.where((e) {
        final eventStart = e.start?.dateTime;
        return eventStart != null &&
            eventStart.year == current.year &&
            eventStart.month == current.month &&
            eventStart.day == current.day;
      }).toList();

      final dayMinutes = dayEvents.fold(0, (sum, event) {
        if (event.start?.dateTime != null && event.end?.dateTime != null) {
          return sum + event.end!.dateTime!.difference(event.start!.dateTime!).inMinutes;
        }
        return sum;
      });

      dailyLoad[current] = dayMinutes / 480.0; // 8 ore = 480 minuti

      current = current.add(const Duration(days: 1));
    }

    // Calcola ore per tipo
    for (final event in events) {
      if (event.start?.dateTime != null && event.end?.dateTime != null) {
        final type = _categorizeEvent(event);
        final minutes = event.end!.dateTime!.difference(event.start!.dateTime!).inMinutes;
        hoursByType[type] = (hoursByType[type] ?? 0) + minutes;
      }
    }

    // Calcola statistiche
    final loads = dailyLoad.values.toList();
    final avgLoad = loads.isEmpty ? 0.0 : loads.reduce((a, b) => a + b) / loads.length;
    final peakLoad = loads.isEmpty ? 0.0 : loads.reduce(max);

    return WorkloadMetrics(
      dailyLoad: dailyLoad,
      hoursByType: hoursByType,
      averageLoad: avgLoad,
      peakLoad: peakLoad,
      totalHours: hoursByType.values.fold(0, (a, b) => a + b) / 60,
    );
  }

  /// Categorizza un evento
  String _categorizeEvent(gcal.Event event) {
    final summary = event.summary?.toLowerCase() ?? '';

    if (summary.contains('1:1') || summary.contains('one on one')) {
      return 'One-on-One';
    } else if (summary.contains('standup') || summary.contains('daily')) {
      return 'Standup';
    } else if (summary.contains('review')) {
      return 'Review';
    } else if (summary.contains('planning')) {
      return 'Planning';
    } else if (summary.contains('interview')) {
      return 'Interview';
    } else if (event.attendees != null && event.attendees!.length > 5) {
      return 'Large Meeting';
    } else {
      return 'Regular Meeting';
    }
  }

  /// Confronta con dati storici
  WorkloadComparison _compareWithHistorical(
      WorkloadMetrics current,
      MeetingInsights historical,
      ) {
    final historicalAvgHours = historical.totalAnalyzedMeetings > 0
        ? (historical.averageMeetingDuration * historical.totalAnalyzedMeetings / 60 / 20)
        : 0.0;


    final loadDifference = current.averageLoad - (historical.totalAnalyzedMeetings > 0 ? historicalAvgHours / 8 : 0.0);

    return WorkloadComparison(
      currentAvgLoad: current.averageLoad,
      historicalAvgLoad: historical.totalAnalyzedMeetings > 0 ? historicalAvgHours / 8 : 0.0,
      difference: loadDifference,
      trend: loadDifference > 0.1 ? WorkloadTrend.increasing :
      loadDifference < -0.1 ? WorkloadTrend.decreasing :
      WorkloadTrend.stable,
    );
  }

  /// Genera previsione del carico di lavoro
  WorkloadPrediction _generateWorkloadPrediction(
      WorkloadMetrics metrics,
      WorkloadComparison comparison,
      ) {
    final buffer = StringBuffer();
    final recommendations = <String>[];

    // Valuta il carico generale
    if (metrics.averageLoad > 0.8) {
      buffer.write('Il tuo carico di lavoro sarà molto alto, ');
      buffer.write('con una media del ${(metrics.averageLoad * 100).round()}% del tempo occupato. ');
      recommendations.add('Considera di delegare alcuni meeting non critici');
      recommendations.add('Blocca del tempo per lavoro concentrato');
    } else if (metrics.averageLoad > 0.6) {
      buffer.write('Avrai un carico di lavoro sostenuto ma gestibile, ');
      buffer.write('circa ${(metrics.averageLoad * 100).round()}% del tempo in meeting. ');
      recommendations.add('Mantieni buffer tra i meeting per evitare stress');
    } else {
      buffer.write('Il carico di lavoro sarà moderato, ');
      buffer.write('con ${(metrics.averageLoad * 100).round()}% del tempo in meeting. ');
      recommendations.add('Ottimo momento per pianificare attività di sviluppo personale');
    }

    // Confronto con storico
    switch (comparison.trend) {
      case WorkloadTrend.increasing:
        buffer.write('Questo è ${(comparison.difference * 100).abs().round()}% in più del solito. ');
        recommendations.add('Preparati mentalmente per un periodo più intenso');
        break;
      case WorkloadTrend.decreasing:
        buffer.write('Questo è ${(comparison.difference * 100).abs().round()}% in meno del normale. ');
        recommendations.add('Approfitta per recuperare task arretrati');
        break;
      case WorkloadTrend.stable:
        buffer.write('In linea con il tuo carico abituale. ');
        break;
    }

    // Identifica giorni critici
    final criticalDays = metrics.dailyLoad.entries
        .where((e) => e.value > 0.9)
        .map((e) => e.key)
        .toList();

    if (criticalDays.isNotEmpty) {
      buffer.write('Attenzione a: ');
      buffer.write(criticalDays.map((d) => DateFormat('EEEE d', 'it').format(d)).join(', '));
      buffer.write(' - giorni particolarmente pieni.');
      recommendations.add('Pianifica pause strategiche nei giorni più intensi');
    }

    return WorkloadPrediction(
      summary: buffer.toString(),
      recommendations: recommendations,
      criticalDays: criticalDays,
      suggestedFocusTime: _suggestFocusTime(metrics),
    );
  }

  /// Suggerisce tempo per focus
  List<DateTime> _suggestFocusTime(WorkloadMetrics metrics) {
    return metrics.dailyLoad.entries
        .where((e) => e.value < 0.5)
        .map((e) => e.key)
        .toList();
  }

  /// Gestisce suggerimenti di ottimizzazione
  Future<AIResponse> _handleSuggestOptimization(UserIntent intent) async {
    final now = DateTime.now();
    final nextWeek = now.add(const Duration(days: 7));

    // Ottieni eventi della prossima settimana
    final events = await _getAllEvents(now, nextWeek);

    // Analizza problemi e opportunità
    final optimizations = await _analyzeOptimizationOpportunities(events);

    if (optimizations.isEmpty) {
      return AIResponse(
        success: true,
        message: 'Il tuo calendario sembra ben organizzato! Non ho trovato ottimizzazioni urgenti.',
        suggestions: [
          'Continua a mantenere buffer tra i meeting',
          'Ricordati di bloccare tempo per lavoro concentrato',
        ],
      );
    }

    // Prioritizza le ottimizzazioni
    optimizations.sort((a, b) => b.impact.compareTo(a.impact));

    return AIResponse(
      success: true,
      message: _generateOptimizationSummary(optimizations),
      data: {
        'optimizations': optimizations,
      },
      suggestions: optimizations.take(3).map((o) => o.description).toList(),
      actions: optimizations
          .where((o) => o.actionable)
          .take(2)
          .map((o) => AIAction(
        type: ActionType.optimize,
        label: o.actionLabel ?? 'Azione Ottimizzazione', // CORRETTO
        parameters: o.actionParameters,
      ))
          .toList(),
    );
  }

  /// Analizza opportunità di ottimizzazione
  Future<List<OptimizationOpportunity>> _analyzeOptimizationOpportunities(
      List<gcal.Event> events,
      ) async {
    final opportunities = <OptimizationOpportunity>[];

    // 1. Identifica meeting back-to-back
    final backToBackGroups = _findBackToBackMeetings(events);
    if (backToBackGroups.isNotEmpty) {
      opportunities.add(OptimizationOpportunity(
        type: OptimizationType.backToBack,
        description: 'Hai ${backToBackGroups.length} gruppi di meeting consecutivi. '
            'Considera di aggiungere buffer di 10-15 minuti.',
        impact: 0.8,
        actionable: true,
        actionLabel: 'Aggiungi buffer automatici',
        actionParameters: {'groups': backToBackGroups},
      ));
    }

    // 2. Identifica meeting che potrebbero essere email
    final shortMeetings = events.where((e) {
      if (e.start?.dateTime != null && e.end?.dateTime != null) {
        final duration = e.end!.dateTime!.difference(e.start!.dateTime!).inMinutes;
        return duration <= 15 && (e.attendees?.length ?? 0) <= 2;
      }
      return false;
    }).toList();

    if (shortMeetings.length > 2) {
      opportunities.add(OptimizationOpportunity(
        type: OptimizationType.meetingToEmail,
        description: 'Hai ${shortMeetings.length} meeting molto brevi che potrebbero essere email.',
        impact: 0.6,
        actionable: false,
      ));
    }

    // 3. Identifica giorni sovraccarichi
    final overloadedDays = _findOverloadedDays(events);
    if (overloadedDays.isNotEmpty) {
      opportunities.add(OptimizationOpportunity(
        type: OptimizationType.balanceLoad,
        description: 'Alcuni giorni sono troppo pieni. Considera di redistribuire i meeting.',
        impact: 0.9,
        actionable: true,
        actionLabel: 'Suggerisci redistribuzione',
        actionParameters: {'days': overloadedDays},
      ));
    }

    // 4. Identifica meeting ricorrenti poco partecipati
    final insights = _patternAnalyzer.getInsights();
    final recurringPatterns = insights.patterns.where((p) => p.isRecurring);

    for (final pattern in recurringPatterns) {
      // Qui potresti analizzare la partecipazione se avessi accesso ai dati
      if (pattern.confidence < 0.5) {
        opportunities.add(OptimizationOpportunity(
          type: OptimizationType.reviewRecurring,
          description: 'Il meeting ricorrente "${pattern.key}" potrebbe necessitare revisione.',
          impact: 0.5,
          actionable: false,
        ));
      }
    }

    return opportunities;
  }

  /// Trova meeting back-to-back
  List<List<gcal.Event>> _findBackToBackMeetings(List<gcal.Event> events) {
    final sorted = events.toList()
      ..sort((a, b) => (a.start?.dateTime ?? DateTime.now())
          .compareTo(b.start?.dateTime ?? DateTime.now()));

    final groups = <List<gcal.Event>>[];
    List<gcal.Event>? currentGroup;

    for (int i = 0; i < sorted.length - 1; i++) {
      final current = sorted[i];
      final next = sorted[i + 1];

      if (current.end?.dateTime != null && next.start?.dateTime != null) {
        final gap = next.start!.dateTime!.difference(current.end!.dateTime!).inMinutes;

        if (gap <= 5) { // Considerato back-to-back se meno di 5 minuti
          if (currentGroup == null) {
            currentGroup = [current];
          }
          currentGroup.add(next);
        } else if (currentGroup != null) {
          groups.add(currentGroup);
          currentGroup = null;
        }
      }
    }

    if (currentGroup != null && currentGroup.length > 1) {
      groups.add(currentGroup);
    }

    return groups;
  }

  /// Trova giorni sovraccarichi
  List<DateTime> _findOverloadedDays(List<gcal.Event> events) {
    final dayLoads = <DateTime, int>{};

    for (final event in events) {
      if (event.start?.dateTime != null && event.end?.dateTime != null) {
        final day = DateTime(
          event.start!.dateTime!.year,
          event.start!.dateTime!.month,
          event.start!.dateTime!.day,
        );

        final duration = event.end!.dateTime!.difference(event.start!.dateTime!).inMinutes;
        dayLoads[day] = (dayLoads[day] ?? 0) + duration;
      }
    }

    // Giorni con più di 6 ore di meeting
    return dayLoads.entries
        .where((e) => e.value > 360)
        .map((e) => e.key)
        .toList();
  }

  /// Genera sommario delle ottimizzazioni
  String _generateOptimizationSummary(List<OptimizationOpportunity> optimizations) {
    final buffer = StringBuffer();

    buffer.write('Ho identificato ${optimizations.length} opportunità di ottimizzazione. ');

    final highImpact = optimizations.where((o) => o.impact > 0.7).length;
    if (highImpact > 0) {
      buffer.write('$highImpact di queste hanno un impatto significativo. ');
    }

    // Menziona la più importante
    if (optimizations.isNotEmpty) {
      final top = optimizations.first;
      buffer.write('\n\nLa più importante: ${top.description}');
    }

    return buffer.toString();
  }

  /// Gestisce la richiesta di sommario
  Future<AIResponse> _handleProvideSummary(UserIntent intent) async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    final weekEnd = now.add(const Duration(days: 7));

    // Ottieni eventi
    final todayEvents = await _getAllEvents(todayStart, todayEnd);
    final weekEvents = await _getAllEvents(now, weekEnd);

    // Ottieni insights
    final insights = _patternAnalyzer.getInsights();

    // Genera sommario
    final summary = _generateExecutiveSummary(
      todayEvents: todayEvents,
      weekEvents: weekEvents,
      insights: insights,
    );

    return AIResponse(
      success: true,
      message: summary,
      data: {
        'todayCount': todayEvents.length,
        'weekCount': weekEvents.length,
        'insights': insights,
      },
      suggestions: _generateSummaryActions(todayEvents, weekEvents),
    );
  }

  /// Genera sommario esecutivo
  String _generateExecutiveSummary({
    required List<gcal.Event> todayEvents,
    required List<gcal.Event> weekEvents,
    required MeetingInsights insights,
  }) {
    final buffer = StringBuffer();

    // Oggi
    buffer.write('📅 **Oggi**: ');
    if (todayEvents.isEmpty) {
      buffer.write('Nessun meeting programmato. Ottimo per lavoro concentrato!\n');
    } else {
      buffer.write('${todayEvents.length} meeting');
      final totalMinutes = todayEvents.fold(0, (sum, e) {
        if (e.start?.dateTime != null && e.end?.dateTime != null) {
          return sum + e.end!.dateTime!.difference(e.start!.dateTime!).inMinutes;
        }
        return sum;
      });
      buffer.write(' (${totalMinutes ~/ 60}h ${totalMinutes % 60}min totali)\n');

      // Prossimo meeting
      final upcoming = todayEvents
          .where((e) => e.start?.dateTime?.isAfter(DateTime.now()) ?? false)
          .toList();

      if (upcoming.isNotEmpty) {
        final next = upcoming.first;
        buffer.write('Prossimo: ${next.summary} alle ${DateFormat('HH:mm').format(next.start!.dateTime!)}\n');
      }
    }

    buffer.write('\n');

    // Settimana
    buffer.write('📊 **Prossima settimana**: ');
    buffer.write('${weekEvents.length} meeting totali\n');

    // Distribuzione
    final dayDistribution = <String, int>{};
    for (final event in weekEvents) {
      if (event.start?.dateTime != null) {
        final day = DateFormat('EEEE', 'it').format(event.start!.dateTime!);
        dayDistribution[day] = (dayDistribution[day] ?? 0) + 1;
      }
    }
    if (dayDistribution.isNotEmpty) {
      final busiestDay = dayDistribution.entries
          .reduce((a, b) => a.value > b.value ? a : b);
      buffer.write('Giorno più impegnato: ${busiestDay.key} (${busiestDay.value} meeting)\n');
    }


    buffer.write('\n');

    // Insights storici
    if (insights.totalAnalyzedMeetings > 0) {
      buffer.write('💡 **Insights dai tuoi pattern**:\n');
      buffer.write('• Media meeting: ${insights.averageMeetingDuration.round()} minuti\n');
      buffer.write('• Giorno tipicamente più busy: ${insights.busiestDay}\n');

      if (insights.topDiscussionTopics.isNotEmpty) {
        buffer.write('• Topic frequenti: ${insights.topDiscussionTopics.take(3).join(", ")}\n');
      }
    }

    return buffer.toString();
  }

  /// Genera azioni dal sommario
  List<String> _generateSummaryActions(
      List<gcal.Event> todayEvents,
      List<gcal.Event> weekEvents,
      ) {
    final actions = <String>[];

    // Se oggi è libero
    if (todayEvents.isEmpty) {
      actions.add('Blocca 2-3 ore per deep work oggi');
      actions.add('Rivedi e pianifica la settimana');
    }

    // Se la settimana è molto piena
    if (weekEvents.length > 15) {
      actions.add('Valuta quali meeting sono davvero necessari');
      actions.add('Proteggi del tempo per te stesso');
    }

    // Se ci sono pattern di back-to-back
    final backToBack = _findBackToBackMeetings(weekEvents);
    if (backToBack.isNotEmpty) {
      actions.add('Aggiungi buffer tra i meeting consecutivi');
    }

    return actions;
  }

  // Metodi di utilità

  /// Estrae la durata dal testo
  int _extractDuration(String text) {
    final patterns = [
      RegExp(r'(\d+)\s*or[ae]', caseSensitive: false),
      RegExp(r'(\d+)\s*minut[oi]', caseSensitive: false),
      RegExp(r'(\d+)h', caseSensitive: false),
      RegExp(r'(\d+)\s*min', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        final value = int.tryParse(match.group(1)!) ?? 0;
        if (text.contains('or') || text.contains('h')) {
          return value * 60;
        }
        return value;
      }
    }

    return 60; // Default 1 ora
  }

  /// Estrae il tipo di meeting
  String _extractMeetingType(String text) {
    final types = {
      'standup': ['standup', 'daily'],
      'one-on-one': ['1:1', 'one on one', 'uno a uno'],
      'review': ['review', 'revisione'],
      'planning': ['planning', 'pianificazione'],
      'brainstorming': ['brainstorming', 'ideazione'],
      'presentazione': ['presentazione', 'demo'],
    };

    final lower = text.toLowerCase();

    for (final entry in types.entries) {
      if (entry.value.any((keyword) => lower.contains(keyword))) {
        return entry.key;
      }
    }

    return 'meeting';
  }

  /// Estrae l'urgenza
  String _extractUrgency(String text) {
    final urgentKeywords = ['urgente', 'oggi', 'subito', 'asap', 'prima possibile'];
    final lower = text.toLowerCase();

    if (urgentKeywords.any((k) => lower.contains(k))) {
      return 'urgent';
    }

    return 'normal';
  }

  /// Estrae partecipanti
  List<String> _extractParticipants(String text) {
    // Implementazione semplificata
    // In produzione, potresti usare NER o pattern più sofisticati
    final emailPattern = RegExp(r'\b[\w._%+-]+@[\w.-]+\.[A-Z|a-z]{2,}\b');
    return emailPattern.allMatches(text).map((m) => m.group(0)!).toList();
  }

  /// Estrae timeframe
  String _extractTimeframe(String text) {
    if (text.contains('oggi')) return 'today';
    if (text.contains('domani')) return 'tomorrow';
    if (text.contains('settimana')) return 'week';
    if (text.contains('mese')) return 'month';
    return 'week';
  }

  /// Estrae periodo
  String _extractPeriod(String text) {
    return _extractTimeframe(text); // Riusa la stessa logica
  }

  /// Ottiene la data di fine per un timeframe
  DateTime _getEndDateForTimeframe(DateTime start, String timeframe) {
    switch (timeframe) {
      case 'today':
        return start.add(const Duration(days: 1));
      case 'tomorrow':
        return start.add(const Duration(days: 2));
      case 'week':
        return start.add(const Duration(days: 7));
      case 'month':
        return DateTime(start.year, start.month + 1, start.day);
      default:
        return start.add(const Duration(days: 7));
    }
  }

  /// Ottiene tutti gli eventi da entrambi i calendari
  Future<List<gcal.Event>> _getAllEvents(DateTime start, DateTime end) async {
    final googleEvents = await _googleService.getEvents(
      timeMin: start,
      timeMax: end,
    );

    final outlookEvents = await _outlookService.getEvents(
      startDate: start,
      endDate: end,
    );

    return [...googleEvents, ...outlookEvents];
  }

  /// Identifica blocchi liberi
  List<FreeBlock> _identifyFreeBlocks(
      List<gcal.Event> events,
      DateTime dayStart,
      DateTime dayEnd,
      ) {
    final blocks = <FreeBlock>[];

    // Ordina eventi
    final sorted = events.toList()
      ..sort((a, b) => (a.start?.dateTime ?? dayStart)
          .compareTo(b.start?.dateTime ?? dayStart));

    DateTime lastEnd = dayStart.add(const Duration(hours: 8)); // Inizio giornata lavorativa

    for (final event in sorted) {
      if (event.start?.dateTime != null && event.end?.dateTime != null) {
        final eventStart = event.start!.dateTime!;

        if (eventStart.isAfter(lastEnd)) {
          blocks.add(FreeBlock(
            start: lastEnd,
            end: eventStart,
            duration: eventStart.difference(lastEnd).inMinutes,
          ));
        }

        lastEnd = event.end!.dateTime!;
      }
    }

    // Ultimo blocco fino a fine giornata
    final dayEndWork = dayStart.add(const Duration(hours: 18));
    if (lastEnd.isBefore(dayEndWork)) {
      blocks.add(FreeBlock(
        start: lastEnd,
        end: dayEndWork,
        duration: dayEndWork.difference(lastEnd).inMinutes,
      ));
    }

    return blocks;
  }

  /// Controlla se uno slot è back-to-back
  bool _checkIfBackToBack(DateTime slot, List<gcal.Event> events) {
    for (final event in events) {
      if (event.start?.dateTime != null && event.end?.dateTime != null) {
        final diff1 = slot.difference(event.end!.dateTime!).inMinutes.abs();
        final diff2 = event.start!.dateTime!.difference(slot).inMinutes.abs();

        if (diff1 <= 5 || diff2 <= 5) {
          return true;
        }
      }
    }
    return false;
  }

  /// Ottiene suggerimenti contestuali
  List<String> _getContextualSuggestions() {
    final hour = DateTime.now().hour;
    final suggestions = <String>[];

    if (hour < 12) {
      suggestions.add('Trova il miglior momento per un meeting oggi pomeriggio');
    } else if (hour < 17) {
      suggestions.add('Analizza il mio tempo libero per domani');
    } else {
      suggestions.add('Mostrami il carico di lavoro della prossima settimana');
    }

    suggestions.add('Suggerisci ottimizzazioni per il mio calendario');
    suggestions.add('Dammi un sommario della mia settimana');

    return suggestions;
  }

  /// Formatta data e ora
  String _formatDateTime(DateTime dt) {
    return DateFormat('EEEE d MMMM alle HH:mm', 'it').format(dt);
  }

  /// Genera suggerimenti per il tempo libero
  List<String> _generateFreeTimeSuggestions(
      Map<DateTime, List<OptimalSlot>> slotsByDay,
      List<OptimalSlot> freeSlots,
      ) {
    final suggestions = <String>[];

    // Conta slot ad alta energia
    final highEnergySlots = freeSlots.where((s) => s.energyLevel == EnergyLevel.high).length;
    if (highEnergySlots > 0) {
      suggestions.add('Hai $highEnergySlots slot ad alta energia - perfetti per attività importanti');
    }

    // Giorni con più tempo libero
    if (slotsByDay.isNotEmpty) { // Aggiunto controllo
      final bestDay = slotsByDay.entries
          .reduce((a, b) => a.value.length > b.value.length ? a : b);
      suggestions.add('${DateFormat('EEEE', 'it').format(bestDay.key)} è il giorno con più tempo libero');
    }


    // Suggerimenti basati sul totale
    final totalSlots = freeSlots.length;
    if (totalSlots < 5) {
      suggestions.add('Considera di proteggere più tempo per te stesso');
    } else {
      suggestions.add('Buona disponibilità di tempo - usala saggiamente!');
    }

    return suggestions;
  }
}

// Classi di supporto

/// Intento dell'utente
class UserIntent {
  final IntentType type;
  final Map<String, dynamic> parameters;

  UserIntent({
    required this.type,
    this.parameters = const {},
  });
}

/// Tipo di intento
enum IntentType {
  scheduleOptimal,
  analyzeFreeTime,
  predictWorkload,
  suggestOptimization,
  provideSummary,
  unknown,
}

/// Contesto della conversazione
class ConversationContext {
  final String input;
  final InputType inputType;
  final DateTime timestamp;

  ConversationContext({
    required this.input,
    required this.inputType,
    required this.timestamp,
  });
}

/// Tipo di input
enum InputType {
  voice,
  text,
}

/// Risposta AI
class AIResponse {
  final bool success;
  final String message;
  final Map<String, dynamic>? data;
  final List<String> suggestions;
  final List<AIAction> actions;
  final List<AIVisualization> visualizations;

  AIResponse({
    required this.success,
    required this.message,
    this.data,
    this.suggestions = const [],
    this.actions = const [],
    this.visualizations = const [],
  });
}

/// Azione AI
class AIAction {
  final ActionType type;
  final String label;
  final Map<String, dynamic>? parameters;

  AIAction({
    required this.type,
    required this.label,
    this.parameters,
  });
}

/// Tipo di azione
enum ActionType {
  createEvent,
  showAlternatives,
  optimize,
}

/// Visualizzazione AI
class AIVisualization {
  final VisualizationType type;
  final dynamic data;

  AIVisualization({
    required this.type,
    required this.data,
  });
}

/// Tipo di visualizzazione
enum VisualizationType {
  workloadChart,
  freeTimeHeatmap,
  optimizationSuggestions,
}

/// Slot suggerito arricchito
class EnrichedSlotSuggestion {
  final SlotSuggestion base;
  final DayContext dayContext;
  final double energyLevel;
  final double finalScore;

  // Aggiungi i getter per start e end che delegano a base
  DateTime get start => base.start;
  DateTime get end => base.end;


  EnrichedSlotSuggestion({
    required this.base,
    required this.dayContext,
    required this.energyLevel,
    required this.finalScore,
  });
}

/// Contesto del giorno
class DayContext {
  final int totalMeetings;
  final double meetingDensity;
  final int largestFreeBlock;
  final bool isBackToBack;
  final bool hasEarlierMeetings;
  final bool hasLaterMeetings;

  DayContext({
    required this.totalMeetings,
    required this.meetingDensity,
    required this.largestFreeBlock,
    required this.isBackToBack,
    required this.hasEarlierMeetings,
    required this.hasLaterMeetings,
  });
}

/// Blocco libero
class FreeBlock {
  final DateTime start;
  final DateTime end;
  final int duration;

  FreeBlock({
    required this.start,
    required this.end,
    required this.duration,
  });
}

/// Metriche carico di lavoro
class WorkloadMetrics {
  final Map<DateTime, double> dailyLoad;
  final Map<String, int> hoursByType;
  final double averageLoad;
  final double peakLoad;
  final double totalHours;

  WorkloadMetrics({
    required this.dailyLoad,
    required this.hoursByType,
    required this.averageLoad,
    required this.peakLoad,
    required this.totalHours,
  });
}

/// Confronto carico di lavoro
class WorkloadComparison {
  final double currentAvgLoad;
  final double historicalAvgLoad;
  final double difference;
  final WorkloadTrend trend;

  WorkloadComparison({
    required this.currentAvgLoad,
    required this.historicalAvgLoad,
    required this.difference,
    required this.trend,
  });
}

/// Trend carico di lavoro
enum WorkloadTrend {
  increasing,
  decreasing,
  stable,
}

/// Previsione carico di lavoro
class WorkloadPrediction {
  final String summary;
  final List<String> recommendations;
  final List<DateTime> criticalDays;
  final List<DateTime> suggestedFocusTime;

  WorkloadPrediction({
    required this.summary,
    required this.recommendations,
    required this.criticalDays,
    required this.suggestedFocusTime,
  });
}

/// Opportunità di ottimizzazione
class OptimizationOpportunity {
  final OptimizationType type;
  final String description;
  final double impact;
  final bool actionable;
  final String? actionLabel;
  final Map<String, dynamic>? actionParameters;

  OptimizationOpportunity({
    required this.type,
    required this.description,
    required this.impact,
    required this.actionable,
    this.actionLabel,
    this.actionParameters,
  });
}

/// Tipo di ottimizzazione
enum OptimizationType {
  backToBack,
  meetingToEmail,
  balanceLoad,
  reviewRecurring,
}

/// Risultato previsione
class PredictionResult {
  final DateTime timestamp;
  final Map<String, dynamic> predictions;

  PredictionResult({
    required this.timestamp,
    required this.predictions,
  });
}