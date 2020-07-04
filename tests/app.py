import json
import lib50.crypto

from flask import Flask, request


app = Flask(__name__)


def valid_payload(payload):
    """Gets the expected payload."""

    del payload["tag_hash"]
    with open("results.json") as f:
        return payload == json.load(f)


def valid_signature(payload, signature, public_key=f"tests/public.pem"):
    """Determines if a signature is valid"""

    with open(public_key, "rb") as f:
        return lib50.crypto.verify(
            payload,
            signature,
            lib50.crypto.load_public_key(f.read())
        )


@app.route("/validate", methods=["GET", "POST"])
def validate():
    """Validates the incoming response. Returns 200 if signature and JSON data are valid; else 400."""

    assert valid_signature(request.data, request.headers["X-Payload-Signature"])
    assert valid_payload(request.get_json())

    return ""
