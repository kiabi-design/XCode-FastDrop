#!/usr/bin/env python3
"""
Логгер протокола ОРИГИНАЛЬНОГО FastDrop (Android / Windows / ...).

Запустите на компьютере в той же Wi-Fi сети:
    python3 scripts/sniff_fastdrop.py

Потом в оригинальном приложении отправьте любой маленький файл (лучше .txt с текстом
"HELLO123") на IP этого компьютера. Скрипт покажет:
  * UDP-пакеты на порту 14681 (так устройства находят друг друга);
  * первые байты TCP-соединения на порту 14680 (заголовок файла) и общий размер.

Скопируйте весь вывод и пришлите — по нему можно точно воспроизвести протокол.
"""
import socket
import sys
import threading
import time

TCP_PORT = 14680
UDP_PORT = 14681
PEEK = 600


def dump(label: str, data: bytes) -> None:
    print(f"\n--- {label} ({len(data)} bytes) ---")
    print("HEX :", data.hex(" "))
    print("TEXT:", repr(data.decode("utf-8", errors="replace")))


def udp_listener() -> None:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    s.bind(("", UDP_PORT))
    print(f"[UDP] слушаю {UDP_PORT}")
    while True:
        data, addr = s.recvfrom(65535)
        dump(f"UDP от {addr[0]}:{addr[1]}", data)


def handle(conn: socket.socket, addr) -> None:
    print(f"\n[TCP] соединение от {addr[0]}:{addr[1]}")
    conn.settimeout(4)
    first = b""
    try:
        first = conn.recv(PEEK)
    except socket.timeout:
        pass
    dump("TCP начало потока", first)

    # Многие протоколы ждут ответ «принято» — пробуем несколько вариантов и смотрим реакцию.
    total = len(first)
    for reply in (b"\x01", b"OK\n", b"ACCEPT\n"):
        try:
            conn.sendall(reply)
            print(f"[TCP] отправил ответ {reply!r}")
            break
        except OSError:
            break
    conn.settimeout(6)
    try:
        while True:
            chunk = conn.recv(1 << 20)
            if not chunk:
                break
            if total < PEEK * 2:
                dump("TCP продолжение", chunk[:PEEK])
            total += len(chunk)
    except socket.timeout:
        pass
    print(f"[TCP] всего получено {total} байт, соединение закрыто")
    conn.close()


def tcp_listener() -> None:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("", TCP_PORT))
    s.listen(5)
    print(f"[TCP] слушаю {TCP_PORT}")
    while True:
        conn, addr = s.accept()
        threading.Thread(target=handle, args=(conn, addr), daemon=True).start()


if __name__ == "__main__":
    threading.Thread(target=udp_listener, daemon=True).start()
    threading.Thread(target=tcp_listener, daemon=True).start()
    ip = "?"
    try:
        probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        probe.connect(("8.8.8.8", 80))
        ip = probe.getsockname()[0]
    except OSError:
        pass
    print(f"Мой IP: {ip}. Отправьте файл из оригинального приложения на этот IP. Ctrl+C — выход.")
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        sys.exit(0)
