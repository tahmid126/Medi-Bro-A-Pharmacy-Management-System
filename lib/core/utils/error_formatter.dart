import 'package:flutter/foundation.dart';

class ErrorFormatter {
  /// Sanitizes any raw exception or error string so that sensitive backend URLs,
  /// internal endpoints, tokens, and raw stack traces are NEVER displayed to end-users.
  static String format(dynamic error) {
    if (error == null) return '';

    // Log raw error in debug mode only
    debugPrint('[ErrorFormatter] Raw error: $error');

    final raw = error.toString().replaceAll('Exception: ', '').trim();
    final lower = raw.toLowerCase();

    // 1. Network / Connection / DNS Errors
    if (lower.contains('socketexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('clientexception') ||
        lower.contains('no address associated with hostname') ||
        lower.contains('connection refused') ||
        lower.contains('connection timed out') ||
        lower.contains('network is unreachable') ||
        lower.contains('handshakeexception') ||
        lower.contains('errno = 7') ||
        lower.contains('failed to connect')) {
      return 'Unable to connect to the server. Please check your internet connection.';
    }

    // 2. Authentication Errors
    if (lower.contains('invalid login credentials') ||
        lower.contains('invalid credentials') ||
        lower.contains('invalid_grant') ||
        lower.contains('invalid password') ||
        lower.contains('wrong password')) {
      return 'Incorrect email or password. Please check your credentials.';
    }

    if (lower.contains('email not confirmed')) {
      return 'Your email is not verified. Please check your inbox.';
    }

    if (lower.contains('user already registered') || lower.contains('already registered')) {
      return 'An account with this email already exists.';
    }

    if (lower.contains('too many requests') || lower.contains('rate limit')) {
      return 'Too many failed attempts. Please wait a moment and try again.';
    }

    // 3. Prevent any sensitive technical details or URLs from being exposed
    if (lower.contains('http://') ||
        lower.contains('https://') ||
        lower.contains('supabase.co') ||
        lower.contains('grant_type') ||
        lower.contains('uri=') ||
        lower.contains('postgrestexception') ||
        lower.contains('os error') ||
        lower.contains('stack trace') ||
        lower.contains('select ') ||
        lower.contains('insert into') ||
        lower.contains('relation ') ||
        lower.contains('column ')) {
      return 'An unexpected error occurred. Please try again.';
    }

    // Return sanitized clean message if short and safe
    if (raw.length < 100 && !raw.contains('{') && !raw.contains('(')) {
      return raw;
    }

    return 'An unexpected error occurred. Please try again.';
  }
}
