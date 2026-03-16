import 'dart:ui';

import 'package:flutter/material.dart';

enum AppLanguage { english, spanish }

class AppStrings {
  const AppStrings._(this.language);

  final AppLanguage language;

  static AppStrings of(BuildContext context) {
    return fromLocale(Localizations.localeOf(context));
  }

  static AppStrings fromLocale(Locale locale) {
    final code = locale.languageCode.toLowerCase();
    return AppStrings._(
      code.startsWith('es') ? AppLanguage.spanish : AppLanguage.english,
    );
  }

  static AppStrings fromSystem() {
    return fromLocale(PlatformDispatcher.instance.locale);
  }

  bool get isSpanish => language == AppLanguage.spanish;

  String get appTitle => 'DondePaso';
  String get points => isSpanish ? 'Puntos' : 'Points';
  String get known => isSpanish ? 'Conocido' : 'Known';
  String get today => isSpanish ? 'Hoy' : 'Today';
  String get passive => isSpanish ? 'Seguir' : 'Track';
  String get settings => isSpanish ? 'Ajustes' : 'Settings';
  String get legal => isSpanish ? 'Legal' : 'Legal';
  String get permissions => isSpanish ? 'Permisos' : 'Permissions';
  String get restartTracking => isSpanish ? 'Reactivar' : 'Reactivate';
  String get resetProgress =>
      isSpanish ? 'Reiniciar progreso' : 'Reset progress';
  String get cancel => isSpanish ? 'Cancelar' : 'Cancel';
  String get delete => isSpanish ? 'Borrar' : 'Delete';
  String get close => isSpanish ? 'Cerrar' : 'Close';
  String get ok => isSpanish ? 'Ok' : 'OK';
  String get openSettings => isSpanish ? 'Ajustes' : 'Settings';
  String get openGps => isSpanish ? 'Abrir GPS' : 'Open GPS';
  String get whereAmI => isSpanish ? 'Donde estoy' : 'Where I am';
  String get active => isSpanish ? 'Activo' : 'Active';
  String get off => isSpanish ? 'Apagado' : 'Off';
  String get tracking => isSpanish ? 'Seguimiento' : 'Tracking';
  String get map => isSpanish ? 'Mapa' : 'Map';
  String get privacy => isSpanish ? 'Privacidad' : 'Privacy';
  String get termsAndPrivacy =>
      isSpanish ? 'Terminos y privacidad' : 'Terms and privacy';
  String get movement => isSpanish ? 'Movimiento' : 'Movement';
  String get yourProgress => isSpanish ? 'Tu progreso' : 'Your progress';
  String get knownKm => isSpanish ? 'Km conocidos' : 'Known km';
  String get totalKnownKm =>
      isSpanish ? 'Km conocidos total' : 'Total known km';
  String get traveledTodayKm =>
      isSpanish ? 'Km recorridos hoy' : 'Km traveled today';
  String get trackingProfile =>
      isSpanish ? 'Perfil de rastreo' : 'Tracking profile';
  String get profileBatterySaver =>
      isSpanish ? 'Ahorro' : 'Saver';
  String get profileBalanced =>
      isSpanish ? 'Medio' : 'Balanced';
  String get profilePrecise =>
      isSpanish ? 'Preciso' : 'Precise';
  String get profileCustom =>
      isSpanish ? 'Personalizado' : 'Custom';
  String get customDistance =>
      isSpanish ? 'Distancia minima' : 'Min distance';
  String get customInterval =>
      isSpanish ? 'Intervalo' : 'Interval';
  String get adaptiveTracking =>
      isSpanish ? 'Adaptar segun movimiento' : 'Adaptive tracking';
  String get adaptiveTrackingBody => isSpanish
      ? 'Cuando detecta poco movimiento, baja precision para ahorrar bateria y vuelve a subirla al moverte.'
      : 'When movement is low, it reduces tracking intensity to save battery and raises it again once you move.';
  String get passiveMode => isSpanish ? 'Modo pasivo' : 'Passive mode';
  String get passiveModeBody => isSpanish
      ? 'Cuando esta activo, DondePaso sigue registrando en segundo plano y Android muestra una notificacion persistente.'
      : 'When enabled, DondePaso keeps recording in the background and Android shows a persistent notification.';
  String get passiveModeOffBody => isSpanish
      ? 'Si lo apagas, desaparece la notificacion, pero el rastreo pasivo deja de funcionar.'
      : 'If you turn it off, the notification disappears, but passive tracking stops working.';
  String customDistanceValue(int meters) =>
      isSpanish ? '$meters m' : '$meters m';
  String customIntervalValue(int seconds) =>
      isSpanish ? '$seconds s' : '$seconds s';
  String get status => isSpanish ? 'Estado' : 'Status';
  String get fading => isSpanish ? 'Olvido' : 'Fade';
  String get todaySteps => isSpanish ? 'Pasos hoy' : 'Steps today';
  String get activityPulse => isSpanish ? 'Pulso activo' : 'Activity pulse';
  String get localOnly => isSpanish ? 'Solo local' : 'Local only';
  String get locked => isSpanish ? 'Bloqueado' : 'Locked';
  String get noCloud =>
      isSpanish ? 'Privado por diseno' : 'Private by design';

