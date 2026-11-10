import 'package:flutter/material.dart';

import 'package:nfc_foodtech_app/theme_controller.dart';

import 'package:nfc_foodtech_app/features/perfil/screens/perfil_screen.dart';
import 'package:nfc_foodtech_app/features/auth/screens/cambiar_contrasena_screen.dart';
import 'package:nfc_foodtech_app/features/alertas/screens/notificaciones_screen.dart';
import 'package:nfc_foodtech_app/features/alertas/screens/preferencias_notificaciones_screen.dart';
import 'package:nfc_foodtech_app/features/configuracion/screens/ayuda_screen.dart';
import 'package:nfc_foodtech_app/features/configuracion/screens/solicitud_soporte_screen.dart';

class ConfiguracionScreen extends StatefulWidget {
  const ConfiguracionScreen({
    super.key,
    this.integrada = false,
    this.onCerrarSesion,
  });

  final bool integrada;
  final VoidCallback? onCerrarSesion;

  @override
  State<ConfiguracionScreen> createState() => _ConfiguracionScreenState();
}

class _ConfiguracionScreenState extends State<ConfiguracionScreen> {
  static const Color verde = Color(0xFF236B4A);

  bool _guardandoTema = false;

  Future<void> _elegirTema(ThemeMode modo) async {
    if (_guardandoTema) return;

    setState(() => _guardandoTema = true);

    final guardado = await appTheme.cambiar(modo);

    if (!mounted) return;

    setState(() => _guardandoTema = false);

    if (!guardado) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo guardar el tema.')),
      );
    }
  }

  void _abrirPantalla(Widget pantalla) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => pantalla));
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final esquema = tema.colorScheme;

    final oscuro = tema.brightness == Brightness.dark;

    final colorPrincipal = oscuro ? esquema.onSurface : verde;

    return Scaffold(
      backgroundColor: tema.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Configuración'),
        automaticallyImplyLeading: !widget.integrada,
        backgroundColor: tema.scaffoldBackgroundColor,
        foregroundColor: colorPrincipal,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Cuenta
                Text(
                  'Cuenta',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: colorPrincipal,
                  ),
                ),

                const SizedBox(height: 10),

                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(
                          Icons.person_outline,
                          color: colorPrincipal,
                        ),
                        title: const Text('Mi perfil'),
                        subtitle: const Text(
                          'Consultar y editar datos personales',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _abrirPantalla(const PerfilScreen()),
                      ),

                      const Divider(height: 1),

                      ListTile(
                        leading: Icon(
                          Icons.lock_outline,
                          color: colorPrincipal,
                        ),
                        title: const Text('Cambiar contraseña'),
                        subtitle: const Text('Seguridad de tu cuenta'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () =>
                            _abrirPantalla(const CambiarContrasenaScreen()),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 26),

                // Apariencia
                Text(
                  'Apariencia',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: colorPrincipal,
                  ),
                ),

                const SizedBox(height: 8),

                const Text('Selecciona cómo quieres ver la aplicación.'),

                const SizedBox(height: 10),

                Card(
                  child: RadioGroup<ThemeMode>(
                    groupValue: appTheme.modo,
                    onChanged: (valor) {
                      if (_guardandoTema || valor == null) {
                        return;
                      }

                      _elegirTema(valor);
                    },
                    child: Column(
                      children: [
                        RadioListTile<ThemeMode>(
                          title: const Text('Claro'),
                          secondary: const Icon(Icons.light_mode_outlined),
                          value: ThemeMode.light,
                          enabled: !_guardandoTema,
                        ),

                        const Divider(height: 1),

                        RadioListTile<ThemeMode>(
                          title: const Text('Oscuro'),
                          secondary: const Icon(Icons.dark_mode_outlined),
                          value: ThemeMode.dark,
                          enabled: !_guardandoTema,
                        ),

                        const Divider(height: 1),

                        RadioListTile<ThemeMode>(
                          title: const Text('Según el dispositivo'),
                          secondary: const Icon(
                            Icons.settings_brightness_outlined,
                          ),
                          value: ThemeMode.system,
                          enabled: !_guardandoTema,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                Text(
                  'La apariencia se guarda por cuenta '
                  'en este dispositivo.',
                  style: TextStyle(
                    fontSize: 12,
                    color: esquema.onSurfaceVariant,
                  ),
                ),

                const SizedBox(height: 26),

                // Notificaciones
                Text(
                  'Notificaciones',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: colorPrincipal,
                  ),
                ),

                const SizedBox(height: 10),

                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(
                          Icons.notifications_outlined,
                          color: colorPrincipal,
                        ),
                        title: const Text('Centro de notificaciones'),
                        subtitle: const Text(
                          'Consultar avisos y recordatorios',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () =>
                            _abrirPantalla(const NotificacionesScreen()),
                      ),

                      const Divider(height: 1),

                      ListTile(
                        leading: Icon(
                          Icons.tune_rounded,
                          color: colorPrincipal,
                        ),
                        title: const Text('Preferencias de notificaciones'),
                        subtitle: const Text(
                          'Configurar tipos de avisos y horarios',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _abrirPantalla(
                          const PreferenciasNotificacionesScreen(),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 26),

                // Ayuda y soporte
                Text(
                  'Ayuda y soporte',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: colorPrincipal,
                  ),
                ),

                const SizedBox(height: 10),

                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(
                          Icons.help_outline_rounded,
                          color: colorPrincipal,
                        ),
                        title: const Text('Ayuda y preguntas frecuentes'),
                        subtitle: const Text(
                          'Consultar guías y resolver dudas',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _abrirPantalla(const AyudaScreen()),
                      ),

                      const Divider(height: 1),

                      // M13 - Solicitudes de soporte
                      ListTile(
                        leading: Icon(
                          Icons.support_agent_outlined,
                          color: colorPrincipal,
                        ),
                        title: const Text('Solicitudes de soporte'),
                        subtitle: const Text(
                          'Preparar consultas, reportes '
                          'de errores y sugerencias',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () =>
                            _abrirPantalla(const SolicitudSoporteScreen()),
                      ),
                    ],
                  ),
                ),

                if (widget.onCerrarSesion != null)
                  TextButton.icon(
                    onPressed: widget.onCerrarSesion,
                    icon: const Icon(Icons.logout),
                    label: const Text('Cerrar sesión'),
                  ),
                const SizedBox(height: 28),

                Center(
                  child: Text(
                    'NFC-FoodTech · Cada alimento cuenta 🌱',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: esquema.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
