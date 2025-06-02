// lib/services/ai/command_service.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Tipo di input ricevuto
enum InputType { voice, text }

/// Tipo di comando riconosciuto
enum CommandType {
  // Comandi calendario
  showFreeSlots,
  scheduleEvent,
  blockTime,

  // Comandi analisi
  dailySummary,
  workloadAnalysis,

  // Comandi relazioni
  contactReminder,

  // Comandi generali
  unknown
}

/// Rappresenta un comando parsato
class ParsedCommand {
  final String originalText;
  final CommandType type;
  final Map<String, dynamic> parameters;
  final double confidence;
  final DateTime timestamp;

  ParsedCommand({
    required this.originalText,
    required this.type,
    required this.parameters,
    required this.confidence,
    required this.timestamp,
  });
}

/// Rappresenta un pattern di utilizzo per ML
class UsagePattern {
  final String userId;
  final CommandType commandType;
  final TimeOfDay timeOfDay;
  final int dayOfWeek;
  final Map<String, dynamic> context;
  final DateTime timestamp;

  UsagePattern({
    required this.userId,
    required this.commandType,
    required this.timeOfDay,
    required this.dayOfWeek,
    required this.context,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'commandType': commandType.toString(),
    'hour': timeOfDay.hour,
    'minute': timeOfDay.minute,
    'dayOfWeek': dayOfWeek,
    'context': context,
    'timestamp': timestamp.toIso8601String(),
  };
}

/// Servizio principale per gestire comandi AI
class AICommandService {
  static final AICommandService _instance = AICommandService._internal();
  factory AICommandService() => _instance;
  AICommandService._internal();

  // Lista patterns per learning (in produzione useremo Isar DB)
  final List<UsagePattern> _patterns = [];

  /// Parser principale dei comandi
  Future<ParsedCommand> parseCommand(String input, InputType inputType) async {
    final normalizedInput = _normalizeInput(input);

    // Analizza il comando
    final analysis = _analyzeCommand(normalizedInput);

    // Registra il pattern per ML
    _recordPattern(analysis);

    return analysis;
  }

  /// Normalizza l'input (rimuove punteggiatura, lowercase, etc)
  String _normalizeInput(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[.,!?;]'), '')
        .trim();
  }

  /// Analizza il comando e estrae parametri
  ParsedCommand _analyzeCommand(String input) {
    // Keywords mapping per comandi
    final commandKeywords = {
      CommandType.showFreeSlots: [
        'slot liberi', 'quando sono libero', 'tempo libero',
        'disponibilità', 'buchi', 'finestre libere'
      ],
      CommandType.scheduleEvent: [
        'fissa', 'prenota', 'organizza', 'metti in agenda',
        'segna', 'aggiungi evento', 'crea appuntamento'
      ],
      CommandType.blockTime: [
        'blocca', 'riserva', 'tieni libero', 'no meeting'
      ],
      CommandType.dailySummary: [
        'riepilogo', 'riassunto', 'cosa ho oggi', 'programma',
        'agenda del giorno'
      ],
      CommandType.workloadAnalysis: [
        'carico di lavoro', 'quanto lavoro', 'ore lavorate',
        'analisi carico'
      ],
    };

    CommandType detectedType = CommandType.unknown;
    double highestScore = 0.0;
    Map<String, dynamic> parameters = {};

    // Cerca keywords nei comandi
    commandKeywords.forEach((type, keywords) {
      for (String keyword in keywords) {
        if (input.contains(keyword)) {
          double score = keyword.split(' ').length / input.split(' ').length;
          if (score > highestScore) {
            highestScore = score;
            detectedType = type;
          }
        }
      }
    });

    // Estrai parametri specifici per tipo comando
    parameters = _extractParameters(input, detectedType);

    return ParsedCommand(
      originalText: input,
      type: detectedType,
      parameters: parameters,
      confidence: highestScore,
      timestamp: DateTime.now(),
    );
  }

