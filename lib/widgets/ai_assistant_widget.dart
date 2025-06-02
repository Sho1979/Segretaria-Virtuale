// lib/widgets/ai_assistant_widget.dart

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../services/ai/ai_assistant_service.dart';
import '../services/ai/meeting_pattern_analyzer.dart';
import '../providers/auth_provider.dart';
import 'package:intl/intl.dart';
import 'dart:async';

/// Widget per l'assistente AI intelligente
class AIAssistantWidget extends StatefulWidget {
  const AIAssistantWidget({Key? key}) : super(key: key);

  @override
  State<AIAssistantWidget> createState() => _AIAssistantWidgetState();
}

class _AIAssistantWidgetState extends State<AIAssistantWidget>
    with SingleTickerProviderStateMixin {
  late AIAssistantService _aiService;
  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;

  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<ChatMessage> _messages = [];
  bool _isProcessing = false;
  bool _isExpanded = false;

  // Stati per visualizzazioni
  WorkloadMetrics? _workloadMetrics;
  List<OptimizationOpportunity>? _optimizations;
  MeetingInsights? _insights;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _initializeAI();
  }

  Future<void> _initializeAI() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    _aiService = AIAssistantService(
      googleService: authProvider.googleCalendarService!,
      outlookService: authProvider.outlookCalendarService!,
    );

    await _aiService.initialize();

    // Messaggio di benvenuto
    _addMessage(ChatMessage(
      text: 'Ciao! Sono il tuo assistente AI per il calendario. '
          'Posso aiutarti a trovare il momento migliore per i meeting, '
          'analizzare il tuo carico di lavoro e ottimizzare il tuo tempo. '
          'Come posso aiutarti oggi?',
      isUser: false,
      timestamp: DateTime.now(),
      suggestions: [
        'Trova il miglior momento per un meeting di 1 ora',
        'Analizza il mio carico di lavoro questa settimana',
        'Mostrami ottimizzazioni per il mio calendario',
      ],
    ));
  }

  void _addMessage(ChatMessage message) {
    setState(() {
      _messages.add(message);
    });

    // Scrolla alla fine
    Timer(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage(String text) async {
    if (text.isEmpty || _isProcessing) return;

    // Aggiungi messaggio utente
    _addMessage(ChatMessage(
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
    ));

    _textController.clear();

    setState(() {
      _isProcessing = true;
    });

    try {
      // Processa con AI
      final response = await _aiService.processCommand(text);

      // Aggiungi risposta AI
      _addMessage(ChatMessage(
        text: response.message,
        isUser: false,
        timestamp: DateTime.now(),
        suggestions: response.suggestions,
        actions: response.actions,
        data: response.data,
      ));

      // Gestisci visualizzazioni se presenti
      if (response.data != null) {
        _handleResponseData(response.data!);
      }

    } catch (e) {
      _addMessage(ChatMessage(
        text: 'Mi dispiace, ho avuto un problema nel processare la richiesta. '
            'Puoi riprovare?',
        isUser: false,
        timestamp: DateTime.now(),
        isError: true,
      ));

      if (kDebugMode) {
        print('Errore AI: $e');
      }
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  void _handleResponseData(Map<String, dynamic> data) {
    setState(() {
      if (data.containsKey('metrics')) {
        _workloadMetrics = data['metrics'] as WorkloadMetrics;
      }
      if (data.containsKey('optimizations')) {
        _optimizations = data['optimizations'] as List<OptimizationOpportunity>;
      }
      if (data.containsKey('insights')) {
        _insights = data['insights'] as MeetingInsights;
      }
    });
  }

  Future<void> _handleAction(AIAction action) async {
    switch (action.type) {
      case ActionType.createEvent:
      // Implementa creazione evento
        if (action.parameters != null) {
          // Qui potresti aprire un dialog per confermare i dettagli
          _showCreateEventDialog(action.parameters!);
        }
        break;

      case ActionType.showAlternatives:
      // Mostra alternative
        _sendMessage('Mostrami le alternative');
        break;

      case ActionType.optimize:
      // Esegui ottimizzazione
        _showOptimizationDialog(action);
        break;
    }
  }

  void _showCreateEventDialog(Map<String, dynamic> params) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Conferma Creazione Meeting'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Inizio: ${DateFormat('dd/MM HH:mm').format(params['start'])}'),
            Text('Fine: ${DateFormat('dd/MM HH:mm').format(params['end'])}'),
            if (params['summary'] != null)
              Text('Titolo: ${params['summary']}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Implementa creazione evento
              _sendMessage('Conferma la creazione del meeting');
            },
            child: const Text('Conferma'),
          ),
        ],
      ),
    );
  }

  void _showOptimizationDialog(AIAction action) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Applica Ottimizzazione'),
        content: Text(action.label),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _sendMessage('Applica l\'ottimizzazione: ${action.label}');
            },
            child: const Text('Applica'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: _isExpanded ? MediaQuery.of(context).size.height * 0.8 : 400,
      child: Card(
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      children: [
                        Expanded(child: _buildChatArea()),
                        _buildInputArea(),
                      ],
                    ),
                  ),
                  if (_isExpanded && (_workloadMetrics != null ||
                      _optimizations != null ||
                      _insights != null))
                    Expanded(
                      flex: 2,
                      child: _buildVisualizationPanel(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withOpacity(0.1),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) => Transform.scale(
              scale: _isProcessing ? _pulseAnimation.value : 1.0,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).primaryColor,
                      Theme.of(context).primaryColor.withOpacity(0.6),
                    ],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).primaryColor.withOpacity(0.3),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Assistente AI',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _isProcessing ? 'Sto pensando...' : 'Pronto ad aiutarti',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(_isExpanded ? Icons.compress : Icons.expand),
            onPressed: () => setState(() => _isExpanded = !_isExpanded),
            tooltip: _isExpanded ? 'Comprimi' : 'Espandi',
          ),
        ],
      ),
    );
  }

  Widget _buildChatArea() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: ListView.builder(
        controller: _scrollController,
        itemCount: _messages.length,
        itemBuilder: (context, index) {
          final message = _messages[index];
          return _buildMessage(message);
        },
      ),
    );
  }

  Widget _buildMessage(ChatMessage message) {
    final isUser = message.isUser;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              backgroundColor: Theme.of(context).primaryColor.withOpacity(0.2),
              child: Icon(
                Icons.auto_awesome,
                size: 20,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isUser
                        ? Theme.of(context).primaryColor
                        : Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: !isUser ? Border.all(
                      color: Theme.of(context).dividerColor,
                    ) : null,
                  ),
                  child: Text(
                    message.text,
                    style: TextStyle(
                      color: isUser ? Colors.white : null,
                    ),
                  ),
                ),
                if (message.suggestions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildSuggestions(message.suggestions),
                ],
                if (message.actions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildActions(message.actions),
                ],
              ],
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: Theme.of(context).primaryColor.withOpacity(0.2),
              child: Icon(
                Icons.person,
                size: 20,
                color: Theme.of(context).primaryColor,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSuggestions(List<String> suggestions) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: suggestions.map((suggestion) =>
          InkWell(
            onTap: () => _sendMessage(suggestion),
            child: Chip(
              label: Text(
                suggestion,
                style: const TextStyle(fontSize: 12),
              ),
              backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
            ),
          ),
      ).toList(),
    );
  }

  Widget _buildActions(List<AIAction> actions) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: actions.map((action) =>
          ElevatedButton.icon(
            onPressed: () => _handleAction(action),
            icon: Icon(
              action.type == ActionType.createEvent ? Icons.add_circle :
              action.type == ActionType.showAlternatives ? Icons.list :
              Icons.auto_fix_high,
              size: 16,
            ),
            label: Text(
              action.label,
              style: const TextStyle(fontSize: 12),
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
      ).toList(),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              decoration: InputDecoration(
                hintText: 'Chiedi qualsiasi cosa sul tuo calendario...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Theme.of(context).primaryColor.withOpacity(0.05),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              onSubmitted: _sendMessage,
            ),
          ),
          const SizedBox(width: 8),
          FloatingActionButton(
            mini: true,
            onPressed: _isProcessing ? null : () => _sendMessage(_textController.text),
            backgroundColor: _isProcessing ? Colors.grey : null,
            child: _isProcessing
                ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
                : const Icon(Icons.send),
          ),
        ],
      ),
    );
  }

  Widget _buildVisualizationPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: Theme.of(context).dividerColor,
          ),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_workloadMetrics != null) ...[
              _buildWorkloadVisualization(),
              const SizedBox(height: 24),
            ],
            if (_insights != null) ...[
              _buildInsightsPanel(),
              const SizedBox(height: 24),
            ],
            if (_optimizations != null) ...[
              _buildOptimizationsPanel(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWorkloadVisualization() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Carico di Lavoro',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        // Visualizzazione semplificata senza fl_chart
        Container(
          height: 200,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: _workloadMetrics!.dailyLoad.entries.map((entry) {
                    final height = entry.value * 150;
                    final color = entry.value > 0.8 ? Colors.red :
                    entry.value > 0.6 ? Colors.orange :
                    Colors.green;

                    return Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              '${(entry.value * 100).round()}%',
                              style: const TextStyle(fontSize: 10),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              height: height,
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              DateFormat('E', 'it').format(entry.key),
                              style: const TextStyle(fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildLegendItem('Basso', Colors.green),
            const SizedBox(width: 16),
            _buildLegendItem('Medio', Colors.orange),
            const SizedBox(width: 16),
            _buildLegendItem('Alto', Colors.red),
          ],
        ),
      ],
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildInsightsPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'I Tuoi Pattern',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        _buildInsightCard(
          icon: Icons.access_time,
          title: 'Durata Media Meeting',
          value: '${_insights!.averageMeetingDuration.round()} min',
          color: Colors.blue,
        ),
        const SizedBox(height: 8),
        _buildInsightCard(
          icon: Icons.calendar_today,
          title: 'Giorno più Impegnato',
          value: _insights!.busiestDay,
          color: Colors.orange,
        ),
        const SizedBox(height: 8),
        _buildInsightCard(
          icon: Icons.repeat,
          title: 'Meeting Ricorrenti',
          value: '${_insights!.recurringMeetingsCount}',
          color: Colors.green,
        ),
        if (_insights!.topDiscussionTopics.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Topic Frequenti',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _insights!.topDiscussionTopics.map((topic) =>
                Chip(
                  label: Text(topic, style: const TextStyle(fontSize: 12)),
                  backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                ),
            ).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildInsightCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptimizationsPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ottimizzazioni Suggerite',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        ..._optimizations!.map((opt) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildOptimizationCard(opt),
        )),
      ],
    );
  }

  Widget _buildOptimizationCard(OptimizationOpportunity opt) {
    final color = opt.impact > 0.7 ? Colors.red :
    opt.impact > 0.5 ? Colors.orange :
    Colors.blue;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: color.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                opt.type == OptimizationType.backToBack ? Icons.timer_off :
                opt.type == OptimizationType.meetingToEmail ? Icons.email :
                opt.type == OptimizationType.balanceLoad ? Icons.balance :
                Icons.refresh,
                color: color,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  opt.description,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Impatto: ',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Expanded(
                child: LinearProgressIndicator(
                  value: opt.impact,
                  backgroundColor: Colors.grey.withOpacity(0.2),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(opt.impact * 100).round()}%',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

/// Messaggio della chat
class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final List<String> suggestions;
  final List<AIAction> actions;
  final Map<String, dynamic>? data;
  final bool isError;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.suggestions = const [],
    this.actions = const [],
    this.data,
    this.isError = false,
  });
}