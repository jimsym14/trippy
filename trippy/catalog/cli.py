"""Local catalog import/publish/search tools. No AI or remote database writes."""

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
from uuid import UUID

from trippy.data.database import make_engine, sqlite_url
from .importer import CITY_ID, import_extract
from .service import Catalog


def main(argv=None):
    parser=argparse.ArgumentParser(description="Trippy local-only catalog tools")
    parser.add_argument("operation",choices=("import","publish","coverage","search"))
    parser.add_argument("--database",type=Path,default=Path(".local/catalog.sqlite"))
    parser.add_argument("--source",type=Path)
    parser.add_argument("--geography-source",type=Path)
    parser.add_argument("--version",type=UUID)
    parser.add_argument("--expected-active",type=UUID)
    parser.add_argument("--query",default="")
    args=parser.parse_args(argv)
    if not args.database.is_file():parser.error("An existing migrated local database is required")
    engine=make_engine(sqlite_url(args.database))
    try:
        if args.operation=="import":
            if not args.source or not args.geography_source:parser.error("Import requires source and geography-source")
            result=import_extract(engine,args.source,json.loads(args.geography_source.read_text()),
                geography_retrieved_at=datetime.fromtimestamp(args.geography_source.stat().st_mtime,timezone.utc))
        elif args.operation=="publish":
            if not args.version:parser.error("Publish requires version")
            result=Catalog(engine).publish(CITY_ID,str(args.version),
                expected_active=str(args.expected_active) if args.expected_active else None)
        elif args.operation=="coverage":result=Catalog(engine).coverage(CITY_ID)
        else:result=Catalog(engine).search(CITY_ID,query=args.query,limit=10)
        print(json.dumps(result,ensure_ascii=False,default=str,indent=2))
    finally:engine.dispose()


if __name__=="__main__":main()
