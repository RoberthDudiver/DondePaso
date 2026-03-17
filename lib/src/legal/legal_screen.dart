import 'package:flutter/material.dart';

import '../i18n/app_strings.dart';

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final sections = _sections(strings);

    return Scaffold(
      appBar: AppBar(title: Text(strings.legal)),
      body: ListView.separated(
        padding: const EdgeInsets.all(18),
        itemBuilder: (context, index) {
          final section = sections[index];
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                for (final paragraph in section.body)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      paragraph,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.4,
                        color: Colors.white.withValues(alpha: 0.84),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
        separatorBuilder: (_, _) => const SizedBox(height: 14),
        itemCount: sections.length,
      ),
    );
  }

  List<_LegalSection> _sections(AppStrings strings) {
    if (strings.isSpanish) {
      return const [
        _LegalSection(
          title: 'Terminos de uso',
          body: [
            'DondePaso es una herramienta de exploracion personal y visual. La app muestra una representacion aproximada de las zonas que el usuario recorre y no constituye una fuente oficial de navegacion, seguridad, salud ni ubicacion precisa.',
            'El usuario usa la app bajo su propio criterio. DondePaso no garantiza exactitud total del mapa revelado, continuidad del rastreo pasivo, disponibilidad permanente del sensor de pasos ni compatibilidad con todas las capas de ahorro de bateria del sistema.',
            'El uso de DondePaso requiere conceder permisos del sistema, como ubicacion, seguridad del dispositivo y, cuando corresponda, reconocimiento de actividad. Si el usuario no concede esos permisos, algunas funciones no estaran disponibles.',
          ],
        ),
        _LegalSection(
          title: 'Politica de privacidad',
          body: [
            'Actualmente DondePaso esta diseñado para guardar y procesar la informacion del recorrido en este dispositivo. No enviamos coordenadas, rutas ni historial individual a servidores remotos para el funcionamiento normal de la app.',
            'La informacion principal de la experiencia, como zonas descubiertas, puntos, kilometros conocidos y pasos diarios, se conserva localmente en el telefono del usuario. El acceso a esa informacion queda protegido por la seguridad del propio dispositivo cuando esta funcion esta activa.',
            'El usuario puede borrar su progreso local desde la app. Al hacerlo, se eliminan las zonas descubiertas, puntos y datos locales asociados al experimento guardados por DondePaso en el dispositivo.',
          ],
        ),
        _LegalSection(
          title: 'Datos anonimos y estadisticas futuras',
          body: [
            'Aunque hoy la experiencia principal es local, en el futuro podriamos ofrecer la posibilidad de participar en analisis anonimos y agregados, por ejemplo para estimar medias de kilometros conocidos, porcentaje aproximado de ciudad recorrida, nivel de exploracion general o resultados de encuestas anonimas dentro de la app.',
            'Si ese modulo se habilita, no deberia activarse por defecto. Requeriria consentimiento explicito e informado dentro de la app antes de cualquier envio. La participacion seria opcional y no seria necesaria para usar DondePaso.',
            'En ese escenario, la politica de privacidad, los avisos dentro de la app y las declaraciones en las tiendas deberan actualizarse para reflejar exactamente que datos anonimos se recopilan, con que fin estadistico o de investigacion, y como el usuario puede retirar su consentimiento.',
          ],
        ),
        _LegalSection(
          title: 'Encuestas anonimas',
          body: [
            'DondePaso podria mostrar en el futuro encuestas anonimas opcionales para entender mejor habitos de exploracion, movilidad percibida o relacion emocional con el entorno urbano.',
            'Esas encuestas, si se activan, deberian indicar claramente que son opcionales, que no condicionan el uso de la app y si sus respuestas se quedaran en el dispositivo o se enviaran anonimamente para analisis agregados.',
          ],
        ),
        _LegalSection(
          title: 'Aviso importante',
          body: [
            'Estos textos sirven como base de producto y transparencia, pero no reemplazan asesoria legal profesional. Antes de publicar en tiendas o activar cualquier envio de datos, conviene revisar esta documentacion con asesoria juridica y adaptar el texto a la jurisdiccion aplicable.',
          ],
        ),
      ];
    }

    return const [
      _LegalSection(
        title: 'Terms of use',
        body: [
          'DondePaso is a personal and visual exploration tool. The app shows an approximate representation of the areas the user moves through and does not serve as an official source of navigation, safety, health, or precise location.',
          'The user operates the app at their own discretion. DondePaso does not guarantee full accuracy of the revealed map, uninterrupted passive tracking, permanent availability of the step sensor, or compatibility with every battery-saving layer used by the operating system.',
          'Using DondePaso requires granting system permissions such as location, device security, and, when applicable, activity recognition. If the user does not grant those permissions, some features will not be available.',
        ],
      ),
      _LegalSection(
        title: 'Privacy policy',
        body: [
          'At the moment, DondePaso is designed to store and process route information on this device. We do not send coordinates, routes, or an individual movement history to remote servers for the normal operation of the app.',
          'The core experience data, including discovered areas, points, known kilometers, and daily steps, is kept locally on the user’s phone. Access to that information is protected by the phone’s own security when that feature is enabled.',
          'The user can erase their local progress from inside the app. Doing so removes discovered areas, points, and the related local experiment data stored by DondePaso on the device.',
        ],
      ),
      _LegalSection(
        title: 'Future anonymous data and statistics',
        body: [
          'While the core experience is currently local, in the future we may offer an option to participate in anonymous and aggregated analysis, for example to estimate averages for known kilometers, approximate city knowledge percentage, general exploration levels, or in-app anonymous survey results.',
          'If that module is ever enabled, it should not be on by default. It would require explicit and informed in-app consent before any data leaves the device. Participation would be optional and would not be required in order to use DondePaso.',
          'In that scenario, the privacy policy, in-app disclosures, and store declarations would need to be updated so they accurately explain which anonymous data is collected, for what statistical or research purpose, and how the user can withdraw consent.',
        ],
      ),
      _LegalSection(
        title: 'Anonymous surveys',
        body: [
          'In the future, DondePaso may display optional anonymous surveys to better understand exploration habits, perceived mobility, or the emotional relationship people have with their urban environment.',
          'If enabled, those surveys should clearly explain that participation is optional, that access to the app does not depend on answering, and whether responses stay on device or are sent anonymously for aggregated analysis.',
        ],
      ),
      _LegalSection(
        title: 'Important notice',
        body: [
          'These texts are a product and transparency baseline, but they are not a replacement for professional legal advice. Before publishing in stores or enabling any data transmission, it is advisable to review this documentation with legal counsel and adapt it to the relevant jurisdiction.',
        ],
      ),
    ];
  }
}

class _LegalSection {
  const _LegalSection({required this.title, required this.body});

  final String title;
  final List<String> body;
}
