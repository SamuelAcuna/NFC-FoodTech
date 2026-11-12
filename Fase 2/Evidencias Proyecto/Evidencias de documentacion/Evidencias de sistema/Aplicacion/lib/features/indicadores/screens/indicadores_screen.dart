import 'dart:convert';
import 'package:nfc_foodtech_app/shared/models/resumen_indicadores.dart';
import 'package:nfc_foodtech_app/shared/services/lectura_movimientos.dart';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:nfc_foodtech_app/shared/widgets/acceso_hogar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:nfc_foodtech_app/features/indicadores/screens/comparativa_mensual_screen.dart';
import 'package:nfc_foodtech_app/features/indicadores/screens/recomendaciones_screen.dart';

class IndicadoresScreen extends StatefulWidget {
  final Map<String, dynamic> hogar;

  const IndicadoresScreen({super.key, required this.hogar});

  @override
  State<IndicadoresScreen> createState() => _IndicadoresScreenState();
}

class _IndicadoresScreenState extends State<IndicadoresScreen> {
  static const Color verde = Color(0xFF236B4A);
  static const Color fondo = Color(0xFFF3F7F3);

  bool get _modoOscuro => Theme.of(context).brightness == Brightness.dark;

  Color get _colorFondo =>
      _modoOscuro ? Theme.of(context).scaffoldBackgroundColor : fondo;

  Color get _colorSuperficie => _modoOscuro
      ? Theme.of(context).colorScheme.surfaceContainerLow
      : Colors.white;

  Color get _colorAcento =>
      _modoOscuro ? Theme.of(context).colorScheme.primary : verde;

  Color get _colorBorde => _modoOscuro
      ? Theme.of(context).colorScheme.outlineVariant
      : const Color(0xFFDCE8DE);

  Color get _colorTextoSecundario => _modoOscuro
      ? Theme.of(context).colorScheme.onSurfaceVariant
      : Colors.black54;

  Color get _colorError =>
      _modoOscuro ? Theme.of(context).colorScheme.error : Colors.red;

  Color get _colorAdvertencia =>
      _modoOscuro ? Colors.deepOrange.shade200 : Colors.deepOrange;

  Color get _colorPista => _modoOscuro
      ? Theme.of(context).colorScheme.surfaceContainerHighest
      : const Color(0xFFE7EEE8);

  Color get _colorConsumo =>
      _modoOscuro ? Colors.blue.shade200 : const Color(0xFF1565C0);

  Color get _colorDescarte =>
      _modoOscuro ? Colors.deepOrange.shade200 : const Color(0xFFC45126);

  final _supabase = Supabase.instance.client;

  bool _cargando = true;
  int _revisionCarga = 0;
  String? _usuarioDatosId;
  bool _exportando = false;
  bool _datosParciales = false;

  String? _error;

  // =====================================================
  // INDICADORES HISTÓRICOS EXISTENTES
  // =====================================================

  int _cantidadConsumos = 0;
  int _cantidadDescartes = 0;
  int _descartesEvitables = 0;
  int _descartesNoEvitables = 0;
  int _descartesSinClasificar = 0;
  int _descartesConPrecio = 0;

  double _costoDesperdicioConocido = 0;

  PresentacionPerdidaEconomica get _perdida => PresentacionPerdidaEconomica(
    descartes: _cantidadDescartes,
    descartesConPrecio: _descartesConPrecio,
    costoConocido: _costoDesperdicioConocido,
  );

  final Map<String, double> _consumido = {'g': 0, 'ml': 0, 'un': 0};

  final Map<String, double> _descartado = {'g': 0, 'ml': 0, 'un': 0};

  List<Map<String, dynamic>> _alimentosDescartados = [];

  // =====================================================
  // R59: APROVECHAMIENTO DEL MES ACTUAL
  // =====================================================

  double? _aprovechamientoMes;

  int _cantidadConsumosMes = 0;
  int _cantidadDescartesMes = 0;
  int _ingresosEvaluadosMes = 0;

  final Map<String, double?> _aprovechamientoPorUnidadMes = {
    'g': null,
    'ml': null,
    'un': null,
  };

  // =====================================================
  // R61: RANKING HISTÓRICO POR CATEGORÍA
  // =====================================================

  List<Map<String, dynamic>> _categoriasDescartadas = [];

