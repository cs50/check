from flask import Flask, request
from hashlib import sha512
from tests import check_payload, get_payload, valid_signature


app = Flask(__name__)


@app.route("/validate", methods=["GET", "POST"])
def validate():
    """Validates the incoming response. Returns 200 if signature and JSON data are valid; else 400."""

    status_code = 400
    if request.is_json:
        payload = request.get_json()

        # Check signature, then compare payload
        if valid_signature(request.headers["X-Payload-Signature"], request.data):
            expected_payload = get_payload(payload["org"], payload["repo"], payload["slug"])
            status_code = check_payload(payload, expected_payload)

    return "", status_code


if __name__ == "__main__":
    app.run(port=8080)
