import 'package:flutter/material.dart';

class AyudaScreen extends StatefulWidget {
  const AyudaScreen({super.key});

  @override
  State<AyudaScreen> createState() => _AyudaScreenState();
}

class _AyudaScreenState extends State<AyudaScreen> {
  static const Color verde = Color(0xFF236B4A);

  final TextEditingController _busquedaController = TextEditingController();

  String _busqueda = '';

  static const List<_PreguntaAyuda> _preguntas = [
    _PreguntaAyuda(
      categoria: 'Cuenta y acceso',
      pregunta: '¿Cómo puedo crear una cuenta?',
      respuesta:
          'Desde la pantalla de inicio selecciona '
          '"Crear una cuenta". Ingresa tu correo electrónico, '
          'contraseña y confirmación. Si se solicita verificar '
          'el correo, sigue las instrucciones que recibas.',
    ),
    _PreguntaAyuda(
      categoria: 'Cuenta y acceso',
      pregunta: '¿Puedo ingresar con Google?',
      respuesta:
          'Sí. Desde la pantalla de inicio puedes seleccionar '
          '"Continuar con Google" y completar el proceso '
          'de autenticación.',
    ),
    _PreguntaAyuda(
      categoria: 'Cuenta y acceso',
      pregunta: '¿Qué hago si olvidé mi contraseña?',
      respuesta:
          'Selecciona "¿Olvidaste tu contraseña?" en el inicio '
          'de sesión. Ingresa tu correo electrónico para '
          'solicitar un enlace de recuperación. '
          'El envío depende de la disponibilidad del '
          'servicio de correo.',
    ),
    _PreguntaAyuda(
      categoria: 'Cuenta y acceso',
      pregunta: '¿Cómo cambio mi contraseña?',
      respuesta:
          'Inicia sesión, entra a Configuración y '
          'selecciona "Cambiar contraseña". Sigue '
          'las instrucciones para actualizarla.',
    ),
    _PreguntaAyuda(
      categoria: 'Cuenta y acceso',
      pregunta: '¿Cómo modifico mis datos personales?',
      respuesta:
          'Entra a "Mi perfil", modifica los datos '
          'que necesites y presiona "Guardar cambios".',
    ),
    _PreguntaAyuda(
      categoria: 'Configuración',
      pregunta: '¿Cómo cambio el tema de la aplicación?',
      respuesta:
          'Ingresa a Configuración y busca "Apariencia". '
          'Puedes elegir el modo claro, oscuro o según '
          'el dispositivo. La preferencia se guarda '
          'para tu cuenta en este dispositivo.',
    ),
    _PreguntaAyuda(
      categoria: 'Configuración',
      pregunta: '¿Puedo volver a ver el tutorial?',
      respuesta:
          'Actualmente el tutorial aparece al ingresar '
          'por primera vez. Más adelante incorporaremos '
          'una opción para repetirlo desde la ayuda.',
    ),
    _PreguntaAyuda(
      categoria: 'Notificaciones',
      pregunta: '¿Cómo configuro las notificaciones?',
      respuesta:
          'Entra al Centro de notificaciones y selecciona '
          '"Configurar preferencias", o accede desde '
          'Configuración. Puedes guardar tus preferencias '
          'de avisos, días de anticipación y horario.',
    ),
    _PreguntaAyuda(
      categoria: 'Notificaciones',
      pregunta: '¿Por qué todavía no recibo alertas?',
      respuesta:
          'Consulta las alertas de caducidad desde Inventario '
          'y el Centro de notificaciones. Revisa las fechas '
          'de tus alimentos y tus preferencias de avisos. '
          'La recepción fuera de la aplicación depende del '
          'servicio de envío y de los permisos de Android.',
    ),
    _PreguntaAyuda(
      categoria: 'Hogares',
      pregunta: '¿Qué es un hogar en NFC-FoodTech?',
      respuesta:
          'Un hogar es un espacio compartido para gestionar '
          'alimentos y consultar su información. Puedes crear '
          'uno o unirte mediante un código desde Mi hogar. '
          'Cada usuario puede pertenecer a un solo hogar activo, '
          'y un hogar puede tener varios integrantes.',
    ),
    _PreguntaAyuda(
      categoria: 'Alimentos e inventario',
      pregunta: '¿Cómo registro los alimentos?',
      respuesta:
          'Desde el Home selecciona Registrar alimentos. '
          'Elige un alimento e indica cantidad, unidad, '
          'precio, ubicación y fecha de caducidad según '
          'las opciones del formulario. Necesitas un hogar activo.',
    ),
    _PreguntaAyuda(
      categoria: 'Alimentos e inventario',
      pregunta: '¿La fecha estimada garantiza que el alimento sea seguro?',
      respuesta:
          'No. Las fechas estimadas son orientativas '
          'y podrán modificarse manualmente. '
          'No reemplazan las indicaciones del fabricante '
          'ni las recomendaciones de seguridad alimentaria.',
    ),
    _PreguntaAyuda(
      categoria: 'Consumo y desperdicio',
      pregunta: '¿Cómo registro el consumo?',
      respuesta:
          'Desde Registrar consumo o Mi inventario, selecciona '
          'un ingreso disponible y utiliza Consumir. Indica '
          'la cantidad utilizada y confirma para descontarla '
          'del inventario.',
    ),
    _PreguntaAyuda(
      categoria: 'Consumo y desperdicio',
      pregunta: '¿Cómo consulto el desperdicio?',
      respuesta:
          'Registra los descartes desde Inventario. En Análisis '
          'puedes consultar cantidades consumidas y descartadas '
          'por unidad, además del costo estimado del desperdicio '
          'para los registros que tienen precio conocido.',
    ),
  ];

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  List<_PreguntaAyuda> get _resultados {
    final texto = _busqueda.trim().toLowerCase();

    if (texto.isEmpty) return _preguntas;

    return _preguntas.where((pregunta) {
      return pregunta.pregunta.toLowerCase().contains(texto) ||
          pregunta.respuesta.toLowerCase().contains(texto) ||
          pregunta.categoria.toLowerCase().contains(texto);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final esquema = tema.colorScheme;
    final oscuro = tema.brightness == Brightness.dark;
    final colorPrincipal = oscuro ? esquema.onSurface : verde;

    final resultados = _resultados;

    final categorias = resultados
        .map((pregunta) => pregunta.categoria)
        .toSet()
        .toList();

    return Scaffold(
      backgroundColor: tema.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Ayuda y preguntas frecuentes'),
        backgroundColor: tema.scaffoldBackgroundColor,
        foregroundColor: colorPrincipal,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: esquema.surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: esquema.outlineVariant),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: oscuro
                              ? esquema.surfaceContainerHighest
                              : const Color(0xFFE1F1E6),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Icon(
                          Icons.help_outline_rounded,
                          color: colorPrincipal,
                          size: 42,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '¿En qué podemos ayudarte?',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.bold,
                          color: colorPrincipal,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Encuentra respuestas sobre NFC-FoodTech '
                        'y conoce cómo utilizar sus funciones.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          height: 1.5,
                          color: esquema.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                TextField(
                  controller: _busquedaController,
                  onChanged: (valor) {
                    setState(() => _busqueda = valor);
                  },
                  decoration: InputDecoration(
                    labelText: 'Buscar una pregunta',
                    hintText: 'Ejemplo: contraseña',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _busqueda.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Limpiar búsqueda',
                            onPressed: () {
                              _busquedaController.clear();
                              setState(() => _busqueda = '');
                            },
                            icon: const Icon(Icons.close),
                          ),
                    filled: true,
                    fillColor: esquema.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                Text(
                  '${resultados.length} preguntas encontradas',
                  style: TextStyle(
                    fontSize: 13,
                    color: esquema.onSurfaceVariant,
                  ),
                ),

                if (resultados.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 60),
                    child: Column(
                      children: [
                        Icon(
                          Icons.search_off_rounded,
                          size: 56,
                          color: esquema.onSurfaceVariant,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No encontramos resultados',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Prueba buscando con otras palabras.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: esquema.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),

                for (final categoria in categorias) ...[
                  const SizedBox(height: 24),

                  Text(
                    categoria,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: colorPrincipal,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Card(
                    color: esquema.surface,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(color: esquema.outlineVariant),
                    ),
                    child: Column(
                      children: [
                        for (final pregunta in resultados.where(
                          (elemento) => elemento.categoria == categoria,
                        ))
                          ExpansionTile(
                            key: ValueKey(pregunta.pregunta),
                            title: Text(
                              pregunta.pregunta,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            iconColor: esquema.primary,
                            childrenPadding: const EdgeInsets.fromLTRB(
                              16,
                              0,
                              16,
                              18,
                            ),
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  pregunta.respuesta,
                                  style: TextStyle(
                                    height: 1.6,
                                    fontSize: 14,
                                    color: esquema.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 32),

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

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PreguntaAyuda {
  final String categoria;
  final String pregunta;
  final String respuesta;

  const _PreguntaAyuda({
    required this.categoria,
    required this.pregunta,
    required this.respuesta,
  });
}
