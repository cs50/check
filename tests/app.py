import json
import lib50.crypto
import os

from flask import Flask, request


app = Flask(__name__)
dirname = os.path.dirname(os.path.abspath(__file__))


def valid_payload(payload):
    """Gets the expected payload."""

    del payload["check50"]["version"]
    del payload["style50"]["version"]
    del payload["tag_hash"]
    with open(os.path.join(dirname, "results.json")) as f:
        return payload == json.load(f)


def valid_signature(payload, signature, public_key=os.path.join(dirname, "public.pem")):
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