  String get onboardingTitle =>
      isSpanish ? 'Revela tu mapa' : 'Reveal your map';

  String get onboardingBody => isSpanish
      ? 'Tu ciudad empieza como un mapa por descubrir. Las calles que recorres se revelan en este telefono y construyen un mapa personal, privado y local.'
      : 'Your city starts like a map waiting to be uncovered. The streets you travel through are revealed on this phone and build a personal, private, local map.';

  String get onboardingExperiment => isSpanish
      ? 'Se siente como descubrir el mapa de un juego de mundo abierto, pero con tu vida real. Mientras mas exploras, mas mundo revelas.'
      : 'It feels like uncovering the map of an open-world game, but with your real life. The more you explore, the more of the world you reveal.';

  String get onboardingActivate =>
      isSpanish ? 'Activar seguimiento' : 'Enable tracking';

  String get locationNeededTitle =>
      isSpanish ? 'Necesitamos ubicacion' : 'Location is required';

  String get locationNeededBody => isSpanish
      ? 'Primero tienes que permitir la ubicacion mientras usas la app para empezar a revelar tu mapa.'
      : 'You first need to allow location while using the app to start revealing your map.';

  String get backgroundNeededTitle => isSpanish
      ? 'Falta permiso en segundo plano'
      : 'Background permission missing';

  String get backgroundNeededBody => isSpanish
      ? 'Si eliges solo mientras usas la app, tu mapa deja de revelarse cuando cierras DondePaso.'
      : 'If you choose while-using-only, your map stops revealing itself once you close DondePaso.';
  String get alwaysPermissionAlertTitle => isSpanish
      ? 'Falta permiso de todo el tiempo'
      : 'Always permission is missing';
  String get alwaysPermissionAlertBody => isSpanish
      ? 'Sin el permiso de ubicacion de todo el tiempo, tu mapa deja de revelarse bien cuando la app queda cerrada.'
      : 'Without always-on location permission, your map cannot keep revealing itself properly when the app is closed.';
  String get grantAlwaysPermission => isSpanish
      ? 'Dar permiso'
      : 'Grant permission';

  String get permissionBlockedTitle =>
      isSpanish ? 'Permiso bloqueado' : 'Permission blocked';

  String get permissionBlockedBody => isSpanish
      ? 'Tienes que cambiarlo desde ajustes del sistema para que tu mapa pueda seguir revelandose en segundo plano.'
      : 'You need to change it in system settings so your map can keep revealing itself in the background.';

  String get gpsTitle => isSpanish ? 'Activa el GPS' : 'Turn GPS on';
  String get gpsBody => isSpanish
      ? 'La ubicacion del telefono esta apagada. Enciendela para que el mapa siga revelando calles aunque la app quede cerrada.'
      : 'Phone location is turned off. Turn it on so the map can keep revealing streets even when the app is closed.';

  String get locatingYou => isSpanish
      ? 'Buscando tu ubicacion...'
      : 'Finding your location...';

  String get locationStillLoading => isSpanish
      ? 'Todavia no pude fijar tu ubicacion. Prueba otra vez en unos segundos.'
      : 'I still could not lock your location. Try again in a few seconds.';

  String get locationCentered => isSpanish
      ? 'Te llevo a tu posicion actual.'
      : 'Centered on your current position.';

  String get localPrivacyTitle =>
      isSpanish ? 'Privacidad local' : 'Local privacy';
  String get localPrivacyBody => isSpanish
      ? 'Tu mapa personal se construye y se queda en este dispositivo. Las calles reveladas, los puntos y el progreso viven localmente.'
      : 'Your personal map is built and stays on this device. Revealed streets, points, and progress live locally.';

  String get experimentTitle =>
      isSpanish ? 'Mundo abierto real' : 'Real-world open world';
  String get experimentBody => isSpanish
      ? 'Piensalo como un mapa de videojuego aplicado a tu vida real: lo que visitas se revela, lo que abandonas se apaga y cada salida amplia tu mundo cotidiano.'
      : 'Think of it as a video game map applied to real life: what you visit is revealed, what you leave behind fades out, and every outing expands your everyday world.';

  String forgetAfterDays(int days) =>
      isSpanish ? 'Se va apagando en $days dias' : 'Fades back over $days days';

  String get mapFadesBody => isSpanish
      ? 'Las calles que no vuelves a pisar se oscurecen de nuevo con el tiempo.'
      : 'Streets you do not revisit fade back into darkness over time.';

