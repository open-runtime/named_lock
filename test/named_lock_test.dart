import 'dart:io' show sleep;
import 'dart:isolate' show Isolate, ReceivePort, SendPort;
import 'dart:math' show Random;
import 'package:runtime_named_locks/runtime_named_locks.dart' show ExecutionCall, NamedLock;
import 'package:safe_int_id/safe_int_id.dart' show safeIntId;
import 'package:test/test.dart' show equals, expect, group, isA, test, throwsA;

class IntentionalTestException implements Exception {
  final String message;
  IntentionalTestException({String this.message = "Intentional test exception message."});
  @override
  String toString() => message;
}

void main() {
  group('Testing execution calls exception handling', () {
    test('Unsafe exception catch', () async {
      String name = '${safeIntId.getId()}_named_lock';

      final ExecutionCall<void, IntentionalTestException> execution = ExecutionCall<void, IntentionalTestException>(
        callable: () => throw IntentionalTestException(),
      );

      expect(
        () => NamedLock.guard<void, IntentionalTestException>(
          name: name,
          execution: execution,
        ),
        throwsA(isA<IntentionalTestException>()),
      );

      expect(execution.error.get?.anticipated.get, isA<IntentionalTestException>());
      expect(execution.completer.isCompleted, true);
      expect(execution.successful.isSet, true);
      expect(execution.successful.get, false);
    });

    test('Safe exception catch', () async {
      String name = '${safeIntId.getId()}_named_lock';

      final ExecutionCall<void, Exception> execution = ExecutionCall<void, Exception>(
        callable: () => throw IntentionalTestException(),
        /* Setting safe to true here */ safe: true,
      );

      final guarded = NamedLock.guard<void, Exception>(
        name: name,
        execution: execution,
      );

      expect(guarded.completer.isCompleted, true);
      expect(guarded.successful.isSet, true);
      expect(guarded.successful.get, false);
      expect(guarded.error.get?.anticipated.get, isA<IntentionalTestException>());
      expect(guarded.error.get?.unknown.get, equals(null));
      expect(guarded.error.get?.trace.get, isA<StackTrace>());
      expect(() => guarded.error.get?.rethrow_(), throwsA(isA<IntentionalTestException>()));
    });
  });

  group('NativeLock calling [guard] from single and multiple isolates and measuring reentrant behavior.', () {
    test('Reentrant within a single isolate', () async {
      String name = '${safeIntId.getId()}_named_lock';

      int nested_calculation() {
        final ExecutionCall<int, Exception> _execution = NamedLock.guard(
          name: name,
          execution: ExecutionCall<int, Exception>(
            callable: () {
              sleep(Duration(milliseconds: Random().nextInt(5000)));
              return 3 + 4;
            },
          ),
        );

        return _execution.returned;
      }

      final ExecutionCall<int, Exception> execution = NamedLock.guard(
        name: name,
        execution: ExecutionCall<int, Exception>(
          callable: () {
            sleep(Duration(milliseconds: Random().nextInt(2000)));
            return (nested_calculation() * 2) + 5;
          },
        ),
      );

      expect(execution.returned, equals(19));
    });

    test('Reentrant Behavior Across Several Isolates', () async {
      Future<int> spawn_isolate(String name, int id) async {
        // The entry point for the isolate
        void isolate_entrypoint(SendPort sender) {
          final ExecutionCall<int, Exception> _returnable = NamedLock.guard<int, Exception>(
            name: name,
            execution: ExecutionCall<int, Exception>(
              callable: () {
                print("Isolate $id is executing with a guard.");
                sleep(Duration(milliseconds: Random().nextInt(2000)));

                ExecutionCall<int, Exception> call = (NamedLock.guard<int, Exception>(
                  name: name,
                  execution: ExecutionCall<int, Exception>(
                    callable: () {
                      print("Isolate $id with nested guard is executing.");
                      sleep(Duration(milliseconds: Random().nextInt(2000)));
                      return 2;
                    },
                  ),
                ));

                return 2 * call.returned;
              },
            ),
          );

          sender.send(_returnable.returned);
        }

        // Create a receive port to get messages from the isolate
        final ReceivePort receiver = ReceivePort();

        // Spawn the isolate
        await Isolate.spawn(isolate_entrypoint, receiver.sendPort);

        // Wait for the isolate to send its message
        return await receiver.first as int;
      }

      String name = '${safeIntId.getId()}_named_sem';

      final ExecutionCall<Future<int>, Exception> execution = NamedLock.guard(
        name: name,
        execution: ExecutionCall<Future<int>, Exception>(
          callable: () async {
            sleep(Duration(milliseconds: Random().nextInt(2000)));
            final result_one = spawn_isolate(name, 1);
            final result_two = spawn_isolate(name, 2);
            final result_three = spawn_isolate(name, 3);
            final result_four = spawn_isolate(name, 4);
            final outcomes = await Future.wait([result_one, result_two, result_three, result_four]);
            print('Outcomes: $outcomes');
            return outcomes.reduce((a, b) => a + b);
          },
        ),
      );

      final returned = await execution.returned;
      expect(returned, equals(16));
    });
  });
}
