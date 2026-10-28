"""Disposable TLS terminator for matrix tests; production ingress is platform-managed."""
import socket
import ssl
import threading

context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain('/tls/server.crt', '/tls/server.key')


def pump(source, target):
    try:
        while True:
            data = source.recv(65536)
            if not data:
                break
            target.sendall(data)
    except (OSError, ssl.SSLError):
        pass
    finally:
        try:
            target.shutdown(socket.SHUT_WR)
        except OSError:
            pass


def proxy(connection):
    try:
        with context.wrap_socket(connection, server_side=True) as client:
            with socket.create_connection(('supabase-kong', 8000), timeout=15) as upstream:
                upstream.settimeout(180)
                client.settimeout(180)
                writer = threading.Thread(target=pump, args=(client, upstream), daemon=True)
                writer.start()
                pump(upstream, client)
    except (OSError, ssl.SSLError):
        connection.close()


with socket.create_server(('0.0.0.0', 8443)) as listener:
    print('Disposable TLS ingress listening on 8443', flush=True)
    while True:
        connection, _ = listener.accept()
        threading.Thread(target=proxy, args=(connection,), daemon=True).start()
