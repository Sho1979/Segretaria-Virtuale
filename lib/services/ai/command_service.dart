// lib/services/ai/command_service.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Tipo di input ricevuto
enum InputType { voice, text }

/// Tipo di comando riconosciuto
enum CommandType {
  // Comandi calendario
  showFreeSlots,
  scheduleEvent,
  blockTime,
  rescheduleEvent,
  cancelEvent,

  // Comandi analisi
  dailySummary,
  workloadAnalysis,
  energyAnalysis,
  productivityReport,

  // Comandi task e deleghe
  createReminder,
  delegateTask,
  detectRepetitiveTasks,
  automateTask,

  // Comandi relazioni
  contactReminder,
  vipCheck,
  relationshipAnalysis,

  // Comandi pausa e benessere
  pauseReminder,
  workTimeAlert,
  energyOptimization,

  // Comandi email e documenti
  emailSuggestions,
  followUpReminder,
  draftEmail,

  // Comandi predittivi
  predictiveScheduling,
  anomalyDetection,

  // Multi-comando
  multiCommand,

  // Comandi generali
  unknown
}

/// Rappresenta il contesto dell'utente
class UserContext {
  final TimeOfDay currentTime;
  final int dayOfWeek;
  final double estimatedEnergyLevel;
  final int minutesWorkedToday;
  final DateTime? lastBreak;
  final List<String> recentContacts;
  final Map<String, DateTime> lastContactDates;
  final List<String> todaysTasks;
  final Map<String, int> taskFrequency;
  final String currentLocation;
  final String deviceType;
  final double stressLevel;
  final List<String> upcomingDeadlines;

  UserContext({
    required this.currentTime,
    required this.dayOfWeek,
    required this.estimatedEnergyLevel,
    required this.minutesWorkedToday,
    this.lastBreak,
    this.recentContacts = const [],
    this.lastContactDates = const {},
    this.todaysTasks = const [],
    this.taskFrequency = const {},
    this.currentLocation = 'office',
    this.deviceType = 'mobile',
    this.stressLevel = 0.5,
    this.upcomingDeadlines = const [],
  });
}

/// Intent strategy per analisi avanzata
class IntentStrategy {
  final String pattern;
  final double weight;
  final Function(String) extractor;
  final List<String> contextClues;

  IntentStrategy({
    required this.pattern,
    required this.weight,
    required this.extractor,
    this.contextClues = const [],
  });
}

/// Rappresenta un comando parsato con analisi profonda
class ParsedCommand {
  final String originalText;
  final CommandType type;
  final Map<String, dynamic> parameters;
  final double confidence;
  final DateTime timestamp;
  final List<String> entities;
  final Map<String, double> intentScores;
  final List<String> contextualSuggestions;
  final String? implicitIntent;
  final Map<String, dynamic> metadata;

  ParsedCommand({
    required this.originalText,
    required this.type,
    required this.parameters,
    required this.confidence,
    required this.timestamp,
    this.entities = const [],
    this.intentScores = const {},
    this.contextualSuggestions = const [],
    this.implicitIntent,
    this.metadata = const {},
  });
}

/// Neural-like pattern matcher
class NeuralPatternMatcher {
  final Map<String, List<double>> wordEmbeddings = {};
  final Map<CommandType, List<List<double>>> commandPatterns = {};

  double cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;

    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    if (normA == 0.0 || normB == 0.0) return 0.0;
    return dotProduct / (math.sqrt(normA) * math.sqrt(normB));
  }

  CommandType findBestMatch(String input) {
    // Implementazione semplificata - in produzione useremmo word2vec reale
    double bestScore = 0.0;
    CommandType bestMatch = CommandType.unknown;

    // Analizza similarità con tutti i pattern conosciuti
    commandPatterns.forEach((command, patterns) {
      for (var pattern in patterns) {
        double score = _calculatePatternScore(input, pattern);
        if (score > bestScore) {
          bestScore = score;
          bestMatch = command;
        }
      }
    });

    return bestMatch;
  }

  double _calculatePatternScore(String input, List<double> pattern) {
    // Simulazione di embedding matching
    return 0.75 + (math.Random().nextDouble() * 0.25);
  }
}

/// Classe helper per intent risolto
class _ResolvedIntent {
  final CommandType type;
  final Map<String, dynamic> parameters;

  _ResolvedIntent(this.type, this.parameters);
}

/// Classe helper per comando validato
class _ValidatedCommand {
  final CommandType type;
  final Map<String, dynamic> parameters;

  _ValidatedCommand(this.type, this.parameters);
}

/// Regola contestuale
class ContextualRule {
  final bool Function(UserContext, String) condition;
  final CommandType inferredCommand;
  final double confidence;
  final Map<String, dynamic>? parameters;
  final String? suggestion;

  ContextualRule({
    required this.condition,
    required this.inferredCommand,
    required this.confidence,
    this.parameters,
    this.suggestion,
  });
}

/// Pattern di utilizzo per learning
class UsagePattern {
  final ParsedCommand command;
  final UserContext context;
  final DateTime timestamp;
  bool successful;

  UsagePattern({
    required this.command,
    required this.context,
    required this.timestamp,
    required this.successful,
  });
}

/// Servizio principale per gestire comandi AI - ULTRA INTELLIGENTE
class AICommandService {
  static final AICommandService _instance = AICommandService._internal();
  factory AICommandService() => _instance;
  AICommandService._internal() {
    _initializeStrategies();
    _initializeContextualRules();
  }

  // Neural pattern matcher
  final NeuralPatternMatcher _neuralMatcher = NeuralPatternMatcher();

  // Lista patterns per learning
  final List<UsagePattern> _patterns = [];

  // Cache intelligente per velocizzare risposte
  final Map<String, ParsedCommand> _commandCache = {};

  // Strategie di intent detection
  final Map<CommandType, List<IntentStrategy>> _intentStrategies = {};

  // Regole contestuali
  final List<ContextualRule> _contextualRules = [];

  // Keywords urgenza estese
  final Set<String> _urgencyKeywords = {
    'scadenza', 'deadline', 'urgente', 'oggi', 'imprevisto',
    'emergenza', 'subito', 'asap', 'entro oggi', 'importante',
    'critico', 'priorità', 'immediatamente', 'ora', 'adesso',
    'entro le', 'prima di', 'non oltre', 'tassativo', 'inderogabile'
  };

  // Sinonimi e variazioni
  final Map<String, List<String>> _synonyms = {
    'mostra': ['visualizza', 'fammi vedere', 'dimmi', 'elenca', 'quali sono'],
    'libero': ['disponibile', 'vuoto', 'senza impegni', 'free'],
    'blocca': ['riserva', 'prenota', 'occupa', 'segna come occupato'],
    'memo': ['ricordami', 'promemoria', 'reminder', 'nota', 'appunta'],
    'riepilogo': ['sommario', 'riassunto', 'recap', 'brief', 'overview'],
    'delega': ['assegna', 'passa', 'trasferisci', 'affida', 'chiedi a'],
  };

  // Patterns temporali avanzati
  final Map<String, DateTime Function(DateTime)> _temporalPatterns = {
    'fine settimana': (now) => _getNextWeekend(now),
    'inizio settimana': (now) => _getNextMonday(now),
    'metà settimana': (now) => _getNextWednesday(now),
    'fine mese': (now) => _getEndOfMonth(now),
    'inizio mese prossimo': (now) => _getStartOfNextMonth(now),
  };

  /// Inizializza strategie di intent detection
  void _initializeStrategies() {
    // Strategie per showFreeSlots
    _intentStrategies[CommandType.showFreeSlots] = [
      IntentStrategy(
        pattern: r'(?:quando|dove|che|quali).*(?:libero|disponibile|posso)',
        weight: 0.9,
        extractor: (input) => _extractTimeContext(input),
        contextClues: ['calendario', 'agenda', 'impegni'],
      ),
      IntentStrategy(
        pattern: r'(?:trova|cerca|mostra).*(?:tempo|spazio|slot|buco)',
        weight: 0.85,
        extractor: (input) => _extractDuration(input),
      ),
      IntentStrategy(
        pattern: r'(?:ho|avrò|avrei).*(?:tempo|minuti|ore).*(?:per|di)',
        weight: 0.8,
        extractor: (input) => _extractPurpose(input),
      ),
    ];

    // Strategie per delegateTask
    _intentStrategies[CommandType.delegateTask] = [
      IntentStrategy(
        pattern: r'(?:fai fare|chiedi a|passa a|dì a).*(?:di|che)',
        weight: 0.95,
        extractor: (input) => _extractDelegation(input),
      ),
      IntentStrategy(
        pattern: r'(?:può|potrebbe|dovrebbe).*(?:occuparsi|fare|gestire)',
        weight: 0.85,
        extractor: (input) => _extractDelegation(input),
      ),
    ];

    // Continua per tutti i CommandType...
  }

