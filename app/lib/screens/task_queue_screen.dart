import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../repository/bunny_models.dart';
import '../repository/http_bunny_repository.dart';

/// Shows `GET /tasks` (M24) -- every pending + currently-running task_queue
/// job, in the order they'll actually run. Server-only, same as
/// [ServerLogsScreen] (standalone mode's [FfiBunnyRepository.getTasks]
/// always returns an empty list, since it has no background queue of its
/// own). Unlike [ServerLogsScreen]'s explicit-refresh-only pattern, this
/// polls while open -- jobs here are expected to start/finish on their own
/// while the screen is up, same cadence as [SearchesScreen]'s sync-status
/// poll.
class TaskQueueScreen extends StatefulWidget {
  final HttpBunnyRepository repository;

  const TaskQueueScreen({super.key, required this.repository});

  @override
  State<TaskQueueScreen> createState() => _TaskQueueScreenState();
}

class _TaskQueueScreenState extends State<TaskQueueScreen> {
  Future<List<BunnyTask>>? _tasksFuture;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => setState(_load));
  }

  void _load() {
    _tasksFuture = widget.repository.getTasks();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  String _priorityLabel(AppLocalizations l10n, BunnyTaskPriority priority) => switch (priority) {
    BunnyTaskPriority.high => l10n.taskQueuePriorityHigh,
    BunnyTaskPriority.medium => l10n.taskQueuePriorityMedium,
    BunnyTaskPriority.low => l10n.taskQueuePriorityLow,
  };

  Color _priorityColor(BuildContext context, BunnyTaskPriority priority) => switch (priority) {
    BunnyTaskPriority.high => Theme.of(context).colorScheme.error,
    BunnyTaskPriority.medium => Theme.of(context).colorScheme.tertiary,
    BunnyTaskPriority.low => Theme.of(context).colorScheme.outline,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.taskQueueScreenTitle)),
      body: FutureBuilder<List<BunnyTask>>(
        future: _tasksFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final tasks = snapshot.data!;
          if (tasks.isEmpty) {
            return Center(child: Text(l10n.taskQueueEmptyState));
          }
          return ListView.builder(
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              final task = tasks[index];
              return ListTile(
                leading: task.status == BunnyTaskStatus.running
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(Icons.schedule, color: Theme.of(context).colorScheme.outline),
                title: Text(task.label),
                subtitle: Text(task.status == BunnyTaskStatus.running ? l10n.taskQueueStatusRunning : l10n.taskQueueStatusPending),
                trailing: Chip(
                  label: Text(_priorityLabel(l10n, task.priority)),
                  labelStyle: TextStyle(color: _priorityColor(context, task.priority)),
                  side: BorderSide(color: _priorityColor(context, task.priority)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
