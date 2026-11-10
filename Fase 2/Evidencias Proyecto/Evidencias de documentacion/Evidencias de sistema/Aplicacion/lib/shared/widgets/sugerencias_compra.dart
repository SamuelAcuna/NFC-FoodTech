import 'package:supabase_flutter/supabase_flutter.dart';

const periodoHistorialSugerencias = 30;
const diasReposicionSugerencias = 7;
const minimoDiasConsumoSugerencias = 2;

class SugerenciaCompra {
  final int alimentoId;
  final String nombre;
  final String unidadBase;
  final int diasConsumo;
  final double consumido;
  final double disponible;
  final double objetivo;
  final double sugerido;

  const SugerenciaCompra({
    required this.alimentoId,
    required this.nombre,
    required this.unidadBase,
    required this.diasConsumo,
    required this.consumido,
    required this.disponible,
    required this.objetivo,
    required this.sugerido,
  });

  double get diasCobertura =>
      disponible / (consumido / periodoHistorialSugerencias);
}

class ResultadoSugerenciasCompra {
  final List<SugerenciaCompra> sugerencias;
  final Set<int> pendientes;
  final int registrosInvalidos;

  const ResultadoSugerenciasCompra({
    required this.sugerencias,
    required this.pendientes,
    this.registrosInvalidos = 0,
  });
}

double? _numero(dynamic valor) {
  final numero = double.tryParse(valor?.toString() ?? '');
  return numero != null && numero.isFinite ? numero : null;
}

int? _id(dynamic valor) => int.tryParse(valor?.toString() ?? '');

int compararSugerenciasCompra(SugerenciaCompra a, SugerenciaCompra b) {
  final cobertura = a.diasCobertura.compareTo(b.diasCobertura);
  if (cobertura != 0) return cobertura;
  final nombre = a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
  return nombre != 0 ? nombre : a.alimentoId.compareTo(b.alimentoId);
}

