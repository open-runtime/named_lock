import 'dart:async' show Completer, Future;
import 'package:runtime_native_semaphores/runtime_native_semaphores.dart' show LatePropertyAssigned;

typedef ExecutionCallType<R, E extends Exception> = R Function();

class ExecutionCallErrors<E extends Exception> {
  E? anticipated;

  dynamic unknown;

  StackTrace? trace;

  ExecutionCallErrors({E? this.anticipated, dynamic this.unknown, this.trace});

  @override
  toString() => 'ExecutionCallErrors(anticipated: $anticipated, Unknown: $unknown, Trace: $trace)';
}

class ExecutionCall<R, E extends Exception> {
  final completer = Completer<R>();

  final ExecutionCallType<R, E> _callable;

  late final R _returned;

  R get returned =>
      LatePropertyAssigned(() => _returned) ? _returned : (throw Exception('[returned] value is not available. To ensure property availabilities [await completer.future]. '));

  late final ExecutionCallErrors<E> _error;

  ExecutionCallErrors<E> get error =>
      LatePropertyAssigned(() => _error) ? _error : (throw Exception('[error] value is not available yet. To ensure property availabilities [await completer.future].'));

  // Keeping this nullable for polling purposes
  late final bool _successful;

  bool get successful => LatePropertyAssigned(() => _successful)
      ? _successful
      : (throw Exception('[successful] value is not available yet. To ensure property availabilities [await completer.future].'));

  late final bool guarded;

  bool verbose;

  // TODO put lock on here?

  // Identifier is the name of the semaphore
  // Callable is the function to be executed
  // Todo pass along lock instance?
  ExecutionCall({required ExecutionCallType<R, E> callable, this.verbose = false}) : _callable = callable;

  ExecutionCall<R, E> execute() {
    if (verbose) print('Calling Guarded ExecutionCall.execute()');
    bool _guarded = LatePropertyAssigned<bool>(() => guarded);
    _guarded || (throw Exception('Call to execute() can only be executed internally from the Lock.guard method.'));

    try {
      if (verbose) print('Attempting Guarded ExecutionCall.callable()');

      final R returnable = _callable();

      if (verbose) print('Guarded ExecutionCall Returnable: $returnable');

      returnable is Future
          ? returnable
              .then((_returnable) => _successful = (completer..complete(_returned = _returnable)).isCompleted)
              .catchError((e, trace) => (_error = ExecutionCallErrors<E>(unknown: e is E ? e : null, anticipated: e is E ? e : null, trace: trace)).unknown)
              .whenComplete(() => _successful = false)
          : _successful = (completer..complete(_returned = returnable)).isCompleted;

      if (verbose && returnable is Future)
        print('Guarded ExecutionCall has returned an asynchronous result and will complete when property completer.future is resolved.');
      else if (verbose) print('Guarded ExecutionCall returned a synchronous result and was successful: $_successful');
    } on E catch (e, trace) {
      // Set successful to false
      _successful = (_error = ExecutionCallErrors<E>(anticipated: e, trace: trace)) is! ExecutionCallErrors<E>;
    } catch (e, trace) {
      // Set successful to false
      _successful = (_error = ExecutionCallErrors<E>(unknown: e, trace: trace)) is! ExecutionCallErrors<E>;
    }

    if (verbose) print('Guarded execution call failed with errors: $error');

    return this;
  }
}