  /// Inizializza regole contestuali
  void _initializeContextualRules() {
    _contextualRules.addAll([
      // Regola: Se sono le 9 e chiede "cosa ho?", è un daily summary
      ContextualRule(
        condition: (context, input) =>
        context.currentTime.hour >= 8 &&
            context.currentTime.hour <= 10 &&
            input.contains('cosa') &&
            (input.contains('ho') || input.contains('devo')),
        inferredCommand: CommandType.dailySummary,
        confidence: 0.95,
      ),

      // Regola: Se ha lavorato >90 min senza pausa E non sta chiedendo altro esplicitamente
      ContextualRule(
        condition: (context, input) =>
        context.minutesWorkedToday > 90 &&
            (context.lastBreak == null ||
                DateTime.now().difference(context.lastBreak!).inMinutes > 90) &&
            // IMPORTANTE: Applica SOLO se l'utente non sta chiedendo altro
            (input.trim().isEmpty || // Input vuoto
                input.toLowerCase().contains('pausa') || // O sta chiedendo esplicitamente una pausa
                input.toLowerCase().contains('break') ||
                input.toLowerCase().contains('riposo')),
        inferredCommand: CommandType.pauseReminder,
        confidence: 0.7, // Ridotto da 0.9 a 0.7
        suggestion: "Hai lavorato per più di 90 minuti. Ricordati di fare una pausa!",
      ),

      // Regola: Venerdì pomeriggio + "libero" = blocca tempo
      ContextualRule(
        condition: (context, input) =>
        context.dayOfWeek == DateTime.friday &&
            context.currentTime.hour >= 14 &&
            (input.contains('libero') || input.contains('stacco')),
        inferredCommand: CommandType.blockTime,
        confidence: 0.85,
        parameters: {'timePeriod': 'afternoon', 'reason': 'weekend_prep'},
      ),
    ]);
  }
  /// Parser principale con intelligenza avanzata
  Future<ParsedCommand> parseCommand(
      String input,
      InputType inputType,
      [UserContext? userContext]
      ) async {
    // Check cache prima
    final cacheKey = _generateCacheKey(input, userContext);
    if (_commandCache.containsKey(cacheKey)) {
      return _commandCache[cacheKey]!;
    }

    // Pre-processing avanzato
    final preprocessed = _advancedPreprocessing(input);

    // Estrai contesto se non fornito
    userContext ??= await getCurrentUserContext();

    // Analisi multi-livello
    final analysis = await _performMultiLevelAnalysis(
        preprocessed,
        inputType,
        userContext
    );

    // Cache del risultato
    _commandCache[cacheKey] = analysis;

    // Registra per learning
    _recordPattern(analysis, userContext);

    // Cleanup cache se troppo grande
    if (_commandCache.length > 100) {
      _cleanupCache();
    }

    return analysis;
  }

  /// Pre-processing avanzato dell'input
  String _advancedPreprocessing(String input) {
    String processed = input.toLowerCase().trim();

    // Rimuovi "SVP" e variazioni
    processed = processed.replaceAll(RegExp(r'^(svp|hey svp|ok svp|ehi svp)[,:]?\s*'), '');

    // Espandi contrazioni italiane
    final contractions = {
      "un'": "una ",
      "l'": "la ",
      "d'": "di ",
      "all'": "alla ",
      "dell'": "della ",
      "nell'": "nella ",
    };
    contractions.forEach((key, value) {
      processed = processed.replaceAll(key, value);
    });

    // Normalizza spazi multipli
    processed = processed.replaceAll(RegExp(r'\s+'), ' ');

    // Correggi typos comuni
    processed = _correctCommonTypos(processed);

    // Espandi abbreviazioni
    processed = _expandAbbreviations(processed);

    return processed;
  }

  /// Corregge errori di battitura comuni
  String _correctCommonTypos(String input) {
    final typoMap = {
      'calndario': 'calendario',
      'appuntameto': 'appuntamento',
      'richordami': 'ricordami',
      'disponibilita': 'disponibilità',
      'riepilogo': 'riepilogo',
      'settimna': 'settimana',
      'lunedi': 'lunedì',
      'martedi': 'martedì',
      'mercoledi': 'mercoledì',
      'giovedi': 'giovedì',
      'venerdi': 'venerdì',
    };

    String corrected = input;
    typoMap.forEach((typo, correct) {
      corrected = corrected.replaceAll(typo, correct);
    });

    return corrected;
  }

  /// Espande abbreviazioni comuni
  String _expandAbbreviations(String input) {
    final abbrevMap = {
      'asap': 'il prima possibile',
      'fyi': 'per tua informazione',
      'vs': 'versus',
      'h': ' ore',
      'min': ' minuti',
      'gg': ' giorni',
      'sett': ' settimana',
      'tel': 'telefono',
      'msg': 'messaggio',
    };

    String expanded = input;
    abbrevMap.forEach((abbrev, full) {
      expanded = expanded.replaceAll(RegExp('\\b$abbrev\\b'), full);
    });

    return expanded;
  }
  /// Analisi multi-livello ultra intelligente
  Future<ParsedCommand> _performMultiLevelAnalysis(
      String input,
      InputType inputType,
      UserContext context
      ) async {
    // 1. Analisi lessicale e sintattica
    final lexicalAnalysis = _performLexicalAnalysis(input);

    // 2. Riconoscimento entità (NER simulato)
    final entities = _performEntityRecognition(input, lexicalAnalysis);

    // 3. Intent detection con multiple strategie
    final intentScores = await _performIntentDetection(input, entities, context);

    // 4. Applicazione regole contestuali
    final contextualAdjustments = _applyContextualRules(input, context, intentScores);

    // 5. Risoluzione ambiguità
    final resolvedIntent = _resolveAmbiguities(intentScores, contextualAdjustments, context);

    // 6. Estrazione parametri intelligente
    final parameters = _extractSmartParameters(input, resolvedIntent, entities, context);

    // 7. Validazione e correzione
    final validated = _validateAndCorrect(resolvedIntent, parameters, context);

    // 8. Generazione suggerimenti contestuali
    final suggestions = _generateContextualSuggestions(validated, context);

    // 9. Rilevamento intent impliciti
    final implicitIntent = _detectImplicitIntent(input, context, validated);

    // 10. Calcolo confidence finale
    final finalConfidence = _calculateFinalConfidence(
        intentScores,
        contextualAdjustments,
        validated
    );

    return ParsedCommand(
      originalText: input,
      type: validated.type,
      parameters: validated.parameters,
      confidence: finalConfidence,
      timestamp: DateTime.now(),
      entities: entities,
      intentScores: intentScores,
      contextualSuggestions: suggestions,
      implicitIntent: implicitIntent,
      metadata: {
        'inputType': inputType.toString(),
        'context': context,
        'processingTime': DateTime.now().millisecondsSinceEpoch,
        'ambiguityResolved': resolvedIntent.type != validated.type,
      },
    );
  }

  /// Analisi lessicale avanzata
  Map<String, dynamic> _performLexicalAnalysis(String input) {
    final words = input.split(' ');
    final analysis = <String, dynamic>{
      'words': words,
      'wordCount': words.length,
      'verbs': <String>[],
      'nouns': <String>[],
      'temporal': <String>[],
      'quantifiers': <String>[],
      'negations': <String>[],
    };

    // Pattern per identificare parti del discorso
    final verbPatterns = ['are', 'ere', 'ire', 'a', 'i', 'o', 'ato', 'uto', 'ito'];
    final temporalWords = {
      'oggi', 'domani', 'ieri', 'ora', 'dopo', 'prima',
      'mattina', 'pomeriggio', 'sera', 'settimana', 'mese'
    };
    final quantifiers = {
      'tutto', 'tutti', 'alcuni', 'molti', 'pochi', 'nessuno',
      'ogni', 'qualche', 'vari', 'diversi'
    };
    final negations = {'non', 'mai', 'niente', 'nessuno', 'senza'};

    for (var word in words) {
      // Identifica verbi (semplificato)
      if (verbPatterns.any((pattern) => word.endsWith(pattern))) {
        (analysis['verbs'] as List<String>).add(word);
      }

      // Identifica riferimenti temporali
      if (temporalWords.contains(word)) {
        (analysis['temporal'] as List<String>).add(word);
      }

      // Identifica quantificatori
      if (quantifiers.contains(word)) {
        (analysis['quantifiers'] as List<String>).add(word);
      }

      // Identifica negazioni
      if (negations.contains(word)) {
        (analysis['negations'] as List<String>).add(word);
      }
    }

    return analysis;
  }

