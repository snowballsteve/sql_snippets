
/* 
Table endpoints. Stores all the endpoints of all the lines.
*/
drop table if exists endpoints;
create table endpoints as
select
ST_SetSRID(ST_StartPoint(geom),3734) as start
,ST_SetSRID(ST_EndPoint(geom),3734) as end
,id as id
,geom
from centerlines;

drop index if exists endpoints_start_idx;
drop index if exists endpoints_end_idx;
create index endpoints_start_idx on endpoints using GIST(start);
create index endpoints_end_idx on endpoints using GIST("end");



/* 
Table intersections. Determine which endpoints are close enough to be considered an intersection. Currently using 5 units of the projection, which is in feet.
*/
drop table if exists intersections;
create table intersections as
select
ST_MakePoint((ST_X(a.start) + ST_X(b.start))/2.0,(ST_Y(a.start) + ST_Y(b.start))/2.0) as intersection
,a.geom as a_geom
,b.geom as b_geom
,a.id as a_id
,b.id as b_id
from
endpoints a,
endpoints b
where ST_DWithin(a.start,b.start,5) and a.id <> b.id
union
select
ST_MakePoint((ST_X(a.start) + ST_X(b.end))/2.0,(ST_Y(a.start) + ST_Y(b.end))/2.0) as intersection
,a.geom as a_geom
,b.geom as b_geom
,a.id as a_id
,b.id as b_id
from
endpoints a,
endpoints b
where ST_DWithin(a.start,b.end,5) and a.id <> b.id
union
select
ST_MakePoint((ST_X(a.end) + ST_X(b.start))/2.0,(ST_Y(a.end) + ST_Y(b.start))/2.0) as intersection
,a.geom as a_geom
,b.geom as b_geom
,a.id as a_id
,b.id as b_id
from
endpoints a,
endpoints b
where ST_DWithin(a.end,b.start,5) and a.id <> b.id
union
select
ST_MakePoint((ST_X(a.end) + ST_X(b.end))/2.0,(ST_Y(a.end) + ST_Y(b.end))/2.0) as intersection
,a.geom as a_geom
,b.geom as b_geom
,a.id as a_id
,b.id as b_id
from
endpoints a,
endpoints b
where ST_DWithin(a.end,b.end,5) and a.id <> b.id;

update intersections set intersection=ST_SetSRID(intersection,3734);
drop index if exists intersection_idx;
create index intersection_idx on intersections using GIST(intersection);






/* 
Table Buffers. Buffers the intersection by 10 units. Where the buffer crosses the road is the point we will measure the angle from
*/
drop table if exists buffers;
create table buffers as
select 
intersections.intersection,
ST_SetSRID(ST_ExteriorRing(ST_Buffer(intersections.intersection, 10)),3734) as extring
,intersections.a_geom as a_geom
,intersections.b_geom as b_geom
,intersections.a_id
,intersections.b_id
FROM intersections;

create index buffers_idx1 on buffers using GIST(extring);
create index buffers_idx2 on buffers using GIST(intersection);
create index buffers_idx3 on buffers using GIST(a_geom);
create index buffers_idx4 on buffers using GIST(b_geom);


/* 
Table a_points. The points and intersection from which the angle between will be calculated
*/
drop table if exists a_points;
create table a_points as
select
ST_GeometryN(ST_Intersection(buffers.extring,buffers.b_geom), 1) as point1
,ST_GeometryN(ST_Intersection(buffers.extring,buffers.a_geom), 1) as point2
,buffers.intersection
,buffers.a_id
,buffers.b_id
from buffers;

/* 
Table centerline_angles. The final output, delete the interim after this if wanted. ID pairs of all centerlines and the angle of turn from a_id to b_id, geom is intersection of centerline a and centerline b
*/
drop table if exists centerline_angles;
create table centerline_angles as
select
a_points.a_id
,a_points.b_id
,intersection
,abs(round(degrees(ST_Azimuth(a_points.intersection,a_points.point2) - ST_Azimuth(a_points.intersection,a_points.point1))::decimal,0)) as angle
from a_points
