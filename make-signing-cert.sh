#!/bin/bash
# Legt einmalig ein eigenes Zertifikat „Pixelcat Signing“ im Schlüsselbund an (kostenlos, selbst signiert).
# build.sh signiert Pixelcat damit statt ad hoc: macOS erkennt die App dann nach jedem Update wieder,
# und die Erlaubnisse (Bedienungshilfen für den Katzenkorb, Steuerung von Spotify und Musik) bleiben erhalten.
#
# Aufruf: ./make-signing-cert.sh
# Mit Sicherung: Das Skript fragt nach einem Passwort und legt eine .p12-Datei an. Damit lässt sich das Zertifikat
# auf einem anderen Mac oder nach einem Neuaufsetzen wieder einspielen (Doppelklick auf die Datei).
# Ohne Frage: NO_BACKUP=1 ./make-signing-cert.sh (Sicherung später in der Schlüsselbundverwaltung exportieren).
set -euo pipefail

NAME="${PIXELCAT_SIGN_IDENTITY:-Pixelcat Signing}"
KEYCHAIN="${KEYCHAIN:-${HOME}/Library/Keychains/login.keychain-db}"
BACKUP="${BACKUP:-${HOME}/Documents/Pixelcat-Signatur-Sicherung.p12}"

if security find-identity -p codesigning "${KEYCHAIN}" 2>/dev/null | grep -q "\"${NAME}\""; then
  echo "✓ Das Zertifikat „${NAME}“ ist schon da. Nichts zu tun."
  exit 0
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/pixelcat-cert.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT

cat > "${WORK}/cert.conf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = ${NAME}
[ ext ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

echo "→ Erzeuge Zertifikat „${NAME}“ (20 Jahre gültig) …"
/usr/bin/openssl req -x509 -newkey rsa:2048 -sha256 -days 7300 -nodes \
  -keyout "${WORK}/key.pem" -out "${WORK}/cert.pem" -config "${WORK}/cert.conf" 2>/dev/null

# Passwort für die Sicherung direkt vom Terminal lesen. Geht das nicht (kein Terminal), ohne Sicherung weiter.
PASSWORD="${BACKUP_PASSWORD:-}"
# NO_BACKUP=1: gar nicht fragen (z. B. wenn das Terminal keine Eingabe annimmt)
if [ "${NO_BACKUP:-0}" != "1" ] && [ -z "${PASSWORD}" ] && { : < /dev/tty; } 2>/dev/null; then
  echo
  echo "Passwort für die Sicherungsdatei eintippen (unsichtbar), dann Enter. Nur Enter = keine Sicherung:"
  read -r -s PASSWORD < /dev/tty || PASSWORD=""
  echo
fi
P12_PASSWORD="${PASSWORD:-pixelcat-import}"
/usr/bin/openssl pkcs12 -export -inkey "${WORK}/key.pem" -in "${WORK}/cert.pem" -name "${NAME}" \
  -out "${WORK}/identity.p12" -passout "pass:${P12_PASSWORD}"

echo "→ Lege es im Schlüsselbund ab (codesign darf es ohne Nachfrage benutzen) …"
security import "${WORK}/identity.p12" -k "${KEYCHAIN}" -P "${P12_PASSWORD}" -T /usr/bin/codesign >/dev/null

if [ -n "${PASSWORD}" ]; then
  cp "${WORK}/identity.p12" "${BACKUP}"
  chmod 600 "${BACKUP}"
  echo "✓ Sicherung: ${BACKUP} (gut aufheben, nicht ins Git-Repository legen)"
else
  echo "  Keine Sicherungsdatei angelegt. Später möglich: Schlüsselbundverwaltung › „${NAME}“ › Rechtsklick › Exportieren."
fi

if security find-identity -p codesigning "${KEYCHAIN}" | grep -q "\"${NAME}\""; then
  echo "✓ Fertig. ./build.sh signiert ab jetzt mit „${NAME}“."
  echo "  Nach dem nächsten Build fragt macOS einmal neu nach den Erlaubnissen – danach bleiben sie."
else
  echo "✗ Das Zertifikat ist nicht im Schlüsselbund aufgetaucht." >&2
  exit 1
fi
