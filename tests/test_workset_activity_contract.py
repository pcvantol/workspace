"""Consumer JSON Schema regex semantics; this is not installed producer evidence."""
import unittest
from workspace_control.advisory_contract import _check
from workspace_control.worklist_peer import WorklistError
class ActivityPatternTests(unittest.TestCase):
    def testSourcePrefixAndClosedIdentityPatterns(self):
        _check('/v1/approved-workset-activity/own/events/abc', {'type':'string','pattern':'^/v1/approved-workset-activity/'})
        for bad in ['/foreign/v1/approved-workset-activity/own', 'https://foreign/v1/approved-workset-activity/']:
            with self.assertRaises(WorklistError):_check(bad, {'type':'string','pattern':'^/v1/approved-workset-activity/'})
        for bad in ['before'+'a'*64, 'a'*64+'after']:
            with self.assertRaises(WorklistError):_check(bad, {'type':'string','pattern':'^[0-9a-f]{64}$'})
