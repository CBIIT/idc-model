Inferring a Model Structure for IDC
===

*Under Construction*

## Motivation and Rationale

The
[Imaging Data Commons](https://datacommons.cancer.gov/repository/imaging-data-commons)
(IDC) of the
[Cancer Research Data Commons](https://datacommons.cancer.gov/)
currently contains a large volume and wide variety of biomedical
images related to participants in a number of large-scale cancer
studies. Many of these studies are represented in other repositories
of the CRDC, such as the [Genomic Data Commons]() and the
[Proteomic Data Commons](). The IDC is intended to be the major image
repository for new studies whose data enter the CRDC
ecosystem. Because of this, it is critical that links between data
related to the same study participants are maintained and preserved
between IDC and other CRDC nodes. It is also important to understand
whether and how clinical data, biospecimen data, and other metadata
informing the image data at IDC can be meaningfully compared to
analogous data for the same participants present at the other
repositories. Practically, relating data at IDC to other data at other
CRDC "nodes" in a consistent and computable way is a key requirement
for the functionality of the
[Cancer Data Aggregator](https://datacommons.cancer.gov/cancer-data-aggregator),
a service that will allow users to query the entire CRDC from a single
point of entry.

A step towards meeting these needs is to compare the data model of the
IDC to those of other CRDC repositories. That is, to understand the
how data variables and their data types compare and perhaps directly
or indirectly map between IDC and other repositories. To do this kind
of comparision, it is helpful to have a computable, standardized
representation of the data models of interest. This is relatively
straightforward for most CRDC node models, but the IDC data model is
of a somewhat different character and structure. 

The IDC has naturally adopted the
[Digital Imaging and Communications in Medicine (DICOM)](https://www.dicomstandard.org/)
international imaging data standard. The standard has many different
components that cover a vast number of data use cases in a complex and
dynamic technological and regulatory space. A "DICOM data model"
exists, but is implicit in the structure of standard as published. We
have created a draft of the IDC-specific portions of the DICOM model
in terms of a
[property graph](https://en.wikipedia.org/wiki/Graph_database#Labeled-property_graph).
We have done this in a mostly automated way, by parsing relevant
portions of the
[DICOM standard](https://www.dicomstandard.org/current).

## IDC Data 

IDC maintains its data in large BigQuery tables, which are relatively
flat; i.e., the data within the cells of these tables are scalars or
at most two-level key-value objects.

[IDC documentation](https://learn.canceridc.dev/dicom/data-model)
indicates that much of its data structure is imputed
to this data by the DICOM standard. The document contains this
warning:

* "The DICOM data model is implicit, and is not defined in a
 machine-readable structured form by the standard!"

This turns out to be not quite true, although it is a job to extract a
machine readable structured form from the XML rendition of the DICOM
standard. We have done this job (approximately) to infer a draft data
model that relates the DICOM attributes stored by IDC back to their 
parent DICOM data structures (i.e., sequence attributes, modules, and
macros).

## DICOM data structures

[DICOM](https://www.dicomstandard.org/) is an extensive and highly
sophisticated data standard that defines a number of different data
structures for different applications and purposes. These include:

* Logical groupings of data elements ("attributes") which organize by
  topic area or function in the real world;
* Template or "form" groupings that bundle elements for data entry
  purposes at the point of data collection;
* Composite groupings of data elements from different real world
  logical groupings that often represent a real world entity as well
  as the executed processes that resulted in that entity;
* Specifications for the serialization of data collected according to a
  grouping, with details on encoding, length, positioning, order, and
  endianness;

and others.

The effort described here concentrates only on the first category, the
logical groups of attributes that are associated with entities found
in the
["DICOM Model of the Real World"](https://dicom.nema.org/medical/dicom/current/output/html/part03.html#chapter_7).

(To load a database based on this model, for example, would entail
parsing DICOM data collection templates to correctly populate
instances of the data nodes described here. A data loader would need
to ensure that patient, series, and image metadata correctly
associated with one another. Templates provide these instance
associations, while this model indicates a way to represent and store
these associations.)

## Capturing DICOM data model structure

DICOM data model structure can be inferred in a more or less
automated way by parsing the XML formatted DocBook source of key parts
of the standard. These XML files are available at
[https://www.dicomstandard.org/current](https://www.dicomstandard.org/current).

### Data Dictionary

The DICOM data dictionary, where DICOM attributes with their tags are
defined, is given in Part 3 of the
standard. [dicom-dict.pl](../dicom/dicom-dict.pl) extracts attribute names,
corresponding keywords, tags, descriptions, and data types into a
reduced json format in [dicom-tables.json](../dicom/dicom-tables.json). The
keywords, which are in general camel-case forms of the attribute
names, are used by IDC as column names in its BigQuery tables. Finding
attributes in the DICOM data dictionary using IDC column names is a
first step to mapping IDC data elements into the DICOM structure.

### Information Objects

DICOM standard Part 3, _Information Object Definitions_, is the source
of the DICOM data model structure. In particular, it includes tables
that relate attributes (data dictionary elements, or "slots" for
actual data observations) to logical groupings that are part of the
standard. 

The main such grouping is the
["Information Module"](https://dicom.nema.org/medical/dicom/current/output/html/part03.html#chapter_C). These
are composed of attributes and standardized groups of attributes in a
hierarchical way. The groups of attributes can be other modules or so-called
["Macros"](https://dicom.nema.org/medical/dicom/current/output/html/part03.html#sect_5.4).
 In addition, certain attributes (in particular,
["Sequences"](https://dicom.nema.org/medical/dicom/current/output/html/part03.html#sect_5.2))
are themselves composed of a set of certain scalar-valued attributes.

Any given attribute can be composed into a Module, therefore, as
itself, or as a member of a sequence attribute, another Module, or a
Macro. The resulting source hierarchy of an attribute within a Module
can be many levels deep. An attribute may also appear in several
different Modules or Macros.

The composition of modules in terms of other modules, macros, and
attributes is given in Part 3 of the
standard. [dicom-info-objects.pl](../dicom/dicom-info-objects.pl)
extracts (from XML) the modules and their hierarchies down to the simple
attribute level, preserving the structure, into a reduced json format
in [dicom-im.json](../dicom/dicom-im.json).

### Simple database

The above json reductions are transformed into tables in a simple
[SQLite database](../dicom/dicom.db). The number of unique DICOM model entities
recorded in this way are

|Entity |Count |
|------|----:|
|attribute | 4157|
|macro | 271|
|module | 385|
|Total | 4778|

## Modules and the DICOM Model of the Real World

The DICOM "Model of the Real World" (MRW) is a graph of entities and
relationships that specifically calls out the physical objects that
DICOM information entities represent and describe. DICOM information
modules are associated with most of these real-world
entities. The basic backbone of the MRW is 

    Patient (> Visit) > Study > Series 

A "Study" in DICOM is an imaging procedure performed on a single
Patient, generally for a medically indicated purpose. The Study yields
a Series of imaging findings. These findings include the Images
themselves. Note that this meaning for the term "Study" is different
from that in typical CRDC node models.

The [TCIA](https://www.cancerimagingarchive.net/) model backbone
augments this model, making it more relevant to typical NCI research
projects:

    Collection > Patient > Study > Series > Image

where a Collection is a group of patients (for example, those
participating in a trial or research study), and the Image (as a data
object) is of central interest.

The TCIA/DICOM backbone is analogous to the model backbones of other
CRDC node models. DICOM information modules are grouped under the
real-world entities as part of the standard (see Part 3, Appendix C of
the standard). To create a representation of the IDC data model in a
form analogous to other CRDC models, our strategy is to define top
level model nodes using these real world entities, and connect
associated information modules to these using graph relationships
(edges).

## Implicit structure of IDC data

By running simple queries on the open 
[IDC data tables]((https://learn.canceridc.dev/data/organization-of-data/files-and-metadata#bigquery-tables)), 
we could obtain all column names in use. Based on documentation and
inspection, it is clear that DICOM attributes are represented in IDC
tables by columns named with attribute keywords. 

### Filtering DICOM entities to minimally cover IDC columns

Using these ~875 keywords as input, we can use the simple database above to
filter down to the possible DICOM information modules and other components that
can contain the attributes represented. This initial filter indicated
that 749 DICOM standard attributes (that is, keywords that are mapped
to DICOM tags)  are present among the column names,
and 500 DICOM possible higher-level entities could contain these attributes.

Since many attributes are reused across different modules and macros
in the standard, this is not the minimal set of DICOM entities that
could cover the IDC attributes. To get closer to the minimal set, we
can examine the set of attributes that reside in only a single parent
entity. Based on this criterion, there are 113 of these entities that
are required to cover the IDC set.

We then ask how many of *all* the IDC attributes can be contained
in just those 113 entities. We find that these entities incorporate 628 of
the 749 standard IDC attributes.

For the remaining (749-623 = 126) IDC DICOM attributes, the final
question is: how many additional DICOM entities must be added to the
113 to cover these? These are entities that can appear as children of
more than one parent entity, so a further filtering process is
necessary to select the appropriate parents. However, the total number
of possible parent entities to cover these remaining attributes
is 213. At this point, we can cover all IDC DICOM standard attributes
with 326 higher-level entities.

Finally, we note that 88 of the 749 standard attributes are "sequence"
attributes, which are actually containers including a defined set of
mainly scalar-valued attributes. Therefore, some scalar-valued DICOM
attributes are part of the IDC model by virtue of these sequences, and
are not specified explicitly as Bigquery column names.

### Extracting a hierarchy of entities and pruning

The [dicom-info-objects.pl](../dicom/dicom-info-objects.pl) script extracts
the DICOM hierarchy of modules, macros, and attributes from XML of
Part 3 of the standards. The output JSON,
[dicom-im.json](../dicom/dicom-im.json), is parsed into a regularized tree
data structure. This is recursively filtered by
[parse-tree-im.pl](../dicom/parse-tree-im.pl), to identify the subtree of
entities that contain DICOM attributes used by IDC.

This subtree is output in
[Model Description Format](https://github.com/CBIIT/bento-mdf) as
[idc-dicom-model.yaml](../model-desc/idc-dicom-model.yaml), which enables it to be
automatically loaded into a Neo4j graph database for further
inspection. Modules, macros, and sequence attributes are considered
'nodes', scalar-valued attributes are treated as 'properties', and the
inclusion of components (specified in tables in Part 3) are
represented by 'relationships' or 'edges'.

## Adding the Real World Model

The standard defines a number of real world models for specific use
cases. Here we draft a top-level IDC DICOM model using the Part
3, Fig. 7-1a MRW as a basis. 

<img src="/doc/PS3.3_7-1a.svg" width="500px"/>

Below these top-level nodes, we
can collect information modules (as discussed above), mainly according
to the groupings that are defined in the titles of the top-level
sections of the standard's Part 3 Appendix C. "Collecting" here means
using graph relationships to link module nodes to the top level,
real-world nodes.

In this draft, we are also creating a number of modality-specific
nodes (e.g., Radiotherapy Modality, Magnetic Resonance Modality, etc.)
to aggregate modules specific to these technologies. Some of the
modules contain Series descriptors and some contain Image
descriptors. In the draft graph, we allow for a Modality node to link
to either a Series or an Image node. This can be made more precise in
another iteration.

For IDC, Segmentation and Measurements are key data groupings. These
have IDC-specific customizations and will need additional
consideration.

The real world model layer of the graph representation is rendered as
MDF in [idc-dicom-mrw-model.yaml](../model-desc/idc-dicom-mrw-model.yaml). The
merge feature of MDF allows this part of the model to be changed 
readily, while keeping the DICOM data structures constant in the
separate file above.

We loaded a clean Neo4j graph database running in a Docker container
with the entire draft model using the `load-mdf.py` script included in
the Python package
[bento-mdf](https://github.com/CBIIT/bento-mdf/drivers/python) as
follows:

    $ load-mdf.py --handle IDC --commit test --bolt bolt://localhost:<port> \
                  idc-dicom-mrw-model.yaml idc-dicom-model.yaml


## Examining the Draft Model

At the topmost level, we see the draft model recapitulates the main
features of the basic MRW of the standard:

<img src="/doc/idc-mrw.png" width="500px"/>

The [IDC documentation](https://learn.canceridc.dev/dicom/data-model)
describes a simple example of the use of DICOM information entities. 
It notes that the "Patient Information Module will...include such
attributes as PatientID, PatientName, and PatientSex". This example
can be searched and found in the draft model:

<img src="/doc/idc-patient-node.png" width="500px"/>







