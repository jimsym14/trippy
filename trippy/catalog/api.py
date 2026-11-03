"""Catalog routes share the backend's verified user/admin dependencies."""

from typing import Literal
from uuid import UUID
from fastapi import Depends, Query

from trippy.backend.common import DomainError
from trippy.backend.contracts import Request
from .service import Catalog


class Publication(Request):
    expected_active_version_id: UUID | None = None


def register_routes(app, engine, principal, admin, request_key):
    catalog = Catalog(engine)

    @app.get("/v2/catalog/{city_id}/places")
    def places(city_id:UUID,user=Depends(principal),q:str=Query(default="",max_length=160),
        family:Literal["food","coffee","sights","outdoors","nightlife","shopping","stay","transport","other"]|None=None,
        shortlisted_only:bool=False,after:UUID|None=None,limit:int=Query(default=30,ge=1,le=100),
        latitude:float|None=Query(default=None,ge=-89,le=89),longitude:float|None=Query(default=None,ge=-180,le=180),
        radius_m:int=Query(default=2000,ge=1,le=20000)):
        if (latitude is None)!=(longitude is None):
            raise DomainError("coordinate_pair_required",422)
        return catalog.search(str(city_id),query=q,family=family,shortlisted_only=shortlisted_only,
            after=str(after) if after else None,limit=limit,latitude=latitude,longitude=longitude,radius_m=radius_m)

    @app.get("/v2/catalog/{city_id}/coverage")
    def coverage(city_id:UUID,user=Depends(principal)):
        return catalog.coverage(str(city_id))

    @app.post("/v2/admin/catalog/{city_id}/versions/{version_id}/publish")
    def publish(city_id:UUID,version_id:UUID,body:Publication,user=Depends(admin),key=Depends(request_key)):
        return catalog.publish(str(city_id),str(version_id),principal=user,key=key,
            expected_active=str(body.expected_active_version_id) if body.expected_active_version_id else None)
