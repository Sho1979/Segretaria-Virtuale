// lib/widgets/floating_summary_widget.dart

import 'package:flutter/material.dart';
import 'dart:async';

class FloatingSummaryWidget extends StatefulWidget {
  final Map<String, dynamic> stats;
  final VoidCallback? onTap;

  const FloatingSummaryWidget({
    Key? key,
    required this.stats,
    this.onTap,
  }) : super(key: key);

  @override
  State<FloatingSummaryWidget> createState() => _FloatingSummaryWidgetState();
}

class _FloatingSummaryWidgetState extends State<FloatingSummaryWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    // Mostra il widget dopo un breve delay
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _animationController.forward();
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 20,
      right: 20,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: _isExpanded ? 300 : 120,
          height: _isExpanded ? 200 : 120,
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_isExpanded ? 16 : 60),
            ),
            child: InkWell(
              onTap: () {
                setState(() {
                  _isExpanded = !_isExpanded;
                });
                widget.onTap?.call();
              },
              borderRadius: BorderRadius.circular(_isExpanded ? 16 : 60),
              child: Padding(
                padding: EdgeInsets.all(_isExpanded ? 16 : 8),
                child: _isExpanded ? _buildExpandedView() : _buildCollapsedView(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsedView() {
    final todayEvents = widget.stats['todayEvents'] ?? 0;
    final nextEvent = widget.stats['nextEvent'];
    final hasNextEvent = nextEvent != null;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Theme.of(context).primaryColor,
                Theme.of(context).primaryColor.withOpacity(0.7),
              ],
            ),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '$todayEvents',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Eventi oggi',
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        if (hasNextEvent) ...[
          const SizedBox(height: 4),
          Text(
            _formatTimeUntilNext(nextEvent['time']),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).primaryColor,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _buildExpandedView() {
    final todayEvents = widget.stats['todayEvents'] ?? 0;
    final weekEvents = widget.stats['weekEvents'] ?? 0;
    final nextEvent = widget.stats['nextEvent'];
    final completedToday = widget.stats['completedToday'] ?? 0;
    final totalHoursToday = widget.stats['totalHoursToday'] ?? 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Riepilogo',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () {
                setState(() {
                  _isExpanded = false;
                });
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        const Divider(),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatRow(
                  icon: Icons.today,
                  label: 'Eventi oggi',
                  value: '$todayEvents',
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(height: 8),
                _buildStatRow(
                  icon: Icons.date_range,
                  label: 'Eventi settimana',
                  value: '$weekEvents',
                  color: Colors.blue,
                ),
                const SizedBox(height: 8),
                _buildStatRow(
                  icon: Icons.check_circle,
                  label: 'Completati oggi',
                  value: '$completedToday',
                  color: Colors.green,
                ),
                const SizedBox(height: 8),
                _buildStatRow(
                  icon: Icons.access_time,
                  label: 'Ore in meeting',
                  value: '${totalHoursToday.toStringAsFixed(1)}h',
                  color: Colors.orange,
                ),
                if (nextEvent != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Prossimo evento',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          nextEvent['title'] ?? 'Evento',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _formatTimeUntilNext(nextEvent['time']),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  String _formatTimeUntilNext(DateTime? eventTime) {
    if (eventTime == null) return '';

    final now = DateTime.now();
    final difference = eventTime.difference(now);

    if (difference.isNegative) {
      return 'In corso';
    }

    if (difference.inMinutes < 60) {
      return 'tra ${difference.inMinutes} min';
    } else if (difference.inHours < 24) {
      return 'tra ${difference.inHours}h';
    } else {
      return 'tra ${difference.inDays}g';
    }
  }
}