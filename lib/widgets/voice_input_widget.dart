// lib/widgets/voice_input_widget.dart

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../services/ai/command_service.dart';
import 'dart:async';

class VoiceInputWidget extends StatefulWidget {
  final Function(ParsedCommand) onCommandReceived;

  const VoiceInputWidget({
    Key? key,
    required this.onCommandReceived,
  }) : super(key: key);

  @override
  State<VoiceInputWidget> createState() => _VoiceInputWidgetState();
}

class _VoiceInputWidgetState extends State<VoiceInputWidget>
    with TickerProviderStateMixin {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final AICommandService _aiService = AICommandService();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _chipScrollController = ScrollController();

  bool _isListening = false;
  bool _speechEnabled = false;
  String _transcribedText = '';
  double _confidence = 0.0;
  bool _isProcessing = false;

  // Tracking per debug
  String? _lastProcessedCommand;
  CommandType? _lastCommandType;

  // Animazioni
  late AnimationController _animationController;
  late AnimationController _fadeController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _fadeAnimation;

  // Timer per auto-stop del microfono
  Timer? _listeningTimer;

  // Storia comandi per quick access
  final List<String> _commandHistory = [];
  static const int _maxHistoryItems = 5;

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _initAnimations();
    _loadCommandHistory();
  }

  void _initAnimations() {
    // Animazione per il bottone microfono
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.3,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    // Animazione fade per feedback visuale
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    ));

    _fadeController.forward();
  }

  @override
  void dispose() {
    _speech.stop();
    _animationController.dispose();
    _fadeController.dispose();
    _textController.dispose();
    _chipScrollController.dispose();
    _listeningTimer?.cancel();
    super.dispose();
  }

  /// Inizializza speech recognition con gestione errori avanzata
  void _initSpeech() async {
    try {
      _speechEnabled = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) return;

          debugPrint('🎤 Speech status: $status');

          setState(() {
            _isListening = status == 'listening';
          });

          if (status == 'done' || status == 'notListening') {
            _stopListeningAnimation();
          }
        },
        onError: (error) {
          if (!mounted) return;

          debugPrint('🔴 Speech error: ${error.errorMsg} - permanent: ${error.permanent}');

          setState(() {
            _isListening = false;
          });

          _stopListeningAnimation();

          // Gestione errori specifici
          if (error.errorMsg.contains('permission')) {
            _showError('Permesso microfono negato. Controlla le impostazioni.');
          } else if (error.permanent) {
            _showError('Errore permanente del microfono. Riavvia l\'app.');
          }
        },
        debugLogging: kDebugMode,
      );

      debugPrint('✅ Speech enabled: $_speechEnabled');

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('❌ Errore inizializzazione speech: $e');
      if (mounted) {
        setState(() {
          _speechEnabled = false;
        });
      }
    }
  }

  /// Carica storia comandi
  Future<void> _loadCommandHistory() async {
    // In produzione, caricheresti da SharedPreferences
    // Per ora usiamo una lista vuota
  }

  /// Salva comando nella storia
  void _saveToHistory(String command) {
    if (command.trim().isEmpty) return;

    // Rimuovi duplicati
    _commandHistory.remove(command);

    // Aggiungi in cima
    _commandHistory.insert(0, command);

    // Mantieni solo gli ultimi N
    if (_commandHistory.length > _maxHistoryItems) {
      _commandHistory.removeLast();
    }

    // In produzione, salvare in SharedPreferences
  }

  /// Avvia ascolto vocale con gestione avanzata
  void _startListening() async {
    if (!_speechEnabled) {
      if (kIsWeb) {
        _showError('🎤 Consenti l\'accesso al microfono nel browser');
      } else {
        _showError('🎤 Microfono non disponibile su questo dispositivo');
      }
      return;
    }

    try {
      // Pulisci testo precedente
      setState(() {
        _transcribedText = '';
        _confidence = 0.0;
      });

      await _speech.listen(
        onResult: (result) {
          if (!mounted) return;

          setState(() {
            _transcribedText = result.recognizedWords;
            _confidence = result.confidence;
          });

          debugPrint('🎙️ Trascritto: "$_transcribedText" (confidence: ${_confidence.toStringAsFixed(2)})');

          if (result.finalResult && _transcribedText.isNotEmpty) {
            _processCommand(_transcribedText, InputType.voice);
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        localeId: 'it_IT',
        onSoundLevelChange: (level) {
          // Potresti mostrare un indicatore visuale del livello audio
        },
        cancelOnError: true,
        partialResults: true,
        listenMode: stt.ListenMode.dictation,
      );

      _animationController.repeat(reverse: true);

      // Auto-stop dopo 30 secondi
      _listeningTimer?.cancel();
      _listeningTimer = Timer(const Duration(seconds: 30), () {
        if (_isListening) {
          _stopListening();
        }
      });

      if (mounted) {
        setState(() {
          _isListening = true;
        });
      }
    } catch (e) {
      debugPrint('❌ Errore avvio ascolto: $e');
      _showError('Impossibile avviare il microfono');
    }
  }

  /// Ferma ascolto
  void _stopListening() async {
    _listeningTimer?.cancel();
    await _speech.stop();
    _stopListeningAnimation();

    if (mounted) {
      setState(() {
        _isListening = false;
      });
    }
  }

  void _stopListeningAnimation() {
    _animationController.stop();
    _animationController.reset();
  }

  /// Processa comando con debug avanzato
  void _processCommand(String input, InputType type) async {
    if (input.trim().isEmpty) return;

    // Previeni doppi click
    if (_isProcessing) {
      debugPrint('⚠️ Comando già in elaborazione, ignorato: "$input"');
      return;
    }

    setState(() {
      _isProcessing = true;
      _lastProcessedCommand = input;
    });

    debugPrint('\n🔵 ===== INIZIO PROCESSAMENTO COMANDO =====');
    debugPrint('📝 Input originale: "$input"');
    debugPrint('🎯 Tipo input: $type');
    debugPrint('⏰ Timestamp: ${DateTime.now().toIso8601String()}');

    _showProcessing();

    // Salva nella storia
    _saveToHistory(input);

    try {
      // Preprocessa l'input per gestire riferimenti temporali
      String processedInput = input;
      DateTime? targetDate;

      final lowerInput = input.toLowerCase();
      debugPrint('📝 Input lowercase: "$lowerInput"');

      // Gestione date
      if (lowerInput.contains('domani')) {
        targetDate = DateTime.now().add(const Duration(days: 1));
        processedInput = '$input [date:${targetDate.toIso8601String()}]';
        debugPrint('📅 Rilevata data: DOMANI -> $targetDate');
      } else if (lowerInput.contains('dopodomani')) {
        targetDate = DateTime.now().add(const Duration(days: 2));
        processedInput = '$input [date:${targetDate.toIso8601String()}]';
        debugPrint('📅 Rilevata data: DOPODOMANI -> $targetDate');
      } else if (lowerInput.contains('oggi')) {
        targetDate = DateTime.now();
        processedInput = '$input [date:${targetDate.toIso8601String()}]';
        debugPrint('📅 Rilevata data: OGGI -> $targetDate');
      }

      debugPrint('🔄 Input processato: "$processedInput"');

      // Parsing comando
      final command = await _aiService.parseCommand(processedInput, type);

      // Se il comando originale conteneva riferimenti temporali, assicurati che siano nel comando
      if (targetDate != null && command.parameters['date'] == null) {
        command.parameters['date'] = targetDate;
        debugPrint('📅 Data aggiunta ai parametri');
      }

      // Debug del comando parsato
      debugPrint('\n🎯 COMANDO PARSATO:');
      debugPrint('   Tipo: ${command.type}');
      debugPrint('   Parametri: ${command.parameters}');
      debugPrint('   Confidenza: ${command.confidence.toStringAsFixed(2)}');
      debugPrint('   Entities: ${command.entities}');

      setState(() {
        _lastCommandType = command.type;
      });

      // Invia al dashboard
      widget.onCommandReceived(command);

      // Mostra feedback
      _showCommandProcessed(command);

      if (mounted) {
        setState(() {
          _transcribedText = '';
          _textController.clear();
        });
      }
    } catch (e, stackTrace) {
      debugPrint('❌ ERRORE processamento comando: $e');
      debugPrint('📚 Stack trace: $stackTrace');
      _showError('Errore nel processare il comando');
    } finally {
      setState(() {
        _isProcessing = false;
      });
      debugPrint('🔵 ===== FINE PROCESSAMENTO COMANDO =====\n');
    }
  }

  /// Mostra stato processing
  void _showProcessing() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: const [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 16),
            Text('Elaborazione comando...'),
          ],
        ),
        duration: const Duration(seconds: 1),
        backgroundColor: Colors.blue,
      ),
    );
  }

  /// Mostra comando processato con più dettagli
  void _showCommandProcessed(ParsedCommand command) {
    if (!mounted) return;

    IconData icon;
    Color color;
    String typeText = command.type.toString().split('.').last;

    switch (command.type) {
      case CommandType.showFreeSlots:
        icon = Icons.event_available;
        color = Colors.green;
        break;
      case CommandType.scheduleEvent:
        icon = Icons.event;
        color = Colors.blue;
        break;
      case CommandType.pauseReminder:
        icon = Icons.free_breakfast;
        color = Colors.orange;
        break;
      case CommandType.dailySummary:
        icon = Icons.today;
        color = Colors.purple;
        break;
      case CommandType.unknown:
        icon = Icons.help_outline;
        color = Colors.grey;
        break;
      default:
        icon = Icons.check_circle;
        color = Colors.teal;
    }

    String message = 'Comando: $typeText';
    if (command.confidence < 0.5) {
      message += ' ⚠️';
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
            if (command.confidence >= 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${(command.confidence * 100).toInt()}%',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Mostra errore con stile
  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  /// Widget per i pulsanti delle azioni rapide MIGLIORATO
  Widget _buildQuickActionButtons() {
    final actions = [
      QuickAction(
        icon: Icons.event_available,
        label: 'Slot liberi',
        command: 'mostra i miei slot liberi per oggi',
        color: Colors.green,
      ),
      QuickAction(
        icon: Icons.today,
        label: 'Oggi',
        command: 'cosa ho in programma oggi',
        color: Colors.blue,
      ),
      QuickAction(
        icon: Icons.add_alarm,
        label: 'Promemoria',
        command: 'crea un nuovo promemoria',
        color: Colors.orange,
      ),
      QuickAction(
        icon: Icons.event,
        label: 'Evento',
        command: 'crea un nuovo evento nel calendario',
        color: Colors.purple,
      ),
      QuickAction(
        icon: Icons.analytics,
        label: 'Analisi',
        command: 'analizza il mio carico di lavoro',
        color: Colors.teal,
      ),
      QuickAction(
        icon: Icons.block,
        label: 'Focus Time',
        command: 'blocca del tempo per concentrarmi',
        color: Colors.indigo,
      ),
      QuickAction(
        icon: Icons.person_add,
        label: 'Delega',
        command: 'voglio delegare un task',
        color: Colors.pink,
      ),
      QuickAction(
        icon: Icons.coffee,
        label: 'Pausa',
        command: 'programma una pausa caffè',
        color: Colors.brown,
      ),
    ];

    return Container(
      height: 48,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListView.builder(
        controller: _chipScrollController,
        scrollDirection: Axis.horizontal,
        itemCount: actions.length,
        itemBuilder: (context, index) {
          final action = actions[index];
          return Padding(
            padding: EdgeInsets.only(
              left: index == 0 ? 0 : 4,
              right: index == actions.length - 1 ? 0 : 4,
            ),
            child: _buildEnhancedActionChip(action),
          );
        },
      ),
    );
  }

  /// Action chip migliorato con animazioni
  Widget _buildEnhancedActionChip(QuickAction action) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isProcessing ? null : () {
          debugPrint('🎯 Quick action tapped: ${action.label}');
          _processCommand(action.command, InputType.text);
        },
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: _isProcessing
                ? Colors.grey.shade200
                : action.color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _isProcessing
                  ? Colors.grey.shade300
                  : action.color.withOpacity(0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                action.icon,
                size: 20,
                color: _isProcessing ? Colors.grey : action.color,
              ),
              const SizedBox(width: 8),
              Text(
                action.label,
                style: TextStyle(
                  color: _isProcessing ? Colors.grey : action.color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Area suggerimenti predittivi migliorata
  Widget _buildPredictiveSuggestions() {
    return FutureBuilder<List<String>>(
      future: _aiService.getPredictiveSuggestions(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        return Container(
          height: 36,
          margin: const EdgeInsets.only(bottom: 12),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: snapshot.data!.length,
            itemBuilder: (context, index) {
              final suggestion = snapshot.data![index];
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ActionChip(
                  label: Text(suggestion),
                  onPressed: _isProcessing ? null : () {
                    _textController.text = suggestion;
                    _processCommand(suggestion, InputType.text);
                  },
                  backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                  side: BorderSide.none,
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// Storia comandi recenti
  Widget _buildCommandHistory() {
    if (_commandHistory.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 32,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _commandHistory.length,
        itemBuilder: (context, index) {
          final command = _commandHistory[index];
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ActionChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.history, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    command.length > 20
                        ? '${command.substring(0, 20)}...'
                        : command,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
              onPressed: _isProcessing ? null : () {
                _textController.text = command;
                _processCommand(command, InputType.text);
              },
              backgroundColor: Colors.grey.shade100,
              side: BorderSide(color: Colors.grey.shade300),
              labelPadding: const EdgeInsets.symmetric(horizontal: 4),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Column(
        children: [
          // Quick actions
          _buildQuickActionButtons(),

          // Suggerimenti predittivi
          _buildPredictiveSuggestions(),

          // Storia comandi
          _buildCommandHistory(),

          // Input area principale
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
              border: Border.all(
                color: _isListening
                    ? Colors.red.withOpacity(0.3)
                    : Colors.grey.withOpacity(0.2),
                width: _isListening ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                // Icona stato
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Icon(
                      _isProcessing
                          ? Icons.hourglass_empty
                          : _isListening
                          ? Icons.hearing
                          : Icons.assistant,
                      key: ValueKey(_isListening),
                      color: _isListening
                          ? Colors.red
                          : Theme.of(context).colorScheme.primary,
                      size: 24,
                    ),
                  ),
                ),

                // Text input
                Expanded(
                  child: TextField(
                    controller: _textController,
                    enabled: !_isProcessing,
                    style: const TextStyle(fontSize: 16),
                    decoration: InputDecoration(
                      hintText: _isListening
                          ? 'Sto ascoltando... (${(_confidence * 100).toInt()}%)'
                          : _isProcessing
                          ? 'Elaborazione in corso...'
                          : 'Chiedi qualcosa alla tua assistente...',
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                    onSubmitted: _isProcessing ? null : (text) {
                      _processCommand(text, InputType.text);
                    },
                    onChanged: (text) {
                      setState(() {}); // Per aggiornare il bottone send
                    },
                  ),
                ),

                // Visualizzatore confidenza vocale
                if (_isListening && _confidence > 0)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    width: 32,
                    height: 32,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: _confidence,
                          strokeWidth: 3,
                          backgroundColor: Colors.grey[300],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _confidence > 0.8
                                ? Colors.green
                                : _confidence > 0.5
                                ? Colors.orange
                                : Colors.red,
                          ),
                        ),
                        Text(
                          '${(_confidence * 100).toInt()}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Bottone invio testo
                if (!_isListening && _textController.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: IconButton(
                      icon: Icon(
                        Icons.send,
                        color: _isProcessing
                            ? Colors.grey
                            : Theme.of(context).colorScheme.primary,
                      ),
                      onPressed: _isProcessing ? null : () {
                        _processCommand(_textController.text, InputType.text);
                      },
                    ),
                  ),

                // Bottone microfono animato
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _isListening ? _pulseAnimation.value : 1.0,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isListening
                                ? Colors.red.withOpacity(0.2)
                                : Colors.transparent,
                          ),
                          child: IconButton(
                            icon: Icon(
                              _isListening ? Icons.mic : Icons.mic_none,
                              color: _isListening
                                  ? Colors.red
                                  : _speechEnabled || kIsWeb
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.grey,
                              size: 28,
                            ),
                            onPressed: (_speechEnabled || kIsWeb) && !_isProcessing
                                ? (_isListening ? _stopListening : _startListening)
                                : () => _showError('Microfono non disponibile'),
                            tooltip: _isListening
                                ? 'Ferma ascolto'
                                : 'Inizia dettatura vocale',
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // Testo trascritto in tempo reale con animazione
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            child: _isListening && _transcribedText.isNotEmpty
                ? Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.hearing,
                    size: 20,
                    color: Colors.amber.shade700,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _transcribedText,
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: Colors.amber.shade900,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (_confidence > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${(_confidence * 100).toInt()}%',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade900,
                        ),
                      ),
                    ),
                ],
              ),
            )
                : const SizedBox.shrink(),
          ),

          // Debug info (solo in debug mode)
          if (kDebugMode && (_lastProcessedCommand != null || _lastCommandType != null))
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'DEBUG INFO:',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  if (_lastProcessedCommand != null)
                    Text(
                      'Ultimo comando: "$_lastProcessedCommand"',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  if (_lastCommandType != null)
                    Text(
                      'Tipo rilevato: ${_lastCommandType.toString().split('.').last}',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                ],
              ),
            ),

          // Info stato microfono migliorato
          if (!_speechEnabled && !kIsWeb && !_isProcessing)
            Container(
              margin: const EdgeInsets.only(top: 12),
              child: Material(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: _initSpeech,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.mic_off,
                          size: 20,
                          color: Colors.orange.shade700,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Microfono non disponibile',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.refresh,
                          size: 16,
                          color: Colors.orange.shade700,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Classe per definire un'azione rapida
class QuickAction {
  final IconData icon;
  final String label;
  final String command;
  final Color color;

  const QuickAction({
    required this.icon,
    required this.label,
    required this.command,
    required this.color,
  });
}