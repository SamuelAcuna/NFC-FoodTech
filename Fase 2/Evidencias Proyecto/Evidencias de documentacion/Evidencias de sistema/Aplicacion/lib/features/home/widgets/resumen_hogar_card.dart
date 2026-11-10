import 'package:flutter/material.dart';
import 'package:nfc_foodtech_app/features/home/models/resumen_hogar.dart';
import 'package:nfc_foodtech_app/shared/models/resumen_indicadores.dart';

class ResumenHogarCard extends StatelessWidget {
  final List<MesResumenHogar>? meses;
  final bool cargando;
  final bool error;
  final VoidCallback onReintentar;
  final VoidCallback? onAnalisis;

  const ResumenHogarCard({
    super.key,
    required this.meses,
    required this.cargando,
    required this.error,
    required this.onReintentar,
    this.onAnalisis,
  });

  String _clp(int valor) =>
      '\$${valor.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.')} CLP';

  String _mes(DateTime fecha) {
    const nombres = [
      'ene',
      'feb',
      'mar',
      'abr',
      'may',
      'jun',
      'jul',
      'ago',
      'sep',
      'oct',
      'nov',
      'dic',
    ];
    return '${nombres[fecha.month - 1]} ${fecha.year}';
  }

  Widget _indicador(
    BuildContext context, {
    required String clave,
    required String titulo,
    required String valor,
    required String detalle,
  }) {
    final esquema = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey(clave),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: esquema.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: esquema.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            valor,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: esquema.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(detalle, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lista = meses;
    final actual = lista?.last.perdida;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Resumen de tu hogar',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (cargando)
              const LinearProgressIndicator()
            else if (error) ...[
              const Text('No se pudo cargar el resumen económico.'),
              TextButton(
                onPressed: onReintentar,
                child: const Text('Reintentar análisis'),
              ),
            ] else if (actual == null)
              const Text('Crea un hogar o únete para ver su resumen.')
            else ...[
              Text('Mes actual · ${_mes(lista!.last.mes)}'),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final perdida = _indicador(
                    context,
                    clave: 'perdida-hogar',
                    titulo: 'Pérdida económica estimada',
                    valor: actual.valorClp == null
                        ? 'Sin datos de precio'
                        : _clp(actual.valorClp!),
                    detalle:
                        '${actual.parcial ? 'Subtotal conocido. ' : ''}${actual.cobertura}',
                  );
                  final desperdicio = _indicador(
                    context,
                    clave: 'porcentaje-desperdicio-hogar',
                    titulo: 'Porcentaje de desperdicio',
                    valor: 'Sin datos suficientes',
                    detalle:
                        'No hay un porcentaje mensual de desperdicio del hogar definido en Indicadores.',
                  );
                  final horizontal =
                      constraints.maxWidth >= 340 &&
                      MediaQuery.textScalerOf(context).scale(14) <= 17;
                  return horizontal
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: perdida),
                            const SizedBox(width: 12),
                            Expanded(child: desperdicio),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            perdida,
                            const SizedBox(height: 12),
                            desperdicio,
                          ],
                        );
                },
              ),
              const SizedBox(height: 8),
              Text(
                PresentacionPerdidaEconomica.criterioValoracion,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            TextButton.icon(
              onPressed: onAnalisis,
              icon: const Icon(Icons.bar_chart),
              label: const Text('Ver análisis completo'),
            ),
          ],
        ),
      ),
    );
  }
}
