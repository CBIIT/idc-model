-- .import info-entities.txt info_entities

CREATE TABLE template_uid (uid_value text, uid_name text, uid_type text, part text );
CREATE INDEX template_uid_uid_value_idx on template_uid (uid_value);
CREATE INDEX template_uid_uid_name_idx on template_uid (uid_name);
CREATE INDEX template_uid_uid_type_idx on template_uid (uid_type);
CREATE TABLE dir_structure_elts (tag text, name text, keyword text, vr text, vm text );
CREATE INDEX dir_structure_elts_tag_idx on dir_structure_elts (tag);
CREATE INDEX dir_structure_elts_name_idx on dir_structure_elts (name);
CREATE INDEX dir_structure_elts_keyword_idx on dir_structure_elts (keyword);
CREATE TABLE context_group_uids (context_uid text, context_identifier text, context_group_name text, comment text );
CREATE INDEX context_group_uids_context_uid_idx on context_group_uids (context_uid);
CREATE INDEX context_group_uids_context_group_name_idx on context_group_uids (context_group_name);
CREATE TABLE data_elts (tag text, name text, keyword text, vr text, vm text, notes text );
CREATE INDEX data_elts_tag_idx on data_elts (tag);
CREATE INDEX data_elts_name_idx on data_elts (name);
CREATE INDEX data_elts_keyword_idx on data_elts (keyword);
CREATE TABLE file_meta_elts (tag text, name text, keyword text, vr text, vm text );
CREATE INDEX file_meta_elts_tag_idx on file_meta_elts (tag);
CREATE INDEX file_meta_elts_name_idx on file_meta_elts (name);
CREATE INDEX file_meta_elts_keyword_idx on file_meta_elts (keyword);
CREATE TABLE uids (uid_value text, uid_name text, uid_keyword text, uid_type text, part text );
CREATE INDEX uids_uid_value_idx on uids (uid_value);
CREATE INDEX uids_uid_name_idx on uids (uid_name);
CREATE INDEX uids_uid_keyword_idx on uids (uid_keyword);
CREATE INDEX uids_uid_type_idx on uids (uid_type);
CREATE TABLE frames_of_reference (uid_value text, uid_name text, uid_keyword text, normative_reference text );
CREATE INDEX frames_of_reference_uid_value_idx on frames_of_reference (uid_value);
CREATE INDEX frames_of_reference_uid_name_idx on frames_of_reference (uid_name);
CREATE INDEX frames_of_reference_uid_keyword_idx on frames_of_reference (uid_keyword);
CREATE TABLE info_entities (name text, tag text, ent_type text, req text, desc text, parent text);
CREATE INDEX info_entities_tag on info_entities( tag );
CREATE INDEX info_entities_name on info_entities( name );
CREATE INDEX info_entities_enttype on info_entities( ent_type );
CREATE INDEX info_entities_parent  on info_entities( parent );

-- .import idc-attr-to-dcm-parent.txt idc_attribs
CREATE TABLE IF NOT EXISTS "idc_attribs"(
  "keyword" TEXT,
  "tag" TEXT,
  "ent_type" TEXT,
  "parent" TEXT
);

-- keyword distribution appearing in idc_attribs
create table kw_dist as ( select count(*) as ct, keyword from idc_attribs group by keyword);

select count(*) from kw_dist;
-- 875 : number of unique keywords in idc_attribs

select count(distinct keyword) from idc_attribs where tag is not null
-- 749 : number of unique keywords in idc_attribs that are represented (with a Tag)
--       in the DICOM standard
--
-- so 127 IDC keywords are custom in some way (though they may conform to DICOM)


-- keywords that fall under only one parent infomation object
select keyword from kw_dist where ct = 1;

-- what are those parent entities?
select keyword, parent from kw_dist as k inner join info_entities as ie on k.tag = ie.tag  where ct = 1;

-- list those parent entities and their entity type:
select distinct parent as par, ent_type as ent from (select keyword, parent, ent_type from kw_dist as k inner join info_entities as ie on k.tag = ie.tag  where ct = 1) order by parent;

-- join these two under one table - idc_single_parents
create table idc_single_parents as select sbq.keyword, sbq.parent, ie2.ent_type as par_type from (select keyword, parent from kw_dist as k inner join info_entities as ie on k.tag = ie.tag  where ct = 1) as sbq inner join info_entities as ie2 on sbq.parent = ie2.name;

-- how many parent entities cover the single-parent IDC columns? 113
select count(distinct parent) from idc_single_parents;
-- 113

select count(distinct parent) from idc_attribs_dicom where keyword in
(select keyword from (select keyword, count(parent) as ct from idc_attribs_dicom group by keyword)
where ct = 1);
-- 113

-- what is the distribution of entities from "all" of dicom?
select ent_type, count(distinct name) as ct from info_entities group by ent_type order by ent_type;
-- attribute	4157
-- macro	271
-- module	385

-- so there is a significant filtering here.

-- how many of all idc keywords (not just the single-parent ones) can be covered by
-- the single-parent parent entities? 623
select count(distinct keyword) from idc_attribs where parent in (select distinct parent from idc_single_parents);
-- 623

-- remaining keywords
select count(distinct keyword) from idc_attribs_dicom
where keyword not in (
select distinct keyword from idc_attribs_dicom where parent in
  (select distinct parent from idc_single_parents)
);

-- distinct parents covering these remaining keywords
select count(distinct parent) from idc_attribs_dicom where keyword in (select distinct keyword from idc_attribs_dicom where keyword not in (select distinct keyword from idc_attribs_dicom where parent in (select distinct parent from idc_single_parents)));
-- 213

-- table with only DICOM-tagged attributes

create table idc_attribs_dicom as select * from idc_attribs where tag is not null;

with recursive
parent_of(ent) as (
values('grid')
union
select parent from info_entities ie, parent_of
where ie.name = parent_of.ent
)
select * from parent_of

-- what IDC attribues are directly included in what modules? These modules are node candidates.