  /// Estrae parametri dal comando
  Map<String, dynamic> _extractParameters(String input, CommandType type) {
    Map<String, dynamic> params = {};

    switch (type) {
      case CommandType.showFreeSlots:
      // Prima controlla se c'è una data esplicita nel tag
        final dateRegex = RegExp(r'\[date:(.*?)\]');
        final dateMatch = dateRegex.firstMatch(input);
        if (dateMatch != null) {
          try {
            params['date'] = DateTime.parse(dateMatch.group(1)!);
          } catch (e) {
            // Ignora errori di parsing
          }
        }

        // Se non c'è tag, cerca riferimenti temporali nel testo
        if (params['date'] == null) {
          if (input.contains('oggi')) {
            params['date'] = DateTime.now();
          } else if (input.contains('domani')) {
            params['date'] = DateTime.now().add(const Duration(days: 1));
          } else if (input.contains('dopodomani')) {
            params['date'] = DateTime.now().add(const Duration(days: 2));
          } else if (input.contains('settimana')) {
            params['dateRange'] = 'week';
          }
        }

        // Cerca durata
        final durationRegex = RegExp(r'(\d+)\s*(ore|ora|minuti|min)');
        final match = durationRegex.firstMatch(input);
        if (match != null) {
          int value = int.parse(match.group(1)!);
          String unit = match.group(2)!;
          params['duration'] = unit.contains('or') ? value * 60 : value;
        }
        break;

      case CommandType.scheduleEvent:
      // Estrai informazioni per creare evento
        final dateRegex = RegExp(r'\[date:(.*?)\]');
        final dateMatch = dateRegex.firstMatch(input);
        if (dateMatch != null) {
          try {
            params['date'] = DateTime.parse(dateMatch.group(1)!);
          } catch (e) {
            // Ignora errori di parsing
          }
        }

        if (params['date'] == null) {
          if (input.contains('domani')) {
            params['date'] = DateTime.now().add(const Duration(days: 1));
          } else if (input.contains('oggi')) {
            params['date'] = DateTime.now();
          }
        }

        // Cerca orario
        final timeRegex = RegExp(r'alle (\d{1,2}):?(\d{0,2})');
        final timeMatch = timeRegex.firstMatch(input);
        if (timeMatch != null) {
          final hour = int.parse(timeMatch.group(1)!);
          final minute = timeMatch.group(2)?.isNotEmpty == true
              ? int.parse(timeMatch.group(2)!)
              : 0;
          params['time'] = TimeOfDay(hour: hour, minute: minute);
        }
        break;

      case CommandType.blockTime:
      // Cerca giorno specifico
        final days = ['lunedì', 'martedì', 'mercoledì', 'giovedì',
          'venerdì', 'sabato', 'domenica'];
        for (int i = 0; i < days.length; i++) {
          if (input.contains(days[i])) {
            params['dayOfWeek'] = i + 1;
            break;
          }
        }

        // Cerca orari
        final timeRegex = RegExp(r'(\d{1,2}):?(\d{0,2})');
        final times = timeRegex.allMatches(input).toList();
        if (times.isNotEmpty) {
          params['startTime'] = times.first.group(0);
          if (times.length > 1) {
            params['endTime'] = times.last.group(0);
          }
        }
        break;

      case CommandType.dailySummary:
      case CommandType.workloadAnalysis:
      // Estrai data dal tag se presente
        final dateRegex = RegExp(r'\[date:(.*?)\]');
        final dateMatch = dateRegex.firstMatch(input);
        if (dateMatch != null) {
          try {
            params['date'] = DateTime.parse(dateMatch.group(1)!);
          } catch (e) {
            // Ignora errori di parsing
          }
        }

        // Se non c'è tag, cerca riferimenti temporali
        if (params['date'] == null) {
          if (input.contains('oggi')) {
            params['date'] = DateTime.now();
          } else if (input.contains('domani')) {
            params['date'] = DateTime.now().add(const Duration(days: 1));
          }
        }
        break;

      default:
        break;
    }

    return params;
  }

  /// Registra pattern per machine learning
  void _recordPattern(ParsedCommand command) {
    if (command.type != CommandType.unknown) {
      final now = DateTime.now();
      final pattern = UsagePattern(
        userId: 'current_user', // In produzione useremo l'ID reale
        commandType: command.type,
        timeOfDay: TimeOfDay.fromDateTime(now),
        dayOfWeek: now.weekday,
        context: {
          'parameters': command.parameters,
          'confidence': command.confidence,
        },
        timestamp: now,
      );

      _patterns.add(pattern);

      // Trigger analisi se abbiamo abbastanza dati
      if (_patterns.length % 10 == 0) {
        _analyzePatterns();
      }
    }
  }

