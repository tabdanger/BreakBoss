import base64, os, re, sys
# Turns the App Store Connect key into a .p8 file whatever shape Codemagic hands it over in:
# the file text, the text with literal \n, everything on one line, base64 of the file, or the bare body.
# Codemagic's integration can also hand over a reference instead of the text: @file:<path>,
# @env:<variable> (the form its CLI tools take) or a plain path to the .p8.
raw = os.environ.get("KEY", "").strip().strip('"').strip("'")
shape = "text"
for _ in range(3):
    if raw.startswith("@file:") or (raw.startswith(("/", "~")) and os.path.isfile(os.path.expanduser(raw))):
        shape = "a file reference"
        path = os.path.expanduser(raw[6:] if raw.startswith("@file:") else raw)
        raw = open(path).read().strip() if os.path.isfile(path) else ""
    elif raw.startswith("@env:"):
        shape = "an environment variable reference"
        raw = os.environ.get(raw[5:], "").strip()
    else:
        break
raw = raw.replace("\\n", "\n").replace("\r", "")
def body_of(text):
    m = re.search(r"-----BEGIN ([A-Z ]*)PRIVATE KEY-----(.*?)-----END [A-Z ]*PRIVATE KEY-----", text, re.S)
    return (m.group(1), m.group(2)) if m else None
found = body_of(raw)
if not found:
    try:
        decoded = base64.b64decode(re.sub(r"\s+", "", raw), validate=True).decode("utf-8", "replace")
    except Exception:
        decoded = ""
    found = body_of(decoded) or ("", raw)
kind, body = found
body = re.sub(r"\s+", "", body)
if not body:
    sys.exit("empty key")
lines = [body[i:i + 64] for i in range(0, len(body), 64)]
label = f"{kind}PRIVATE KEY"
sys.stdout.write(f"-----BEGIN {label}-----\n" + "\n".join(lines) + f"\n-----END {label}-----\n")
print(f"key: {shape}, {'had BEGIN/END lines' if body_of(raw) else 'no BEGIN/END lines'}, {len(raw)} characters, {raw.count(chr(10)) + 1} lines", file=sys.stderr)