  /// Riconoscimento entità avanzato
  List<String> _performEntityRecognition(String input, Map<String, dynamic> lexicalAnalysis) {
    final entities = <String>[];

    // Pattern per nomi propri
    final namePattern = RegExp(r'\b[A-Z][a-z]+\b');
    final matches = namePattern.allMatches(input);
    for (var match in matches) {
      final name = match.group(0)!;
      if (!_isCommonWord(name)) {
        entities.add(name);
      }
    }

    // Pattern per email
    final emailPattern = RegExp(r'\b[\w\.-]+@[\w\.-]+\.\w+\b');
    entities.addAll(emailPattern.allMatches(input).map((m) => m.group(0)!));

    // Pattern per numeri di telefono
    final phonePattern = RegExp(r'\b(?:\+39\s?)?3\d{2}\s?\d{6,7}\b');
    entities.addAll(phonePattern.allMatches(input).map((m) => m.group(0)!));

    // Pattern per date
    final datePattern = RegExp(r'\b\d{1,2}[/-]\d{1,2}(?:[/-]\d{2,4})?\b');
    entities.addAll(datePattern.allMatches(input).map((m) => m.group(0)!));

    // Pattern per orari
    final timePattern = RegExp(r'\b\d{1,2}:\d{2}(?::\d{2})?\b');
    entities.addAll(timePattern.allMatches(input).map((m) => m.group(0)!));

    // Aggiungi temporal entities dal lexical analysis
    entities.addAll((lexicalAnalysis['temporal'] as List<String>?) ?? []);

    return entities.toSet().toList(); // Rimuovi duplicati
  }

  /// Intent detection con strategie multiple
  Future<Map<String, double>> _performIntentDetection(
      String input,
      List<String> entities,
      UserContext context
      ) async {
    final scores = <String, double>{};

    // 1. Pattern matching classico
    final patternScores = _performPatternMatching(input);

    // 2. Neural-like matching
    final neuralScores = _performNeuralMatching(input);

    // 3. Keyword density analysis
    final keywordScores = _performKeywordAnalysis(input);

    // 4. Context-aware scoring
    final contextScores = _performContextAnalysis(input, context);

    // 5. Entity-based scoring
    final entityScores = _performEntityAnalysis(entities);

    // Combina tutti gli scores con pesi
    for (var commandType in CommandType.values) {
      final typeStr = commandType.toString();
      double combinedScore = 0.0;

      combinedScore += (patternScores[typeStr] ?? 0.0) * 0.3;
      combinedScore += (neuralScores[typeStr] ?? 0.0) * 0.25;
      combinedScore += (keywordScores[typeStr] ?? 0.0) * 0.2;
      combinedScore += (contextScores[typeStr] ?? 0.0) * 0.15;
      combinedScore += (entityScores[typeStr] ?? 0.0) * 0.1;

      if (combinedScore > 0) {
        scores[typeStr] = combinedScore;
      }
    }

    return scores;
  }

  /// Pattern matching con regex avanzati
  Map<String, double> _performPatternMatching(String input) {
    final scores = <String, double>{};

    // Definisci pattern complessi per ogni comando
    final commandPatterns = {
      CommandType.showFreeSlots: [
        RegExp(r'(?:mostra|dimmi|quali sono|trova).*(?:slot|spazi|tempo).*liber[oi]'),
        RegExp(r'quando.*(?:posso|sono|ho).*(?:liber[oi]|disponibil[ei])'),
        RegExp(r'(?:ho|avrò|avrei).*tempo.*(?:per|di)'),
        RegExp(r'cerca.*(?:buc[oh]i|finestre).*(?:calendario|agenda)'),
      ],
      CommandType.scheduleEvent: [
        RegExp(r'(?:fissa|prenota|metti|aggiungi).*(?:appuntamento|evento|meeting)'),
        RegExp(r'(?:organizza|programma|schedula).*(?:incontro|riunione)'),
        RegExp(r'(?:segna|crea).*(?:in agenda|calendario)'),
      ],
      CommandType.createReminder: [
        RegExp(r'(?:memo|ricorda|promemoria).*(?:di|che|per)'),
        RegExp(r'(?:non.*dimenticare|appunta|segna).*(?:che|di)'),
        RegExp(r'(?:reminder|nota).*(?:per|entro|domani)'),
      ],
      CommandType.delegateTask: [
        RegExp(r'(?:delega|assegna|passa).*(?:a|per).*[A-Z][a-z]+'),
        RegExp(r'(?:chiedi|dì).*a.*[A-Z][a-z]+.*(?:di|che)'),
        RegExp(r'(?:fai fare|affida|trasferisci).*(?:task|compito|lavoro)'),
      ],
      CommandType.dailySummary: [
        RegExp(r'(?:riepilogo|riassunto|sommario).*(?:giorn[oata]|oggi)'),
        RegExp(r'(?:cosa|che cosa|che).*(?:ho|devo).*(?:fare|oggi)'),
        RegExp(r'(?:agenda|programma|impegni).*(?:di oggi|odiern[oi])'),
      ],
      CommandType.workloadAnalysis: [
        RegExp(r'(?:analizza|mostra|calcola).*carico.*lavoro'),
        RegExp(r'(?:quanto|quante ore).*(?:ho lavorato|lavoro)'),
        RegExp(r'(?:report|analisi|bilancio).*(?:ore|tempo|lavoro)'),
      ],
    };

    // Calcola score per ogni pattern
    commandPatterns.forEach((command, patterns) {
      double maxScore = 0.0;
      for (var pattern in patterns) {
        if (pattern.hasMatch(input)) {
          // Score basato su completezza del match
          final match = pattern.firstMatch(input)!;
          final matchLength = match.end - match.start;
          final score = matchLength / input.length;
          maxScore = math.max(maxScore, score);
        }
      }
      if (maxScore > 0) {
        scores[command.toString()] = maxScore;
      }
    });

    return scores;
  }

  /// Neural-like pattern matching
  Map<String, double> _performNeuralMatching(String input) {
    final scores = <String, double>{};

    // Simula word embeddings e similarity matching
    for (var command in CommandType.values) {
      if (command != CommandType.unknown) {
        // In produzione useremmo veri embeddings
        final similarity = _neuralMatcher.cosineSimilarity(
            _getInputEmbedding(input),
            _getCommandEmbedding(command)
        );
        if (similarity > 0.5) {
          scores[command.toString()] = similarity;
        }
      }
    }

    return scores;
  }

  /// Analisi densità keywords
  Map<String, double> _performKeywordAnalysis(String input) {
    final scores = <String, double>{};
    final words = input.split(' ');

    // Keywords pesate per comando
    final weightedKeywords = {
      CommandType.showFreeSlots: {
        'libero': 0.9, 'disponibile': 0.9, 'slot': 0.8, 'tempo': 0.7,
        'spazio': 0.7, 'buco': 0.6, 'finestra': 0.6, 'quando': 0.5,
      },
      CommandType.scheduleEvent: {
        'fissa': 0.9, 'prenota': 0.9, 'evento': 0.8, 'appuntamento': 0.8,
        'meeting': 0.8, 'organizza': 0.7, 'crea': 0.6, 'aggiungi': 0.6,
      },
      CommandType.createReminder: {
        'memo': 0.95, 'ricordami': 0.95, 'promemoria': 0.9, 'reminder': 0.9,
        'appunta': 0.8, 'nota': 0.7, 'memorizza': 0.7, 'segna': 0.6,
      },
      CommandType.delegateTask: {
        'delega': 0.95, 'assegna': 0.9, 'passa': 0.8, 'affida': 0.8,
        'trasferisci': 0.7, 'chiedi': 0.6, 'incarica': 0.7,
      },
    };

    // Calcola score basato su keyword density
    weightedKeywords.forEach((command, keywords) {
      double totalScore = 0.0;
      int matchCount = 0;

      for (var word in words) {
        // Controlla anche sinonimi
        final expandedWord = _expandWithSynonyms(word);
        for (var expanded in expandedWord) {
          if (keywords.containsKey(expanded)) {
            totalScore += keywords[expanded]!;
            matchCount++;
          }
        }
      }

      if (matchCount > 0) {
        // Normalizza per lunghezza input
        scores[command.toString()] = totalScore / math.sqrt(words.length);
      }
    });

    return scores;
  }

