# Informe: LAB-04 Hardening de PostgreSQL

- Profesor: Alexis Moises Montaño Araujo
- Estudiante: Camilo Angulo
- Materia: Gestión de Seguridad y Desempeño de Bases de Datos, Unidad II (tema 2.6)
- Fecha: 25 de octubre de 2026

Los resultados, las tablas antes y después, los cambios y el checklist están en README.md, configuracion/baseline.md y configuracion/cambios.md. Aquí respondo las preguntas del laboratorio.

## 1. Preguntas del informe

**1. ¿Cuál era la principal superficie de ataque?**

La exposición de red del servicio. El servidor escuchaba en todas las interfaces (listen_addresses = *), y la última regla de pg_hba.conf dejaba entrar a cualquier origen con solo la contraseña. Lo comprobé desde otro contenedor: desde 172.17.0.3 conecté con la contraseña de postgres al servidor en 172.17.0.2.

**2. ¿Qué configuración representaba el mayor riesgo?**

La combinación de tres cosas: escucha en todas las interfaces, la regla host all all all scram-sha-256 y que el único usuario era el superusuario postgres. Con eso, cualquiera que consiguiera una sola contraseña entraba por red con todos los privilegios. Cada cosa por separado era menos grave que las tres juntas.

**3. ¿Qué cambio produjo la mayor reducción de exposición?**

listen_addresses = localhost. Antes, dentro del contenedor el servicio escuchaba en 00000000:1538 (todas las interfaces) y la conexión de otro contenedor entraba. Después escucha en 0100007F:1538 (127.0.0.1) y en ::1, y esa misma conexión da Connection refused. El cambio de pg_hba.conf fue el que más protegió dentro de la base, pero listen_addresses cierra el acceso antes de llegar a ella.

**4. ¿Qué diferencia existe entre firewall y pg_hba.conf?**

El firewall decide quién puede llegar al puerto, y actúa antes de que PostgreSQL intervenga. pg_hba.conf decide quién puede autenticarse una vez que llegó: con qué usuario, a qué base, desde qué dirección y con qué método. No son equivalentes y se necesitan los dos. En mi prueba se ve: con el servidor escuchando en todas las interfaces, el rechazo lo hacía pg_hba.conf, y después de cerrar listen_addresses ya ni llegaba a pg_hba.conf, porque el puerto no estaba abierto en esa interfaz. En el firewall solo diseñé la regla, no la apliqué.

**5. ¿Qué diferencia existe entre autenticación y autorización?**

La autenticación verifica quién eres (usuario y contraseña, o peer). La autorización determina qué puede hacer esa identidad. En el laboratorio se vio: app_user se autentica bien, pero cuando intentó borrar la tabla o crear un rol, PostgreSQL se lo negó (must be owner of table y permission denied to create role). Se autenticó, pero no estaba autorizado.

**6. ¿Por qué una cuenta de aplicación no debe ser SUPERUSER?**

Porque si la aplicación se compromete (por ejemplo, con una inyección SQL), el atacante hereda lo que puede hacer la cuenta. Con un superusuario podría leer y borrar todas las bases, crear roles, y en general controlar el servidor. Con app_user solo puede leer, insertar y actualizar en las tablas que se le dieron.

**7. ¿Por qué cambiar el puerto no es hardening suficiente?**

Porque no cambia la autenticación, la autorización ni la exposición, solo el número. Quien escanea la red encuentra el servicio en cualquier puerto. En mi propio laboratorio el puerto publicado en el equipo era 5434 y no 5432, y el servicio seguía expuesto: conecté desde otro contenedor al 5432 interno sin problema. Cambiar el puerto puede reducir el ruido de escaneos automáticos, pero no sustituye lo demás.

**8. ¿Por qué listen_addresses = '*' puede ser innecesario?**

Porque hace que el servidor acepte conexiones por todas las interfaces, aunque solo necesite una. Si la aplicación está en el mismo equipo, basta localhost. Si está en otro, basta la IP privada del servidor. Con * se amplía la superficie sin ningún beneficio, y quedaría expuesta cualquier interfaz que se agregue después, por ejemplo una pública. Eso sí, con * no cualquiera entra, porque también intervienen pg_hba.conf y la red.

