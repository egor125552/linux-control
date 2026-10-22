#!/usr/bin/env bash
set -euo pipefail
umask 077
echo '=== REMOTE DESKTOP COMMANDER: NEW AUTHORIZATION ==='
echo "HOST=$(hostname)"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
cat > "$temp/cert.pem" <<'CERTIFICATE'
-----BEGIN CERTIFICATE-----
MIIERTCCAq2gAwIBAgIUB9TasWlWOYdtm6EzYUx5o1pBxb8wDQYJKoZIhvcNAQEL
BQAwMjEwMC4GA1UEAwwnRXBoZW1lcmFsIEdpdEh1YiBSdW5uZXIgQXV0aCBEaWFn
bm9zdGljMB4XDTI2MTAyMjIxMTQwNFoXDTI2MTAyMzIxMTQwNFowMjEwMC4GA1UE
AwwnRXBoZW1lcmFsIEdpdEh1YiBSdW5uZXIgQXV0aCBEaWFnbm9zdGljMIIBojAN
BgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEA1WHVREqPZtb40UxX35gLazSrUTQz
I1qAGXG293/wMyKhWSVHoYCAasY+0YyEuHRfkFSuOfwBwIZYVtA1SuLCm00xtHue
KgyzEbCNnKkcWdI7YvivK2w9yWH6tFuhcYOm1wbLNmqW7Vol2Gr6CKgwqg56zJ/j
zrFMgR9JfGT+UyueC4x6AmMbwa62IklGJ1fESgnyoN/51J2ie/3OttwUEkuvTGmc
q8ES586pTbdgfmrzZc560ArNMDnQT/iDYGkGAy8m8oaRpoQPPtGB4MbrjU+wVEZE
TwWpS7NoZ7IzLyiWwoc7ZHqnKP7wKz0JA5//owWhPjr47LaQXlMLmTA6JsHM7H4D
y0L/mOx4epI8TyqIOzjpphatI/LJkFFK+QfZE0b+d6ofP7G9YWVcuTHwJgdBf3sw
rai6mVAauJcYQounUkQxyqbY+rT/z21sQf8ta4IxhwKmN0laztYnZ9yd8XeRFF0M
hFwcLoUq/h7Xytn6awWkdzDOoXDq6PxVVu93AgMBAAGjUzBRMB0GA1UdDgQWBBT7
ZeS6TEEwU0At+LQsuxTh2z6OYzAfBgNVHSMEGDAWgBT7ZeS6TEEwU0At+LQsuxTh
2z6OYzAPBgNVHRMBAf8EBTADAQH/MA0GCSqGSIb3DQEBCwUAA4IBgQAX2GswAfYF
hjwhAO/SY8JdE5kfULtbD8H3vQVlhv7Cdrq2vSzpo7VRqER456ytjwARews7oHqK
O007iVWC6cYHiDelwJABtZDCOqc4PO+Ifv+R8fVmHQ+3/7daAhyVjeAEEzuMtB0h
yr6Gk54c6BI1f7NfT4+9SgVhEwDD7HIbDoqcEj+huIy/1Lvm3navMjX4PxkAFhez
hlCOJY7gWoxu8noPUWiY+RHdTWm/9zY1e6a2dzuFXVnL3d+CvsWmNMIG4EpVaL6f
WIZkCW8tdDkDC68jkhvjFXmjIpt3rS3NSz0n7L+wXKDOFUJCbYcr3B3tuAaleKjm
UQRMGIlGfVR3KhqI9UuIo/kPh2AriJ2/vdFB0TI6GhRmjgXqJueZGI1qF5T1xAPi
f+/99LhHLTdEVvbGa2174EDulcpgnggWoH4fEyucomV4GnxBGwwRJ909+X1kfnid
TF7wngvi1ARdHFYtUxhyjvHXkr0rIFnAGoVA2u7hapyvQtOPQSwCOC0=
-----END CERTIFICATE-----
CERTIFICATE
systemctl restart desktop-commander-remote.service
sleep 7
echo "SERVICE_STATUS=$(systemctl is-active desktop-commander-remote.service || true)"
journalctl -u desktop-commander-remote.service --since '2 minutes ago' --no-pager -o cat | tail -n 180 > "$temp/journal.txt"
echo "JOURNAL_LINES=$(wc -l < "$temp/journal.txt")"
openssl cms -encrypt -binary -aes256 -in "$temp/journal.txt" -out "$temp/journal.cms" -outform DER -recip "$temp/cert.pem"
echo 'BEGIN_ENCRYPTED_JOURNAL'
base64 -w 0 "$temp/journal.cms"
echo
echo 'END_ENCRYPTED_JOURNAL'
echo '=== END AUTHORIZATION JOB ==='
