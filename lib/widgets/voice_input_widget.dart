// lib/widgets/voice_input_widget.dart

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../services/ai/command_service.dart';

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
    with SingleTickerProviderStateMixin {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final AICommandService _aiService = AICommandService();
  final TextEditingController _textController = TextEditingController();

  bool _isListening = false;
  bool _speechEnabled = false;
  String _transcribedText = '';
  double _confidence = 0.0;

  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initSpeech();

    // Animazione per il bottone microfono
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _speech.stop();
    _animationController.dispose();
    _textController.dispose();
    super.dispose();
  }

  /// Inizializza speech recognition
  void _initSpeech() async {
    try {
      _speechEnabled = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) return; // Controllo mounted
          print('Speech status: $status');
          setState(() {
            _isListening = status == 'listening';
          });
        },
        onError: (error) {
          if (!mounted) return; // Controllo mounted
          print('Errore speech dettagliato: ${error.errorMsg} - ${error.permanent}');
          setState(() {
            _isListening = false;
          });
        },
        debugLogging: true,
      );
      print('Speech enabled: $_speechEnabled');

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('Errore inizializzazione speech: $e');
      if (mounted) {
        setState(() {
          _speechEnabled = false;
        });
      }
    }
  }

  /// Avvia ascolto vocale
  void _startListening() async {
    if (!_speechEnabled) {
      if (kIsWeb) {
        _showError('Per usare il microfono, consenti l\'accesso quando richiesto dal browser');
      } else {
        _showError('Microfono non disponibile');
      }
      return;
    }

    try {
      await _speech.listen(
        onResult: (result) {
          if (!mounted) return; // Controllo mounted
          setState(() {
            _transcribedText = result.recognizedWords;
            _confidence = result.confidence;
          });

          if (result.finalResult) {
            _processCommand(_transcribedText, InputType.voice);
          }
        },
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 2),
        localeId: 'it_IT',
        onSoundLevelChange: (level) {
          // Opzionale: mostra livello audio
        },
      );

      _animationController.repeat(reverse: true);
      if (mounted) {
        setState(() {
          _isListening = true;
        });
      }
    } catch (e) {
      print('Errore avvio ascolto: $e');
      _showError('Errore nell\'avviare il microfono');
    }
  }

  /// Ferma ascolto
  void _stopListening() async {
    await _speech.stop();
    _animationController.stop();
    _animationController.reset();
    if (mounted) {
      setState(() {
        _isListening = false;
      });
    }
  }

  /// Processa comando (vocale o testo)
  void _processCommand(String input, InputType type) async {
    if (input.trim().isEmpty) return;

    _showProcessing();

    try {
      // Preprocessa l'input per gestire riferimenti temporali
      String processedInput = input;
      DateTime? targetDate;

      final lowerInput = input.toLowerCase();

      if (lowerInput.contains('domani')) {
        targetDate = DateTime.now().add(const Duration(days: 1));
        // Aggiungi la data al comando per il parser
        processedInput = '$input [date:${targetDate.toIso8601String()}]';
      } else if (lowerInput.contains('dopodomani')) {
        targetDate = DateTime.now().add(const Duration(days: 2));
        processedInput = '$input [date:${targetDate.toIso8601String()}]';
      } else if (lowerInput.contains('oggi')) {
        targetDate = DateTime.now();
        processedInput = '$input [date:${targetDate.toIso8601String()}]';
      }

      final command = await _aiService.parseCommand(processedInput, type);

      // Se il comando originale conteneva riferimenti temporali, assicurati che siano nel comando
      if (targetDate != null && command.parameters['date'] == null) {
        command.parameters['date'] = targetDate;
      }

      widget.onCommandReceived(command);
      _showCommandProcessed(command);

      if (mounted) {
        setState(() {
          _transcribedText = '';
          _textController.clear();
        });
      }
    } catch (e) {
      print('Errore processamento comando: $e');
      _showError('Errore nel processare il comando');
    }
  }

  /// Mostra stato processing
  void _showProcessing() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Elaborazione comando...'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  /// Mostra comando processato
  void _showCommandProcessed(ParsedCommand command) {
    if (!mounted) return;
    String message = 'Comando: ${command.type.toString().split('.').last}';
    if (command.confidence < 0.5) {
      message += ' (confidenza bassa)';
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: command.type == CommandType.unknown
            ? Colors.orange
            : Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Mostra errore
  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  /// Widget per i pulsanti delle azioni rapide
  Widget _buildQuickActionButtons() {
    return Container(
      height: 40,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildActionChip(
            icon: Icons.event_available,
            label: 'Slot liberi',
            onPressed: () => _processCommand('mostra slot liberi oggi', InputType.text),
          ),
          const SizedBox(width: 8),
          _buildActionChip(
            icon: Icons.today,
            label: 'Riepilogo oggi',
            onPressed: () => _processCommand('cosa ho oggi', InputType.text),
          ),
          const SizedBox(width: 8),
          _buildActionChip(
            icon: Icons.add_alarm,
            label: 'Nuovo promemoria',
            onPressed: () => _processCommand('crea promemoria', InputType.text),
          ),
          const SizedBox(width: 8),
          _buildActionChip(
            icon: Icons.event,
            label: 'Nuovo evento',
            onPressed: () => _processCommand('crea nuovo evento', InputType.text),
          ),
          const SizedBox(width: 8),
          _buildActionChip(
            icon: Icons.analytics,
            label: 'Analisi carico',
            onPressed: () => _processCommand('analizza carico lavoro oggi', InputType.text),
          ),
          const SizedBox(width: 8),
          _buildActionChip(
            icon: Icons.block,
            label: 'Blocca tempo',
            onPressed: () => _processCommand('blocca tempo per focus', InputType.text),
          ),
          const SizedBox(width: 8),
          _buildActionChip(
            icon: Icons.person_add,
            label: 'Delega task',
            onPressed: () => _processCommand('delega task', InputType.text),
          ),
          const SizedBox(width: 8),
          _buildActionChip(
            icon: Icons.free_breakfast,
            label: 'Pausa',
            onPressed: () => _processCommand('ricordami di fare una pausa', InputType.text),
          ),
        ],
      ),
    );
  }

  /// Widget per un singolo action chip
  Widget _buildActionChip({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onPressed,
      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
      labelStyle: TextStyle(
        color: Theme.of(context).colorScheme.onSecondaryContainer,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Pulsanti azioni rapide - NUOVA SEZIONE
        _buildQuickActionButtons(),

        // Area suggerimenti predittivi
        FutureBuilder<List<String>>(
          future: _aiService.getPredictiveSuggestions(),
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const SizedBox.shrink();
            }

            return Container(
              height: 40,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: snapshot.data!.length,
                itemBuilder: (context, index) {
                  final suggestion = snapshot.data![index];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      label: Text(suggestion),
                      onPressed: () {
                        _textController.text = suggestion;
                        _processCommand(suggestion, InputType.text);
                      },
                      backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
                      labelStyle: TextStyle(
                        color: Theme.of(context).colorScheme.onTertiaryContainer,
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),

        // Input area
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Text input
              Expanded(
                child: TextField(
                  controller: _textController,
                  decoration: InputDecoration(
                    hintText: _isListening
                        ? 'Sto ascoltando...'
                        : 'Chiedi qualcosa alla tua SVP...',
                    border: InputBorder.none,
                  ),
                  onSubmitted: (text) {
                    _processCommand(text, InputType.text);
                  },
                ),
              ),

              // Visualizzatore confidenza vocale
              if (_isListening && _confidence > 0)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    value: _confidence,
                    strokeWidth: 2,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _confidence > 0.8 ? Colors.green : Colors.orange,
                    ),
                  ),
                ),

              // Bottone invio testo
              if (!_isListening && _textController.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () {
                    _processCommand(_textController.text, InputType.text);
                  },
                ),

              // Bottone microfono
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _isListening ? _pulseAnimation.value : 1.0,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isListening
                            ? Colors.red.withOpacity(0.1)
                            : Colors.transparent,
                      ),
                      child: IconButton(
                        icon: Icon(
                          _isListening ? Icons.mic : Icons.mic_none,
                          color: _isListening ? Colors.red : null,
                        ),
                        onPressed: _speechEnabled || kIsWeb
                            ? (_isListening ? _stopListening : _startListening)
                            : () => _showError('Microfono non disponibile'),
                        tooltip: _isListening ? 'Ferma ascolto' : 'Inizia dettatura',
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),

        // Testo trascritto in tempo reale
        if (_isListening && _transcribedText.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.hearing,
                  size: 16,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _transcribedText,
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: Colors.grey[700],
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Info stato microfono (solo per debug)
        if (!_speechEnabled && !kIsWeb)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.orange[800]),
                const SizedBox(width: 8),
                Text(
                  'Microfono non disponibile',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange[800],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}