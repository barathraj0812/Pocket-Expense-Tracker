import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_expense_tracker/widgets/custom_subject_field.dart';

void main() {
  testWidgets('dropdown selects saved subjects and permits manual entry', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomSubjectField(
            controller: controller,
            focusNode: focus,
            savedSubjects: const ['Stationery'],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Choose a saved subject'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stationery'));
    await tester.pumpAndSettle();
    expect(controller.text, 'Stationery');

    await tester.tap(find.byTooltip('Choose a saved subject'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enter a different subject…'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextFormField), 'One-off repair');
    expect(controller.text, 'One-off repair');
    expect(tester.takeException(), isNull);
  });

  testWidgets('subject field allows empty value and long names wrap safely', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomSubjectField(
            controller: controller,
            focusNode: focus,
            savedSubjects: const [
              'An exceptionally long saved subject name that should wrap safely',
            ],
          ),
        ),
      ),
    );
    expect(controller.text, isEmpty);
    await tester.tap(find.byTooltip('Choose a saved subject'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
