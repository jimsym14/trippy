import copy
from datetime import timedelta
from hashlib import sha256
import json
from pathlib import Path
import struct
import tempfile
import unittest
from uuid import uuid4

from alembic import command
from alembic.config import Config
from fastapi.testclient import TestClient
from sqlalchemy import func, insert, select, update

from trippy.backend.api import create_app
from trippy.backend.auth import Principal
from trippy.backend.common import DomainError, transaction, utcnow
from trippy.catalog.acquire import BARCELONA_BBOX, point_wkb
from trippy.catalog.importer import CITY_ID, import_extract, load_extract
from trippy.catalog.normalize import normalize_feature, shortlist, stable
from trippy.catalog.service import Catalog
from trippy.data import schema_v3 as s
from trippy.data.database import make_engine, sqlite_url

ROOT=Path(__file__).resolve().parents[1]
OWNER="00000000-0000-4000-8000-000000000001"


def feature(key,name="Synthetic museum",category="museum",x=2.17,y=41.38,closed=False):
    return {"type":"Feature","geometry":{"type":"Point","coordinates":[x,y]},"properties":{
        "id":key,"version":1,"names":{"primary":name,"common":{"ca":"Museu Sintètic"}},
        "taxonomy":{"primary":category,"hierarchy":[category]},"confidence":.9,
        "operating_status":"permanently_closed" if closed else "open",
        "addresses":[{"freeform":"Synthetic 1","locality":"Barcelona","country":"ES"}],
        "websites":["https://example.org/venue"],
        "sources":[{"dataset":"Overture","license":"CDLA-Permissive-2.0","record_id":key,"property":""}]}}


def geography_document():
    return {"entities":{q:{"labels":{"en":{"value":name}},"lastrevid":1,"claims":{"P625":[{
        "rank":"normal","mainsnak":{"datavalue":{"value":{"latitude":41.38,"longitude":2.17,
        "globe":"http://www.wikidata.org/entity/Q2"}}}}]}} for q,name in
        (("Q46","Synthetic continent"),("Q29","Synthetic country"),("Q5705","Synthetic region"),("Q1492","Synthetic city"))}}


class CatalogTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.folder=Path(self.temp.name)
        self.url=sqlite_url(self.folder/"catalog.sqlite")
        config=Config(str(ROOT/"alembic.ini"))
        config.set_main_option("sqlalchemy.url",self.url)
        command.upgrade(config,"head")
        self.engine=make_engine(self.url)
        self.catalog=Catalog(self.engine)
        self.features=[feature("one"),feature("two","Cafè Síntètic","cafe",2.18,41.39),
                       feature("three","Synthetic restaurant","restaurant",2.175,41.385),
                       feature("closed","Closed museum","museum",2.177,41.388,closed=True)]
        self.private_place=str(uuid4())
        with transaction(self.engine) as c:
            c.execute(insert(s.app_users).values(id=OWNER))
            c.execute(insert(s.user_places).values(id=self.private_place,owner_id=OWNER,name="Private place"))

    def tearDown(self):
        self.engine.dispose()
        self.temp.cleanup()

    def source(self,features=None,filename="source.geojsonl"):
        path=self.folder/filename
        data="".join(json.dumps(v,ensure_ascii=False)+"\n" for v in (features if features is not None else self.features))
        path.write_text(data)
        manifest={"provider":"overture","complete":True,"sha256":sha256(data.encode()).hexdigest(),
            "artifact_bytes":len(data.encode()),"records":len(features if features is not None else self.features),
            "release":"2026-10-21.0","bbox":list(BARCELONA_BBOX),"scope_label":"Synthetic pilot bbox",
            "collection_url":"https://stac.overturemaps.org/2026-10-21.0/places/place/collection.json",
            "retrieved_at":utcnow().isoformat()}
        path.with_suffix(path.suffix+".manifest.json").write_text(json.dumps(manifest))
        return path

    def imported(self,path=None,**kwargs):
        return import_extract(self.engine,path or self.source(),geography_document(),geography_retrieved_at=utcnow(),**kwargs)

    def publish(self,result,expected=None):
        return self.catalog.publish(CITY_ID,result["catalog_version_id"],expected_active=expected)

    def count(self,table):
        with self.engine.connect() as c:return c.execute(select(func.count()).select_from(table)).scalar_one()

    def test_basic_import_preserves_private_data_and_is_not_ai_enrichment(self):
        result=self.imported()
        self.assertEqual(result["report"]["accepted_records"],4)
        self.assertEqual(result["report"]["enriched_records"],0)
        self.assertEqual(self.count(s.entities),4)
        self.assertEqual(self.count(s.geographies),4)
        self.assertEqual(self.count(s.geography_references),4)
        self.assertEqual(self.count(s.user_places),1)
        self.assertEqual(self.catalog.search(CITY_ID)["items"],[])
        self.publish(result)
        output=self.catalog.search(CITY_ID)["items"]
        self.assertEqual(len(output),3)
        self.assertTrue(all(v["data_level"]=="basic_source_inventory" and not v["is_enriched"] for v in output))
        self.assertTrue(all("rating" not in v and "source_properties" not in v for v in output))
        with self.engine.connect() as c:
            self.assertIsNone(c.execute(select(s.entities.c.official_url).where(s.entities.c.id==stable("overture:one"))).scalar_one())

    def test_identical_extract_is_idempotent_and_exact_source_id_duplicates_are_removed(self):
        path=self.source([self.features[0],copy.deepcopy(self.features[0])])
        first=self.imported(path)
        second=self.imported(path)
        self.assertTrue(second["already_imported"])
        self.assertEqual(first["catalog_version_id"],second["catalog_version_id"])
        self.assertEqual(first["report"]["duplicate_records"],1)
        self.assertEqual(self.count(s.entities),1)
        self.assertEqual(self.count(s.catalog_snapshots),1)

    def test_conflicting_same_source_id_fails_without_database_writes(self):
        changed=copy.deepcopy(self.features[0]);changed["properties"]["names"]["primary"]="Different name"
        with self.assertRaisesRegex(ValueError,"Conflicting records"):
            self.imported(self.source([self.features[0],changed]))
        self.assertEqual(self.count(s.entities),0)

    def test_partial_tampered_or_count_mismatched_artifact_cannot_be_imported(self):
        for change in ("hash","complete","count"):
            path=self.source(filename=change+".geojsonl")
            manifest_path=path.with_suffix(path.suffix+".manifest.json")
            manifest=json.loads(manifest_path.read_text())
            if change=="hash":path.write_text(path.read_text()+" ")
            elif change=="complete":manifest["complete"]=False
            else:manifest["records"]=999
            manifest_path.write_text(json.dumps(manifest))
            with self.assertRaises(ValueError):self.imported(path)
        self.assertEqual(self.count(s.catalog_versions),0)

    def test_invalid_geometry_unknown_license_and_outside_scope_are_counted_not_invented(self):
        outside=feature("outside",x=3,y=42)
        invalid=feature("line");invalid["geometry"]["type"]="LineString"
        restricted=feature("license");restricted["properties"]["sources"][0]["license"]="ODbL-1.0"
        result=self.imported(self.source([self.features[0],outside,invalid,restricted]))
        self.assertEqual(result["report"]["accepted_records"],1)
        self.assertEqual(result["report"]["rejected_records"],3)

    def test_nearby_same_name_with_distinct_source_ids_remains_separate_and_review_needed(self):
        near=feature("near",x=2.17001,y=41.38001)
        result=self.imported(self.source([self.features[0],near]))
        self.assertEqual(result["report"]["identity_conflicts"],1)
        self.assertEqual(result["report"]["shortlist"]["actual"],0)
        self.assertEqual(self.count(s.entities),2)
        self.publish(result)
        self.assertEqual({v["identity_status"] for v in self.catalog.search(CITY_ID)["items"]},{"review_needed"})

    def test_branches_with_same_name_far_apart_are_not_merged_or_flagged(self):
        distant=feature("distant",x=2.19,y=41.40)
        result=self.imported(self.source([self.features[0],distant]))
        self.assertEqual(result["report"]["identity_conflicts"],0)
        self.assertEqual(result["report"]["shortlist"]["actual"],2)

    def test_refresh_stays_draft_until_atomic_publish_and_can_roll_back(self):
        first=self.imported()
        self.publish(first)
        changed=copy.deepcopy(self.features)
        changed[0]["properties"]["names"]["primary"]="New museum name"
        second=self.imported(self.source(changed,"refresh.geojsonl"))
        self.assertEqual(self.catalog.search(CITY_ID,query="New museum")["items"],[])
        self.publish(second,first["catalog_version_id"])
        self.assertEqual(len(self.catalog.search(CITY_ID,query="New museum")["items"]),1)
        self.assertEqual(self.count(s.entities),4)
        self.publish(first,second["catalog_version_id"])
        self.assertEqual(self.catalog.search(CITY_ID,query="New museum")["items"],[])
        self.assertEqual(self.count(s.user_places),1)

    def test_removed_source_entity_is_retired_without_deleting_private_reference(self):
        first=self.imported();self.publish(first)
        with transaction(self.engine) as c:
            c.execute(update(s.user_places).where(s.user_places.c.id==self.private_place).values(catalog_entity_id=stable("overture:one")))
        second=self.imported(self.source(self.features[1:],"removed.geojsonl"))
        self.publish(second,first["catalog_version_id"])
        self.assertEqual(self.count(s.entities),4)
        with self.engine.connect() as c:
            self.assertEqual(c.execute(select(s.entities.c.publication_status).where(s.entities.c.id==stable("overture:one"))).scalar_one(),"retired")
            self.assertEqual(c.execute(select(s.user_places.c.catalog_entity_id)).scalar_one(),stable("overture:one"))

    def test_private_or_restricted_source_cannot_be_published_or_leak_into_search(self):
        result=self.imported()
        with transaction(self.engine) as c:
            source_id=c.execute(select(s.catalog_import_runs.c.source_id)).scalar_one()
            c.execute(update(s.source_records).where(s.source_records.c.id==source_id).values(owner_id=OWNER,scope_key=OWNER))
        with self.assertRaises(DomainError):self.publish(result)
        self.assertEqual(self.catalog.search(CITY_ID)["items"],[])

    def test_policy_revocation_hides_published_inventory(self):
        result=self.imported();self.publish(result)
        with transaction(self.engine) as c:
            c.execute(update(s.source_policies).where(s.source_policies.c.provider=="overture-places").values(status="restricted"))
        self.assertEqual(self.catalog.search(CITY_ID)["items"],[])
        with self.assertRaises(DomainError):self.catalog.coverage(CITY_ID)

    def test_expired_retention_hides_search_and_coverage_and_blocks_republication(self):
        result=self.imported();self.publish(result)
        with transaction(self.engine) as c:
            source_id=c.execute(select(s.catalog_import_runs.c.source_id)).scalar_one()
            c.execute(update(s.source_records).where(s.source_records.c.id==source_id).values(retention_until=utcnow()-timedelta(seconds=1)))
        self.assertEqual(self.catalog.search(CITY_ID)["items"],[])
        with self.assertRaises(DomainError):self.catalog.coverage(CITY_ID)
        with self.assertRaises(DomainError):self.publish(result,result["catalog_version_id"])

    def test_field_permissions_remove_address_and_website_without_exposing_source_payload(self):
        result=self.imported();self.publish(result)
        with transaction(self.engine) as c:
            c.execute(update(s.source_policies).where(s.source_policies.c.provider=="overture-places").values(
                allowed_fields=["name","coordinates","category"]))
        items=self.catalog.search(CITY_ID)["items"]
        self.assertEqual(len(items),3)
        self.assertTrue(all(v["address"] is None and v["website_url"] is None for v in items))

    def test_expected_active_version_blocks_late_publish(self):
        result=self.imported();self.publish(result)
        with self.assertRaises(DomainError) as caught:self.publish(result)
        self.assertEqual(caught.exception.code,"catalog_revision_conflict")

    def test_accents_aliases_pagination_and_exact_radius_search(self):
        result=self.imported();self.publish(result)
        self.assertEqual(len(self.catalog.search(CITY_ID,query="cafe sintetic")["items"]),1)
        self.assertEqual(len(self.catalog.search(CITY_ID,query="Museu Sintetic")["items"]),3)
        first=self.catalog.search(CITY_ID,limit=1)
        second=self.catalog.search(CITY_ID,after=first["next_cursor"],limit=10)
        ids=[v["entity_id"] for v in first["items"]+second["items"]]
        self.assertEqual(len(set(ids)),3)
        nearby=self.catalog.search(CITY_ID,latitude=41.38,longitude=2.17,radius_m=600)
        self.assertEqual([v["entity_id"] for v in nearby["items"]],[stable("overture:one")])
        self.assertEqual(nearby["items"][0]["distance_m"],0)

    def test_size_cap_failure_rolls_back_catalog_and_preserves_private_data(self):
        with self.assertRaises(DomainError):self.imported(max_database_bytes=1)
        self.assertEqual(self.count(s.entities),0)
        self.assertEqual(self.count(s.geographies),0)
        self.assertEqual(self.count(s.user_places),1)

    def test_catalog_api_requires_identity_and_admin_publish_cannot_be_spoofed(self):
        result=self.imported()
        class TestAuth:
            def verify(self,token):return Principal(OWNER,token=="admin")
        with TestClient(create_app(self.engine,auth=TestAuth())) as client:
            path=f"/v2/admin/catalog/{CITY_ID}/versions/{result['catalog_version_id']}/publish"
            self.assertEqual(client.post(path,headers={"Authorization":"Bearer user","Idempotency-Key":"publish"},json={}).status_code,403)
            self.assertEqual(client.get(f"/v2/catalog/{CITY_ID}/places").status_code,401)
            headers={"Authorization":"Bearer admin","Idempotency-Key":"publish"}
            first=client.post(path,headers=headers,json={})
            self.assertEqual(first.status_code,200)
            self.assertEqual(client.post(path,headers=headers,json={}).json(),first.json())
            self.assertEqual(client.get(f"/v2/catalog/{CITY_ID}/places",headers=headers).status_code,200)
            self.assertEqual(client.get(f"/v2/catalog/{CITY_ID}/places?latitude=41",headers=headers).status_code,422)


