SELECT version();
SHOW port;
SHOW listen_addresses;
SHOW ssl;
SHOW password_encryption;

SELECT pid, usename, datname, client_addr, client_port, application_name
FROM pg_stat_activity;

SHOW config_file;
SHOW hba_file;
SHOW ident_file;
SHOW data_directory;
SHOW log_directory;
SHOW log_connections;
SHOW log_disconnections;

SELECT line_number, type, database, user_name, address, auth_method
FROM pg_hba_file_rules;

SELECT rolname, rolsuper, rolinherit, rolcreaterole, rolcreatedb, rolcanlogin
FROM pg_roles
WHERE rolname !~ '^pg_'
ORDER BY rolname;

SELECT extname, extversion FROM pg_extension ORDER BY extname;

SHOW max_connections;
SHOW superuser_reserved_connections;
SHOW statement_timeout;
SHOW idle_in_transaction_session_timeout;

-- pg_stat_ssl no trae usename ni client_addr, por eso el join
SELECT a.pid, a.usename, a.client_addr, s.ssl, s.version, s.cipher
FROM pg_stat_ssl s
JOIN pg_stat_activity a ON a.pid = s.pid
WHERE s.pid = pg_backend_pid();