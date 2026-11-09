import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_exception.dart';

/// Turns anything the backend or network throws into a short, safe message.
/// Our SQL functions raise user-facing messages (SQLSTATE P0001), which pass
/// through; unexpected database errors never leak internals.
AppException appExceptionFrom(Object e) {
  if (e is AppException) return e;
  if (e is PostgrestException) {
    final code = e.code ?? '';
    final hint = e.hint ?? '';
    if (code == 'P0001') return AppException(e.message);
    if (code == '28000' || code == 'PGRST301' || code == 'PGRST302' || hint == 'UNAUTHENTICATED') {
      return AppException('Please sign in again.');
    }
    if (hint == 'FORBIDDEN') return AppException(e.message);
    if (code == '42501') return AppException('You do not have permission to do that.');
    return AppException('Something went wrong. Please try again.');
  }
  if (e is AuthException) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login') || m.contains('invalid credentials')) {
      return AppException('Invalid email or password.');
    }
    if (m.contains('already registered') || m.contains('already been registered')) {
      return AppException('An account with this email already exists.');
    }
    if (m.contains('not confirmed')) return AppException('Please confirm your email address first.');
    if (e.statusCode == '429' || m.contains('rate limit') || m.contains('too many')) {
      return AppException('Too many attempts. Please wait a moment and try again.');
    }
    return AppException(e.message);
  }
  if (e is FunctionException) {
    final d = e.details;
    if (d is Map && d['error'] is Map && (d['error'] as Map)['message'] is String) {
      return AppException((d['error'] as Map)['message'] as String);
    }
    return AppException('The request could not be completed. Please try again.');
  }
  if (e is SocketException || e is TimeoutException || e is HttpException) {
    return AppException('No connection. Check your internet and try again.');
  }
  return AppException('Something went wrong. Please try again.');
}