class SourceNormalizationTests(unittest.TestCase):
    def test_only_source_point_geometry_is_used_and_both_byte_orders_work(self):
        for little,endian in ((1,"<"),(0,">")):
            value=bytes([little])+struct.pack(endian+"Idd",1,2.17,41.38)
            self.assertEqual(point_wkb(value),(2.17,41.38))
        with self.assertRaises(ValueError):point_wkb(bytes([1])+struct.pack("<Idd",2,2.17,41.38))

    def test_legacy_categories_and_v2_taxonomy_keep_source_category(self):
        original=feature("legacy",category="specialty_coffee_shop")
        original["properties"]["categories"]=original["properties"].pop("taxonomy")
        record=normalize_feature(original,BARCELONA_BBOX)
        self.assertEqual(record["source_category"],"specialty_coffee_shop")
        self.assertEqual(record["family"],"coffee")

    def test_shortlist_uses_real_records_is_bounded_and_never_sets_enriched(self):
        records=[normalize_feature(feature(str(i),name=f"Restaurant {i}",category="restaurant",
            x=2.08+(i%20)*.006,y=41.32+(i%15)*.007),BARCELONA_BBOX) for i in range(600)]
        report=shortlist(records)
        self.assertEqual(report["actual"],500)
        self.assertEqual(sum(v["shortlist_rank"] is not None for v in records),500)
        self.assertTrue(all("is_enriched" not in v for v in records))


if __name__=="__main__":unittest.main()