  /// Analizza i pattern per suggerimenti predittivi
  Future<List<String>> getPredictiveSuggestions() async {
    final now = DateTime.now();
    final currentHour = now.hour;
    final currentDay = now.weekday;

    List<String> suggestions = [];

    // Analizza pattern frequenti per ora/giorno corrente
    Map<CommandType, int> frequencyMap = {};

    for (var pattern in _patterns) {
      // Considera pattern simili (±1 ora, stesso giorno settimana)
      if ((pattern.timeOfDay.hour - currentHour).abs() <= 1 &&
          pattern.dayOfWeek == currentDay) {
        frequencyMap[pattern.commandType] =
            (frequencyMap[pattern.commandType] ?? 0) + 1;
      }
    }

    // Ordina per frequenza e genera suggerimenti
    var sortedCommands = frequencyMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    for (var entry in sortedCommands.take(3)) {
      suggestions.add(_generateSuggestion(entry.key));
    }

    // Se non ci sono suggerimenti basati su pattern, mostra quelli default
    if (suggestions.isEmpty) {
      suggestions = [
        "Mostra slot liberi oggi",
        "Riepilogo giornata",
        "Analizza carico di lavoro"
      ];
    }

    return suggestions;
  }

  /// Genera suggerimento testuale per tipo comando
  String _generateSuggestion(CommandType type) {
    switch (type) {
      case CommandType.showFreeSlots:
        return "Mostra slot liberi oggi";
      case CommandType.dailySummary:
        return "Riepilogo giornata";
      case CommandType.workloadAnalysis:
        return "Analizza carico di lavoro";
      case CommandType.blockTime:
        return "Blocca tempo per focus";
      case CommandType.scheduleEvent:
        return "Crea nuovo appuntamento";
      default:
        return "";
    }
  }

  /// Analizza pattern per insights
  void _analyzePatterns() {
    if (_patterns.isEmpty) return;

    // Calcola comando più usato
    Map<CommandType, int> commandCounts = {};
    for (var pattern in _patterns) {
      commandCounts[pattern.commandType] =
          (commandCounts[pattern.commandType] ?? 0) + 1;
    }

    // Calcola orari di picco utilizzo
    Map<int, int> hourCounts = {};
    for (var pattern in _patterns) {
      hourCounts[pattern.timeOfDay.hour] =
          (hourCounts[pattern.timeOfDay.hour] ?? 0) + 1;
    }

    if (commandCounts.isNotEmpty) {
      final mostUsed = commandCounts.entries.reduce((a, b) => a.value > b.value ? a : b);
      debugPrint('AI Insights - Most used command: ${mostUsed.key}');
    }

    if (hourCounts.isNotEmpty) {
      final peakHour = hourCounts.entries.reduce((a, b) => a.value > b.value ? a : b);
      debugPrint('AI Insights - Peak usage hour: ${peakHour.key}:00');
    }
  }

  /// Ottieni insights sull'utilizzo
  Map<String, dynamic> getUsageInsights() {
    if (_patterns.isEmpty) {
      return {'message': 'Non ci sono ancora abbastanza dati'};
    }

    // Analisi comandi più usati
    Map<CommandType, int> commandCounts = {};
    for (var pattern in _patterns) {
      commandCounts[pattern.commandType] =
          (commandCounts[pattern.commandType] ?? 0) + 1;
    }

    // Analisi orari
    Map<int, int> hourlyUsage = {};
    for (var pattern in _patterns) {
      hourlyUsage[pattern.timeOfDay.hour] =
          (hourlyUsage[pattern.timeOfDay.hour] ?? 0) + 1;
    }

    return {
      'totalCommands': _patterns.length,
      'mostUsedCommand': commandCounts.entries.isNotEmpty
          ? commandCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key.toString()
          : 'none',
      'peakHour': hourlyUsage.entries.isNotEmpty
          ? hourlyUsage.entries.reduce((a, b) => a.value > b.value ? a : b).key
          : 0,
      'commandDistribution': commandCounts.map((k, v) => MapEntry(k.toString(), v)),
    };
  }
}