**9. ¿Qué papel tiene el sistema operativo en la seguridad de PostgreSQL?**

PostgreSQL guarda los datos y la configuración en archivos. Si un usuario del sistema operativo puede leerlos, se salta GRANT y REVOKE, porque no pasa por el servidor. Por eso el directorio de datos debe estar en 0700 y los archivos de configuración en 0600 con dueño postgres (así estaban y así los dejé), y server.key en 0600. Además, el sistema operativo decide quién puede entrar al servidor, qué se publica en la red y cómo se protegen los respaldos y los registros.

**10. ¿Qué controles deberían revisarse periódicamente?**

- Las reglas de pg_hba.conf y quién las puede modificar.
- Los roles y sus privilegios, sobre todo superusuarios y cuentas que ya no se usen.
- listen_addresses, el puerto y los puertos publicados en el equipo.
- TLS: la versión mínima y el vencimiento del certificado (el de laboratorio lo hice de 365 días).
- Los permisos de los archivos de configuración, el directorio de datos y las llaves.
- Las extensiones instaladas.
- Las actualizaciones de PostgreSQL y del sistema (la versión es 16.15).
- Los registros de conexiones y rechazos.
- Las contraseñas y su rotación.

## 2. Respuestas de las actividades

**Actividad 1: ¿por qué conocer la superficie de ataque debe preceder al hardening?** Porque no se puede reducir lo que no se conoce. Con el inventario inicial supe qué estaba abierto, qué era necesario y qué no, evité quitar algo que la aplicación sí usa y tuve el "antes" para comparar con el "después".

**Actividad 2: ¿por qué conocer la ubicación de los archivos?** Para saber qué proteger y qué revisar. Hay que distinguir datos (/var/lib/postgresql/data), configuración (postgresql.conf), autenticación (pg_hba.conf y pg_ident.conf) y registros. También evita editar un archivo equivocado: hba_file indica cuál es el que realmente está usando el servidor.

**Actividad 7: autenticación y contraseñas.** scram-sha-256 protege la contraseña: no viaja en claro durante el intercambio y se guarda como un verificador con sal. No es un cifrado reversible, no se puede recuperar la contraseña a partir de lo guardado (lo mismo que vi en LAB-02 con crypt). Y una contraseña fuerte no compensa los permisos excesivos: si alguien se autentica con una cuenta que puede hacer de todo, puede hacer de todo, aunque la contraseña sea excelente.

**Actividad 8: roles.**

| Rol | LOGIN | SUPERUSER | CREATEROLE | CREATEDB | Función |
|---|---|---|---|---|---|
| postgres | Sí | Sí | Sí | Sí | Administración, solo por socket local con peer |
| app_user | Sí | No | No | No | La aplicación: leer, insertar y actualizar |
| consulta_user | Sí | No | No | No | Solo lectura |

Antes del hardening solo existía postgres.

**Actividad 9: ¿qué riesgo hay si la aplicación usa una cuenta administrativa?** El mismo de la pregunta 6: un error o un ataque a la aplicación se convierte en control total del servidor.

**Actividad 10: extensiones.** Solo está plpgsql, que viene con PostgreSQL. La pgcrypto del LAB-02 no está instalada en esta instancia. Una extensión no es insegura por estar instalada, pero se deja solo lo necesario.

**Actividad 11: parámetros de conexión.**

- max_connections (100): máximo de conexiones simultáneas.
- superuser_reserved_connections (3): lugares reservados para superusuarios, para poder entrar a administrar aunque el servidor esté lleno.
- statement_timeout (0, sin límite): cancela las consultas que duran más del tiempo indicado.
- idle_in_transaction_session_timeout (antes 0, ahora 60 s): cierra las sesiones que se quedan quietas dentro de una transacción.

Mantener conexiones abiertas indefinidamente consume memoria y lugares de max_connections, y una transacción abierta puede retener bloqueos. Si se agotan los lugares, nadie más se puede conectar, y eso es un problema de disponibilidad.

**Actividad 12: permisos del sistema operativo.**

