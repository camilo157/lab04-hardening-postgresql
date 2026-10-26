# Cambios realizados

Camilo Angulo | LAB-04 | 25 de octubre de 2026

Todos los cambios los hice en el contenedor pg-lab04 (PostgreSQL 16.15), que es solo para esta práctica. Las contraseñas de las cuentas no están en ningún archivo del repositorio: los roles se crean sin contraseña en el script y la contraseña se asignó aparte con \password.

## Lista de cambios

| # | Cambio | Cómo | Por qué | Cómo volver atrás |
|---|---|---|---|---|
| 1 | Cuentas separadas: app_user y consulta_user, sin SUPERUSER, CREATEDB ni CREATEROLE, y una base basedatos_app | sql/02-roles.sql | La aplicación no debe conectarse con postgres. Con permisos mínimos, una aplicación comprometida no puede administrar el servidor | Quitar los permisos y borrar los roles y la base (DROP DATABASE, DROP OWNED BY y DROP ROLE) |
| 2 | TLS activado: certificado autofirmado, ssl = on | openssl en el directorio de datos, chmod 600 a server.key, ALTER SYSTEM SET ssl = on y recarga | Sin TLS las credenciales y las consultas viajan sin cifrar. Además las reglas hostssl lo necesitan | ALTER SYSTEM RESET ssl y recargar |
| 3 | Registro de conexiones y desconexiones | log_connections y log_disconnections en on | Sin esto no se sabe quién entró ni quién fue rechazado | ALTER SYSTEM RESET y recargar |
| 4 | Límite a sesiones inactivas dentro de una transacción | idle_in_transaction_session_timeout = 60 s | Una sesión que se queda abierta dentro de una transacción retiene recursos y bloqueos | ALTER SYSTEM RESET y recargar |
| 5 | pg_hba.conf nuevo, con reglas específicas y rechazo por defecto | Copia del original como pg_hba.conf.bak, reemplazo con configuracion/pg_hba.hardened.conf, revisión con pg_hba_file_rules y recarga | Se quitó el trust y la regla que permitía cualquier origen | Copiar pg_hba.conf.bak sobre pg_hba.conf y recargar |
| 6 | listen_addresses = localhost | ALTER SYSTEM y reinicio del contenedor (este parámetro no se aplica con una recarga) | El servidor no tiene por qué escuchar en interfaces que no usa | ALTER SYSTEM RESET listen_addresses y reiniciar |

Antes de recargar el pg_hba.conf nuevo revisé la vista pg_hba_file_rules: salieron seis reglas con la columna error vacía. Eso confirmó que PostgreSQL entendía el archivo antes de aplicarlo, y evita quedarse sin acceso por un error de sintaxis. El respaldo pg_hba.conf.bak pesa 5743 bytes, igual que el pg_hba.conf original del servidor sin modificar.

## Actividad 3: listen_addresses

- Configuración encontrada: * (todas las interfaces).
- Interfaces necesarias: en el laboratorio, solo la local, porque las pruebas se hacen desde el propio servidor. En un servidor real con la aplicación en otro equipo, solo la interfaz privada donde está ese equipo.
- Interfaces innecesarias: todas las demás.
- Resultado: dentro del contenedor, /proc/net/tcp pasó de 00000000:1538 (0.0.0.0:5432) a 0100007F:1538 (127.0.0.1:5432), y en IPv6 escucha solo en ::1. La conexión desde otro contenedor pasó de conectar a Connection refused.

Comparación de las dos arquitecturas:

```
Internet -> Firewall -> Servidor PostgreSQL (5432)

Internet X Firewall -> Red privada -> Servidor PostgreSQL
```

La segunda reduce mejor la exposición. En la primera el puerto 5432 está al alcance de internet y todo depende de que la contraseña aguante y de que no haya una vulnerabilidad en el servidor. En la segunda el servidor no es alcanzable desde afuera, y solo llega quien ya está dentro de la red privada. Se bloquea el acceso antes de que se hable con PostgreSQL.

## Actividad 5: la regla permisiva

```
Regla actual:
host    all    all    all    scram-sha-256
```

Esta era la última regla del pg_hba.conf original. El valor all en la dirección equivale a 0.0.0.0/0 y a ::/0.

- Qué bases permite: todas.
- Qué usuarios permite: todos, incluido el superusuario postgres.
- Qué direcciones permite: cualquiera, IPv4 e IPv6.
- Método: scram-sha-256, que es bueno, pero es lo único que se exige.
- Por qué es una exposición innecesaria: con un solo dato (la contraseña) cualquier equipo que llegue al puerto puede entrar, incluso como superusuario. Se vio en la prueba: desde otro contenedor (172.17.0.3) conecté al servidor (172.17.0.2) con la contraseña de postgres.
- Qué necesito saber para restringirla: qué aplicación se conecta, a qué base, con qué usuario, desde qué IP o red, y si debe exigirse TLS.

