#!/usr/bin/env python3
import base64
import pathlib
import unittest
from update_feed import inspect_feed

SIGNATURE = base64.b64encode(bytes(64)).decode()
FEED = f'''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
<sparkle:version>3</sparkle:version><sparkle:shortVersionString>0.1.1</sparkle:shortVersionString>
<sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion><sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
<enclosure url="https://github.com/codebooker/StudioPrompter/releases/download/0.1.1/StudioPrompter-0.1.1-macos-arm64.zip" length="100" sparkle:edSignature="{SIGNATURE}"/>
</item></channel></rss>'''


class UpdateFeedChecks(unittest.TestCase):
    def test_initial_feed(self):
        self.assertIsNone(inspect_feed('<rss><channel/></rss>'))
        inspect_feed(pathlib.Path('updates/appcast.xml').read_bytes())

    def test_stable_release(self):
        self.assertEqual(inspect_feed(FEED, tag='0.1.1')['build'], 3)

    def test_reject_bad_releases(self):
        for changed in [
            FEED.replace('https://github.com/', 'http://github.com/'),
            FEED.replace('codebooker/StudioPrompter', 'someone/another-app'),
            FEED.replace('>arm64<', '>x86_64<'),
            FEED.replace('>13.0<', '>14.0<'),
            FEED.replace('>3<', '>two<'),
            FEED.replace(SIGNATURE, 'unsigned'),
            FEED.replace('length="100"', 'length="0"'),
            FEED.replace('0.1.1', '0.1.1-beta.1'),
            FEED.replace('<item>', '<item><sparkle:channel>beta</sparkle:channel>'),
        ]:
            with self.subTest(changed=changed):
                with self.assertRaises(ValueError):
                    inspect_feed(changed, tag='0.1.1')

    def test_reject_wrong_tag_empty_and_downgrade(self):
        for kwargs in [dict(tag='0.2.0'), dict(previous=FEED), dict(previous=FEED.replace('>3<', '>4<'))]:
            with self.assertRaises(ValueError):
                inspect_feed(FEED, **kwargs)
        with self.assertRaises(ValueError):
            inspect_feed('<rss><channel/></rss>', tag='0.1.1')
        with self.assertRaises(ValueError):
            inspect_feed('<html>error</html>')

if __name__ == '__main__':
    unittest.main()