ResultadoSugerenciasCompra calcularSugerenciasCompra({
  required String hogarId,
  required DateTime ahora,
  required List<Map<String, dynamic>> items,
  required List<Map<String, dynamic>> movimientos,
  required List<Map<String, dynamic>> alimentos,
  required List<Map<String, dynamic>> itemsLista,
}) {
  final fin = ahora.toUtc();
  final inicio = fin.subtract(
    const Duration(days: periodoHistorialSugerencias),
  );
  final itemsPorId = <String, Map<String, dynamic>>{};
  final alimentosPorId = <int, Map<String, dynamic>>{};
  final existencias = <int, double>{};
  final stockInvalido = <int>{};
  var invalidos = 0;

  for (final alimento in alimentos) {
    final id = _id(alimento['id']);
    if (id == null ||
        alimento['activo'] != true ||
        (alimento['hogar_id'] != null &&
            alimento['hogar_id'].toString() != hogarId) ||
        !['g', 'ml', 'un'].contains(alimento['unidad_base'])) {
      continue;
    }
    alimentosPorId[id] = alimento;
  }

  for (final item in items) {
    if (item['hogar_id']?.toString() != hogarId) continue;
    final id = item['id']?.toString() ?? '';
    final alimentoId = _id(item['alimento_id']);
    if (id.isEmpty || alimentoId == null) {
      invalidos++;
      continue;
    }
    itemsPorId.putIfAbsent(id, () => item);
  }

  for (final item in itemsPorId.values) {
    if (item['estado'] != 'DISPONIBLE') continue;
    final alimentoId = _id(item['alimento_id'])!;
    final restante = _numero(item['cantidad_restante']);
    if (restante == null || restante < 0) {
      stockInvalido.add(alimentoId);
      invalidos++;
    } else {
      existencias[alimentoId] = (existencias[alimentoId] ?? 0) + restante;
    }
  }

  final pendientes = itemsLista
      .where((item) => item['estado'] == 'PENDIENTE')
      .map((item) => _id(item['alimento_id']))
      .whereType<int>()
      .toSet();
  final cantidades = <int, double>{};
  final dias = <int, Set<DateTime>>{};
  final movimientosVistos = <String>{};

  for (final movimiento in movimientos) {
    if (movimiento['tipo'] != 'CONSUMO') continue;
    final item = itemsPorId[movimiento['despensa_item_id']?.toString()];
    if (item == null) continue;
    final cantidad = _numero(movimiento['cantidad']);
    final fecha = DateTime.tryParse(movimiento['fecha']?.toString() ?? '');
    final id = movimiento['id']?.toString() ?? '';
    if (cantidad == null || cantidad <= 0 || fecha == null || id.isEmpty) {
      invalidos++;
      continue;
    }
    if (fecha.isBefore(inicio) ||
        fecha.isAfter(fin) ||
        !movimientosVistos.add(id))
      continue;

    final alimentoId = _id(item['alimento_id'])!;
    // movimiento.cantidad ya está expresada en la unidad base del ingreso.
    cantidades[alimentoId] = (cantidades[alimentoId] ?? 0) + cantidad;
    final local = fecha.toLocal();
    dias
        .putIfAbsent(alimentoId, () => <DateTime>{})
        .add(DateTime(local.year, local.month, local.day));
  }

  final sugerencias = <SugerenciaCompra>[];
  for (final entrada in cantidades.entries) {
    final id = entrada.key;
    final alimento = alimentosPorId[id];
    final consumo = entrada.value;
    final stock = existencias[id] ?? 0;
    if (alimento == null ||
        pendientes.contains(id) ||
        stockInvalido.contains(id) ||
        (dias[id]?.length ?? 0) < minimoDiasConsumoSugerencias)
      continue;
    if (!consumo.isFinite || !stock.isFinite) {
      invalidos++;
      continue;
    }

    final objetivo =
        consumo * (diasReposicionSugerencias / periodoHistorialSugerencias);
    final cantidad = objetivo - stock;
    if (!cantidad.isFinite || cantidad <= 0) continue;
    final sugerido = double.parse(cantidad.toStringAsFixed(3));
    if (sugerido <= 0 || sugerido > 9999999.999) continue;

    sugerencias.add(
      SugerenciaCompra(
        alimentoId: id,
        nombre: alimento['nombre']?.toString() ?? 'Alimento #$id',
        unidadBase: alimento['unidad_base'].toString(),
        diasConsumo: dias[id]!.length,
        consumido: consumo,
        disponible: stock,
        objetivo: objetivo,
        sugerido: sugerido,
      ),
    );
  }
  sugerencias.sort(compararSugerenciasCompra);
  return ResultadoSugerenciasCompra(
    sugerencias: sugerencias,
    pendientes: pendientes,
    registrosInvalidos: invalidos,
  );
}

Future<void> validarListaSugerenciasCompra({
  required SupabaseClient supabase,
  required String hogarId,
  required String listaId,
}) async {
  if (hogarId.isEmpty || listaId.isEmpty)
    throw StateError('Faltan datos del hogar o de la lista.');
  final lista = await supabase
      .from('lista_compra')
      .select('id, hogar_id, estado')
      .eq('id', listaId)
      .eq('hogar_id', hogarId)
      .eq('estado', 'ABIERTA')
      .maybeSingle()
      .timeout(const Duration(seconds: 8));
  if (lista == null ||
      lista['id']?.toString() != listaId ||
      lista['hogar_id']?.toString() != hogarId ||
      lista['estado'] != 'ABIERTA') {
    throw StateError(
      'La lista ya no está disponible para este hogar o fue cerrada.',
    );
  }
}

