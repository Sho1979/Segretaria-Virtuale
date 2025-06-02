// lib/widgets/free_slots_analyzer_widget.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/calendar/free_slots_analyzer.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;

class FreeSlotAnalyzerWidget extends StatefulWidget {
  const FreeSlotAnalyzerWidget({Key? key}) : super(key: key);

  @override
  State<FreeSlotAnalyzerWidget> createState() => _FreeSlotAnalyzerWidgetState();
}

class _FreeSlotAnalyzerWidgetState extends State<FreeSlotAnalyzerWidget> {
  final FreeSlotAnalyzerService _analyzer = FreeSlotAnalyzerService();
  List<OptimalSlot>? _optimalSlots;
  bool _isLoading = false;
  DateTime _selectedDate = DateTime.now();
  int _daysToAnalyze = 7;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        const SizedBox(height: 16),
        _buildControls(),
        const SizedBox(height: 16),
        Expanded(
          child: _buildSlotsList(),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Analizzatore Slot Liberi',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Trova i momenti migliori per le tue attività',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Periodo di analisi',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  DropdownButton<int>(
                    value: _daysToAnalyze,
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem(value: 1, child: Text('Oggi')),
                      const DropdownMenuItem(value: 3, child: Text('Prossimi 3 giorni')),
                      const DropdownMenuItem(value: 7, child: Text('Prossima settimana')),
                      const DropdownMenuItem(value: 14, child: Text('Prossime 2 settimane')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _daysToAnalyze = value;
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _analyzeSlots,
              icon: _isLoading
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : const Icon(Icons.search),
              label: Text(_isLoading ? 'Analizzando...' : 'Analizza'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlotsList() {
    if (_optimalSlots == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.schedule,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'Clicca "Analizza" per trovare i tuoi slot liberi ottimali',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    if (_optimalSlots!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.event_busy,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'Nessuno slot libero trovato nel periodo selezionato',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    // Raggruppa slot per giorno
    final slotsByDay = <DateTime, List<OptimalSlot>>{};
    for (final slot in _optimalSlots!) {
      final day = DateTime(slot.start.year, slot.start.month, slot.start.day);
      slotsByDay.putIfAbsent(day, () => []).add(slot);
    }

    return ListView.builder(
      itemCount: slotsByDay.length,
      itemBuilder: (context, index) {
        final day = slotsByDay.keys.elementAt(index);
        final slots = slotsByDay[day]!;

        return _buildDaySection(day, slots);
      },
    );
  }

  Widget _buildDaySection(DateTime day, List<OptimalSlot> slots) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            DateFormat('EEEE d MMMM', 'it').format(day),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ...slots.map((slot) => _buildSlotCard(slot)),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildSlotCard(OptimalSlot slot) {
    final duration = slot.end.difference(slot.start);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;

    Color energyColor;
    IconData energyIcon;
    String energyText;

    switch (slot.energyLevel) {
      case EnergyLevel.high:
        energyColor = Colors.green;
        energyIcon = Icons.battery_full;
        energyText = 'Alta energia';
        break;
      case EnergyLevel.medium:
        energyColor = Colors.orange;
        energyIcon = Icons.battery_std;
        energyText = 'Media energia';
        break;
      case EnergyLevel.low:
        energyColor = Colors.red;
        energyIcon = Icons.battery_alert; // CORRETTO
        energyText = 'Bassa energia';
        break;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: energyColor.withOpacity(0.2),
          child: Icon(energyIcon, color: energyColor),
        ),
        title: Text(
          '${DateFormat('HH:mm').format(slot.start)} - ${DateFormat('HH:mm').format(slot.end)}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          'Durata: ${hours}h ${minutes}min • $energyText${slot.reason.isNotEmpty ? ' • ${slot.reason}' : ''}',
        ),
        trailing: IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () => _createEvent(slot),
          tooltip: 'Prenota questo slot',
        ),
      ),
    );
  }

  Future<void> _analyzeSlots() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final endDate = _selectedDate.add(Duration(days: _daysToAnalyze));

      // Simula il recupero degli eventi esistenti
      // In produzione, questi verrebbero dai servizi calendario
      final existingEvents = <gcal.Event>[];

      final slots = await _analyzer.findOptimalSlots(
        startDate: _selectedDate,
        endDate: endDate,
        currentEvents: existingEvents,
      );

      setState(() {
        _optimalSlots = slots;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore nell\'analisi: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _createEvent(OptimalSlot slot) {
    // Implementa la creazione dell'evento
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Creazione evento per ${DateFormat('dd/MM HH:mm').format(slot.start)}',
        ),
      ),
    );
  }
}