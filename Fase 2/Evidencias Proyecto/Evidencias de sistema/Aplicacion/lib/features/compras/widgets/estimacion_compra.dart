import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:nfc_foodtech_app/features/compras/widgets/advertencia_stock.dart';

class EstimacionProducto {
  final int importeClp;
  final DateTime fechaReferencia;

  const EstimacionProducto({
    required this.importeClp,
    required this.fechaReferencia,
  });
}

class EstimacionGasto {
  final Map<String, EstimacionProducto> porItem;
  final int pendientes;

  const EstimacionGasto({required this.porItem, required this.pendientes});

  int get sinEstimacion => pendientes - porItem.length;

  int? get totalConocido => porItem.isEmpty
      ? null
      : porItem.values.fold<int>(0, (total, item) => total + item.importeClp);
}

class _ReferenciaCompra {
  final String id;
  final DateTime fecha;
  final double cantidadBase;
  final double precioTotal;

  const _ReferenciaCompra(
    this.id,
    this.fecha,
    this.cantidadBase,
    this.precioTotal,
  );
}

int? _idAlimento(dynamic valor) => int.tryParse(valor?.toString() ?? '');

EstimacionGasto calcularEstimacionCompra({
  required String hogarId,
  required List<Map<String, dynamic>> items,
  required Map<int, String> unidadesBase,
  required Iterable<Map<String, dynamic>> compras,
}) {
  final referencias = <int, _ReferenciaCompra>{};

  for (final compra in compras) {
    if (compra['hogar_id']?.toString() != hogarId ||
        compra['estado'] != 'COMPRADO' ||
        (compra['despensa_item_id']?.toString() ?? '').isEmpty) {
      continue;
    }

    final alimentoId = _idAlimento(compra['alimento_id']);
    final base = unidadesBase[alimentoId];
    if (alimentoId == null || base == null) continue;

    final cantidadBase = cantidadCompraEnBase(
      compra['cantidad'],
      compra['unidad']?.toString() ?? '',
      base,
    );
    final precio = double.tryParse(
      compra['precio_compra_clp']?.toString() ?? '',
    );
    final fecha = DateTime.tryParse(compra['fecha_compra']?.toString() ?? '');
    final id = compra['id']?.toString() ?? '';

    if (cantidadBase == null ||
        precio == null ||
        !precio.isFinite ||
        precio < 0 ||
        precio > 2147483647 ||
        precio != precio.roundToDouble() ||
        fecha == null ||
        id.isEmpty) {
      continue;
    }

    final anterior = referencias[alimentoId];
    if (anterior == null ||
        fecha.isAfter(anterior.fecha) ||
        (fecha.isAtSameMomentAs(anterior.fecha) &&
            id.compareTo(anterior.id) > 0)) {
      referencias[alimentoId] = _ReferenciaCompra(
        id,
        fecha,
        cantidadBase,
        precio,
      );
    }
  }

  final pendientes = items
      .where((item) => item['estado'] == 'PENDIENTE')
      .toList();
  final estimaciones = <String, EstimacionProducto>{};

  for (final item in pendientes) {
    final id = item['id']?.toString() ?? '';
    final alimentoId = _idAlimento(item['alimento_id']);
    final base = unidadesBase[alimentoId];
    final referencia = referencias[alimentoId];
    if (id.isEmpty || base == null || referencia == null) continue;

    final cantidadBase = cantidadCompraEnBase(
      item['cantidad'],
      item['unidad']?.toString() ?? '',
      base,
    );
    if (cantidadBase == null) continue;

    // El precio histórico es el total de la cantidad comprada, no un precio unitario.
    final importe =
        referencia.precioTotal * (cantidadBase / referencia.cantidadBase);
    if (!importe.isFinite || importe < 0 || importe > 9007199254740991)
      continue;

    estimaciones[id] = EstimacionProducto(
      importeClp: importe.round(),
      fechaReferencia: referencia.fecha,
    );
  }

  return EstimacionGasto(porItem: estimaciones, pendientes: pendientes.length);
}

