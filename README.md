# DondePaso

## Espanol

### Que es

DondePaso es una app mobile de exploracion personal.

La idea es simple:

- Tu mapa empieza casi completamente oscuro.
- Solo se va aclarando en las calles y zonas por donde realmente pasas.
- Si dejas de volver a una zona, esa huella se va apagando con el tiempo.

No intenta decirte a donde ir.
Intenta mostrarte, de forma visual, cuanto de tu entorno conoces de verdad.

Es un experimento personal y social:

- Si tienes pocas zonas activas, probablemente te estas moviendo poco.
- Si casi no cambias tus recorridos, probablemente conoces muy poco de tu propio barrio o ciudad.
- La app busca empujarte a explorar, caminar mas y ampliar tu mundo cotidiano.

### Privacidad

La app esta pensada para ser local-first:

- No sube tu posicion a servidores.
- No construye un historial remoto.
- No comparte rutas ni coordenadas.
- Todo se guarda y se procesa en este dispositivo.

Por eso la app explica al usuario que no lo esta rastreando para terceros.
Lo que existe es un mapa local y visual de su propia huella.

Documentos legales:

- [docs/LEGAL_ES.md](docs/LEGAL_ES.md)
- [docs/LEGAL_EN.md](docs/LEGAL_EN.md)

### Seguridad

Al abrir la app, DondePaso usa la seguridad ya activa del telefono:

- huella
- rostro
- PIN
- patron o metodo equivalente del sistema

Si el dispositivo no tiene seguridad configurada, la app pide activarla primero.

### Movimiento y salud

Ademas del mapa, la app puede mostrar informacion local de actividad:

- pasos diarios
- pulso de actividad
- puntos por descubrimiento
- kilometros conocidos

Esto no reemplaza una app medica ni una plataforma fitness completa.
Es una lectura ligera del movimiento diario para reforzar la idea de exploracion.

### Rastreo pasivo

En Android, DondePaso puede seguir descubriendo zonas con un servicio pasivo y una notificacion persistente.

Importante:

- si el usuario no concede permiso de ubicacion en segundo plano, el descubrimiento se corta al cerrar la app
- el ahorro de bateria agresivo de algunos fabricantes puede frenar el servicio

En iPhone existen limitaciones del sistema mas fuertes que en Android, asi que el comportamiento en segundo plano no puede ser tan continuo.

### Idiomas

La interfaz se adapta automaticamente al idioma del sistema:

- Espanol
- Ingles

### Stack actual

- Flutter
- flutter_map
- geolocator
- flutter_background_service
- permission_handler
- local_auth
- pedometer

### Objetivo del producto

DondePaso no quiere ser solo un rastreador bonito.
Quiere ser una herramienta para que el usuario se pregunte:

- cuanto conozco realmente del lugar donde vivo
- cuanto camino de verdad
- cuanto repito siempre los mismos trayectos
- que tan activa o cerrada se esta volviendo mi vida cotidiana

## English

### What it is

DondePaso is a mobile app for personal exploration.

The core idea is simple:

- Your map starts almost completely dark.
- It only becomes visible in the streets and areas you actually move through.
- If you stop revisiting a place, that footprint slowly fades again.

It does not try to tell you where to go.
It tries to show, visually, how much of your surroundings you truly know.

It is a personal and social experiment:

- If you have very few active areas, you are probably moving less.
- If your routes almost never change, you probably know very little of your own neighborhood or city.
- The app is meant to push you to explore, walk more, and expand your everyday world.

### Privacy

The app is designed as local-first:

- It does not upload your position to servers.
- It does not build a remote history.
- It does not share routes or coordinates.
- Everything is stored and processed on this device.

That is why the app clearly explains that it is not tracking the user for third parties.
What exists is a local, visual map of the user's own footprint.

Legal documents:

- [docs/LEGAL_ES.md](docs/LEGAL_ES.md)
- [docs/LEGAL_EN.md](docs/LEGAL_EN.md)

### Security

When opening the app, DondePaso uses the phone security already enabled by the user:

- fingerprint
- face unlock
- PIN
- pattern or equivalent system credential

If the device has no screen security configured, the app asks the user to enable it first.

### Movement and fitness

Alongside the map, the app can surface lightweight local movement insights:

- daily steps
- activity pulse
- discovery points
- known kilometers

It is not meant to replace a medical app or a full fitness platform.
It is a lightweight reading of daily motion that reinforces the exploration concept.

### Passive tracking

On Android, DondePaso can keep discovering areas through passive tracking with a foreground notification.

Important:

- if the user does not grant background location, discovery stops when the app closes
- aggressive battery optimization from some manufacturers may interrupt the service

On iPhone, system restrictions are much stronger than on Android, so background behavior cannot be as continuous.

### Languages

The interface automatically follows the device language:

- Spanish
- English

### Current stack

- Flutter
- flutter_map
- geolocator
- flutter_background_service
- permission_handler
- local_auth
- pedometer

### Product goal

DondePaso is not meant to be just a pretty tracker.
It is meant to make the user ask:

- how much do I really know of the place where I live
- how much do I actually walk
- how often do I repeat the same routes
- how active or closed off is my everyday life becoming
