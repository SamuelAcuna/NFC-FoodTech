import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'auth_layout.dart';
import 'auth_providers.dart';
import 'mfa_verify_page.dart';

class MfaEnrollPage extends ConsumerStatefulWidget {
  const MfaEnrollPage({super.key});
  @override
  ConsumerState<MfaEnrollPage> createState() => _MfaEnrollPageState();
}

class _MfaEnrollPageState extends ConsumerState<MfaEnrollPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(authControllerProvider).enroll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final enrollment = auth.enrollment;
    return AuthLayout(
      title: 'Configurar verificación en dos pasos',
      description: 'Escanea el QR con tu aplicación de autenticación o copia el secreto. Luego ingresa su código.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthMessage(auth.message),
          if (enrollment != null) ...[
            Center(
              child: SvgPicture.string(
                enrollment.qrCode,
                width: 200,
                height: 200,
                semanticsLabel: 'QR para configurar tu autenticador',
              ),
            ),
            const SizedBox(height: 16),
            const Text('Secreto de configuración'),
            SelectableText(enrollment.secret, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            TotpCodeForm(factorId: enrollment.factorId),
          ] else
            AuthSubmitButton(
              busy: auth.busy,
              label: 'Obtener QR',
              onPressed: auth.enroll,
            ),
          TextButton(
            onPressed: auth.busy ? null : auth.logout,
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
  }
}
