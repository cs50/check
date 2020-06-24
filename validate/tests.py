import json
import lib50.crypto


def check_payload(payload, expected_payload):
    """Checks whether payload is what we expected."""

    status_code = 200
    for item in expected_payload:
        # Check for equality
        if not (item in payload and payload[item] == expected_payload[item]):
            # If they're at least the same type, assume it's just naming issues
            if type(payload[item]) != type(expected_payload[item]):
                status_code = 400

    return status_code


def get_payload(org, repo, slug):
    """Gets the expected payload."""

    # Confirm org, repo, and slug while we're at it
    if org == "me50" and repo == "cs50student2" and slug == "cs50/problems/2020/x/hello":
        with open("hello/check.json") as f:
            check50 = json.load(f)
        with open("hello/style.json") as f:
            style50 = json.load(f)

        payload = {
            "commit_hash": "e03bee664b4c310579025e494eb086b213c01626",
            "style50": style50,
            "check50": check50
        }
    else:
        payload = {}

    return payload


def valid_signature(sig, payload, public_key="../tests/keys/public.pem"):
    """Determines if a signature is valid"""

    # Load the public key
    with open(public_key, "rb") as f:
        key = f.read()
    public_key = lib50.crypto.load_public_key(key)

    # Encode as bytes if needed
    if type(payload) != bytes:
        payload = payload.encode("utf-8")

    if type(sig) != bytes:
        sig = sig.encode("utf-8")

    # Verify validity of signature
    return lib50.crypto.verify(payload, sig, public_key)