  /// Analisi contestuale
  Map<String, double> _performContextAnalysis(String input, UserContext context) {
    final scores = <String, double>{};

    // Boost score basato su contesto temporale
    if (context.currentTime.hour >= 8 && context.currentTime.hour <= 10) {
      scores[CommandType.dailySummary.toString()] = 0.7;
    }

    // Boost per pause se lavora da tanto
    if (context.minutesWorkedToday > 90 &&
        (context.lastBreak == null ||
            DateTime.now().difference(context.lastBreak!).inMinutes > 90)) {
      scores[CommandType.pauseReminder.toString()] = 0.8;
    }

    // Boost per analisi carico lavoro a fine giornata
    if (context.currentTime.hour >= 17) {
      scores[CommandType.workloadAnalysis.toString()] = 0.6;
    }

    // Boost per blocco tempo il venerdì pomeriggio
    if (context.dayOfWeek == DateTime.friday && context.currentTime.hour >= 14) {
      scores[CommandType.blockTime.toString()] = 0.5;
    }

    // Analisi stress e energia
    if (context.stressLevel > 0.7) {
      scores[CommandType.pauseReminder.toString()] =
          (scores[CommandType.pauseReminder.toString()] ?? 0) + 0.3;
    }

    if (context.estimatedEnergyLevel < 0.3) {
      scores[CommandType.energyOptimization.toString()] = 0.6;
    }

    return scores;
  }

  /// Analisi basata su entità
  Map<String, double> _performEntityAnalysis(List<String> entities) {
    final scores = <String, double>{};

    for (var entity in entities) {
      // Se c'è un nome proprio, probabilmente è una delega o contatto
      if (_isPersonName(entity)) {
        scores[CommandType.delegateTask.toString()] =
            (scores[CommandType.delegateTask.toString()] ?? 0) + 0.3;
        scores[CommandType.contactReminder.toString()] =
            (scores[CommandType.contactReminder.toString()] ?? 0) + 0.3;
      }

      // Se c'è una data/ora, probabilmente è scheduling
      if (_isDateTime(entity)) {
        scores[CommandType.scheduleEvent.toString()] =
            (scores[CommandType.scheduleEvent.toString()] ?? 0) + 0.4;
        scores[CommandType.blockTime.toString()] =
            (scores[CommandType.blockTime.toString()] ?? 0) + 0.2;
      }

      // Se c'è un'email, probabilmente riguarda email
      if (entity.contains('@')) {
        scores[CommandType.emailSuggestions.toString()] =
            (scores[CommandType.emailSuggestions.toString()] ?? 0) + 0.5;
      }
    }

    return scores;
  }

  /// Risolve ambiguità tra comandi
  _ResolvedIntent _resolveAmbiguities(
      Map<String, double> intentScores,
      Map<String, dynamic> contextualAdjustments,
      UserContext context
      ) {
    // Trova i top 3 intent
    final sortedIntents = intentScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (sortedIntents.isEmpty) {
      return _ResolvedIntent(CommandType.unknown, {});
    }

    final topIntent = sortedIntents.first;
    final secondIntent = sortedIntents.length > 1 ? sortedIntents[1] : null;

    // Se la differenza è piccola, usa euristica per decidere
    if (secondIntent != null && (topIntent.value - secondIntent.value) < 0.1) {
      // Applica regole di disambiguazione
      return _applyDisambiguationRules(
          topIntent,
          secondIntent,
          intentScores,
          context
      );
    }

    // Altrimenti usa il top intent
    return _ResolvedIntent(
        _stringToCommandType(topIntent.key),
        contextualAdjustments
    );
  }

  /// Estrazione parametri intelligente
  Map<String, dynamic> _extractSmartParameters(
      String input,
      _ResolvedIntent intent,
      List<String> entities,
      UserContext context
      ) {
    final params = <String, dynamic>{};

    // Estrai parametri base
    params.addAll(_extractBaseParameters(input, intent.type));

    // Arricchisci con entità
    params['entities'] = entities;

    // Aggiungi parametri contestuali
    params.addAll(_extractContextualParameters(input, context));

    // Inferisci parametri mancanti
    params.addAll(_inferMissingParameters(intent.type, params, context));

    // Normalizza e valida
    return _normalizeParameters(params, intent.type);
  }
  /// Estrae parametri base per tipo comando
  Map<String, dynamic> _extractBaseParameters(String input, CommandType type) {
    final params = <String, dynamic>{};

    switch (type) {
      case CommandType.showFreeSlots:
      // Estrai data/periodo
        params.addAll(_extractTemporalParameters(input));

        // Estrai durata richiesta
        final durationMatch = RegExp(r'(\d+)\s*(ore|ora|minuti|min)').firstMatch(input);
        if (durationMatch != null) {
          final value = int.parse(durationMatch.group(1)!);
          final unit = durationMatch.group(2)!;
          params['requiredDuration'] = unit.contains('or') ? value * 60 : value;
        } else {
          params['requiredDuration'] = 60; // Default 1 ora
        }

        // Estrai scopo
        if (input.contains('per ')) {
          final purposeMatch = RegExp(r'per\s+(.+?)(?:\s|$)').firstMatch(input);
          if (purposeMatch != null) {
            params['purpose'] = purposeMatch.group(1);
          }
        }
        break;

      case CommandType.scheduleEvent:
        params.addAll(_extractTemporalParameters(input));

        // Estrai titolo evento
        final titlePatterns = [
          RegExp(r'"([^"]+)"'), // Tra virgolette
          RegExp(r'(?:evento|appuntamento|meeting)\s+(.+?)(?:\s+con|\s+alle|\s+per|$)'),
          RegExp(r'(?:chiama|chiamata)\s+(.+?)(?:\s+alle|$)'),
        ];

        for (var pattern in titlePatterns) {
          final match = pattern.firstMatch(input);
          if (match != null) {
            params['title'] = match.group(1)!.trim();
            break;
          }
        }

        // Estrai partecipanti
        final participantMatch = RegExp(r'con\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)').firstMatch(input);
        if (participantMatch != null) {
          params['participants'] = [participantMatch.group(1)!];
        }

        // Estrai luogo
        final locationMatch = RegExp(r'(?:in|presso|a)\s+([A-Z][a-z]+(?:\s+\w+)*)').firstMatch(input);
        if (locationMatch != null) {
          params['location'] = locationMatch.group(1);
        }
        break;

      case CommandType.createReminder:
      // Estrai contenuto promemoria
        final contentPatterns = [
          RegExp(r'(?:memo|ricordami|promemoria)\s+(?:di\s+)?(.+?)(?:\s+entro|\s+per|\s+prima|$)'),
          RegExp(r'(?:che|di)\s+(.+?)(?:\s+entro|\s+domani|$)'),
        ];

        for (var pattern in contentPatterns) {
          final match = pattern.firstMatch(input);
          if (match != null) {
            params['content'] = match.group(1)!.trim();
            break;
          }
        }

        // Estrai deadline
        params.addAll(_extractTemporalParameters(input));

        // Estrai priorità
        if (_isUrgent(input)) {
          params['priority'] = 'high';
        } else if (input.contains('quando puoi') || input.contains('appena possibile')) {
          params['priority'] = 'medium';
        } else {
          params['priority'] = 'normal';
        }
        break;

      case CommandType.delegateTask:
      // Estrai task da delegare
        final taskMatch = RegExp(r'(?:delega|assegna|passa)\s+(.+?)\s+a\s+').firstMatch(input);
        if (taskMatch != null) {
          params['task'] = taskMatch.group(1)!.trim();
        }

        // Estrai assegnatario
        final assigneeMatch = RegExp(r'\s+a\s+([A-Z][a-z]+)').firstMatch(input);
        if (assigneeMatch != null) {
          params['assignee'] = assigneeMatch.group(1)!;
        }

        // Estrai deadline opzionale
        if (input.contains('entro')) {
          params.addAll(_extractTemporalParameters(input));
        }

        // Estrai note/istruzioni
        if (input.contains('di ')) {
          final instructionMatch = RegExp(r'di\s+(.+?)(?:\s+entro|$)').firstMatch(input);
          if (instructionMatch != null) {
            params['instructions'] = instructionMatch.group(1);
          }
        }
        break;

      case CommandType.blockTime:
        params.addAll(_extractTemporalParameters(input));

        // Estrai motivo blocco
        if (input.contains('focus') || input.contains('concentrazione')) {
          params['reason'] = 'focus_time';
        } else if (input.contains('pranzo')) {
          params['reason'] = 'lunch';
        } else if (input.contains('pausa')) {
          params['reason'] = 'break';
        } else if (input.contains('personale')) {
          params['reason'] = 'personal';
        } else {
          params['reason'] = 'blocked';
        }

        // Ricorrenza
        if (input.contains('ogni') || input.contains('tutti')) {
          params['recurring'] = true;

          // Estrai pattern ricorrenza
          if (input.contains('giorno')) {
            params['recurrencePattern'] = 'daily';
          } else if (input.contains('settimana')) {
            params['recurrencePattern'] = 'weekly';
          } else if (input.contains('mese')) {
            params['recurrencePattern'] = 'monthly';
          }
        }
        break;

      case CommandType.contactReminder:
      // Estrai persona da contattare
        final contactMatch = RegExp(r'(?:chiama|contatta|scrivi a|telefona a)\s+([A-Z][a-z]+)').firstMatch(input);
        if (contactMatch != null) {
          params['contact'] = contactMatch.group(1)!;
        }

        // Metodo di contatto
        if (input.contains('chiama') || input.contains('telefona')) {
          params['method'] = 'call';
        } else if (input.contains('mail') || input.contains('email')) {
          params['method'] = 'email';
        } else if (input.contains('messaggio') || input.contains('whatsapp')) {
          params['method'] = 'message';
        } else if (input.contains('scrivi')) {
          params['method'] = 'write';
        }

        // Motivo/argomento
        if (input.contains('per ')) {
          final reasonMatch = RegExp(r'per\s+(.+?)(?:\s+entro|$)').firstMatch(input);
          if (reasonMatch != null) {
            params['reason'] = reasonMatch.group(1);
          }
        }

        // Deadline
        params.addAll(_extractTemporalParameters(input));
        break;

      case CommandType.workloadAnalysis:
      // Periodo di analisi
        if (input.contains('oggi')) {
          params['period'] = 'today';
        } else if (input.contains('settimana')) {
          params['period'] = 'week';
        } else if (input.contains('mese')) {
          params['period'] = 'month';
        } else if (input.contains('anno')) {
          params['period'] = 'year';
        } else {
          // Default basato su contesto
          params['period'] = 'today';
        }

        // Tipo di analisi
        if (input.contains('dettagli') || input.contains('dettagliato')) {
          params['detailed'] = true;
        }

        // Categorie specifiche
        if (input.contains('meeting')) {
          params['category'] = 'meetings';
        } else if (input.contains('email')) {
          params['category'] = 'emails';
        } else if (input.contains('task')) {
          params['category'] = 'tasks';
        }
        break;

      case CommandType.dailySummary:
      // Data per il riepilogo
        params.addAll(_extractTemporalParameters(input));
        if (!params.containsKey('date')) {
          params['date'] = DateTime.now();
        }

        // Formato richiesto
        if (input.contains('breve') || input.contains('veloce')) {
          params['format'] = 'brief';
        } else if (input.contains('dettagli') || input.contains('completo')) {
          params['format'] = 'detailed';
        } else {
          params['format'] = 'standard';
        }

        // Focus specifico
        if (input.contains('priorità')) {
          params['focus'] = 'priorities';
        } else if (input.contains('scadenze')) {
          params['focus'] = 'deadlines';
        }
        break;

      default:
      // Parametri generici
        params.addAll(_extractTemporalParameters(input));
        break;
    }

    return params;
  }