| Archivo | Antes | Después |
|---|---|---|
| Directorio de datos | drwx------ postgres postgres | drwx------ postgres postgres |
| postgresql.conf y pg_ident.conf | -rw------- postgres postgres | -rw------- postgres postgres |
| pg_hba.conf | -rw------- postgres postgres | -rw------- postgres postgres (el nuevo, con 479 bytes) |
| server.key | no existía | -rw------- postgres postgres |
| server.crt | no existía | -rw-r--r-- postgres postgres |

Los permisos de fábrica ya estaban bien. No basta con GRANT y REVOKE porque esos controles solo valen para quien entra por PostgreSQL. Quien lee los archivos del sistema operativo obtiene los datos y las configuraciones sin pasar por el servidor. server.crt es público y por eso está en 644, pero server.key debe quedarse en 600.

**Actividad 13: exposición de red.** Antes, el servicio escuchaba en 0.0.0.0:5432 y [::]:5432 (dentro del contenedor, 00000000:1538). Después escucha solo en 127.0.0.1 y ::1. Fuera de la interfaz necesaria ya no está expuesto el servidor. Pero Docker sigue publicando el puerto en mi equipo (0.0.0.0:5434 en docker port y netstat). No probé qué pasa si alguien se conecta a ese puerto del equipo, pero es superficie innecesaria y queda como pendiente.

**Actividad 15: TLS.** Antes, ssl estaba en off. Ahora ssl = on, las reglas hostssl obligan a usarlo y el registro del servidor muestra la conexión de app_user con TLSv1.3 y TLS_AES_256_GCM_SHA384. Sin TLS el servidor la rechaza (no encryption). Límites: el certificado es autofirmado, y yo conecté con sslmode=require, que cifra pero no verifica la identidad del servidor. Para eso haría falta un certificado de una autoridad confiable y verify-full, como vi en LAB-02. La sesión de administración por socket local no usa TLS, y es normal.

## 3. Caso integral (actividad 18)

El escenario: PostgreSQL acepta conexiones desde cualquier IPv4, una aplicación web se conecta con un usuario administrativo, el servidor escucha en todas las interfaces, el firewall permite el 5432 desde cualquier origen, pg_hba.conf permite all/all desde 0.0.0.0/0, y el administrador dice que no hay problema porque las contraseñas son fuertes.

| # | Problema | Riesgo | Control propuesto |
|---|---|---|---|
| 1 | Acepta conexiones desde cualquier IPv4 | Cualquier equipo de la red o de internet puede intentar entrar | Restringir por firewall y pg_hba.conf a los orígenes que lo necesitan |
| 2 | La aplicación usa un usuario con privilegios administrativos | Una falla en la aplicación (por ejemplo, una inyección SQL) da control total de la base y del servidor | Cuenta de aplicación con los permisos mínimos y sin SUPERUSER |
| 3 | El servidor escucha en todas las interfaces | Queda expuesto en cualquier interfaz, incluso las públicas | listen_addresses con la IP privada o localhost |
| 4 | El firewall permite el 5432 desde cualquier origen | Escaneo, fuerza bruta y explotación de vulnerabilidades del servicio | Regla de permitir solo la red de la aplicación y denegar el resto |
| 5 | pg_hba.conf permite all/all desde 0.0.0.0/0 | Cualquier usuario, base y origen puede intentar autenticarse, incluso el superusuario | Reglas por base, usuario y origen, con reject por defecto |
| 6 | Se confía solo en contraseñas fuertes | Si se roba o se filtra la contraseña, o la aplicación se compromete, no hay otra barrera | Defensa en capas: red, pg_hba.conf, privilegios mínimos y monitoreo |
| 7 | Las cuentas administrativas se pueden usar por red | Fuerza bruta o robo de credenciales contra el superusuario | Administrador solo por socket local con peer, o desde una red de administración |
| 8 | El escenario no menciona TLS | Si no hay cifrado, las credenciales y los datos viajan en claro | ssl = on y reglas hostssl (idealmente verify-full) |
| 9 | El escenario no menciona monitoreo ni registros | Intentos de acceso y accesos indebidos pasan sin ser detectados | log_connections y log_disconnections, y revisión de los rechazos |
| 10 | La aplicación web y la base están sin segmentar | Quien compromete la aplicación llega directo a la base y a otros servicios | Segmentación: la base en una red privada alcanzable solo desde la aplicación |
| 11 | El escenario no menciona límites de conexión ni tiempos | Un ataque o una aplicación con fallas agota las conexiones y deja el servicio sin respuesta | max_connections y timeouts ajustados, y reservar conexiones para administración |
| 12 | El escenario no menciona los archivos ni el sistema operativo | Si los archivos de configuración o los datos se pueden leer, se saltan los permisos de PostgreSQL | Permisos 0700 y 0600 con dueño postgres, y acceso restringido al servidor |
| 13 | No hay una cuenta distinta para consulta ni separación de funciones | Todo se hace con la misma identidad y no se puede saber ni limitar quién hizo qué | Cuentas separadas: administración, aplicación y consulta |

