SELECT 'CREATE DATABASE basedatos_app'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'basedatos_app')
\gexec

-- cuentas separadas por función, sin superusuario
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_user') THEN
        CREATE ROLE app_user LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'consulta_user') THEN
        CREATE ROLE consulta_user LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
    END IF;
END
$$;

\c basedatos_app

CREATE TABLE IF NOT EXISTS clientes_demo (
    id BIGSERIAL PRIMARY KEY,
    nombre VARCHAR(120) NOT NULL,
    ciudad VARCHAR(80)
);

TRUNCATE clientes_demo RESTART IDENTITY;
INSERT INTO clientes_demo (nombre, ciudad) VALUES
('Ana', 'Culiacán'), ('Luis', 'Los Mochis'), ('María', 'Mazatlán');

REVOKE ALL ON DATABASE basedatos_app FROM PUBLIC;
GRANT CONNECT ON DATABASE basedatos_app TO app_user, consulta_user;
GRANT USAGE ON SCHEMA public TO app_user, consulta_user;
GRANT SELECT, INSERT, UPDATE ON clientes_demo TO app_user;
GRANT USAGE ON SEQUENCE clientes_demo_id_seq TO app_user;
GRANT SELECT ON clientes_demo TO consulta_user;

SELECT rolname, rolsuper, rolinherit, rolcreaterole, rolcreatedb, rolcanlogin
FROM pg_roles
WHERE rolname !~ '^pg_'
ORDER BY rolname;

-- la aplicación puede leer y escribir, pero no administrar
SET ROLE app_user;
SELECT * FROM clientes_demo;
INSERT INTO clientes_demo (nombre, ciudad) VALUES ('Prueba app', 'Culiacán');
DROP TABLE clientes_demo;
CREATE ROLE intruso;
RESET ROLE;

-- la cuenta de consulta solo lee
SET ROLE consulta_user;
SELECT * FROM clientes_demo;
INSERT INTO clientes_demo (nombre, ciudad) VALUES ('Prueba consulta', 'Culiacán');
RESET ROLE;