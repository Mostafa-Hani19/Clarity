import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../models/reminder.dart';
import '../../../../providers/reminder_provider.dart';

class HelperReminderScreen extends StatefulWidget {
  const HelperReminderScreen({super.key});

  @override
  State<HelperReminderScreen> createState() => _HelperReminderScreenState();
}

class _HelperReminderScreenState extends State<HelperReminderScreen> {
  String? _blindUserName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
    });
  }

  Future<void> _loadInitialData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final reminderProvider = Provider.of<ReminderProvider>(context, listen: false);

    try {
      final blindUserId = authProvider.linkedUserId;
      if (blindUserId == null) {
        throw Exception('No blind user connected');
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(blindUserId)
          .get();
      setState(() {
        _blindUserName = userDoc.data()?['displayName'] ?? 'Blind User';
      });

      await reminderProvider.initialize();
      await reminderProvider.loadReminders();
    } catch (e) {
      debugPrint('Error loading initial data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    }
  }

  Future<void> _loadReminders() async {
    final reminderProvider = Provider.of<ReminderProvider>(context, listen: false);
    await reminderProvider.loadReminders();
  }

  Future<void> _addReminder() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final reminderProvider = Provider.of<ReminderProvider>(context, listen: false);
    final blindUserId = authProvider.linkedUserId;

    if (blindUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No blind user connected')),
      );
      return;
    }

    final titleController = TextEditingController();
    DateTime? selectedDate = DateTime.now();
    TimeOfDay? selectedTime = TimeOfDay.now();
    RecurrenceType selectedRecurrence = RecurrenceType.none;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Reminder'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'Reminder Title',
                  hintText: 'Enter reminder title',
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                title: const Text('Date'),
                subtitle: Text(selectedDate == null
                    ? 'Select Date'
                    : DateFormat.yMMMd().format(selectedDate!)),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: selectedDate ?? DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date != null) {
                    setState(() => selectedDate = date);
                  }
                },
              ),
              ListTile(
                title: const Text('Time'),
                subtitle: Text(selectedTime == null
                    ? 'Select Time'
                    : selectedTime!.format(context)),
                trailing: const Icon(Icons.access_time),
                onTap: () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: selectedTime ?? TimeOfDay.now(),
                  );
                  if (time != null) {
                    setState(() => selectedTime = time);
                  }
                },
              ),
              DropdownButtonFormField<RecurrenceType>(
                value: selectedRecurrence,
                decoration: const InputDecoration(labelText: 'Repeat'),
                items: const [
                  DropdownMenuItem(value: RecurrenceType.none, child: Text('Never')),
                  DropdownMenuItem(value: RecurrenceType.daily, child: Text('Daily')),
                  DropdownMenuItem(value: RecurrenceType.weekly, child: Text('Weekly')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      selectedRecurrence = value;
                    });
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (titleController.text.isEmpty ||
                  selectedDate == null ||
                  selectedTime == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please fill all fields')),
                );
                return;
              }

              // Create the date time with selected date and time
              final dateTime = DateTime(
                selectedDate!.year,
                selectedDate!.month,
                selectedDate!.day,
                selectedTime!.hour,
                selectedTime!.minute,
              );

              // ignore: unused_local_variable
              final reminder = await reminderProvider.addReminder(
                title: titleController.text,
                dateTime: dateTime,
                userId: blindUserId,
                recurrenceType: selectedRecurrence,
              );

              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Reminder added successfully')),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _editReminder(Reminder reminder) async {
    final reminderProvider = Provider.of<ReminderProvider>(context, listen: false);

    final titleController = TextEditingController(text: reminder.title);
    DateTime? selectedDate = reminder.dateTime;
    TimeOfDay? selectedTime = TimeOfDay.fromDateTime(reminder.dateTime);
    RecurrenceType selectedRecurrence = reminder.recurrenceType;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Reminder'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'Reminder Title',
                  hintText: 'Enter reminder title',
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                title: const Text('Date'),
                subtitle: Text(selectedDate == null
                    ? 'Select Date'
                    : DateFormat.yMMMd().format(selectedDate!)),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: selectedDate ?? DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date != null) {
                    setState(() => selectedDate = date);
                  }
                },
              ),
              ListTile(
                title: const Text('Time'),
                subtitle: Text(selectedTime == null
                    ? 'Select Time'
                    : selectedTime!.format(context)),
                trailing: const Icon(Icons.access_time),
                onTap: () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: selectedTime ?? TimeOfDay.now(),
                  );
                  if (time != null) {
                    setState(() => selectedTime = time);
                  }
                },
              ),
              DropdownButtonFormField<RecurrenceType>(
                value: selectedRecurrence,
                decoration: const InputDecoration(labelText: 'Repeat'),
                items: const [
                  DropdownMenuItem(value: RecurrenceType.none, child: Text('Never')),
                  DropdownMenuItem(value: RecurrenceType.daily, child: Text('Daily')),
                  DropdownMenuItem(value: RecurrenceType.weekly, child: Text('Weekly')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      selectedRecurrence = value;
                    });
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (titleController.text.isEmpty ||
                  selectedDate == null ||
                  selectedTime == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please fill all fields')),
                );
                return;
              }

              final dateTime = DateTime(
                selectedDate!.year,
                selectedDate!.month,
                selectedDate!.day,
                selectedTime!.hour,
                selectedTime!.minute,
              );

              await reminderProvider.updateReminder(
                id: reminder.id,
                title: titleController.text,
                dateTime: dateTime,
                recurrenceType: selectedRecurrence,
              );

              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Reminder updated successfully')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteReminder(Reminder reminder) async {
    final reminderProvider = Provider.of<ReminderProvider>(context, listen: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Reminder'),
        content: Text('Are you sure you want to delete "${reminder.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await reminderProvider.deleteReminder(reminder.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reminder deleted')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Reminders for $_blindUserName'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadReminders,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addReminder,
        child: const Icon(Icons.add),
      ),
      body: Consumer<ReminderProvider>(
        builder: (context, reminderProvider, child) {
          if (reminderProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          } else if (reminderProvider.reminders.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.notifications_none, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No reminders set', style: TextStyle(fontSize: 20)),
                  SizedBox(height: 8),
                  Text('Add a reminder to help your blind user',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          } else {
            return ListView.builder(
              itemCount: reminderProvider.reminders.length,
              itemBuilder: (context, index) {
                final reminder = reminderProvider.reminders[index];
                return Dismissible(
                  key: Key(reminder.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) => _deleteReminder(reminder),
                  child: ListTile(
                    onTap: () => _editReminder(reminder),
                    leading: CircleAvatar(
                      backgroundColor: reminder.isCompleted
                          ? Colors.green
                          : Theme.of(context).primaryColor,
                      child: Icon(
                        reminder.isCompleted ? Icons.check : Icons.notifications,
                        color: Colors.white,
                      ),
                    ),
                    title: Text(reminder.title),
                    subtitle: Text(
                      DateFormat('MMM d, y • h:mm a').format(reminder.dateTime),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (reminder.recurrenceType != RecurrenceType.none)
                          Icon(
                            reminder.recurrenceType == RecurrenceType.daily
                                ? Icons.repeat
                                : Icons.repeat_one,
                            color: Colors.grey,
                          ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteReminder(reminder),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          }
        },
      ),
    );
  }
}