  @override
  void initState() {
    super.initState();
    _cargarIndicadores();
  }

  @override
  void dispose() {
    _revisionCarga++;
    super.dispose();
  }

  // =====================================================
  // FORMATOS
  // =====================================================

  double _numero(dynamic valor) {
    if (valor is num) return valor.toDouble();

    return double.tryParse(valor?.toString() ?? '') ?? 0;
  }

  String _formatearNumero(double valor, {int decimales = 3}) {
    return valor
        .toStringAsFixed(decimales)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '')
        .replaceAll('.', ',');
  }

  String _cantidadTexto(double cantidad, String unidad) {
    if (unidad == 'g' && cantidad >= 1000) {
      return '${_formatearNumero(cantidad / 1000, decimales: 6)} kg';
    }

    if (unidad == 'ml' && cantidad >= 1000) {
      return '${_formatearNumero(cantidad / 1000, decimales: 6)} L';
    }

    return '${_formatearNumero(cantidad)} $unidad';
  }

  String _dinero(double valor) {
    final entero = valor.round().toString();

    return '\$${entero.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.')}';
  }

  String _porcentajeTexto(double? valor) {
    if (valor == null) return 'Sin datos';

    return '${_formatearNumero(valor, decimales: 1)}%';
  }

  String _nombreMes(int mes) {
    const meses = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];

    if (mes < 1 || mes > 12) {
      return 'Mes desconocido';
    }

    return meses[mes - 1];
  }

  String _periodoActual() {
    final ahora = DateTime.now();

    return '${_nombreMes(ahora.month)} de ${ahora.year}';
  }

  // =====================================================
  // CONSULTAR Y CALCULAR INDICADORES
  // =====================================================

  Future<void> _cargarIndicadores() async {
    if (!mounted) return;

    final revision = ++_revisionCarga;
    final usuarioId = _supabase.auth.currentUser?.id;
    bool vigente() =>
        mounted &&
        revision == _revisionCarga &&
        _supabase.auth.currentUser?.id == usuarioId;
    final lectura = LecturaMovimientos(_supabase, vigente);

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final hogarId = widget.hogar['id']?.toString();

      if (hogarId == null || hogarId.isEmpty) {
        throw Exception('No hay un hogar seleccionado.');
      }

      if (!await AccesoHogar.verificar(context)) {
        throw StateError('No se pudo confirmar el acceso al hogar.');
      }
      lectura.comprobar();

      // -------------------------------------------------
      // 1. OBTENER INGRESOS DEL HOGAR
      // -------------------------------------------------

      final respuestaItems = await lectura.leer(
        'despensa_item',
        'id, alimento_id, cantidad_inicial, precio_clp',
        hogarId: hogarId,
      );

      final itemsPorId = <String, Map<String, dynamic>>{};

      for (final dato in respuestaItems) {
        final item = Map<String, dynamic>.from(dato);
        final id = item['id']?.toString();

        if (id != null) {
          itemsPorId[id] = item;
        }
      }

      // -------------------------------------------------
      // 2. OBTENER MOVIMIENTOS
      // -------------------------------------------------

      final idsItems = itemsPorId.keys.toList();

      final movimientos = await lectura.leer(
        'movimiento',
        'id, despensa_item_id, tipo, cantidad, tipo_desperdicio_id, fecha',
        columnaIds: 'despensa_item_id',
        ids: idsItems,
      );

      // -------------------------------------------------
      // 3. OBTENER ALIMENTOS Y SUS CATEGORÍAS
      // -------------------------------------------------

      final idsAlimentos = itemsPorId.values
          .map((item) => (item['alimento_id'] as num).toInt())
          .toSet()
          .toList();

      final alimentosPorId = <int, Map<String, dynamic>>{};

      if (idsAlimentos.isNotEmpty) {
        final respuestaAlimentos = await lectura.leer(
          'alimento',
          'id, nombre, unidad_base, categoria_id',
          columnaIds: 'id',
          ids: idsAlimentos,
        );

        for (final dato in respuestaAlimentos) {
          final alimento = Map<String, dynamic>.from(dato);

          final id = (alimento['id'] as num).toInt();

          alimentosPorId[id] = alimento;
        }
      }

      // -------------------------------------------------
      // 4. OBTENER NOMBRES DE CATEGORÍAS
      // -------------------------------------------------

      final idsCategorias = alimentosPorId.values
          .map((alimento) => alimento['categoria_id'])
          .where((id) => id != null)
          .map((id) => (id as num).toInt())
          .toSet()
          .toList();

      final categoriasPorId = <int, String>{};

      if (idsCategorias.isNotEmpty) {
        final respuestaCategorias = await lectura.leer(
          'categoria',
          'id, nombre',
          columnaIds: 'id',
          ids: idsCategorias,
        );

        for (final dato in respuestaCategorias) {
          final id = (dato['id'] as num).toInt();

          categoriasPorId[id] = dato['nombre']?.toString() ?? 'Sin categoría';
        }
      }

      // -------------------------------------------------
      // 5. OBTENER MOTIVOS DE DESCARTE
      // -------------------------------------------------

      final motivosPorId = <int, bool>{};

      final respuestaMotivos = await lectura.leer(
        'tipo_desperdicio',
        'id, es_evitable',
      );

      for (final dato in respuestaMotivos) {
        final id = (dato['id'] as num).toInt();
        final evitable = dato['es_evitable'];

        if (evitable is bool) {
          motivosPorId[id] = evitable;
        }
      }

      // -------------------------------------------------
      // 6. ACUMULADORES HISTÓRICOS
      // -------------------------------------------------

      final resumen = calcularIndicadores(
        itemsPorId: itemsPorId,
        movimientos: movimientos,
        alimentosPorId: alimentosPorId,
        categoriasPorId: categoriasPorId,
        motivosPorId: motivosPorId,
        ahora: DateTime.now(),
      );

      lectura.comprobar();
      if (!await AccesoHogar.verificar(context)) {
        throw StateError('No se pudo confirmar el acceso al hogar.');
      }
      lectura.comprobar();

      // -------------------------------------------------
      // 13. ACTUALIZAR PANTALLA
      // -------------------------------------------------

      setState(() {
        _usuarioDatosId = usuarioId;
        _cantidadConsumos = resumen.cantidadConsumos;
        _cantidadDescartes = resumen.cantidadDescartes;

        _descartesEvitables = resumen.descartesEvitables;
        _descartesNoEvitables = resumen.descartesNoEvitables;
        _descartesSinClasificar = resumen.descartesSinClasificar;

        _descartesConPrecio = resumen.descartesConPrecio;
        _costoDesperdicioConocido = resumen.costoConocido;

        _consumido
          ..clear()
          ..addAll(resumen.consumido);

        _descartado
          ..clear()
          ..addAll(resumen.descartado);

        _alimentosDescartados = resumen.rankingAlimentos;

        // R59
        _cantidadConsumosMes = resumen.cantidadConsumosMes;
        _cantidadDescartesMes = resumen.cantidadDescartesMes;

        _ingresosEvaluadosMes = resumen.ingresosEvaluados;

        _aprovechamientoMes = resumen.aprovechamientoMes;

        _aprovechamientoPorUnidadMes
          ..clear()
          ..addAll(resumen.aprovechamientoPorUnidad);

        // R61
        _categoriasDescartadas = resumen.rankingCategorias;

        _datosParciales = false;

        _cargando = false;
      });
    } on PostgrestException catch (error) {
      if (!vigente()) return;

      setState(() {
        _error = 'No se completó la consulta. Reintenta. ${error.message}';
        _cargando = false;
      });
    } catch (error) {
      if (!vigente()) return;

      setState(() {
        _error = 'No se completó la consulta. Reintenta. $error';
        _cargando = false;
      });
    }
  }

  // =====================================================
  // R63: EXPORTAR INDICADORES A CSV
  // =====================================================

  String _campoCsv(String valor, {bool esNumero = false}) {
    var limpio = valor.replaceAll('\r', ' ').replaceAll('\n', ' ');

    // Evitar fórmulas al abrir nombres en Excel.
    if (!esNumero && RegExp(r'^\s*[=+@\-\t]').hasMatch(limpio)) {
      limpio = "'$limpio";
    }

    return '"${limpio.replaceAll('"', '""')}"';
  }

  String _filaCsv(
    String seccion,
    String indicador,
    String valor, {
    String unidad = '',
    String detalle = '',
    bool esNumero = false,
  }) {
    return [
      _campoCsv(seccion),
      _campoCsv(indicador),
      _campoCsv(valor, esNumero: esNumero),
      _campoCsv(unidad),
      _campoCsv(detalle),
    ].join(';');
  }

  String _fechaExportacion(DateTime fecha) {
    final dia = fecha.day.toString().padLeft(2, '0');
    final mes = fecha.month.toString().padLeft(2, '0');
    final hora = fecha.hour.toString().padLeft(2, '0');
    final minuto = fecha.minute.toString().padLeft(2, '0');

    return '$dia/$mes/${fecha.year} $hora:$minuto';
  }

  Future<void> _exportarCsv() async {
    if (_cargando ||
        _exportando ||
        _error != null ||
        _supabase.auth.currentUser?.id != _usuarioDatosId) {
      return;
    }

    final revision = _revisionCarga;
    final usuarioId = _usuarioDatosId;
    setState(() {
      _exportando = true;
    });

    try {
      final nombreHogar = widget.hogar['nombre']?.toString() ?? 'Hogar';

      final ahora = DateTime.now();

      final filas = <String>[
        'Sección;Indicador;Valor;Unidad;Detalle',

        _filaCsv('Reporte', 'Proyecto', 'NFC-FoodTech'),

        _filaCsv('Reporte', 'Hogar', nombreHogar),

        _filaCsv('Reporte', 'Fecha de exportación', _fechaExportacion(ahora)),

        _filaCsv('Reporte', 'Alcance general', 'Histórico registrado'),

        _filaCsv('Reporte', 'Período de aprovechamiento', _periodoActual()),

        _filaCsv(
          'Reporte',
          'Estado de los datos',
          _datosParciales ? 'Parcial' : 'Sin límite de consulta detectado',
          detalle: _datosParciales
              ? 'Los indicadores pueden estar '
                    'incompletos por el límite de consulta.'
              : 'Calculado con los movimientos '
                    'consultados en Supabase.',
        ),
      ];

      // -----------------------------------------------
      // MOVIMIENTOS HISTÓRICOS
      // -----------------------------------------------

      filas.addAll([
        _filaCsv(
          'Movimientos',
          'Consumos históricos',
          '$_cantidadConsumos',
          unidad: 'eventos',
          esNumero: true,
        ),

        _filaCsv(
          'Movimientos',
          'Descartes históricos',
          '$_cantidadDescartes',
          unidad: 'eventos',
          esNumero: true,
        ),
      ]);

      // -----------------------------------------------
      // CANTIDADES HISTÓRICAS
      // -----------------------------------------------

      for (final unidad in ['g', 'ml', 'un']) {
        filas.add(
          _filaCsv(
            'Cantidad consumida',
            'Total histórico',
            _formatearNumero(_consumido[unidad] ?? 0),
            unidad: unidad,
            esNumero: true,
          ),
        );

        filas.add(
          _filaCsv(
            'Cantidad descartada',
            'Total histórico',
            _formatearNumero(_descartado[unidad] ?? 0),
            unidad: unidad,
            esNumero: true,
          ),
        );
      }

      // -----------------------------------------------
      // R59: APROVECHAMIENTO MENSUAL
      // -----------------------------------------------

      filas.add(
        _filaCsv(
          'Aprovechamiento mensual',
          'Promedio de aprovechamiento',
          _aprovechamientoMes == null
              ? 'Sin datos'
              : _formatearNumero(_aprovechamientoMes!, decimales: 1),
          unidad: '%',
          esNumero: _aprovechamientoMes != null,
          detalle:
              'Promedio simple del porcentaje '
              'consumido de cada ingreso que tuvo '
              'consumos o descartes en el mes.',
        ),
      );

      filas.addAll([
        _filaCsv(
          'Aprovechamiento mensual',
          'Consumos del mes',
          '$_cantidadConsumosMes',
          unidad: 'eventos',
          esNumero: true,
        ),

        _filaCsv(
          'Aprovechamiento mensual',
          'Descartes del mes',
          '$_cantidadDescartesMes',
          unidad: 'eventos',
          esNumero: true,
        ),

        _filaCsv(
          'Aprovechamiento mensual',
          'Ingresos evaluados',
          '$_ingresosEvaluadosMes',
          unidad: 'ingresos',
          esNumero: true,
        ),
      ]);

      for (final unidad in ['g', 'ml', 'un']) {
        final porcentaje = _aprovechamientoPorUnidadMes[unidad];

        filas.add(
          _filaCsv(
            'Aprovechamiento por unidad',
            'Unidad $unidad',
            porcentaje == null
                ? 'Sin datos'
                : _formatearNumero(porcentaje, decimales: 1),
            unidad: '%',
            esNumero: porcentaje != null,
            detalle:
                'Cantidad consumida / '
                '(cantidad consumida + descartada) '
                'para movimientos del mes '
                'en esta misma unidad.',
          ),
        );
      }

      // -----------------------------------------------
      // CLASIFICACIÓN DE DESCARTES
      // -----------------------------------------------

      filas.addAll([
        _filaCsv(
          'Clasificación de descartes',
          'Evitables',
          '$_descartesEvitables',
          unidad: 'eventos',
          esNumero: true,
        ),
        _filaCsv(
          'Clasificación de descartes',
          'No evitables',
          '$_descartesNoEvitables',
          unidad: 'eventos',
          esNumero: true,
        ),
        _filaCsv(
          'Clasificación de descartes',
          'Sin clasificación',
          '$_descartesSinClasificar',
          unidad: 'eventos',
          esNumero: true,
        ),
      ]);

      // -----------------------------------------------
      // COSTO DEL DESPERDICIO
      // -----------------------------------------------

      filas.add(
        _filaCsv(
          'Costo',
          _perdida.titulo,
          _perdida.valorCsv,
          unidad: 'CLP',
          esNumero: _perdida.valorClp != null,
          detalle: _perdida.detalleCsv,
        ),
      );

      filas.add(
        _filaCsv(
          'Costo',
          'Descartes con precio registrado',
          '$_descartesConPrecio',
          unidad: 'eventos',
          esNumero: true,
          detalle: _perdida.cobertura,
        ),
      );

      // -----------------------------------------------
      // R61: RANKING DE CATEGORÍAS
      // -----------------------------------------------

      for (var indice = 0; indice < _categoriasDescartadas.length; indice++) {
        final categoria = _categoriasDescartadas[indice];

        final nombre = categoria['nombre']?.toString() ?? 'Sin categoría';

        final cantidades = categoria['cantidades'] as Map<String, double>;

        filas.add(
          _filaCsv(
            'Ranking de categorías',
            '${indice + 1}. $nombre',
            '${categoria['eventos']}',
            unidad: 'eventos',
            esNumero: true,
            detalle:
                'Posición según frecuencia '
                'histórica de descartes.',
          ),
        );

        for (final unidad in ['g', 'ml', 'un']) {
          final cantidad = cantidades[unidad] ?? 0;

          if (cantidad <= 0) continue;

          filas.add(
            _filaCsv(
              'Categoría: $nombre',
              'Cantidad descartada',
              _formatearNumero(cantidad),
              unidad: unidad,
              esNumero: true,
            ),
          );
        }
      }

      // -----------------------------------------------
      // RANKING EXISTENTE POR ALIMENTO
      // -----------------------------------------------

      for (final alimento in _alimentosDescartados) {
        final nombre = alimento['nombre']?.toString() ?? 'Alimento';

        final unidad = alimento['unidad']?.toString() ?? '';

        final cantidad = _numero(alimento['cantidad']);

        final eventos = alimento['eventos']?.toString() ?? '0';

        filas.add(
          _filaCsv(
            'Alimentos descartados',
            nombre,
            _formatearNumero(cantidad),
            unidad: unidad,
            esNumero: true,
            detalle: '$eventos evento(s) de descarte',
          ),
        );
      }

      // -----------------------------------------------
      // GUARDAR CSV
      // -----------------------------------------------

      final csv = '${filas.join('\r\n')}\r\n';

      final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)]);

      final fechaArchivo =
          '${ahora.year}'
          '${ahora.month.toString().padLeft(2, '0')}'
          '${ahora.day.toString().padLeft(2, '0')}_'
          '${ahora.hour.toString().padLeft(2, '0')}'
          '${ahora.minute.toString().padLeft(2, '0')}';

      if (!await AccesoHogar.verificar(context) || !mounted) return;
      if (revision != _revisionCarga ||
          _supabase.auth.currentUser?.id != usuarioId ||
          _error != null)
        return;
      final ubicacion = await FileSaver.instance.saveAs(
        name: 'NFC_FoodTech_indicadores_$fechaArchivo',
        bytes: bytes,
        fileExtension: 'csv',
        mimeType: MimeType.csv,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ubicacion == null
                ? 'Se canceló la exportación.'
                : 'Reporte CSV guardado correctamente.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo exportar el CSV: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _exportando = false;
        });
      }
    }
  }

  // =====================================================
  // COMPONENTES DE LA PANTALLA
  // =====================================================

  Widget _tarjetaResumen(
    String titulo,
    String valor,
    IconData icono,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _colorSuperficie,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _colorBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: color),

          const SizedBox(height: 10),

          Text(
            valor,
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),

          const SizedBox(height: 5),

          Text(
            titulo,
            style: TextStyle(fontSize: 12, color: _colorTextoSecundario),
          ),
        ],
      ),
    );
  }

  Widget _tituloSeccion(String texto) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 12),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: _colorAcento,
        ),
      ),
    );
  }

  Widget _filaCantidad(String titulo, double cantidad, String unidad) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(child: Text(titulo)),

          Text(
            _cantidadTexto(cantidad, unidad),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _seccionCantidades(String titulo, Map<String, double> cantidades) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _tituloSeccion(titulo),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _colorSuperficie,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _colorBorde),
          ),
          child: Column(
            children: [
              _filaCantidad(
                'Alimentos medidos en peso',
                cantidades['g'] ?? 0,
                'g',
              ),

              const Divider(),

              _filaCantidad(
                'Alimentos medidos en volumen',
                cantidades['ml'] ?? 0,
                'ml',
              ),

              const Divider(),

              _filaCantidad(
                'Alimentos medidos en unidades',
                cantidades['un'] ?? 0,
                'un',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _filaDato(String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(child: Text(etiqueta)),

          Text(valor, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // =====================================================
  // R59: TARJETA APROVECHAMIENTO MENSUAL
  // =====================================================

  Widget _seccionAprovechamiento() {
    final porcentaje = _aprovechamientoMes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _tituloSeccion('Aprovechamiento de ${_periodoActual()}'),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _colorSuperficie,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _colorBorde),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Promedio de aprovechamiento',
                style: TextStyle(color: _colorTextoSecundario),
              ),

              const SizedBox(height: 8),

              Text(
                _porcentajeTexto(porcentaje),
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: _colorAcento,
                ),
              ),

              const SizedBox(height: 12),

              LinearProgressIndicator(
                value: porcentaje == null
                    ? 0
                    : (porcentaje / 100).clamp(0.0, 1.0),
                minHeight: 10,
                backgroundColor: _colorPista,
                color: _colorAcento,
                borderRadius: BorderRadius.circular(8),
              ),

              const SizedBox(height: 14),

              Text(
                '$_ingresosEvaluadosMes ingreso(s) '
                'con consumos o descartes este mes.',
                style: const TextStyle(fontSize: 13),
              ),

              const SizedBox(height: 5),

              Text(
                '$_cantidadConsumosMes consumo(s) · '
                '$_cantidadDescartesMes descarte(s)',
                style: const TextStyle(fontSize: 13),
              ),

              const SizedBox(height: 14),

              const Divider(),

              const Text(
                'Aprovechamiento por unidad',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 8),

              _filaDato(
                'Productos medidos en g',
                _porcentajeTexto(_aprovechamientoPorUnidadMes['g']),
              ),

              const Divider(),

              _filaDato(
                'Productos medidos en ml',
                _porcentajeTexto(_aprovechamientoPorUnidadMes['ml']),
              ),

              const Divider(),

              _filaDato(
                'Productos medidos en un',
                _porcentajeTexto(_aprovechamientoPorUnidadMes['un']),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        Text(
          'Método: para cada ingreso con movimientos '
          'del mes, se calcula cantidad consumida / '
          '(cantidad consumida + cantidad descartada). '
          'El indicador general es el promedio simple '
          'de esos porcentajes. Cada ingreso tiene el '
          'mismo peso en el promedio, independientemente '
          'de su cantidad o unidad de medida.',
          style: TextStyle(fontSize: 12, color: _colorTextoSecundario),
        ),

        const SizedBox(height: 6),

        Text(
          'Solo considera movimientos registrados. '
          'No incluye las cantidades que siguen '
          'disponibles ni permite estimar consumos '
          'que no fueron informados.',
          style: TextStyle(fontSize: 12, color: _colorTextoSecundario),
        ),
      ],
    );
  }

  // =====================================================
  // CLASIFICACIÓN HISTÓRICA
  // =====================================================

  Widget _seccionClasificacion() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _tituloSeccion('Clasificación de descartes'),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _colorSuperficie,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _colorBorde),
          ),
          child: Column(
            children: [
              _filaDato('Descartes evitables', '$_descartesEvitables'),

              const Divider(),

              _filaDato('Descartes no evitables', '$_descartesNoEvitables'),

              const Divider(),

              _filaDato('Sin clasificación', '$_descartesSinClasificar'),
            ],
          ),
        ),

        const SizedBox(height: 8),

        Text(
          'Estos valores indican eventos de descarte, '
          'no cantidades totales de alimentos.',
          style: TextStyle(fontSize: 12, color: _colorTextoSecundario),
        ),
      ],
    );
  }

  // =====================================================
  // PÉRDIDA ECONÓMICA EXISTENTE
  // =====================================================

  Widget _seccionCosto() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _tituloSeccion(_perdida.titulo),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _colorSuperficie,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _colorBorde),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _perdida.sinPrecios
                    ? 'Sin datos de precio'
                    : _dinero(_costoDesperdicioConocido),
                style: TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.bold,
                  color: _colorAcento,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                _perdida.cobertura,
                style: TextStyle(fontSize: 13, color: _colorTextoSecundario),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        Text(
          PresentacionPerdidaEconomica.criterioValoracion,
          style: TextStyle(fontSize: 12, color: _colorTextoSecundario),
        ),
      ],
    );
  }

  // =====================================================
  // R61: RANKING POR CATEGORÍAS
  // =====================================================

  Widget _seccionCategorias() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _tituloSeccion('Categorías con más descartes'),

        if (_categoriasDescartadas.isEmpty)
          Text(
            'Todavía no hay descartes registrados '
            'para calcular el ranking por categoría.',
            style: TextStyle(color: _colorTextoSecundario),
          )
        else
          ..._categoriasDescartadas.take(10).toList().asMap().entries.map((
            entrada,
          ) {
            final posicion = entrada.key + 1;
            final categoria = entrada.value;

            final nombre = categoria['nombre']?.toString() ?? 'Sin categoría';

            final eventos = categoria['eventos'] as int;

            final cantidades = categoria['cantidades'] as Map<String, double>;

            final partes = <String>[];

            for (final unidad in ['g', 'ml', 'un']) {
              final cantidad = cantidades[unidad] ?? 0;

              if (cantidad <= 0) continue;

              partes.add(_cantidadTexto(cantidad, unidad));
            }

            final descripcionCantidades = partes.isEmpty
                ? 'Sin cantidades'
                : partes.join(' · ');

            return Card(
              color: _colorSuperficie,
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: _colorBorde),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: _modoOscuro
                      ? Theme.of(context).colorScheme.surfaceContainerHighest
                      : const Color(0xFFFFEFE8),
                  child: Text(
                    '$posicion',
                    style: TextStyle(
                      color: _colorDescarte,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(
                  nombre,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '$eventos descarte(s)\n'
                  '$descripcionCantidades',
                ),
                isThreeLine: true,
                trailing: Icon(Icons.bar_chart_outlined, color: _colorDescarte),
              ),
            );
          }),

        const SizedBox(height: 8),

        Text(
          'Ranking histórico ordenado por número '
          'de eventos de descarte. Las cantidades '
          'se muestran por separado según su '
          'unidad de medida.',
          style: TextStyle(fontSize: 12, color: _colorTextoSecundario),
        ),
      ],
    );
  }

  // =====================================================
  // RANKING EXISTENTE POR ALIMENTO
  // =====================================================

  Widget _seccionAlimentos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _tituloSeccion('Alimentos con descartes'),

        if (_alimentosDescartados.isEmpty)
          Text(
            'Todavía no hay descartes registrados.',
            style: TextStyle(color: _colorTextoSecundario),
          )
        else
          ..._alimentosDescartados.take(10).map((alimento) {
            final nombre = alimento['nombre'].toString();

            final unidad = alimento['unidad'].toString();

            final cantidad = _numero(alimento['cantidad']);

            final eventos = alimento['eventos'] as int;

            return Card(
              color: _colorSuperficie,
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: _modoOscuro
                      ? Theme.of(context).colorScheme.surfaceContainerHighest
                      : const Color(0xFFFFEFE8),
                  child: Icon(Icons.delete_outline, color: _colorDescarte),
                ),
                title: Text(
                  nombre,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text('$eventos descarte(s)'),
                trailing: Text(
                  _cantidadTexto(cantidad, unidad),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _colorDescarte,
                  ),
                ),
              ),
            );
          }),

        const SizedBox(height: 8),

        Text(
          'Ordenado por número de descartes. '
          'Las cantidades mantienen la unidad '
          'correspondiente a cada alimento.',
          style: TextStyle(fontSize: 12, color: _colorTextoSecundario),
        ),
      ],
    );
  }

  // =====================================================
  // PANTALLA PRINCIPAL
  // =====================================================

  @override
  Widget build(BuildContext context) {
    final nombreHogar = widget.hogar['nombre']?.toString() ?? 'Hogar';

    return Scaffold(
      backgroundColor: _colorFondo,
      appBar: AppBar(
        leading: Navigator.of(context).canPop()
            ? null
            : AccesoHogar.botonVolver(context),
        backgroundColor: verde,
        foregroundColor: Colors.white,
        title: const Text('Indicadores del hogar'),
        actions: [
          // EXPORTAR CSV
          IconButton(
            tooltip: 'Exportar reporte CSV',
            onPressed: (_cargando || _exportando || _error != null)
                ? null
                : _exportarCsv,
            icon: const Icon(Icons.file_download_outlined),
          ),

          // RECOMENDACIONES
          IconButton(
            tooltip: 'Ver recomendaciones',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => RecomendacionesScreen(hogar: widget.hogar),
                ),
              );
            },
            icon: const Icon(Icons.lightbulb_outline),
          ),

          // COMPARATIVA MENSUAL
          IconButton(
            tooltip: 'Comparativa mensual',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ComparativaMensualScreen(hogar: widget.hogar),
                ),
              );
            },
            icon: const Icon(Icons.calendar_month_outlined),
          ),

          // ACTUALIZAR
          IconButton(
            tooltip: 'Actualizar indicadores',
            onPressed: _cargando ? null : _cargarIndicadores,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, color: _colorError, size: 42),

                    const SizedBox(height: 12),

                    Text(
                      'No se pudieron cargar '
                      'los indicadores.\n$_error',
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 12),

                    ElevatedButton(
                      onPressed: _cargarIndicadores,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Hogar: $nombreHogar',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _colorAcento,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  'Resumen histórico de los '
                  'movimientos registrados.',
                  style: TextStyle(color: _colorTextoSecundario),
                ),

                if (_datosParciales) ...[
                  const SizedBox(height: 12),

                  Text(
                    'Atención: se alcanzó el '
                    'límite de consulta. '
                    'Los indicadores pueden '
                    'estar incompletos.',
                    style: TextStyle(
                      color: _colorAdvertencia,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                // EXPORTAR CSV
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _exportando ? null : _exportarCsv,
                    icon: _exportando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_outlined),
                    label: Text(
                      _exportando
                          ? 'Exportando reporte...'
                          : 'Exportar indicadores a CSV',
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                // RESUMEN HISTÓRICO
                Row(
                  children: [
                    Expanded(
                      child: _tarjetaResumen(
                        'Movimientos de consumo',
                        '$_cantidadConsumos',
                        Icons.restaurant_outlined,
                        _colorConsumo,
                      ),
                    ),

                    const SizedBox(width: 10),

                    Expanded(
                      child: _tarjetaResumen(
                        'Movimientos de descarte',
                        '$_cantidadDescartes',
                        Icons.delete_outline,
                        _colorDescarte,
                      ),
                    ),
                  ],
                ),

                // R59
                _seccionAprovechamiento(),

                // INDICADORES EXISTENTES
                _seccionCantidades('Cantidad consumida', _consumido),

                _seccionCantidades('Cantidad descartada', _descartado),

                _seccionClasificacion(),

                _seccionCosto(),

                // R61
                _seccionCategorias(),

                // RANKING POR ALIMENTOS
                _seccionAlimentos(),

                const SizedBox(height: 20),
              ],
            ),
    );
  }
}
