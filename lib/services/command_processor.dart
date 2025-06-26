class ParsedCommand {
  final String type;
  final String? payload;

  ParsedCommand(this.type, [this.payload]);
}

class CommandProcessor {
  /// Parses the response returned by Gemini and extracts the command/action.
  ///
  /// Supported formats:
  /// - ACTION:NAVIGATE:screen
  /// - ACTION:CALL
  /// - ACTION:MESSAGE:Hello there
  /// - RESPONSE:This is a general reply
  ParsedCommand parse(String response) {
    response = response.trim();

    if (response.startsWith('ACTION:')) {
      final parts = response.substring(7).split(':');

      if (parts.isNotEmpty) {
        final type = parts[0];
        final payload = parts.length > 1 ? parts.sublist(1).join(':') : null;
        return ParsedCommand(type, payload);
      }
    } else if (response.startsWith('RESPONSE:')) {
      return ParsedCommand('RESPONSE', response.substring(9).trim());
    }

    // Default to plain text response if format is unknown
    return ParsedCommand('RESPONSE', response);
  }
}
