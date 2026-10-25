import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_expense_tracker/data/app_database.dart';
import 'package:pocket_expense_tracker/screens/custom_subjects_screen.dart';

void main() {
  testWidgets('subject manager can add a subject and leave its route safely', (
    tester,
  ) async {
    final database = _SubjectDatabase();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => CustomSubjectsScreen(database: database),
                  ),
                ),
                child: const Text('Open settings'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    expect(find.text('No saved subjects yet.'), findsNothing);
    expect(find.textContaining('No saved subjects yet.'), findsOneWidget);

    await tester.tap(find.text('Add subject'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.showKeyboard(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Stationery');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pump();
    expect(
      tester.takeException(),
      isNull,
      reason: 'The dialog controller must remain alive through route teardown.',
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(database.values, ['Stationery']);
    expect(find.text('Stationery'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Open settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _SubjectDatabase extends AppDatabase {
  _SubjectDatabase() : super(pathOverride: 'unused');

  final List<String> values = [];

  @override
  Future<List<String>> customSubjects() async => List.of(values);

  @override
  Future<void> addCustomSubject(String value) async => values.add(value.trim());

  @override
  Future<void> renameCustomSubject(String oldValue, String newValue) async {
    values[values.indexOf(oldValue)] = newValue.trim();
  }

  @override
  Future<void> deleteCustomSubject(String subject) async =>
      values.remove(subject);
}
