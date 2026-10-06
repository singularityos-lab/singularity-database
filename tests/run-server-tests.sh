#!/usr/bin/env bash
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
BUILD_DIR="${1:-${SDB_BUILD_DIR:-$REPO/build/subprojects/singularity-database}}"

find_first () {
    local c
    for c in "$@"; do
        [ -n "$c" ] || continue
        if [ -x "$c" ]; then echo "$c"; return 0; fi
        if command -v "$c" >/dev/null 2>&1; then command -v "$c"; return 0; fi
    done
    return 1
}

if [ -z "${PG_BINDIR:-}" ]; then
    if command -v initdb >/dev/null 2>&1 && command -v pg_ctl >/dev/null 2>&1; then
        PG_BINDIR="$(dirname "$(command -v initdb)")"
    else
        for d in $(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V -r) /usr/local/pgsql/bin; do
            if [ -x "$d/initdb" ] && [ -x "$d/postgres" ]; then PG_BINDIR="$d"; break; fi
        done
    fi
fi
MARIADBD="$(find_first "${MARIADBD:-}" mariadbd mysqld /usr/sbin/mariadbd /usr/sbin/mysqld /usr/libexec/mariadbd /usr/libexec/mysqld)" || MARIADBD=""
MARIADB_INSTALL_DB="$(find_first "${MARIADB_INSTALL_DB:-}" mariadb-install-db mysql_install_db)" || MARIADB_INSTALL_DB=""
MARIADB_CLIENT="$(find_first "${MARIADB_CLIENT:-}" mariadb mysql)" || MARIADB_CLIENT=""
SSHD="$(find_first "${SSHD:-}" sshd /usr/sbin/sshd)" || SSHD=""
OPENSSL="$(find_first openssl)" || OPENSSL=""
SSH_KEYGEN="$(find_first ssh-keygen)" || SSH_KEYGEN=""
PYTHON="$(find_first python3)" || PYTHON=""

have_pg=0
have_my=0
have_ssh=0
[ -n "${PG_BINDIR:-}" ] && [ -x "$PG_BINDIR/initdb" ] && [ -x "$PG_BINDIR/postgres" ] && [ -x "$PG_BINDIR/psql" ] && have_pg=1
[ -n "$MARIADBD" ] && [ -n "$MARIADB_INSTALL_DB" ] && [ -n "$MARIADB_CLIENT" ] && have_my=1
[ -n "$SSHD" ] && [ -n "$SSH_KEYGEN" ] && command -v ssh >/dev/null 2>&1 && have_ssh=1

if [ -z "$OPENSSL" ] || [ -z "$PYTHON" ] || { [ $have_pg = 0 ] && [ $have_my = 0 ]; }; then
    echo "servers: skipped, need openssl, python3 and PostgreSQL or MariaDB server binaries"
    exit 77
fi

for t in database-pg-test database-mysql-test database-client-test; do
    if [ ! -x "$BUILD_DIR/$t" ]; then
        echo "servers: $BUILD_DIR/$t not found, build it first or pass the build dir"
        exit 1
    fi
done

OWN_SCRATCH=0
if [ -n "${SDB_SERVER_SCRATCH:-}" ]; then
    S="$SDB_SERVER_SCRATCH"
    mkdir -p "$S" || exit 1
    S="$(cd "$S" && pwd)"
else
    S="$(mktemp -d "${TMPDIR:-/tmp}/sdb-servers.XXXXXX")" || exit 1
    OWN_SCRATCH=1
fi

PIDS=()

stop_pid () {
    local pid="$1" sig="${2:-TERM}"
    [ -n "$pid" ] || return 0
    [ "$pid" -ge 1000 ] 2>/dev/null || return 0
    [ -r "/proc/$pid/cmdline" ] || return 0
    if tr '\0' ' ' < "/proc/$pid/cmdline" | grep -qF "$S"; then
        kill "-$sig" "$pid" 2>/dev/null
        for _ in $(seq 1 60); do
            [ -e "/proc/$pid" ] || return 0
            sleep 0.25
        done
        kill -KILL "$pid" 2>/dev/null
    fi
}