Future<EstimacionGasto> consultarEstimacionCompra({
  required SupabaseClient supabase,
  required String hogarId,
  required List<Map<String, dynamic>> items,
  required Map<int, String> unidadesBase,
}) async {
  final ids = items
      .where((item) => item['estado'] == 'PENDIENTE')
      .map((item) => _idAlimento(item['alimento_id']))
      .whereType<int>()
      .where(unidadesBase.containsKey)
      .toSet()
      .toList();
  final compras = <Map<String, dynamic>>[];
  if (hogarId.isEmpty) throw StateError('No hay un hogar seleccionado.');

  const loteAlimentos = 100;
  const paginaListas = 100;
  const paginaCompras = 400;

  for (var inicio = 0; inicio < ids.length; inicio += loteAlimentos) {
    final fin = inicio + loteAlimentos < ids.length
        ? inicio + loteAlimentos
        : ids.length;
    final lote = ids.sublist(inicio, fin);
    var desdeLista = 0;

    while (true) {
      // La relación con lista_compra limita todas las referencias al mismo hogar.
      Future<List<Map<String, dynamic>>> consultarPagina(
        int desdeCompra, {
        List<String>? listas,
      }) async {
        var consulta = supabase
            .from('lista_compra')
            .select(
              'id, hogar_id, lista_compra_item('
              'id, alimento_id, cantidad, unidad, estado, '
              'despensa_item_id, fecha_compra, precio_compra_clp)',
            )
            .eq('hogar_id', hogarId)
            .eq('lista_compra_item.estado', 'COMPRADO')
            .inFilter('lista_compra_item.alimento_id', lote);
        if (listas != null) consulta = consulta.inFilter('id', listas);

        return await consulta
            .order('id')
            .order(
              'fecha_compra',
              referencedTable: 'lista_compra_item',
              ascending: false,
            )
            .order('id', referencedTable: 'lista_compra_item', ascending: false)
            .range(
              listas == null ? desdeLista : 0,
              listas == null
                  ? desdeLista + paginaListas - 1
                  : listas.length - 1,
            )
            .range(
              desdeCompra,
              desdeCompra + paginaCompras - 1,
              referencedTable: 'lista_compra_item',
            )
            .timeout(const Duration(seconds: 8));
      }

      var respuesta = await consultarPagina(0);
      final cantidadListas = respuesta.length;
      var desdeCompra = 0;

      while (true) {
        final siguientes = <String>[];
        for (final lista in respuesta) {
          if (lista['hogar_id']?.toString() != hogarId) continue;
          final historial = lista['lista_compra_item'];
          if (historial is! List)
            throw StateError('El historial llegó incompleto.');

          for (final compra in historial) {
            if (compra is! Map)
              throw StateError('La compra histórica no es válida.');
            compras.add({
              ...Map<String, dynamic>.from(compra),
              'hogar_id': hogarId,
            });
          }
          if (historial.length == paginaCompras) {
            siguientes.add(lista['id'].toString());
          }
        }

        if (siguientes.isEmpty) break;
        desdeCompra += paginaCompras;
        respuesta = await consultarPagina(desdeCompra, listas: siguientes);
      }

      if (cantidadListas < paginaListas) break;
      desdeLista += paginaListas;
    }
  }

  return calcularEstimacionCompra(
    hogarId: hogarId,
    items: items,
    unidadesBase: unidadesBase,
    compras: compras,
  );
}

String dineroEstimadoCompra(int importe) =>
    '\$${importe.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.')}';

String fechaReferenciaCompra(DateTime fecha) {
  final local = fecha.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/${local.year}';
}

class ResumenEstimacionCompra extends StatelessWidget {
  final EstimacionGasto? estimacion;
  final bool cargando;
  final bool error;

  const ResumenEstimacionCompra({
    super.key,
    required this.estimacion,
    this.cargando = false,
    this.error = false,
  });

  @override
  Widget build(BuildContext context) {
    final datos = estimacion;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Total estimado conocido',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            if (cargando)
              const Text('Calculando estimación...')
            else if (error)
              const Text(
                'Estimación no disponible. Puedes seguir comprando y actualizar la lista para reintentar.',
              )
            else if (datos != null && datos.pendientes == 0)
              const Text('No hay productos pendientes.')
            else ...[
              Text(
                datos?.totalConocido == null
                    ? 'Sin estimación'
                    : dineroEstimadoCompra(datos!.totalConocido!),
              ),
              Text('${datos?.sinEstimacion ?? 0} producto(s) sin estimación.'),
              const Text('Referencia histórica; el precio final puede variar.'),
            ],
          ],
        ),
      ),
    );
  }
}
