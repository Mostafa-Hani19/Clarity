import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import '../../../../providers/reminder_provider.dart';
import '../../../../models/reminder.dart';
import '../../../../providers/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BlindReminderScreen extends StatefulWidget {
  const BlindReminderScreen({super.key});

  @override
  State<BlindReminderScreen> createState() => _BlindReminderScreenState();
}

class _BlindReminderScreenState extends State<BlindReminderScreen> {
  final _titleController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  RecurrenceType _selectedRecurrence = RecurrenceType.none;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    final provider = Provider.of<ReminderProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    // Add debug prints to help diagnose the issue
    debugPrint('👤 AuthProvider - Current User ID: ${authProvider.currentUserId}');
    debugPrint('🔐 AuthProvider - Is Authenticated: ${authProvider.isAuthenticated}');
    
    // Get stored user ID from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final storedUserId = prefs.getString('user_id');
    debugPrint('💾 SharedPreferences - User ID: $storedUserId');
    
    // Store user ID in SharedPreferences if authenticated but not stored
    if (authProvider.isAuthenticated && authProvider.currentUserId != null && storedUserId == null) {
      await prefs.setString('user_id', authProvider.currentUserId!);
      debugPrint('✅ Stored user ID in SharedPreferences: ${authProvider.currentUserId}');
    }
    
    await provider.initialize();
    await provider.loadReminders();
    
    // Check reminders after loading
    debugPrint('📋 Number of reminders loaded: ${provider.reminders.length}');
    if (provider.reminders.isNotEmpty) {
      debugPrint('📋 First reminder: ${provider.reminders.first.title} at ${provider.reminders.first.dateTime}');
    }
  }

  Future<void> _showAddReminderDialog() async {
    _titleController.clear();
    _selectedDate = DateTime.now();
    _selectedTime = TimeOfDay.now();
    _selectedRecurrence = RecurrenceType.none;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Reminder'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Reminder Title',
                  hintText: 'Enter reminder title',
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                title: const Text('Date'),
                subtitle: Text(DateFormat.yMMMd().format(_selectedDate)),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date != null) {
                    setState(() => _selectedDate = date);
                  }
                },
              ),
              ListTile(
                title: const Text('Time'),
                subtitle: Text(_selectedTime.format(context)),
                trailing: const Icon(Icons.access_time),
                onTap: () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: _selectedTime,
                  );
                  if (time != null) {
                    setState(() => _selectedTime = time);
                  }
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<RecurrenceType>(
                value: _selectedRecurrence,
                decoration: const InputDecoration(
                  labelText: 'Repeat',
                ),
                items: const [
                  DropdownMenuItem(value: RecurrenceType.none, child: Text('Never')),
                  DropdownMenuItem(value: RecurrenceType.daily, child: Text('Daily')),
                  DropdownMenuItem(value: RecurrenceType.weekly, child: Text('Weekly')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedRecurrence = value);
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
              if (_titleController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a reminder title')),
                );
                return;
              }

              final provider = Provider.of<ReminderProvider>(context, listen: false);
              final authProvider = Provider.of<AuthProvider>(context, listen: false);

              if (!authProvider.isAuthenticated) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please log in to add reminders')),
                );
                return;
              }
              
              // Create the date time with selected date and time
              final dateTime = DateTime(
                _selectedDate.year,
                _selectedDate.month,
                _selectedDate.day,
                _selectedTime.hour,
                _selectedTime.minute,
              );
              
              final userId = authProvider.currentUserId;
              if (userId == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('User ID not available')),
                );
                return;
              }

              final reminder = await provider.addReminder(
                title: _titleController.text.trim(),
                dateTime: dateTime,
                userId: userId,
                recurrenceType: _selectedRecurrence,
              );

              if (reminder == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Failed to add reminder - Please try again')),
                );
                return;
              }

              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Reminder added successfully')),
              );
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
        title: const Text('Reminders'),
        centerTitle: true,
      ),
      body: Consumer<ReminderProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.reminders.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.calendar_today, size: 80, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text('No Reminders', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  const Text(
                    'Tap the plus button to add a reminder.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          final sortedReminders = List<Reminder>.from(provider.reminders)
            ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

          final authProvider = Provider.of<AuthProvider>(context, listen: false);

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sortedReminders.length,
            itemBuilder: (context, index) {
              final reminder = sortedReminders[index];
              final isFromHelper = reminder.userId == authProvider.linkedUserId;

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
                  contentPadding: const EdgeInsets.all(16),
                  title: Row(
                    children: [
                      Text('${index + 1}. ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(reminder.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                            ),
                            if (isFromHelper)
                              Tooltip(
                                message: 'Added by your helper',
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.person_outline, size: 16, color: Colors.blue),
                                      SizedBox(width: 4),
                                      Text('Helper', style: TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 16),
                          const SizedBox(width: 8),
                          Text(DateFormat.yMMMd().format(reminder.dateTime)),
                          const SizedBox(width: 16),
                          const Icon(Icons.access_time, size: 16),
                          const SizedBox(width: 8),
                          Text(DateFormat.jm().format(reminder.dateTime)),
                        ],
                      ),
                    ],
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
                  onTap: () => _editReminder(reminder),
                ),
              );
            },
          );
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            FloatingActionButton(
              onPressed: _showAddReminderDialog,
              heroTag: 'add_reminder',
              child: const Icon(Icons.add, size: 32, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