Los problemas 8, 9, 11 y 12 son cosas que el escenario no cuenta, y los incluí como riesgos que habría que verificar, no como hechos.

**¿Es suficiente tener contraseñas fuertes?**

No. Una contraseña fuerte protege contra una sola cosa: que alguien adivine la credencial. Pero la seguridad tiene varias capas y cada una cubre algo distinto:

- **Autenticación:** la contraseña fuerte ayuda aquí, pero se puede robar, filtrar o reutilizar, y si la usa la propia aplicación, un atacante que la comprometa entra con credenciales válidas.
- **Autorización:** con la aplicación usando un usuario administrativo, no importa qué tan fuerte sea la contraseña, quien llegue a esa cuenta puede hacer cualquier cosa.
- **Red:** con el puerto abierto a cualquier origen, el servidor puede recibir fuerza bruta, escaneos y ataques a vulnerabilidades del servicio, incluso antes de autenticarse, y la contraseña no ayuda en nada ahí.
- **Configuración:** reglas amplias en pg_hba.conf, sin TLS y sin límites de conexión dejan fallas que la contraseña no cubre.
- **Sistema operativo:** quien lee los archivos de PostgreSQL no necesita ninguna contraseña.
- **Monitoreo:** sin registros, no se detecta un intento de acceso ni un uso indebido a tiempo.

Lo viví en el laboratorio: antes del hardening, el servidor tenía contraseña y aun así conecté desde otro contenedor sin ningún obstáculo más.

## 4. Reflexión

**¿Qué cambiaría primero en un servidor PostgreSQL que ya está funcionando en producción?**

Primero averiguaría quién se conecta de verdad, sin cambiar nada: revisaría las conexiones activas, pg_hba.conf y los registros. En el escenario del laboratorio se dice que no se sabe con precisión qué conexiones remotas son necesarias. Si cierro algo sin saberlo, puedo tumbar la aplicación, y eso afecta la disponibilidad y la continuidad, que son justo lo que se quiere proteger.

Con esa lista, el primer cambio sería restringir quién puede llegar al servidor en el firewall y en la red, dejando solo a la aplicación y a los administradores. Lo elegiría primero por tres motivos:

- **Riesgo y exposición:** es lo que más reduce la superficie. Quien no llega al puerto no puede probar contraseñas ni explotar una vulnerabilidad.
- **Impacto y continuidad:** no requiere reiniciar PostgreSQL ni tocar la aplicación, y se puede revertir de inmediato si algo falla.
- **Disponibilidad:** al conocer las conexiones legítimas antes, el riesgo de cortar a alguien válido es menor.

Después seguiría con pg_hba.conf (con respaldo, y revisándolo con pg_hba_file_rules antes de recargar, que no requiere reinicio), luego los privilegios de la cuenta de la aplicación (se prueba bien antes, porque puede romper funciones) y por último los cambios que piden reinicio, como listen_addresses, en una ventana planeada. TLS lo haría en paralelo, pero con cuidado de no cortar a los clientes que todavía no lo usan.

Lo que no haría es cambiar todo de golpe ni cambiar el puerto. Una parte de este orden sale de lo que vi en el laboratorio (por ejemplo, que listen_addresses necesita reinicio y pg_hba.conf solo recarga), pero no lo probé en producción, así que es un criterio y no algo que haya comprobado.