  /// Estrae parametri temporali complessi
  Map<String, dynamic> _extractTemporalParameters(String input) {
    final params = <String, dynamic>{};

    // Data assoluta (es. 15/06/2024)
    final dateRegex = RegExp(r'(\d{1,2})[/\-](\d{1,2})(?:[/\-](\d{2,4}))?');
    final dateMatch = dateRegex.firstMatch(input);
    if (dateMatch != null) {
      final day = int.parse(dateMatch.group(1)!);
      final month = int.parse(dateMatch.group(2)!);
      final year = dateMatch.group(3) != null
          ? int.parse(dateMatch.group(3)!)
          : DateTime.now().year;
      params['date'] = DateTime(year, month, day);
    }

    // Riferimenti relativi
    final now = DateTime.now();
    if (input.contains('oggi')) {
      params['date'] = now;
    } else if (input.contains('domani')) {
      params['date'] = now.add(const Duration(days: 1));
    } else if (input.contains('dopodomani')) {
      params['date'] = now.add(const Duration(days: 2));
    } else if (input.contains('ieri')) {
      params['date'] = now.subtract(const Duration(days: 1));
    }

    // Giorni della settimana
    final weekDays = {
      'lunedì': DateTime.monday,
      'martedì': DateTime.tuesday,
      'mercoledì': DateTime.wednesday,
      'giovedì': DateTime.thursday,
      'venerdì': DateTime.friday,
      'sabato': DateTime.saturday,
      'domenica': DateTime.sunday,
    };

    for (var entry in weekDays.entries) {
      if (input.contains(entry.key)) {
        var targetDay = entry.value;
        var daysUntil = targetDay - now.weekday;

        // Gestisci "prossimo" e "scorso"
        if (input.contains('prossim')) {
          if (daysUntil <= 0) daysUntil += 7;
        } else if (input.contains('scors')) {
          if (daysUntil >= 0) daysUntil -= 7;
        } else {
          // Default: prossima occorrenza
          if (daysUntil < 0) daysUntil += 7;
        }

        params['date'] = now.add(Duration(days: daysUntil));
        break;
      }
    }

    // Periodi speciali
    _temporalPatterns.forEach((pattern, calculator) {
      if (input.contains(pattern)) {
        final result = calculator(now);
        if (result is DateTime) {
          params['date'] = result;
        } else if (result is Map) {
          params.addAll(result as Map<String, dynamic>);
        }
      }
    });

    // Orari
    final timeRegex = RegExp(r'(?:alle\s+)?(\d{1,2})(?::(\d{2}))?(?:\s*(am|pm))?');
    final timeMatch = timeRegex.firstMatch(input);
    if (timeMatch != null) {
      var hour = int.parse(timeMatch.group(1)!);
      final minute = timeMatch.group(2) != null ? int.parse(timeMatch.group(2)!) : 0;
      final ampm = timeMatch.group(3);

      // Gestisci AM/PM
      if (ampm == 'pm' && hour < 12) hour += 12;
      if (ampm == 'am' && hour == 12) hour = 0;

      params['time'] = TimeOfDay(hour: hour, minute: minute);
    }

    // Periodi del giorno
    if (input.contains('mattina') || input.contains('mattino')) {
      params['timePeriod'] = 'morning';
      params['time'] ??= const TimeOfDay(hour: 9, minute: 0);
    } else if (input.contains('pranzo')) {
      params['timePeriod'] = 'lunch';
      params['time'] ??= const TimeOfDay(hour: 13, minute: 0);
    } else if (input.contains('pomeriggio')) {
      params['timePeriod'] = 'afternoon';
      params['time'] ??= const TimeOfDay(hour: 15, minute: 0);
    } else if (input.contains('sera')) {
      params['timePeriod'] = 'evening';
      params['time'] ??= const TimeOfDay(hour: 19, minute: 0);
    } else if (input.contains('notte')) {
      params['timePeriod'] = 'night';
      params['time'] ??= const TimeOfDay(hour: 22, minute: 0);
    }

    // Range temporali
    if (input.contains('da ') && input.contains(' a ')) {
      final rangeRegex = RegExp(r'da\s+(.+?)\s+a\s+(.+?)(?:\s|$)');
      final rangeMatch = rangeRegex.firstMatch(input);
      if (rangeMatch != null) {
        // Parsing semplificato - in produzione sarebbe più robusto
        params['startTime'] = rangeMatch.group(1);
        params['endTime'] = rangeMatch.group(2);
      }
    }

    // Durata
    final durationRegex = RegExp(r'per\s+(\d+)\s*(ore|ora|minuti|min|giorni|giorno|settimane|settimana)');
    final durationMatch = durationRegex.firstMatch(input);
    if (durationMatch != null) {
      final value = int.parse(durationMatch.group(1)!);
      final unit = durationMatch.group(2)!;

      int minutes = 0;
      if (unit.contains('min')) {
        minutes = value;
      } else if (unit.contains('or')) {
        minutes = value * 60;
      } else if (unit.contains('giorn')) {
        minutes = value * 24 * 60;
      } else if (unit.contains('settiman')) {
        minutes = value * 7 * 24 * 60;
      }

      params['duration'] = minutes;
    }

    return params;
  }

