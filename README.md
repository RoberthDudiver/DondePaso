# DondePaso

## Español

### Qué es

DondePaso es una app mobile de exploración personal.

La idea es simple:

- Tu mapa empieza casi completamente oscuro.
- Solo se va aclarando en las calles y zonas por donde realmente pasas.
- Si dejas de volver a una zona, esa huella se va apagando con el tiempo.

La mejor forma de entenderlo es esta:

DondePaso se siente como descubrir el mapa de un juego de mundo abierto, pero con tu vida real.

No revela un territorio ficticio.
Revela cuánto de tu barrio, tu ciudad y tu rutina has explorado de verdad.

No intenta decirte a dónde ir.
Intenta darte una forma visual y personal de entender cuánto de tu entorno conoces realmente, como si fueras revelando un mapa de videojuego en la vida real.

Es un experimento personal y social:

- Si tienes pocas zonas activas, probablemente te estás moviendo poco.
- Si casi no cambias tus recorridos, probablemente conoces muy poco de tu propio barrio o ciudad.
- La app busca empujarte a explorar, caminar más y ampliar tu mundo cotidiano.

### Privacidad

La app está pensada para ser local-first:

- No sube tu posición a servidores.
- No construye un historial remoto.
- No comparte rutas ni coordenadas.
- Todo se guarda y se procesa en este dispositivo.

Por eso la app deja claro que el mapa vive en su propio dispositivo y representa una huella personal de movimiento.
La experiencia está pensada para ser privada por diseño, simple y local.

Documentos legales:

- [docs/LEGAL_ES.md](docs/LEGAL_ES.md)
- [docs/LEGAL_EN.md](docs/LEGAL_EN.md)

### Seguridad

Al abrir la app, DondePaso usa la seguridad ya activa del teléfono:

- huella
- rostro
- PIN
- patrón o método equivalente del sistema

Si el dispositivo no tiene seguridad configurada, la app pide activarla primero.

### Movimiento y salud

Además del mapa, la app puede mostrar información local de actividad:

- pasos diarios
- pulso de actividad
- puntos por descubrimiento
- kilómetros conocidos

Esto no reemplaza una app médica ni una plataforma fitness completa.
Es una lectura ligera del movimiento diario para reforzar la idea de exploración.

### Rastreo pasivo

En Android, DondePaso puede seguir descubriendo zonas con un servicio pasivo y una notificación persistente.

Importante:

- si el usuario no concede permiso de ubicación en segundo plano, el descubrimiento se corta al cerrar la app
- el ahorro de batería agresivo de algunos fabricantes puede frenar el servicio

En iPhone existen limitaciones del sistema más fuertes que en Android, así que el comportamiento en segundo plano no puede ser tan continuo.

### Idiomas

La interfaz se adapta automáticamente al idioma del sistema:

- Español
- Inglés

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

- cuánto conozco realmente del lugar donde vivo
- cuánto camino de verdad
- cuánto repito siempre los mismos trayectos
- qué tan activa o cerrada se está volviendo mi vida cotidiana

## English

### What it is

DondePaso is a mobile app for personal exploration.

The core idea is simple:

- Your map starts almost completely dark.
- It only becomes visible in the streets and areas you actually move through.
- If you stop revisiting a place, that footprint slowly fades again.

The easiest way to describe it is this:

DondePaso feels like uncovering the map of an open-world game, but with your real life.

It does not reveal a fictional world.
It reveals how much of your neighborhood, your city, and your routine you have truly explored.

It does not try to tell you where to go.
It tries to give you a personal, visual way to understand how much of your surroundings you truly know, as if you were uncovering a game map in real life.

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

That is why the app makes it clear that the map lives on the user's own device and represents a personal movement footprint.
The experience is designed to be private by design, simple, and local.

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

## Community

DondePaso is now open to community feedback and contributions.

- Use `Discussions` for ideas, questions, and product conversations.
- Use `Issues` for bugs and concrete feature requests.
- See [CONTRIBUTING.md](CONTRIBUTING.md) for collaboration guidelines.
