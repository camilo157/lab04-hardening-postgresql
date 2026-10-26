# LAB-04: Hardening y configuración segura de PostgreSQL

- Profesor: Alexis Moises Montaño Araujo
- Estudiante: Camilo Angulo
- Materia: Gestión de Seguridad y Desempeño de Bases de Datos, Unidad II (tema 2.6)
- Motor: PostgreSQL 16.15 en Docker
- Fecha: 25 de octubre de 2026

## Objetivo

Revisar cómo viene configurado un servidor PostgreSQL recién instalado, encontrar lo que lo deja innecesariamente expuesto, aplicar medidas de hardening y comprobar con pruebas que los cambios funcionan, comparando el estado antes y después.

## Entorno

Usé un contenedor aparte, solo para esta práctica (pg-lab04), creado con la imagen postgres:16 y su configuración por defecto, para tener un "antes" limpio. La contraseña del contenedor y las de las cuentas son de laboratorio y no están en ningún archivo del repositorio: los roles se crean sin contraseña en el script y la contraseña se les asignó aparte con \password.

```
docker run -d --name pg-lab04 -e POSTGRES_PASSWORD=<contraseña-de-laboratorio> -p 5434:5432 postgres:16
docker exec pg-lab04 mkdir -p /lab04
docker cp sql/. pg-lab04:/lab04
docker exec -it -u postgres pg-lab04 psql -U postgres -a -f /lab04/01-inspeccion.sql
```

Los scripts 02, 03 y 04 se corren igual. Usé -u postgres porque después del hardening el administrador local entra con peer, que exige ser el usuario postgres del sistema. Los archivos del repositorio:

- sql/: 01-inspeccion, 02-roles, 03-configuracion y 04-verificacion.
- configuracion/: baseline.md (línea base), cambios.md (qué cambié y cómo volver atrás) y pg_hba.hardened.conf (las reglas nuevas).
- evidencias/: las capturas 01 a 06.
- informe.md: las preguntas del laboratorio y el caso integral.

## Superficie de ataque inicial

| Elemento | Estado actual | ¿Es necesario? | Riesgo |
|---|---|---|---|
| Puerto PostgreSQL | 5432 en el servidor, publicado en mi equipo como 0.0.0.0:5434 | El puerto del servicio sí; publicarlo en todas las interfaces del equipo, no | Cualquiera que llegue a ese puerto puede intentar autenticarse |
| Interfaces de escucha | listen_addresses = * | No, en el laboratorio solo hace falta la local | El servicio queda expuesto en todas las redes |
| Conexiones remotas | Se aceptan de cualquier origen con contraseña (regla host all all all) | Solo las de la aplicación | Lo comprobé: desde otro contenedor (172.17.0.3) conecté con la contraseña de postgres a 172.17.0.2 |
| Usuarios administrativos | postgres, que es superusuario y el único rol; no había cuentas de aplicación | Un administrador sí; usarlo para la aplicación, no | Si se compromete la aplicación o la contraseña, se pierde todo el servidor |
| SSL/TLS | ssl = off | Sí | El tráfico y las contraseñas viajan sin cifrar |
| Métodos de autenticación | trust en local, loopback y replicación; scram-sha-256 para el resto | scram-sha-256 sí; trust no | Con trust se entra sin contraseña |

Otros datos del servidor sin endurecer: versión PostgreSQL 16.15, password_encryption = scram-sha-256, solo la extensión plpgsql, max_connections 100, superuser_reserved_connections 3, statement_timeout y idle_in_transaction_session_timeout en 0, y log_connections y log_disconnections apagados.

Archivos que identifiqué (actividad 2):

| Archivo | Ruta |
|---|---|
| postgresql.conf | /var/lib/postgresql/data/postgresql.conf |
| pg_hba.conf | /var/lib/postgresql/data/pg_hba.conf |
| pg_ident.conf | /var/lib/postgresql/data/pg_ident.conf |
| Directorio de datos | /var/lib/postgresql/data |
| Registros | Directorio log dentro del de datos |

## Hallazgos

1. PostgreSQL escuchaba en todas las interfaces (listen_addresses = *).
2. La última regla de pg_hba.conf, host all all all scram-sha-256, equivale a 0.0.0.0/0: permitía cualquier base, usuario y origen.
3. Seis de las siete reglas usaban trust (local, loopback y replicación), o sea, entrar sin contraseña.
4. Solo existía el superusuario postgres, sin cuentas separadas para una aplicación.
5. TLS estaba apagado.
6. No se registraban las conexiones ni las desconexiones, así que no habría rastro de quién entró.
7. No había límite para sesiones que se quedan abiertas dentro de una transacción.
8. El puerto del contenedor está publicado en todas las interfaces de mi equipo.

Lo que ya venía bien: password_encryption = scram-sha-256, el directorio de datos con permisos drwx------ y los archivos de configuración con -rw------- y dueño postgres, y la única extensión era plpgsql.

## Cambios realizados

El detalle, con la forma de volver atrás cada uno, está en configuracion/cambios.md.

| # | Cambio |
|---|---|
| 1 | Cuentas separadas app_user y consulta_user, sin SUPERUSER, CREATEDB ni CREATEROLE |
| 2 | TLS activado con un certificado autofirmado (ssl = on) |
| 3 | log_connections y log_disconnections en on |
| 4 | idle_in_transaction_session_timeout = 60 s |
| 5 | pg_hba.conf reemplazado por reglas específicas (con un respaldo del original) |
| 6 | listen_addresses = localhost |

## Justificación de los cambios

