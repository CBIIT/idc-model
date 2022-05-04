use JSON::ize;
use Set::Scalar;
use List::Util qw/any none uniqstr/;
use strict;

my $j = J "dicom-im-tp.json";
open my $fh, "idc-dicom-attr-tags.txt" or die $!;
my @idc;
while (<$fh>) {
  chomp;
  push @idc, $_;
}
my $idc = Set::Scalar->new(@idc);
my %sequences;

my %dedup;
my %idx; # modules, macros
my %aidx; # attributes
my @flds = qw/name tag ent_type desc req parent parent_tag/;

# index the entities
for my $k (keys %$j) {
  my $elt = $j->{$k};
  $elt->{key} = $k;
  $k = lc $k;
  $k =~ s/attributes//;
  $k =~ s/attributes//;
  $k =~ m/^(.*?)\s+(module|macro)/;
  my $name = $1;
  unless ($name) {
    warn "issue in '$k' as module name\n";
    next;
  }
  my $type = ($2 // "special");
  $name =~ s/[[:punct:]]/_/g;
  $name =~ s/\s/_/g;
  my $ent;
  $elt->{name} = $name;
  warn "No name for '$k'\n" unless $name;
  $ent->{ent} = $elt;
  $ent->{type} = $type;
  if ($elt->{xmlid}) {
    $ent->{tag} = $elt->{xmlid};
    $idx{$elt->{xmlid}} = $ent;
  }
}

# entities:
#  module
#  macro
#  attribute
# name tag ent_type req desc parent

for my $k (keys %$j) {
  my $id = $j->{$k}{xmlid};
  process( $idx{$id}{ent}{data}, $idx{$id} );
}


my (%pridx, %praidx);
# prune attributes to leave only IDC dicom attributes
my $dicom = Set::Scalar->new( keys %aidx );

foreach my $tag ($idc->members) {
  $praidx{$tag} = $aidx{$tag};
}

# collect sequence attributes that contain IDC simple attributes
for my $att (grep { $_->{ent}{attribute_name} =~ /Sequence$/ } values %aidx) {
  my $children_tags = Set::Scalar->new( map { $_->{tag} } @{$att->{children}} );
  if (($children_tags * $idc)->size) {
    $praidx{$att->{tag}} = $aidx{$att->{tag}};
  }
}

# prune macros - those that now have only empty children
my @macros = grep {$_->{type} eq 'macro'} values %idx;
foreach my $mcr (@macros) {
  my @kids = map {
    if ($praidx{$_->{tag}}) {
      $praidx{$_->{tag}};
    }
    elsif ($_->{type} eq 'macro') {
      $_;
    }
    else {
      ();
    }
  } @{$mcr->{children}};
  if (@kids) {
    $mcr->{children} = \@kids;
    $pridx{ $mcr->{tag} } = $mcr;
  }
}

# prune modules
my @modules = grep {$_->{type} eq 'module'} values %idx;
foreach my $mod (@modules) {
  my @kids = map {
    if ($praidx{$_->{tag}}) {
      $praidx{$_->{tag}};
    }
    elsif ($_->{type} eq 'macro' and $pridx{$_->{tag}}) {
      $_;
    }
    else {
      ();
    }
  } @{$mod->{children}};
  if (@kids) {
    $mod->{children} = \@kids;
    $pridx{ $mod->{tag} } = $mod;
  }
}

# MDF
my $mdf = {
  Nodes => {},
  Relationships => {
    includes_macro => {
      Mul => "many_to_many",
      Ends => [],
    },
    includes_sequence => {
      Mul => "many_to_many",
      Ends => [],
    },
   },
  PropDefinitions => {},
  Terms => {},
};
my $nodes = $mdf->{Nodes};
my $propdefs = $mdf->{PropDefinitions};
my $macro_ends => $mdf->{Relationships}{includes_macro}{Ends};
my $seq_ends => $mdf->{Relationships}{includes_sequence}{Ends};

@modules = grep {$_->{type} eq 'module' } values %pridx;
@macros = grep {$_->{type} eq 'macro' } values %pridx;
my $seen_atts = Set::Scalar->new();
my $seen_macros = Set::Scalar->new();

foreach my $mod (@modules) {
  parse_ent($mod);
}

open my $fh, ">idc-dicom-model.yaml" or die $!;
print $fh Y($mdf);
1;
###
sub parse_ent  {
  my ($ent) = @_;
  return unless ($ent && $ent->{ent} && keys %{$ent->{ent}});
  my $ent_name = $ent->{ent}{name} || norm_attr_name($ent->{ent}{attribute_name});
  if ($nodes->{$ent_name}) {
    if ($nodes->{$ent_name}{Tags}{dicom_type} eq
	$ent->{type}) { # already seen it
      return;
    }
    else { # entity of different type has the same base name
      $ent_name = $ent->{ent}{name} .= "_$$ent{type}";
    }
  }
  my $nspec = {
    Tags => {
      dicom_type => $ent->{type},
      dicom_source => $ent->{tag},
      ($ent->{ent}{toplevel} ? (dicom_toplevel => $ent->{ent}{toplevel}) : ()),
    },
    Props => []
   };
  my $props = [];
  for my $att (@{$ent->{children}}) {
    if ($att->{type} eq 'attribute') {
      my $nm = norm_attr_name( $att->{ent}{attribute_name} );
      if ($nm =~ /sequence$/i && $att->{children}) {
	if (!$seen_atts->has( "${ent_name},$nm" )) {
	  push @{$mdf->{Relationships}{includes_sequence}{Ends}}, {
	    Src => $ent_name,
	    Dst => $nm
	  };
	  # print "$ent_name -> (seq) $nm\n";
	  $seen_atts->insert("${ent_name},$nm");
	  parse_ent($att);
	}
      }
      else { # simple attr
	push @$props, $nm;
	unless ($propdefs->{$nm}) {
	  $propdefs->{$nm} = {
	    Tags => {
	      dicom_name => $att->{ent}{attribute_name},
	      dicom_tag => $att->{tag},
	      dicom_type => $att->{type},
	    },
	    $att->{ent}{attribute_description} ?
	    (Desc => $att->{ent}{attribute_description}) :
	    (),
	    Type => 'TBD'
	  };
	}
      }
    }
    elsif ($att->{type} eq 'macro') {
      if (!$seen_macros->has( "${ent_name},$$att{ent}{name}" )) {
	push @{$mdf->{Relationships}{includes_macro}{Ends}}, {
	  Src => $ent_name,
	  Dst => $att->{ent}{name}
	};
	# print "$ent_name -> (mac) $$att{ent}{name}\n";
	$seen_macros->insert("${ent_name},$$att{ent}{name}");
	parse_ent($att);
      }
    }
    elsif ($att->{type} eq 'module') {
      warn "hmm, a module in a module\n";
    }
    else {
      1; # skip
    }
  }
  if (@$props) {
    push @{$nspec->{Props}}, uniqstr @$props;
  }
  $nodes->{$ent_name} = $nspec;
  return;
}


sub process {
  my ( $data, $parent ) = @_;
  for my $chld (@$data) {
    my $chld_ent;
    my $chld_name = norm_attr_name($chld->{attribute_name});
    if ($chld->{link}) {
      $chld_ent = $idx{$chld->{link}};
    }
    else {
      # this assumes any two attributes with the same tags are the same
      # (which may not be quite the case in different DICOM contexts)
      unless ($aidx{$chld->{tag}}) {
	$aidx{$chld->{tag}} = {ent => $chld,
			       type => 'attribute',
			       tag => $chld->{tag} };
      }
      $chld_ent = $aidx{$chld->{tag}};
    }
    push @{$parent->{children}}, $chld_ent;
    if ($chld->{contains}) {
      process($chld->{contains}, $chld_ent);
    }
  }
}

sub norm_attr_name {
  my ($nm) = @_;
  $nm = lc $nm;
  $nm =~ s/\s/_/g;
  $nm =~ s/'//g;
  $nm =~ s/.\N{MICRO SIGN}/u/g;
  $nm =~ s/[[:punct:]]/_/g;
  $nm =~ s/_{2,}/_/g;
  $nm =~ s/^_//;
  $nm =~ s/_$//;
  return $nm;
}

1;