  /// Estrae parametri contestuali
  Map<String, dynamic> _extractContextualParameters(String input, UserContext context) {
    final params = <String, dynamic>{};

    // Se non specificata una data, usa contesto per inferire
    if (!input.contains(RegExp(r'oggi|domani|dopodomani|\d{1,2}/\d{1,2}'))) {
      // Se è mattina e chiede qualcosa, probabilmente è per oggi
      if (context.currentTime.hour < 12) {
        params['implicitDate'] = DateTime.now();
      }
      // Se è sera e chiede di schedulare, probabilmente è per domani
      else if (context.currentTime.hour > 18) {
        params['implicitDate'] = DateTime.now().add(const Duration(days: 1));
      }
    }

    // Inferisci urgenza dal contesto
    if (context.stressLevel > 0.7 || context.upcomingDeadlines.isNotEmpty) {
      params['contextualUrgency'] = true;
    }

    // Inferisci energia disponibile
    params['availableEnergy'] = context.estimatedEnergyLevel;

    // Aggiungi info su contatti recenti per suggerimenti
    if (context.recentContacts.isNotEmpty) {
      params['recentContacts'] = context.recentContacts;
    }

    return params;
  }

  /// Inferisce parametri mancanti
  Map<String, dynamic> _inferMissingParameters(
      CommandType type,
      Map<String, dynamic> existingParams,
      UserContext context
      ) {
    final inferred = <String, dynamic>{};

    switch (type) {
      case CommandType.showFreeSlots:
      // Se non ha data, assume oggi
        if (!existingParams.containsKey('date')) {
          inferred['date'] = DateTime.now();
        }
        // Se non ha durata, usa default basato su energia
        if (!existingParams.containsKey('requiredDuration')) {
          inferred['requiredDuration'] = context.estimatedEnergyLevel > 0.6 ? 90 : 60;
        }
        break;

      case CommandType.scheduleEvent:
      // Se non ha titolo, genera uno generico
        if (!existingParams.containsKey('title')) {
          if (existingParams.containsKey('participants')) {
            inferred['title'] = 'Meeting con ${existingParams['participants'][0]}';
          } else {
            inferred['title'] = 'Nuovo appuntamento';
          }
        }
        // Se non ha durata, stima basata su tipo
        if (!existingParams.containsKey('duration')) {
          if (existingParams['title'].toString().toLowerCase().contains('call')) {
            inferred['duration'] = 30;
          } else {
            inferred['duration'] = 60;
          }
        }
        break;

      case CommandType.createReminder:
      // Se non ha deadline, metti fine giornata
        if (!existingParams.containsKey('date') && !existingParams.containsKey('time')) {
          inferred['time'] = const TimeOfDay(hour: 18, minute: 0);
          inferred['date'] = DateTime.now();
        }
        break;

      case CommandType.blockTime:
      // Se non ha end time, blocca 2 ore di default
        if (existingParams.containsKey('time') && !existingParams.containsKey('endTime')) {
          final startTime = existingParams['time'] as TimeOfDay;
          inferred['endTime'] = TimeOfDay(
              hour: (startTime.hour + 2) % 24,
              minute: startTime.minute
          );
        }
        break;

      default:
        break;
    }

    return inferred;
  }

  /// Normalizza e valida parametri
  Map<String, dynamic> _normalizeParameters(Map<String, dynamic> params, CommandType type) {
    final normalized = Map<String, dynamic>.from(params);

    // Normalizza date al fuso orario corretto
    if (normalized.containsKey('date') && normalized['date'] is DateTime) {
      final date = normalized['date'] as DateTime;
      // Assicura che sia nel fuso orario corretto
      normalized['date'] = date.toLocal();
    }

    // Valida orari (non permettere scheduling notturno senza consenso)
    if (normalized.containsKey('time') && normalized['time'] is TimeOfDay) {
      final time = normalized['time'] as TimeOfDay;
      if (time.hour >= 20 || time.hour < 8) {
        normalized['requiresConfirmation'] = true;
        normalized['warning'] = 'Orario fuori dall\'orario lavorativo standard';
      }
    }

    // Rimuovi parametri non validi per il tipo
    switch (type) {
      case CommandType.showFreeSlots:
        normalized.remove('participants');
        normalized.remove('assignee');
        break;
      case CommandType.dailySummary:
        normalized.remove('duration');
        normalized.remove('method');
        break;
      default:
        break;
    }

    return normalized;
  }
  /// Applica regole contestuali SENZA sovrascrivere comandi espliciti
  Map<String, dynamic> _applyContextualRules(
      String input,
      UserContext context,
      Map<String, double> intentScores
      ) {
    final adjustments = <String, dynamic>{};

    // Controlla se c'è già un comando con alta confidenza
    final topIntent = intentScores.entries
        .where((e) => e.value > 0.6)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final hasStrongIntent = topIntent.isNotEmpty && topIntent.first.value > 0.7;

    for (var rule in _contextualRules) {
      if (rule.condition(context, input)) {
        // Se c'è già un comando forte, aggiungi solo suggerimenti
        if (hasStrongIntent && rule.inferredCommand == CommandType.pauseReminder) {
          // NON cambiare il comando, ma aggiungi il suggerimento
          adjustments['pauseSuggestion'] = rule.suggestion;
          adjustments['shouldShowPauseReminder'] = true;
          adjustments['minutesWorked'] = context.minutesWorkedToday;
        } else if (!hasStrongIntent) {
          // Solo se non c'è un comando chiaro, applica la regola
          intentScores[rule.inferredCommand.toString()] =
              (intentScores[rule.inferredCommand.toString()] ?? 0) + rule.confidence;

          if (rule.parameters != null) {
            adjustments.addAll(rule.parameters!);
          }

          if (rule.suggestion != null) {
            adjustments['contextualSuggestion'] = rule.suggestion;
          }
        }
      }
    }

    return adjustments;
  }

  /// Valida e corregge il comando finale
  _ValidatedCommand _validateAndCorrect(
      _ResolvedIntent intent,
      Map<String, dynamic> parameters,
      UserContext context
      ) {
    // Controlla coerenza parametri con tipo comando
    var validatedParams = Map<String, dynamic>.from(parameters);
    var validatedType = intent.type;

    // Correzioni specifiche per tipo
    switch (intent.type) {
      case CommandType.scheduleEvent:
      // Se manca data/ora, non può schedulare
        if (!validatedParams.containsKey('date') && !validatedParams.containsKey('time')) {
          // Converti in showFreeSlots
          validatedType = CommandType.showFreeSlots;
          validatedParams['reason'] = 'Missing datetime for scheduling';
        }
        break;

      case CommandType.delegateTask:
      // Se manca assignee, chiedi
        if (!validatedParams.containsKey('assignee')) {
          validatedParams['requiresInput'] = 'assignee';
          validatedParams['prompt'] = 'A chi vuoi delegare questo task?';
        }
        break;

      default:
        break;
    }

    return _ValidatedCommand(validatedType, validatedParams);
  }

  /// Genera suggerimenti contestuali
  List<String> _generateContextualSuggestions(
      _ValidatedCommand command,
      UserContext context
      ) {
    final suggestions = <String>[];

    switch (command.type) {
      case CommandType.showFreeSlots:
      // Suggerisci basato su energia
        if (context.estimatedEnergyLevel > 0.7) {
          suggestions.add('Hai buona energia, potresti schedulare task impegnativi');
        } else {
          suggestions.add('Energia bassa, meglio task leggeri o una pausa');
        }

        // Suggerisci basato su carico
        if (context.minutesWorkedToday > 360) {
          suggestions.add('Hai già lavorato molto oggi, considera di rimandare a domani');
        }
        break;

      case CommandType.scheduleEvent:
      // Controlla conflitti
        if (command.parameters['time'] != null) {
          suggestions.add('Verifico disponibilità per l\'orario richiesto...');
        }

        // Suggerisci preparazione
        if (command.parameters['title']!.toString().toLowerCase().contains('meeting')) {
          suggestions.add('Vuoi che blocchi 15 minuti prima per prepararti?');
        }
        break;

      case CommandType.delegateTask:
      // Suggerisci basato su frequenza
        final taskName = command.parameters['task']?.toString() ?? '';
        if (taskName.isNotEmpty && (context.taskFrequency[taskName] ?? 0) > 3) {
          suggestions.add('Questo task è ricorrente, considera l\'automazione');
        }
        break;

      case CommandType.dailySummary:
      // Suggerimenti basati su giorno
        if (context.dayOfWeek == DateTime.monday) {
          suggestions.add('Buon inizio settimana! Focus sulle priorità');
        } else if (context.dayOfWeek == DateTime.friday) {
          suggestions.add('Ultimo giorno lavorativo, prepara la prossima settimana');
        }
        break;

      default:
        break;
    }

    // Suggerimenti generali basati su contesto
    if (context.upcomingDeadlines.isNotEmpty) {
      suggestions.add('Hai ${context.upcomingDeadlines.length} scadenze in arrivo');
    }

    if (context.lastContactDates.isNotEmpty) {
      final oldContacts = context.lastContactDates.entries
          .where((e) => DateTime.now().difference(e.value).inDays > 30)
          .toList();
      if (oldContacts.isNotEmpty) {
        suggestions.add('Non senti ${oldContacts.first.key} da più di 30 giorni');
      }
    }

    return suggestions;
  }

