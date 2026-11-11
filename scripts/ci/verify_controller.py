"""Verify the fixed controller packages and an SDK request without AWS access."""

import json
from importlib.metadata import version
from pathlib import Path
from unittest.mock import patch

import boto3
from botocore.stub import Stubber


def main() -> None:
    requirements = Path(__file__).resolve().parents[2] / "ansible/controller-requirements.txt"
    installed = {}
    for line in requirements.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        name, expected = line.split("==", 1)
        actual = version(name)
        if actual != expected:
            raise RuntimeError(f"{name}: expected {expected}, installed {actual}")
        installed[name] = actual

    # Stubber validates the request/response model; the transport guard also
    # prevents an accidental HTTP request if the stub is bypassed.
    with patch(
        "botocore.httpsession.URLLib3Session.send",
        side_effect=AssertionError("AWS HTTP requests are forbidden in this check"),
    ) as transport:
        client = boto3.client(
            "s3",
            region_name="us-east-1",
            aws_access_key_id="offline-ci",
            aws_secret_access_key="offline-ci",
        )
        with Stubber(client) as stubber:
            stubber.add_response("list_buckets", {"Buckets": []}, {})
            if client.list_buckets() != {"Buckets": []}:
                raise RuntimeError("Unexpected stubbed SDK response")
            stubber.assert_no_pending_responses()
        transport.assert_not_called()

    print(
        json.dumps(
            {
                "controller_versions": installed,
                "sdk_check": "stubbed_list_buckets",
                "http_requests": 0,
            }
        )
    )


if __name__ == "__main__":
    main()
