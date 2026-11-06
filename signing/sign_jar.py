#!/usr/bin/env python3
"""
Signiert eine Java-Mod-JAR fuer ZombieBuddy (ZBS-Signatur) und prueft das Ergebnis.

Aufruf:  python3 sign_jar.py <pfad/zur/Mod.jar>
Ergebnis: <pfad/zur/Mod.jar>.zbs direkt neben der JAR.

Format laut ZombieBuddy (ZBSVerifier):
  signiert wird der Text  "ZBS:<SteamID64>:<SHA-256 der JAR, Kleinbuchstaben>"  mit Ed25519.
  Die .zbs-Datei hat drei Zeilen: "ZBS", "SteamID64:<17 Ziffern>", "Signature:<128 Hex-Zeichen>".
Der private Schluessel (ed25519-private.der) liegt neben diesem Skript und darf NIE weitergegeben werden.
"""
import hashlib
import os
import sys

from cryptography.hazmat.primitives import serialization

STEAM_ID64 = "76561197980707470"
HERE = os.path.dirname(os.path.abspath(__file__))
KEY_FILE = os.path.join(HERE, "ed25519-private.der")


def load_key():
    with open(KEY_FILE, "rb") as f:
        return serialization.load_der_private_key(f.read(), password=None)


def public_hex(key):
    raw = key.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    return raw.hex()


def sign(jar_path):
    key = load_key()
    with open(jar_path, "rb") as f:
        sha = hashlib.sha256(f.read()).hexdigest().lower()
    payload = ("ZBS:%s:%s" % (STEAM_ID64, sha)).encode("utf-8")
    sig = key.sign(payload)
    zbs_path = jar_path + ".zbs"
    with open(zbs_path, "w", encoding="ascii", newline="\n") as f:
        f.write("ZBS\nSteamID64:%s\nSignature:%s\n" % (STEAM_ID64, sig.hex()))
    # Gegenprobe wie ZombieBuddy: oeffentlicher Schluessel muss die Signatur bestaetigen
    key.public_key().verify(sig, payload)
    return zbs_path, sha


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("JavaModZBS:" + public_hex(load_key()))
        sys.exit(0)
    zbs, sha = sign(sys.argv[1])
    print("signed:", zbs)
    print("jar sha256:", sha)
    print("public key line for Steam profile:  JavaModZBS:" + public_hex(load_key()))