  /// Rileva intent impliciti
  String? _detectImplicitIntent(
      String input,
      UserContext context,
      _ValidatedCommand command
      ) {
    // Se chiede slot liberi di sera, forse vuole tempo personale
    if (command.type == CommandType.showFreeSlots &&
        command.parameters['timePeriod'] == 'evening') {
      return 'personal_time_management';
    }

    // Se delega molti task, forse è sovraccarico
    if (command.type == CommandType.delegateTask &&
        context.minutesWorkedToday > 480) {
      return 'workload_reduction_needed';
    }

    // Se chiede analisi carico lavoro venerdì sera, forse vuole bilanciare vita-lavoro
    if (command.type == CommandType.workloadAnalysis &&
        context.dayOfWeek == DateTime.friday &&
        context.currentTime.hour > 16) {
      return 'work_life_balance_check';
    }

    // Se crea molti reminder, forse ha problemi di organizzazione
    if (command.type == CommandType.createReminder &&
        context.taskFrequency['reminder'] != null &&
        context.taskFrequency['reminder']! > 10) {
      return 'organization_improvement_needed';
    }

    // Se blocca tempo ripetutamente, cerca routine
    if (command.type == CommandType.blockTime &&
        command.parameters['recurring'] == true) {
      return 'routine_establishment';
    }

    return null;
  }

  /// Calcola confidence finale
  double _calculateFinalConfidence(
      Map<String, double> intentScores,
      Map<String, dynamic> contextualAdjustments,
      _ValidatedCommand command
      ) {
    final baseScore = intentScores[command.type.toString()] ?? 0.0;
    double finalScore = baseScore;

    // Boost per match contestuale
    if (contextualAdjustments.isNotEmpty) {
      finalScore += 0.1;
    }

    // Boost per parametri completi
    if (!command.parameters.containsKey('requiresInput')) {
      finalScore += 0.05;
    }

    // Penalità per ambiguità
    final topScores = intentScores.values.where((s) => s > 0.5).toList();
    if (topScores.length > 1) {
      finalScore -= 0.1 * (topScores.length - 1);
    }

    // Clamp tra 0 e 1
    return finalScore.clamp(0.0, 1.0);
  }

  /// Helper: Estrai contesto temporale
  String _extractTimeContext(String input) {
    if (input.contains('oggi')) return 'today';
    if (input.contains('domani')) return 'tomorrow';
    if (input.contains('settimana')) return 'week';
    if (input.contains('mese')) return 'month';
    return 'unspecified';
  }

  /// Helper: Estrai durata
  String _extractDuration(String input) {
    final match = RegExp(r'(\d+)\s*(ore|ora|minuti|min)').firstMatch(input);
    if (match != null) {
      return '${match.group(1)} ${match.group(2)}';
    }
    return '60 minuti';
  }

  /// Helper: Estrai scopo
  String _extractPurpose(String input) {
    final match = RegExp(r'per\s+(.+?)(?:\s|$)').firstMatch(input);
    return match?.group(1) ?? 'unspecified';
  }

  /// Helper: Estrai info delegazione
  String _extractDelegation(String input) {
    final match = RegExp(r'(?:a|per)\s+([A-Z][a-z]+)').firstMatch(input);
    return match?.group(1) ?? 'unspecified';
  }

  /// Helper: Genera cache key
  String _generateCacheKey(String input, UserContext? context) {
    final contextKey = context != null
        ? '${context.currentTime.hour}_${context.dayOfWeek}_${context.estimatedEnergyLevel.toStringAsFixed(1)}'
        : 'no_context';
    return '${input.toLowerCase().trim()}_$contextKey';
  }

  /// Helper: Pulisce cache vecchia
  void _cleanupCache() {
    if (_commandCache.length <= 50) return;

    // Rimuovi le 50 entry più vecchie
    final sortedKeys = _commandCache.keys.toList();
    for (int i = 0; i < 50; i++) {
      _commandCache.remove(sortedKeys[i]);
    }
  }

  /// Helper: Ottieni contesto utente corrente
  Future<UserContext> getCurrentUserContext() async {
    // Simulazione - in produzione leggerebbe da vari servizi
    final now = DateTime.now();

    return UserContext(
      currentTime: TimeOfDay.now(),
      dayOfWeek: now.weekday,
      estimatedEnergyLevel: _estimateEnergyLevel(now),
      minutesWorkedToday: _calculateMinutesWorked(now),
      lastBreak: _getLastBreak(),
      recentContacts: await _getRecentContacts(),
      lastContactDates: await _getLastContactDates(),
      todaysTasks: await _getTodaysTasks(),
      taskFrequency: await _getTaskFrequency(),
      currentLocation: await _getCurrentLocation(),
      deviceType: _getDeviceType(),
      stressLevel: await _estimateStressLevel(),
      upcomingDeadlines: await _getUpcomingDeadlines(),
    );
  }

  /// Helper: Stima livello energia
  double _estimateEnergyLevel(DateTime now) {
    final hour = now.hour;

    // Curva energia tipica
    if (hour >= 9 && hour <= 11) return 0.9;
    if (hour >= 14 && hour <= 15) return 0.4; // Post-pranzo
    if (hour >= 16 && hour <= 17) return 0.7;
    if (hour >= 18) return 0.3;
    return 0.5;
  }

  /// Helper: Calcola minuti lavorati
  int _calculateMinutesWorked(DateTime now) {
    // Simulazione - assumiamo inizio alle 9
    if (now.hour < 9) return 0;
    return (now.hour - 9) * 60 + now.minute;
  }

  /// Helper: Ottieni ultima pausa
  DateTime? _getLastBreak() {
    // Simulazione
    final now = DateTime.now();
    if (now.hour > 13) {
      return DateTime(now.year, now.month, now.day, 13, 0);
    }
    return null;
  }

  /// Helper: Ottieni contatti recenti
  Future<List<String>> _getRecentContacts() async {
    // Simulazione
    return ['Mario Rossi', 'Laura Bianchi', 'Giuseppe Verdi'];
  }

  /// Helper: Ottieni date ultimi contatti
  Future<Map<String, DateTime>> _getLastContactDates() async {
    // Simulazione
    final now = DateTime.now();
    return {
      'Mario Rossi': now.subtract(const Duration(days: 3)),
      'Laura Bianchi': now.subtract(const Duration(days: 45)),
      'Giuseppe Verdi': now.subtract(const Duration(days: 10)),
    };
  }

  /// Helper: Ottieni task di oggi
  Future<List<String>> _getTodaysTasks() async {
    // Simulazione
    return [
      'Review codice PR #1234',
      'Meeting team standup',
      'Preparare presentazione Q4',
      'Email follow-up clienti',
    ];
  }

  /// Helper: Ottieni frequenza task
  Future<Map<String, int>> _getTaskFrequency() async {
    // Simulazione
    return {
      'email': 45,
      'meeting': 23,
      'review': 15,
      'report': 8,
      'reminder': 12,
    };
  }

  /// Helper: Ottieni posizione corrente
  Future<String> _getCurrentLocation() async {
    // Simulazione
    return 'office';
  }

  /// Helper: Ottieni tipo device
  String _getDeviceType() {
    // In produzione userebbe Platform check
    return 'mobile';
  }

  /// Helper: Stima livello stress
  Future<double> _estimateStressLevel() async {
    // Simulazione basata su vari fattori
    final deadlines = await _getUpcomingDeadlines();
    final worked = _calculateMinutesWorked(DateTime.now());

    double stress = 0.3;
    if (deadlines.length > 3) stress += 0.3;
    if (worked > 480) stress += 0.2;

    return stress.clamp(0.0, 1.0);
  }

  /// Helper: Ottieni scadenze imminenti
  Future<List<String>> _getUpcomingDeadlines() async {
    // Simulazione
    return [
      'Consegna progetto X - 2 giorni',
      'Report mensile - 5 giorni',
    ];
  }