Future<bool> existePendienteSugerido({
  required SupabaseClient supabase,
  required String listaId,
  required int alimentoId,
}) async {
  final filas = await supabase
      .from('lista_compra_item')
      .select('id')
      .eq('lista_id', listaId)
      .eq('alimento_id', alimentoId)
      .eq('estado', 'PENDIENTE')
      .limit(1)
      .timeout(const Duration(seconds: 8));
  return filas.isNotEmpty;
}

Future<ResultadoSugerenciasCompra> consultarSugerenciasCompra({
  required SupabaseClient supabase,
  required String hogarId,
  required String listaId,
  int? alimentoId,
  DateTime? ahora,
}) async {
  final fin = (ahora ?? DateTime.now()).toUtc();
  final inicio = fin.subtract(
    const Duration(days: periodoHistorialSugerencias),
  );
  await validarListaSugerenciasCompra(
    supabase: supabase,
    hogarId: hogarId,
    listaId: listaId,
  );
  const pagina = 400;
  const espera = Duration(seconds: 8);
  final items = <Map<String, dynamic>>[];
  final movimientos = <Map<String, dynamic>>[];
  final alimentos = <Map<String, dynamic>>[];
  final pendientes = <Map<String, dynamic>>[];

  for (var desde = 0; ; desde += pagina) {
    var consulta = supabase
        .from('despensa_item')
        .select('id, hogar_id, alimento_id, estado, cantidad_restante')
        .eq('hogar_id', hogarId);
    if (alimentoId != null) consulta = consulta.eq('alimento_id', alimentoId);
    final filas = await consulta
        .order('id')
        .range(desde, desde + pagina - 1)
        .timeout(espera);
    items.addAll(filas);
    if (filas.length < pagina) break;
  }

  for (var desde = 0; ; desde += pagina) {
    var consulta = supabase
        .from('lista_compra_item')
        .select('id, alimento_id, estado')
        .eq('lista_id', listaId)
        .eq('estado', 'PENDIENTE');
    if (alimentoId != null) consulta = consulta.eq('alimento_id', alimentoId);
    final filas = await consulta
        .order('id')
        .range(desde, desde + pagina - 1)
        .timeout(espera);
    pendientes.addAll(filas);
    if (filas.length < pagina) break;
  }

  final idsItems = items
      .where((item) => item['hogar_id']?.toString() == hogarId)
      .map((item) => item['id']?.toString())
      .whereType<String>()
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList();
  for (var desde = 0; desde < idsItems.length; desde += 80) {
    final finLote = desde + 80 < idsItems.length ? desde + 80 : idsItems.length;
    for (var posicion = 0; ; posicion += pagina) {
      final filas = await supabase
          .from('movimiento')
          .select('id, despensa_item_id, tipo, cantidad, fecha')
          .inFilter('despensa_item_id', idsItems.sublist(desde, finLote))
          .eq('tipo', 'CONSUMO')
          .gte('fecha', inicio.toIso8601String())
          .lte('fecha', fin.toIso8601String())
          .order('fecha', ascending: false)
          .order('id', ascending: false)
          .range(posicion, posicion + pagina - 1)
          .timeout(espera);
      movimientos.addAll(filas);
      if (filas.length < pagina) break;
    }
  }

  final idsAlimentos = items
      .where((item) => item['hogar_id']?.toString() == hogarId)
      .map((item) => _id(item['alimento_id']))
      .whereType<int>()
      .toSet()
      .toList();
  for (var desde = 0; desde < idsAlimentos.length; desde += 100) {
    final finLote = desde + 100 < idsAlimentos.length
        ? desde + 100
        : idsAlimentos.length;
    final filas = await supabase
        .from('alimento')
        .select('id, nombre, unidad_base, hogar_id, activo')
        .inFilter('id', idsAlimentos.sublist(desde, finLote))
        .timeout(espera);
    alimentos.addAll(filas);
  }

  return calcularSugerenciasCompra(
    hogarId: hogarId,
    ahora: fin,
    items: items,
    movimientos: movimientos,
    alimentos: alimentos,
    itemsLista: pendientes,
  );
}
