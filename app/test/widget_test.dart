import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inclusichat/src/app.dart';

void main() {
  testWidgets('login validates required fields', (tester) async {
    await tester.pumpWidget(const InclusiChatApp());

    expect(find.text('InclusiChat'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsOneWidget);

    final signInButton = find.byKey(const Key('signInButton'));
    await tester.ensureVisible(signInButton);
    await tester.tap(signInButton);
    await tester.pump();

    expect(find.text('Escribe tu correo electrónico'), findsOneWidget);
    expect(find.text('Escribe tu contraseña'), findsOneWidget);
  });

  testWidgets('registration validates required fields', (tester) async {
    await tester.pumpWidget(const InclusiChatApp());
    final registrationLink = find.text('Crear cuenta');
    await tester.ensureVisible(registrationLink);
    await tester.tap(registrationLink);
    await tester.pumpAndSettle();

    final createAccountButton = find.byKey(const Key('createAccountButton'));
    await tester.ensureVisible(createAccountButton);
    await tester.tap(createAccountButton);
    await tester.pump();

    expect(find.text('Escribe el nombre que deseas mostrar'), findsOneWidget);
    expect(find.text('Elige tu alias de usuario'), findsOneWidget);
    expect(find.text('Escribe tu correo electrónico'), findsOneWidget);
    expect(find.text('Usa al menos 10 caracteres'), findsOneWidget);
  });
}
