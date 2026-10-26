# Línea base de seguridad: PostgreSQL 16

Camilo Angulo | LAB-04 | 25 de octubre de 2026

Entorno: contenedor Docker pg-lab04 con PostgreSQL 16.15, creado desde la imagen postgres:16 con la configuración por defecto, solo para esta práctica. El "antes" es lo que salió del servidor recién creado; los archivos y la red del "antes" los saqué de un contenedor temporal con la misma configuración. El "después" es el servidor con los cambios de cambios.md.

## Comparación antes y después

| Control | Antes | Después | Justificación |
|---|---|---|---|
| listen_addresses | * (todas las interfaces) | localhost | El servidor solo debe aceptar conexiones donde se necesite. Con * cualquier equipo de la red podía intentar conectarse |
| pg_hba.conf | 7 reglas: 6 con trust (local, loopback y replicación) y host all all all scram-sha-256 | 6 reglas: peer para postgres, scram local, dos hostssl específicas y dos reject | Cada regla limita base, usuario, origen y método. Se quitó el trust y la regla que permitía cualquier origen |
| Método de autenticación | trust en local y loopback, scram-sha-256 para el resto | peer para el administrador local, scram-sha-256 para lo demás | Trust deja entrar sin contraseña. password_encryption ya era scram-sha-256 y no se cambió |
| Usuarios administrativos | Solo postgres (superusuario), con acceso por red si se conocía la contraseña | Sigue siendo el único superusuario, pero solo entra por el socket local con peer | Un superusuario no debe poder entrar por red |
| Cuentas de aplicación | Ninguna: la aplicación habría usado postgres | app_user (SELECT, INSERT, UPDATE) y consulta_user (solo SELECT), sin SUPERUSER, CREATEDB ni CREATEROLE | Mínimo privilegio: una aplicación comprometida no puede administrar el servidor |
| Puerto | 5432 en el servidor, publicado en el equipo en 0.0.0.0:5434 | Igual: no se cambió | Cambiar el puerto no es hardening. El puerto publicado sigue abierto en el equipo y queda como hallazgo pendiente |
| TLS | ssl = off | ssl = on, y las reglas hostssl obligan a usarlo. En el registro aparece TLSv1.3 con TLS_AES_256_GCM_SHA384 | Sin TLS el tráfico y las credenciales viajan sin cifrar. El certificado es autofirmado y solo vale para el laboratorio |
| Permisos del sistema operativo | Directorio de datos drwx------ y archivos de configuración -rw-------, todos de postgres | Igual, y el pg_hba.conf nuevo y server.key también con -rw------- y dueño postgres | Ya estaban bien. Hay que mantenerlos y verificar los archivos nuevos |
| Extensiones | Solo plpgsql | Solo plpgsql | No hay funcionalidad innecesaria instalada |
| Conexiones | max_connections 100, superuser_reserved_connections 3, statement_timeout 0, idle_in_transaction_session_timeout 0, log_connections y log_disconnections en off | idle_in_transaction_session_timeout en 60 s y los dos registros de conexión en on; lo demás igual | Una sesión abierta sin actividad consume recursos. Los registros permiten ver quién entró y quién fue rechazado |
| Conexión desde otro contenedor | Conectó con la contraseña de postgres (origen 172.17.0.3, servidor 172.17.0.2) | Connection refused | Es la comprobación de que se redujo la exposición |

## Línea base propuesta

### Red

- Interfaces: PostgreSQL solo escucha donde hace falta. En el laboratorio, localhost. En un servidor real con la aplicación en otro equipo, la IP privada del servidor y no *.
- Puerto: se documenta (5432), sin considerarlo una medida de seguridad.
- Firewall (propuesta, no lo modifiqué): permitir el origen 10.10.10.0/24 hacia PostgreSQL en el puerto 5432 y denegar cualquier otro origen. El firewall y pg_hba.conf son capas distintas y se necesitan las dos.
- En Docker, publicar el puerto solo en 127.0.0.1 o no publicarlo.

### Autenticación

- Contraseñas con scram-sha-256. Nada de trust ni de md5.
- El administrador entra por el socket local con peer.
- Las contraseñas son largas, únicas, no se guardan en scripts ni en repositorios y se cambian cuando haya sospecha de exposición.

### Autorización

- Cuentas separadas: administración (DBA), aplicación y consulta.
- La aplicación y la consulta no son superusuarios ni pueden crear roles o bases.
- Se revoca el acceso de PUBLIC a la base y se da solo CONNECT y los permisos por tabla que cada cuenta necesita.

### Configuración

- ssl en on, y reglas hostssl para las cuentas que se conectan por red.
- log_connections y log_disconnections en on.
- idle_in_transaction_session_timeout en 60 s. statement_timeout y max_connections se ajustan según la aplicación.
- Solo las extensiones necesarias.

### Sistema operativo

- Directorio de datos con permisos 0700 y archivos de configuración con 0600, dueño postgres.
- server.key con 0600. Las copias de respaldo de la configuración con los mismos permisos.

### Cifrado

- TLS en las conexiones. En producción, un certificado de una autoridad confiable y sslmode=verify-full en los clientes.
- Contraseñas guardadas con hash scram-sha-256, no con cifrado reversible.
- Datos sensibles cifrados por columna, como se vio en LAB-02.

### Mantenimiento

- Actualizar las versiones menores de PostgreSQL (aquí 16.15) con un procedimiento documentado (propuesta).
- Revisar este checklist de forma periódica, y también cada vez que cambie la aplicación.
- Documentar cada cambio de configuración y poder volver al estado anterior (respaldo del pg_hba.conf original).

## Lo que no hice o queda pendiente

- No modifiqué ningún firewall, solo lo diseñé.
- El puerto sigue publicado en 0.0.0.0:5434 en el equipo anfitrión.
- El certificado es autofirmado.
- La política de actualizaciones es una propuesta.
- El archivo pg_hba.conf.bak tiene grupo root, no postgres.