  String get batteryHint => isSpanish
      ? 'En Android conviene sacar el ahorro de bateria para que tu mapa siga revelandose sin cortes.'
      : 'On Android it helps to disable battery saving so your map can keep revealing itself without interruptions.';
  String get community => isSpanish ? 'Comunidad' : 'Community';
  String get communityBody => isSpanish
      ? 'Mira quienes estan construyendo DondePaso contigo y agradece a quienes ya dejaron huella en el proyecto.'
      : 'See who is building DondePaso with you and celebrate the people already leaving a mark on the project.';
  String get openCommunity =>
      isSpanish ? 'Ver colaboradores' : 'View contributors';
  String get communityLoadFailed => isSpanish
      ? 'No pude cargar la comunidad ahora mismo.'
      : 'I could not load the community right now.';
  String get tryAgain => isSpanish ? 'Intentar otra vez' : 'Try again';
  String get topContributors =>
      isSpanish ? 'Top contributors' : 'Top contributors';
  String get topContributorsBody => isSpanish
      ? 'Las personas con mas PRs merged, commits y cambios reales en el proyecto.'
      : 'The people with the most merged PRs, commits, and meaningful changes in the project.';
  String get latestContributors =>
      isSpanish ? 'Ultimos 50 colaboradores' : 'Latest 50 contributors';
  String get latestContributorsBody => isSpanish
      ? 'Una vista reciente de quienes pasaron por el repo y dejaron avances.'
      : 'A recent view of who passed through the repo and left progress behind.';
  String get thankYouContributorsTitle =>
      isSpanish ? 'Gracias por construirlo' : 'Thanks for building it';
  String get thankYouContributorsBody => isSpanish
      ? 'Gracias a todas las personas que colaboran en DondePaso. Cada PR, fix, idea y mejora ayuda a que este experimento crezca con la comunidad.'
      : 'Thanks to everyone contributing to DondePaso. Every PR, fix, idea, and improvement helps this experiment grow with the community.';
  String get communityRole => isSpanish ? 'Rol' : 'Role';
  String get communityScore => isSpanish ? 'Score' : 'Score';
  String get weeklySync => isSpanish ? 'Sync' : 'Sync';
  String get profileLink => isSpanish ? 'Perfil' : 'Profile';
  String get updatedWeekly =>
      isSpanish ? 'Actualiza cada semana' : 'Updates weekly';
  String updatedAt(String value) =>
      isSpanish ? 'Actualizado $value' : 'Updated $value';
  String contributorStats({required int prs, required int commits}) =>
      isSpanish ? '$prs PRs · $commits commits' : '$prs PRs · $commits commits';
  String communityScoreValue(int score) =>
      isSpanish ? 'Score $score' : 'Score $score';

  String get resetDialogTitle => isSpanish ? 'Borrar mapa' : 'Clear map';
  String get resetDialogBody => isSpanish
      ? 'Se eliminan tus zonas descubiertas, tus puntos y tus pasos guardados.'
      : 'Your discovered zones, points, and saved step data will be removed.';

  String get lastCaptureJustNow =>
      isSpanish ? 'Ultima captura hace instantes' : 'Last capture just now';

  String lastCaptureMinutes(int minutes) => isSpanish
      ? 'Ultima captura hace $minutes min'
      : 'Last capture $minutes min ago';

  String lastCaptureHours(int hours) =>
      isSpanish ? 'Ultima captura hace $hours h' : 'Last capture $hours h ago';

  String get lockReason => isSpanish
      ? 'Desbloquea DondePaso con tu seguridad del telefono'
      : 'Unlock DondePaso with your phone security';

  String get unlockTitle =>
      isSpanish ? 'Protegido por tu telefono' : 'Protected by your phone';
  String get unlockBody => isSpanish
      ? 'Para abrir tu mapa personal necesitas huella, rostro o el PIN del dispositivo.'
      : 'To open your personal map you need fingerprint, face unlock, or the device PIN.';
  String get unlockButton => isSpanish ? 'Desbloquear' : 'Unlock';
  String get securityRequiredTitle =>
      isSpanish ? 'Activa seguridad en tu telefono' : 'Enable device security';
  String get securityRequiredBody => isSpanish
      ? 'DondePaso usa la proteccion ya activa en tu telefono. Si no tienes bloqueo configurado, primero activa PIN, patron o huella.'
      : 'DondePaso uses the protection already active on your phone. If you do not have a screen lock configured, enable a PIN, pattern, or biometrics first.';

  String get stepSensorUnavailable =>
      isSpanish ? 'Sensor de pasos no disponible' : 'Step sensor unavailable';
  String get activityLow => isSpanish ? 'Bajo' : 'Low';
  String get activityWarm => isSpanish ? 'En marcha' : 'Moving';
  String get activityHigh => isSpanish ? 'Activo' : 'Active';
  String get activityExplorer => isSpanish ? 'Explorador' : 'Explorer';

  String get serviceNotificationTitle =>
      isSpanish ? 'DondePaso activo' : 'DondePaso active';

  String serviceNotificationContent({
    required double knownKilometers,
    required double traveledTodayKilometers,
  }) {
    if (isSpanish) {
      return '${knownKilometers.toStringAsFixed(1)} km conocidos · ${traveledTodayKilometers.toStringAsFixed(1)} km hoy';
    }
    return '${knownKilometers.toStringAsFixed(1)} km known · ${traveledTodayKilometers.toStringAsFixed(1)} km today';
  }
}

extension AppStringsContext on BuildContext {
  AppStrings get strings => AppStrings.of(this);
}