- **Cuentas separadas:** la aplicación no debe conectarse con el superusuario. Con permisos mínimos, una aplicación comprometida no puede borrar tablas ni crear roles.
- **TLS:** sin cifrado, quien vea la red lee las consultas y las credenciales. Además las reglas hostssl lo necesitan.
- **Registros de conexión:** sin ellos no se puede saber quién entró, desde dónde y quién fue rechazado.
- **Timeout de sesiones inactivas:** una sesión abierta dentro de una transacción retiene recursos y bloqueos.
- **pg_hba.conf nuevo:** se quitó el trust y la regla abierta. Cada regla fija base, usuario, origen y método, y el resto se rechaza.
- **listen_addresses:** el servidor no tiene por qué escuchar donde nadie lo necesita. Es una capa distinta a pg_hba.conf.

## Verificación

| Prueba | Resultado | Evidencia |
|---|---|---|
| listen_addresses y puertos que escuchan | localhost; antes 00000000:1538, ahora 0100007F:1538 (127.0.0.1) y ::1 | 02-listen-addresses.png |
| Otro contenedor hacia el servidor | Antes conectaba; ahora Connection refused | 02-listen-addresses.png |
| pg_hba_file_rules | Seis reglas, con la columna error vacía | 03-pg-hba.png |
| Permisos de app_user y consulta_user | Tres errores esperados: must be owner of table, permission denied to create role y permission denied for table | 04-roles.png |
| app_user con TLS | Entra por la regla de la línea 4 con TLSv1.3 y TLS_AES_256_GCM_SHA384 | 05-tls.png |
| app_user sin TLS | Rechazada: no encryption | 05-tls.png |
| postgres por red | Rechazada por pg_hba.conf | Registro del servidor |
| postgres local sin ser el usuario postgres | Peer authentication failed | Registro del servidor |
| Estado final de la configuración | ssl, registros y timeout aplicados, pending_restart en f | 06-verificacion.png |

Las pruebas de rechazo salen en el registro del servidor, que ahora guarda cada conexión y cada rechazo con la regla de pg_hba.conf que se aplicó.

## Checklist de hardening

"Sí" quiere decir que lo verifiqué en el laboratorio. Lo que no, lo marqué como propuesta o pendiente.

| # | Control | Verificado | Evidencia |
|---|---|---|---|
| 1 | Puerto documentado | Sí: 5432 en el servidor y 5434 publicado en el equipo | baseline.md, 01-superficie-ataque.png |
| 2 | Interfaces de escucha justificadas | Sí: localhost | 02-listen-addresses.png |
| 3 | pg_hba.conf revisado | Sí | 03-pg-hba.png |
| 4 | Redes autorizadas restringidas | Parcial: en pg_hba.conf sí (127.0.0.1/32); en el firewall solo propuesta | cambios.md |
| 5 | Autenticación segura (scram-sha-256, sin trust) | Sí | 03-pg-hba.png |
| 6 | Superusuarios identificados | Sí: solo postgres | 04-roles.png |
| 7 | Cuentas de aplicación separadas | Sí: app_user y consulta_user | 04-roles.png |
| 8 | Privilegios mínimos | Sí: probado con errores de permisos | 04-roles.png |
| 9 | Extensiones revisadas | Sí: solo plpgsql | 01-superficie-ataque.png |
| 10 | TLS verificado | Sí: TLSv1.3 | 05-tls.png |
| 11 | Archivos de configuración protegidos | Sí: -rw------- y dueño postgres | baseline.md |
| 12 | Directorio de datos protegido | Sí: drwx------ y dueño postgres | baseline.md |
| 13 | Firewall documentado | Propuesta: lo diseñé, no lo apliqué | cambios.md |
| 14 | Actualizaciones documentadas | Propuesta: registré la versión 16.15 y escribí un criterio, no hay política real | baseline.md |
| 15 | Configuración registrada | Sí | baseline.md, cambios.md, pg_hba.hardened.conf |
| 16 | Registro de conexiones y desconexiones | Sí | Registro del servidor, 06-verificacion.png |
| 17 | Timeout de sesiones inactivas | Sí: 60 s | 06-verificacion.png |
| 18 | Respaldo del pg_hba.conf y forma de revertir | Sí: pg_hba.conf.bak | cambios.md |
| 19 | Puerto publicado en el equipo restringido | No: sigue en 0.0.0.0:5434, queda pendiente | cambios.md |
| 20 | Sin contraseñas en los scripts ni en el repositorio | Pendiente de revisar con findstr antes del commit | sql/ |

## Conclusiones

Lo que más me sorprendió es que un servidor recién creado, con la contraseña bien puesta, ya tiene varias cosas abiertas: escucha en todas las interfaces, tiene reglas con trust y deja entrar de cualquier origen. Lo comprobé conectándome desde otro contenedor.

La mayor superficie de ataque era la combinación de listen_addresses = * con la regla abierta de pg_hba.conf. El cambio que más redujo la exposición fue listen_addresses = localhost, porque pasó de aceptar la conexión de otro contenedor a Connection refused, y el que más protegió dentro de la base fue reemplazar pg_hba.conf, porque exige TLS, una contraseña, una base y un usuario concretos.

Aprendí que el firewall, pg_hba.conf y los permisos son capas distintas, y que una contraseña fuerte no sustituye a ninguna: por eso la prueba con otro contenedor dio dos mensajes diferentes (primero lo corta la red y después las reglas de acceso). También que antes de recargar pg_hba.conf conviene revisarlo con pg_hba_file_rules y tener un respaldo, porque un error de sintaxis te deja sin acceso.

Lo que no resolví: el puerto sigue publicado en 0.0.0.0:5434 en mi equipo, el certificado es autofirmado, no modifiqué ningún firewall, y la política de actualizaciones es una propuesta. En producción lo primero que revisaría es quién puede llegar al servidor (red, firewall y pg_hba.conf), y después las cuentas con privilegios de más. El detalle va en el informe.