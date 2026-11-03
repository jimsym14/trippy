from copy import deepcopy
import unittest
from trippy.sources.unattended import prepare_chunks
from trippy.sources.unattended_recovery import recover
from tests.test_unattended import REGISTRY, record, response


class RecoveryTests(unittest.TestCase):
    def fixture(self):
        chunk=prepare_chunks([record()],REGISTRY)[0]
        return chunk,response(chunk),chunk['payload']['entries'][0]['claims'][0]['id']

    def test_unsupported_value_preserved_in_quarantine_not_mapped(self):
        chunk,raw,claim_id=self.fixture()
        raw['records']['a']['facets']=[{'key':'place_type','value':'church','claim_ids':[claim_id]}]
        raw['records']['a']['unrepresented_claim_ids']=[]; original=deepcopy(raw)
        recovered=recover(chunk,raw,REGISTRY)
        self.assertEqual(raw,original)
        self.assertEqual(recovered['response']['records']['a']['facets'],[])
        self.assertEqual(recovered['quarantined_facets'][0]['facet']['value'],'church')
        self.assertEqual(recovered['response']['records']['a']['unrepresented_claim_ids'],[claim_id])

    def test_missing_accounting_becomes_unrepresented_not_a_fact(self):
        chunk,raw,claim_id=self.fixture();raw['records']['a']['unrepresented_claim_ids']=[]
        recovered=recover(chunk,raw,REGISTRY)
        self.assertEqual(recovered['response']['records']['a']['unrepresented_claim_ids'],[claim_id])
        self.assertFalse(recovered['response']['records']['a']['facets'])

    def test_overlap_removed_from_unrepresented_only(self):
        chunk,raw,claim_id=self.fixture()
        raw['records']['a']['facets']=[{'key':'service','value':'coffee','claim_ids':[claim_id]}]
        recovered=recover(chunk,raw,REGISTRY)
        self.assertEqual(recovered['response']['records']['a']['unrepresented_claim_ids'],[])
        self.assertEqual(recovered['response']['records']['a']['facets'],raw['records']['a']['facets'])

    def test_quarantine_cannot_hide_invented_evidence(self):
        chunk,raw,_=self.fixture()
        raw['records']['a']['facets']=[{'key':'place_type','value':'church','claim_ids':['invented']}]
        with self.assertRaises(ValueError):recover(chunk,raw,REGISTRY)


if __name__=='__main__':unittest.main()