```
Problema:
Permite a cualquier usuario, a cualquier base y desde cualquier origen.

Origen que realmente necesita acceso:
En el laboratorio, 127.0.0.1. En un entorno real, la red del servidor de aplicación (por ejemplo 10.10.10.0/24).

Base de datos:
basedatos_app

Usuario:
app_user (y consulta_user para lectura)

Regla propuesta:
hostssl    basedatos_app    app_user    127.0.0.1/32    scram-sha-256
```

## Actividad 6: reglas con mínimo privilegio

Cada regla fija base, usuario, origen y método, y es lo más específica que pude hacerla:

```
local     all             postgres                        peer
local     all             all                             scram-sha-256
hostssl   basedatos_app   app_user        127.0.0.1/32    scram-sha-256
hostssl   basedatos_app   consulta_user   127.0.0.1/32    scram-sha-256
host      all             all             0.0.0.0/0       reject
host      all             all             ::/0            reject
```

- El administrador solo entra por el socket local, y el sistema verifica que sea el usuario postgres del sistema (peer).
- Las dos cuentas de la aplicación solo entran a su base, desde 127.0.0.1, con TLS y contraseña.
- Todo lo demás se rechaza. Las dos reglas reject usan 0.0.0.0/0 y ::/0, pero aquí el rango amplio es para negar el acceso y no para permitirlo.
- El orden importa porque PostgreSQL usa la primera regla que coincide: las específicas van antes de los reject.

Las pruebas y lo que dice el registro:

| Prueba | Resultado en el registro |
|---|---|
| app_user con TLS desde 127.0.0.1 | Entra: scram-sha-256 por la regla de la línea 4, con TLSv1.3 |
| app_user sin TLS | Rechazada: pg_hba.conf rejects connection ... no encryption |
| postgres por red | Rechazada: pg_hba.conf rejects connection ... SSL encryption |
| postgres por el socket local siendo root | Peer authentication failed: la regla de la línea 2 exige el usuario postgres del sistema |
| Otro contenedor hacia el servidor | Connection refused: con listen_addresses en localhost no llega ni a pg_hba.conf |

El mensaje de las dos últimas no es el mismo, y se debe a que son dos capas distintas: primero la red (listen_addresses) y después las reglas de acceso (pg_hba.conf). No son equivalentes.

## Actividad 9: tipos de cuentas

| Cuenta | Propósito | LOGIN | Privilegios | Estado |
|---|---|---|---|---|
| DBA | Administración | Sí | Administrativos | Por ahora se usa postgres, solo por socket local con peer. Propuesta: un rol de DBA con nombre propio, sin SUPERUSER, para el trabajo diario |
| app_user | La aplicación | Sí | SELECT, INSERT y UPDATE sobre las tablas necesarias | Creada |
| consulta_user | Consulta | Sí | Solo SELECT | Creada |

Comprobé los límites en el script 02: app_user pudo leer e insertar, pero DROP TABLE dio must be owner of table clientes_demo y CREATE ROLE dio permission denied to create role. consulta_user pudo leer pero el INSERT dio permission denied for table clientes_demo.

## Actividad 14: política de firewall (propuesta)

No modifiqué ningún firewall. Con el ejemplo del laboratorio (PostgreSQL en 10.10.10.20, puerto 5432, y solo la red DBA 10.10.10.0/24 con acceso):

| Origen | Destino | Puerto | Acción |
|---|---|---|---|
| 10.10.10.0/24 | PostgreSQL (10.10.10.20) | 5432 | Permitir |
| Cualquier otro origen | PostgreSQL | 5432 | Denegar |

El firewall y pg_hba.conf no son equivalentes. El firewall decide quién llega al puerto y actúa antes de que el servidor intervenga. pg_hba.conf decide quién puede autenticarse, con qué usuario, a qué base y con qué método, una vez que ya llegó. Si falla el firewall, pg_hba.conf sigue protegiendo, y al revés.

## Observaciones

- El puerto del contenedor sigue publicado en el equipo en 0.0.0.0:5434 (docker port y netstat lo muestran). PostgreSQL ya no escucha fuera de localhost dentro del contenedor, pero el puerto abierto en el equipo es superficie innecesaria. Lo correcto sería crear el contenedor con -p 127.0.0.1:5434:5432 o sin publicar el puerto. No lo cambié, y queda como pendiente.
- pg_hba.conf.bak quedó con grupo root en lugar de postgres, con permisos 0600. No es grave, pero lo corregiría.
- La consulta de TLS del lab no se puede ejecutar tal cual, porque pg_stat_ssl no tiene las columnas usename ni client_addr. Usé un join con pg_stat_activity.
- Después del cambio, los comandos de administración local se ejecutan con docker exec -u postgres, porque el acceso local de postgres pasó de trust a peer.