cleanup () {
    local p
    if [ -f "$S/pg/data/postmaster.pid" ]; then
        p="$(head -1 "$S/pg/data/postmaster.pid" 2>/dev/null)"
        stop_pid "$p" INT
    fi
    if [ -f "$S/my/mysqld.pid" ]; then
        p="$(cat "$S/my/mysqld.pid" 2>/dev/null)"
        stop_pid "$p" TERM
    fi
    if [ -f "$S/ssh/sshd.pid" ]; then
        p="$(cat "$S/ssh/sshd.pid" 2>/dev/null)"
        stop_pid "$p" TERM
    fi
    for p in "${PIDS[@]}"; do stop_pid "$p" TERM; done
    if [ "${OWN_SOCK:-0}" = 1 ]; then
        rm -rf -- "${SOCK:?}/pg" "${SOCK:?}/my.sock" "${SOCK:?}/my.sock.lock"
        rmdir -- "${SOCK:?}" 2>/dev/null
    fi
    if [ $OWN_SCRATCH = 1 ]; then
        rm -rf -- "${S:?}/pg" "${S:?}/my" "${S:?}/ssh" "${S:?}/tls" "${S:?}/client" "${S:?}/tmp" "${S:?}/sock"
        rmdir -- "${S:?}" 2>/dev/null
    fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

free_port () {
    "$PYTHON" -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}

wait_for () {
    local tries="$1"; shift
    for _ in $(seq 1 "$tries"); do
        "$@" >/dev/null 2>&1 && return 0
        sleep 0.25
    done
    return 1
}

mkdir -p "$S/tls" "$S/tmp"
export TMPDIR="$S/tmp" TMP="$S/tmp" TEMP="$S/tmp"

make_ca () {
    local dir="$1"
    [ -f "$dir/ca.crt" ] && return 0
    timeout 60 "$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=SDB Test CA" -keyout "$dir/ca.key" -out "$dir/ca.crt" 2>/dev/null || return 1
    timeout 60 "$OPENSSL" req -newkey rsa:2048 -nodes -subj "/CN=localhost" -keyout "$dir/server.key" -out "$dir/server.csr" 2>/dev/null || return 1
    printf "subjectAltName=DNS:localhost,IP:127.0.0.1\n" > "$dir/ext.cnf"
    timeout 60 "$OPENSSL" x509 -req -in "$dir/server.csr" -CA "$dir/ca.crt" -CAkey "$dir/ca.key" -CAcreateserial -days 3650 -extfile "$dir/ext.cnf" -out "$dir/server.crt" 2>/dev/null || return 1
    timeout 60 "$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=Other CA" -keyout "$dir/other.key" -out "$dir/other.crt" 2>/dev/null || return 1
    chmod 600 "$dir/server.key"
}
make_ca "$S/tls" || { echo "servers: certificate generation failed"; exit 1; }

SOCK="$S/sock"
OWN_SOCK=0
if [ ${#SOCK} -gt 70 ]; then
    SOCK="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/sdb.XXXXXX")" || exit 1
    OWN_SOCK=1
fi
mkdir -p "$SOCK"
chmod 700 "$SOCK"

check_sock () {
    if [ ${#1} -gt 100 ]; then
        echo "servers: socket path too long ($1), set a shorter XDG_RUNTIME_DIR or SDB_SERVER_SCRATCH"
        exit 1
    fi
}

start_pg () {
    local D="$S/pg" B="$PG_BINDIR"
    mkdir -p "$D" "$SOCK/pg"
    PG_PORT="$(free_port)"
    check_sock "$SOCK/pg/.s.PGSQL.$PG_PORT"
    rm -rf -- "${D:?}/data"
    timeout 120 "$B/initdb" -D "$D/data" -U sdb_admin --auth=trust -E UTF8 --locale=C.UTF-8 > "$D/initdb.log" 2>&1 \
        || timeout 120 "$B/initdb" -D "$D/data" -U sdb_admin --auth=trust -E UTF8 --locale=C > "$D/initdb.log" 2>&1 || return 1
    local listen="127.0.0.1"
    if "$PYTHON" -c 'import socket; s=socket.socket(); s.bind(("127.0.0.2", 0))' 2>/dev/null; then listen="127.0.0.1,127.0.0.2"; fi
    cat >> "$D/data/postgresql.conf" <<CONF
listen_addresses = '$listen'
port = $PG_PORT
unix_socket_directories = '$SOCK/pg'
ssl = on
ssl_cert_file = '$S/tls/server.crt'
ssl_key_file = '$S/tls/server.key'
password_encryption = 'scram-sha-256'
shared_buffers = 16MB
max_connections = 40
CONF
    cat > "$D/data/pg_hba.conf" <<HBA
local all sdb_admin trust
local all all scram-sha-256
host all sdb_admin 127.0.0.1/32 trust
host all sdb_md5 127.0.0.1/32 md5
host all sdb_plain 127.0.0.1/32 password
host all all 127.0.0.1/32 scram-sha-256
host all all 127.0.0.2/32 scram-sha-256
HBA
    setsid "$B/postgres" -D "$D/data" </dev/null > "$D/server.log" 2>&1 &
    PIDS+=($!)
    local isready="$B/pg_isready"
    if [ -x "$isready" ]; then
        wait_for 120 timeout 5 "$isready" -h "$SOCK/pg" -p "$PG_PORT" || return 1
    else
        wait_for 120 test -S "$SOCK/pg/.s.PGSQL.$PG_PORT" || return 1
    fi
    local P=(timeout 30 "$B/psql" -h "$SOCK/pg" -p "$PG_PORT" -U sdb_admin -d postgres -q -v ON_ERROR_STOP=1)
    "${P[@]}" -c "CREATE ROLE sdb_scram LOGIN PASSWORD 'scrampass' CREATEDB" \
        && "${P[@]}" -c "SET password_encryption='md5'; CREATE ROLE sdb_md5 LOGIN PASSWORD 'md5pass'" \
        && "${P[@]}" -c "CREATE ROLE sdb_plain LOGIN PASSWORD 'plainpass'" \
        && "${P[@]}" -c "CREATE DATABASE sdb_test OWNER sdb_scram" \
        && "${P[@]}" -c "GRANT ALL ON DATABASE sdb_test TO sdb_md5, sdb_plain" || return 1
    export SDB_PG_HOST=127.0.0.1 SDB_PG_PORT="$PG_PORT" SDB_PG_SOCKET_DIR="$SOCK/pg" SDB_PG_CA="$S/tls/ca.crt" SDB_PG_OTHER_CA="$S/tls/other.crt" SDB_PG_ADMIN=sdb_admin SDB_PG_DB=sdb_test
}

start_my () {
    local D="$S/my"
    mkdir -p "$D/tmp"
    MY_PORT="$(free_port)"
    check_sock "$SOCK/my.sock"
    rm -rf -- "${D:?}/data"
    cat > "$D/my.cnf" <<CNF
[mariadbd]
datadir=$D/data
socket=$SOCK/my.sock
pid-file=$D/mysqld.pid
port=$MY_PORT
bind-address=127.0.0.1
log-error=$D/error.log
tmpdir=$D/tmp
ssl-ca=$S/tls/ca.crt
ssl-cert=$S/tls/server.crt
ssl-key=$S/tls/server.key
plugin-load-add=auth_mysql_sha2
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci
skip-name-resolve
innodb_buffer_pool_size=32M
innodb_log_file_size=16M
max_allowed_packet=64M
performance_schema=OFF
CNF
    timeout 300 "$MARIADB_INSTALL_DB" --defaults-file="$D/my.cnf" --datadir="$D/data" --auth-root-authentication-method=normal --skip-test-db > "$D/install.log" 2>&1 || return 1
    setsid "$MARIADBD" --defaults-file="$D/my.cnf" </dev/null > "$D/server.log" 2>&1 &
    PIDS+=($!)
    local M=(timeout 30 "$MARIADB_CLIENT" --no-defaults -S "$SOCK/my.sock" -uroot)
    wait_for 240 "${M[@]}" -e "SELECT 1" || return 1
    "${M[@]}" -e "
CREATE USER 'sdb_native'@'%' IDENTIFIED VIA mysql_native_password USING PASSWORD('nativepass');
CREATE USER 'sdb_native'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('nativepass');
GRANT ALL PRIVILEGES ON *.* TO 'sdb_native'@'%' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO 'sdb_native'@'localhost' WITH GRANT OPTION;
CREATE USER 'sdb_sha2'@'%' IDENTIFIED VIA caching_sha2_password USING PASSWORD('sha2pass');
CREATE USER 'sdb_sha2'@'localhost' IDENTIFIED VIA caching_sha2_password USING PASSWORD('sha2pass');
GRANT ALL PRIVILEGES ON *.* TO 'sdb_sha2'@'%';
GRANT ALL PRIVILEGES ON *.* TO 'sdb_sha2'@'localhost';
FLUSH PRIVILEGES;" || return 1
    export SDB_MY_HOST=127.0.0.1 SDB_MY_PORT="$MY_PORT" SDB_MY_SOCKET="$SOCK/my.sock" SDB_MY_CA="$S/tls/ca.crt" SDB_MY_OTHER_CA="$S/tls/other.crt"
    export SDB_MY_NATIVE_USER=sdb_native SDB_MY_NATIVE_PASS=nativepass SDB_MY_SHA2_USER=sdb_sha2 SDB_MY_SHA2_PASS=sha2pass
}

start_ssh () {
    local D="$S/ssh"
    mkdir -p "$D"
    chmod 700 "$D"
    SSH_PORT="$(free_port)"
    rm -f -- "${D:?}/host_ed25519" "${D:?}/host_ed25519.pub" "${D:?}/client_key" "${D:?}/client_key.pub" "${D:?}/wrong_key" "${D:?}/wrong_key.pub"
    timeout 30 "$SSH_KEYGEN" -q -t ed25519 -N "" -f "$D/host_ed25519" || return 1
    timeout 30 "$SSH_KEYGEN" -q -t ed25519 -N "" -f "$D/client_key" || return 1
    timeout 30 "$SSH_KEYGEN" -q -t ed25519 -N "" -f "$D/wrong_key" || return 1
    cp "$D/client_key.pub" "$D/authorized_keys"
    chmod 600 "$D/authorized_keys"
    printf "[127.0.0.1]:%s %s\n" "$SSH_PORT" "$(cut -d' ' -f1,2 "$D/host_ed25519.pub")" > "$D/known_hosts"
    local libexec extra=""
    libexec="$(cd "$(dirname "$SSHD")/.." && pwd)/libexec"
    [ -x "$libexec/sshd-session" ] && extra="SshdSessionPath $libexec/sshd-session"
    [ -x "$libexec/sshd-auth" ] && extra="$extra
SshdAuthPath $libexec/sshd-auth"
    cat > "$D/sshd_config" <<CFG
Port $SSH_PORT
ListenAddress 127.0.0.1
HostKey $D/host_ed25519
PidFile $D/sshd.pid
AuthorizedKeysFile $D/authorized_keys
StrictModes no
UsePAM no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AllowTcpForwarding yes
AllowStreamLocalForwarding yes
PermitTTY no
LogLevel VERBOSE
$extra
CFG
    setsid "$SSHD" -D -e -f "$D/sshd_config" </dev/null > "$D/sshd.log" 2>&1 &
    PIDS+=($!)
    wait_for 80 "$PYTHON" -c "import socket; socket.create_connection(('127.0.0.1', $SSH_PORT), 1).close()" || return 1
    export SDB_SSH_PORT="$SSH_PORT" SDB_SSH_USER="$(id -un)" SDB_SSH_KEY="$D/client_key" SDB_SSH_WRONG_KEY="$D/wrong_key" SDB_SSH_KNOWN="$D/known_hosts"
}

status=0
if [ $have_pg = 1 ]; then
    if start_pg; then echo "servers: PostgreSQL on 127.0.0.1:$PG_PORT"; else echo "servers: PostgreSQL failed to start, see $S/pg"; status=1; fi
else
    echo "servers: PostgreSQL binaries not found, pg server tests skipped"
fi
if [ $have_my = 1 ]; then
    if start_my; then echo "servers: MariaDB on 127.0.0.1:$MY_PORT"; else echo "servers: MariaDB failed to start, see $S/my"; status=1; fi
else
    echo "servers: MariaDB binaries not found, mysql server tests skipped"
fi
if [ $have_ssh = 1 ]; then
    if start_ssh; then echo "servers: sshd on 127.0.0.1:$SSH_PORT"; else echo "servers: sshd failed to start, see $S/ssh"; status=1; fi
else
    echo "servers: sshd not found, ssh tunnel tests skipped"
fi
[ $status = 0 ] || exit 1

mkdir -p "$S/client"
export SDB_CLIENT_SCRATCH="$S/client"

for t in database-pg-test database-mysql-test database-client-test; do
    echo "== $t"
    ( cd "$S/tmp" && timeout 600 "$BUILD_DIR/$t" ) || { echo "servers: $t failed"; status=1; }
done
exit $status
