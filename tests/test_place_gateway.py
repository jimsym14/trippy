import io
import json
import unittest
from unittest.mock import patch, MagicMock
from urllib.parse import quote, urlsplit
import bridge_server as bridge

class PlaceGatewayTests(unittest.TestCase):
    def handler(self, path):
        handler = object.__new__(bridge.RequestHandler)
        handler.path = path; handler.headers = {}; handler.replies = []
        handler.send_json = lambda status, payload: handler.replies.append((status, payload))
        handler.send_image = lambda status, mime, data: handler.replies.append((status, mime, data))
        return handler

    def test_long_photo_reference(self):
        name = 'places/ChIJexample/photos/' + 'A' * 900
        handler = self.handler('/api/places/photo?name=' + quote(name, safe=''))
        response = MagicMock(); response.__enter__.return_value = response
        response.read.return_value = b'photo'; response.headers.get_content_type.return_value = 'image/jpeg'
        with patch.object(bridge, 'places_access_allowed', return_value=True), patch.object(bridge, 'places_key', return_value='test'), patch.object(bridge, 'allow_places_request', return_value=True), patch.object(bridge, 'urlopen', return_value=response):
            handler.google_places(urlsplit(handler.path))
        self.assertEqual(handler.replies, [(200, 'image/jpeg', b'photo')])

    def test_reference_registration_and_failure(self):
        records = [{'placeID': 'ChIJexample', 'source': 'videos'}]
        for failed in [False, True]:
            handler = self.handler('/api/places/retain')
            body = json.dumps({'places': records}).encode()
            handler.headers = {'Content-Length': str(len(body))}; handler.rfile = io.BytesIO(body)
            with patch.object(bridge, 'places_access_allowed', return_value=True), patch.object(bridge, 'retain_google_references', side_effect=RuntimeError('private') if failed else None) as retain:
                handler.do_POST()
            retain.assert_called_once_with(records)
            self.assertEqual(handler.replies[0][0], 503 if failed else 200)
            self.assertNotIn('private', str(handler.replies))

    def test_retention_requires_auth(self):
        handler = self.handler('/api/places/retain')
        with patch.object(bridge, 'places_access_allowed', return_value=False), patch.object(bridge, 'retain_google_references') as retain:
            handler.do_POST()
        retain.assert_not_called(); self.assertEqual(handler.replies[0][0], 401)
