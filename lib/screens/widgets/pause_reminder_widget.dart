// lib/widgets/pause_reminder_widget.dart

import 'package:flutter/material.dart';
import 'dart:async';

class PauseReminderWidget extends StatefulWidget {
  final int minutesWorked;
  final VoidCallback? onPauseTaken;
  final VoidCallback? onDismiss;

  const PauseReminderWidget({
    Key? key,
    required this.minutesWorked,
    this.onPauseTaken,
    this.onDismiss,
  }) : super(key: key);

  @override
  State<PauseReminderWidget> createState() => _PauseReminderWidgetState();
}

class _PauseReminderWidgetState extends State<PauseReminderWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;
  Timer? _autoHideTimer;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<double>(
      begin: -1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));

    _animationController.forward();

    // Auto-nascondi dopo 10 secondi
    _autoHideTimer = Timer(const Duration(seconds: 10), () {
      _dismiss();
    });
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  void _dismiss() {
    _animationController.reverse().then((_) {
      widget.onDismiss?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _slideAnimation,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, _slideAnimation.value * 100),
        child: Container(
          margin: const EdgeInsets.all(16),
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            color: Colors.orange.shade50,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.orange.shade200,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.coffee,
                      color: Colors.orange.shade700,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'È ora di una pausa!',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade900,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Hai lavorato per ${widget.minutesWorked} minuti. Una pausa ti aiuterà a rimanere produttivo.',
                          style: TextStyle(
                            color: Colors.orange.shade700,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Pulsante Pausa
                  TextButton(
                    onPressed: () {
                      widget.onPauseTaken?.call();
                      _dismiss();
                    },
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    child: const Text('Pausa'),
                  ),
                  const SizedBox(width: 8),
                  // Pulsante Chiudi
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _dismiss,
                    color: Colors.orange.shade600,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}