  /// Helper: Verifica se è urgente
  bool _isUrgent(String input) {
    return _urgencyKeywords.any((keyword) => input.contains(keyword));
  }

  /// Helper: Espandi con sinonimi
  List<String> _expandWithSynonyms(String word) {
    final expanded = [word];

    _synonyms.forEach((key, synonymList) {
      if (synonymList.contains(word)) {
        expanded.add(key);
      } else if (key == word) {
        expanded.addAll(synonymList);
      }
    });

    return expanded;
  }

  /// Helper: Verifica se è parola comune
  bool _isCommonWord(String word) {
    final commonWords = {
      'Il', 'La', 'Un', 'Una', 'Per', 'Con', 'Su', 'Da',
      'In', 'A', 'Di', 'Che', 'È', 'E', 'Ma', 'O',
    };
    return commonWords.contains(word);
  }

  /// Helper: Verifica se è nome di persona
  bool _isPersonName(String entity) {
    // Semplice euristica - inizia con maiuscola e non è parola comune
    return RegExp(r'^[A-Z][a-z]+').hasMatch(entity) && !_isCommonWord(entity);
  }

  /// Helper: Verifica se è data/ora
  bool _isDateTime(String entity) {
    return RegExp(r'\d{1,2}[/\-:]\d{1,2}').hasMatch(entity) ||
        RegExp(r'\d{1,2}:\d{2}').hasMatch(entity);
  }

  /// Helper: Converti stringa a CommandType
  CommandType _stringToCommandType(String typeStr) {
    for (var type in CommandType.values) {
      if (type.toString() == typeStr) {
        return type;
      }
    }
    return CommandType.unknown;
  }

  /// Helper: Ottieni embedding input (simulato)
  List<double> _getInputEmbedding(String input) {
    // In produzione userebbe word2vec o simili
    final hash = input.hashCode;
    return List.generate(128, (i) => (hash * (i + 1) % 100) / 100.0);
  }

  /// Helper: Ottieni embedding comando (simulato)
  List<double> _getCommandEmbedding(CommandType command) {
    // In produzione userebbe embeddings pre-calcolati
    final hash = command.toString().hashCode;
    return List.generate(128, (i) => (hash * (i + 1) % 100) / 100.0);
  }

  /// Helper: Applica regole disambiguazione
  _ResolvedIntent _applyDisambiguationRules(
      MapEntry<String, double> topIntent,
      MapEntry<String, double> secondIntent,
      Map<String, double> allScores,
      UserContext context
      ) {
    final top = _stringToCommandType(topIntent.key);
    final second = _stringToCommandType(secondIntent.key);

    // Regole specifiche di disambiguazione

    // Se showFreeSlots vs scheduleEvent, guarda se ci sono dettagli evento
    if ((top == CommandType.showFreeSlots && second == CommandType.scheduleEvent) ||
        (top == CommandType.scheduleEvent && second == CommandType.showFreeSlots)) {
      // Se ha titolo o partecipanti, è scheduleEvent
      if (allScores.containsKey('hasEventDetails')) {
        return _ResolvedIntent(CommandType.scheduleEvent, {});
      }
      // Altrimenti showFreeSlots
      return _ResolvedIntent(CommandType.showFreeSlots, {});
    }

    // Se createReminder vs scheduleEvent, guarda se è più memo o evento
    if ((top == CommandType.createReminder && second == CommandType.scheduleEvent) ||
        (top == CommandType.scheduleEvent && second == CommandType.createReminder)) {
      // Se contiene "memo" o "ricordami", è reminder
      if (allScores.containsKey('hasMemoKeywords')) {
        return _ResolvedIntent(CommandType.createReminder, {});
      }
      // Altrimenti evento
      return _ResolvedIntent(CommandType.scheduleEvent, {});
    }

    // Default: usa il top score
    return _ResolvedIntent(top, {});
  }

  /// Registra pattern per learning
  void _recordPattern(ParsedCommand command, UserContext context) {
    _patterns.add(UsagePattern(
      command: command,
      context: context,
      timestamp: DateTime.now(),
      successful: true, // Sarà aggiornato dal feedback
    ));

    // Mantieni solo ultimi 1000 pattern
    if (_patterns.length > 1000) {
      _patterns.removeRange(0, _patterns.length - 1000);
    }
  }

  // Helper date functions
  static DateTime _getNextWeekend(DateTime from) {
    var daysUntilSaturday = DateTime.saturday - from.weekday;
    if (daysUntilSaturday <= 0) daysUntilSaturday += 7;
    return from.add(Duration(days: daysUntilSaturday));
  }

  static DateTime _getNextMonday(DateTime from) {
    var daysUntilMonday = DateTime.monday - from.weekday;
    if (daysUntilMonday <= 0) daysUntilMonday += 7;
    return from.add(Duration(days: daysUntilMonday));
  }

  static DateTime _getNextWednesday(DateTime from) {
    var daysUntilWednesday = DateTime.wednesday - from.weekday;
    if (daysUntilWednesday <= 0) daysUntilWednesday += 7;
    return from.add(Duration(days: daysUntilWednesday));
  }

  static DateTime _getEndOfMonth(DateTime from) {
    return DateTime(from.year, from.month + 1, 0);
  }

  static DateTime _getStartOfNextMonth(DateTime from) {
    return DateTime(from.year, from.month + 1, 1);
  }

  /// Aggiorna feedback su un comando
  void updateCommandFeedback(ParsedCommand command, bool successful) {
    // Trova il pattern corrispondente e aggiorna
    final pattern = _patterns.lastWhere(
          (p) => p.command.originalText == command.originalText &&
          p.command.timestamp == command.timestamp,
      orElse: () => UsagePattern(
        command: command,
        context: UserContext(
          currentTime: TimeOfDay.now(),
          dayOfWeek: DateTime.now().weekday,
          estimatedEnergyLevel: 0.5,
          minutesWorkedToday: 0,
        ),
        timestamp: DateTime.now(),
        successful: successful,
      ),
    );

    pattern.successful = successful;

    // Usa il feedback per migliorare i pesi (reinforcement learning semplificato)
    if (!successful) {
      // Riduci confidence per pattern simili
      _adjustPatternWeights(command, -0.1);
    } else {
      // Aumenta confidence per pattern simili
      _adjustPatternWeights(command, 0.05);
    }
  }

  /// Aggiusta pesi pattern basato su feedback
  void _adjustPatternWeights(ParsedCommand command, double adjustment) {
    // In produzione questo aggiornerebbe i pesi del modello
    // Per ora solo logging
    debugPrint('Adjusting weights for ${command.type}: $adjustment');
  }

  /// Ottieni suggerimenti predittivi basati su context
  Future<List<String>> getPredictiveSuggestions([UserContext? context]) async {
    // Se il context non è fornito, lo otteniamo
    context ??= await getCurrentUserContext();

    final suggestions = <String>[];

    // Analizza pattern storici per l'ora corrente
    final similarPatterns = _patterns.where((p) =>
    (p.context.currentTime.hour - context!.currentTime.hour).abs() <= 1 &&
        p.context.dayOfWeek == context.dayOfWeek &&
        p.successful
    ).toList();

    // Estrai comandi frequenti in questo contesto
    final commandFrequency = <CommandType, int>{};
    for (var pattern in similarPatterns) {
      commandFrequency[pattern.command.type] =
          (commandFrequency[pattern.command.type] ?? 0) + 1;
    }

    // Genera suggerimenti basati su frequenza
    final sortedCommands = commandFrequency.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    for (var entry in sortedCommands.take(3)) {
      suggestions.add(_generateSuggestionForCommand(entry.key, context));
    }

    // Aggiungi suggerimenti contestuali specifici
    if (context.lastBreak == null ||
        DateTime.now().difference(context.lastBreak!).inMinutes > 90) {
      suggestions.add('È ora di fare una pausa');
    }

    if (context.upcomingDeadlines.isNotEmpty) {
      suggestions.add('Rivedi le scadenze in arrivo');
    }

    return suggestions;
  }

  /// Genera suggerimento per comando
  String _generateSuggestionForCommand(CommandType type, UserContext context) {
    switch (type) {
      case CommandType.showFreeSlots:
        return 'Vuoi vedere i tuoi slot liberi per oggi?';
      case CommandType.dailySummary:
        return 'Vuoi il riepilogo della giornata?';
      case CommandType.pauseReminder:
        return 'È ora di una pausa caffè?';
      case CommandType.workloadAnalysis:
        return 'Vuoi analizzare il carico di lavoro?';
      default:
        return 'Posso aiutarti con qualcosa?';
    }
  }
}