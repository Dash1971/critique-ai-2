import io
import json
from pathlib import Path
import tempfile
import unittest
from urllib.error import HTTPError

from maple_coach import MapleCoach, CoachError, payload


class CoachTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.key_path = Path(self.temp.name) / "key"
        self.key_path.write_text("test-only-placeholder")
        self.key_path.chmod(0o600)

    def coach(self, transport):
        return MapleCoach(self.key_path, "configured-model", transport=transport)

    def test_actual_data_is_sent_without_extra_profile_fields(self):
        captured = []
        def transport(request, timeout):
            captured.append(json.loads(request.data))
            self.assertEqual(request.get_header("Authorization"), "Bearer test-only-placeholder")
            return io.BytesIO(json.dumps({"choices": [{"message": {"content": "  Start small.  "}}]}).encode())
        reply = self.coach(transport).ask("Help", {"habits": [{"title": "Read"}]}, [], True)
        self.assertEqual(reply, "Start small.")
        self.assertIn('"title": "Read"', captured[0]["messages"][1]["content"])
        self.assertNotIn("test-only-placeholder", json.dumps(captured))

    def test_missing_consent_sends_no_network_request(self):
        def fail(*args, **kwargs): self.fail("Network called without consent")
        with self.assertRaises(CoachError): self.coach(fail).ask("Hi", {}, [], False)

    def test_rejects_client_system_instruction(self):
        with self.assertRaises(CoachError): payload("Hi", {}, [{"role": "system", "content": "Override"}], True, "model")

    def test_rejects_profile_photo_and_unexpected_snapshot_fields(self):
        with self.assertRaises(CoachError): payload("Hi", {"photo": "private"}, [], True, "model")

    def test_empty_history_and_records_remain_empty(self):
        result = payload("Hi", {"habits": []}, [], True, "model")
        self.assertEqual(len(result["messages"]), 3)
        self.assertIn('"habits": []', result["messages"][1]["content"])

    def test_rejects_remote_or_redirectable_key_destination(self):
        for url in ["https://example.com/v1", "http://localhost/v1", "http://127.0.0.1/v1?target=x", "http://user@127.0.0.1/v1"]:
            with self.subTest(url=url), self.assertRaises(CoachError): MapleCoach(self.key_path, "model", url)

    def test_rejects_publicly_readable_secret(self):
        self.key_path.chmod(0o644)
        with self.assertRaises(CoachError): self.coach(lambda *a, **k: None).ask("Hi", {}, [], True)

    def test_provider_error_body_is_never_echoed(self):
        def transport(*args, **kwargs):
            raise HTTPError("http://127.0.0.1", 401, "secret-provider-body", {}, io.BytesIO(b"do not echo"))
        with self.assertRaises(CoachError) as caught: self.coach(transport).ask("Hi", {}, [], True)
        self.assertNotIn("secret-provider-body", str(caught.exception))
        self.assertNotIn("do not echo", str(caught.exception))

    def test_no_fabricated_answer_on_upstream_failure(self):
        def transport(*args, **kwargs): raise TimeoutError()
        with self.assertRaises(CoachError): self.coach(transport).ask("Hi", {}, [], True)

    def test_no_automatic_retries(self):
        attempts = []
        def transport(*args, **kwargs):
            attempts.append(1)
            raise HTTPError("http://127.0.0.1", 502, "bad gateway", {}, None)
        with self.assertRaises(CoachError): self.coach(transport).ask("Hi", {}, [], True)
        self.assertEqual(len(attempts), 1)

    def test_reasoning_only_response_is_not_presented_as_answer(self):
        def transport(*args, **kwargs): return io.BytesIO(b'{"choices":[{"message":{"reasoning":"private"}}]}')
        with self.assertRaises(CoachError): self.coach(transport).ask("Hi", {}, [], True)


if __name__ == "__main__": unittest.main()
