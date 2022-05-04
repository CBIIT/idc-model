# dicom information objects (part 3)
use XML::Twig;
use JSON::ize;
use v5.10;
use feature 'unicode_strings';

my $srcdir = "source/docbook";
my %ptwigs;

pretty_json();
my %tables = {};

#ptwig("PS3.16");

my $p = XML::Twig->new(
  twig_roots => {
    table => \&parse_table,
  },
  twig_handlers => {
    olink => \&replace_link,
  },

 );

$p->parsefile('part03.xml');

$DB::single=1;
open my $outf, ">dicom-im.json";
print $outf J(\%tables);

sub replace_link {
  my $elt = $_;
  my $doc = $elt->att('targetdoc');
  my $ptr = $elt->att('targetptr');
  my $sel = $elt->att('xrefstyle');
  if ($sel =~ /labelnumber/) {
    $elt->parent->set_text($ptr);
    $elt->cut;
  }
  elsif ($sel =~ /\btitle\b/) {
    my $t = ptwig($doc)->root;
    my $txt = ($t->get_xpath("//section[\@xml:id=\"$ptr\"]/title"))[0]->text;
    $txt =~ s/\N{ZERO WIDTH SPACE}//g;
    $txt = XML::Twig::Elt->new( "#PCDATA" => $txt );
    $txt->replace($elt);
    1;
  }
}
sub parse_table {
  my $tbl = $_;

  my $tbl_name = $tbl->first_child('caption')->text;
  return 1 unless $tbl_name =~ /Attributes$/; # only slurp module/macro attr tables
  $tables{$tbl_name}{xmlid} = $tbl->att('xml:id');
  my $hdrs = $tables{$tbl_name}{hdrs} = [
    map { my $txt = lc $_->text;
	  $txt =~ s/\N{ZERO WIDTH SPACE}//g;
	  $txt =~ s/\s/_/g;
	  $txt; } $_->first_child('thead')->first_child('tr')->children('th')];
  my $data = $tables{$tbl_name}{data} = [];
  my @stack;
  for $tr ($_->first_child('tbody')->children('tr')) {
    my $item;
    my $name = $tr->first_child('td')->text;
    $name =~ s/^(>*)//;
    my $lvl = length($1);
    if (!@stack && ($lvl > 0) or
	@stack && ($lvl-$stack[-1][1] > 1)) {
      die "Error in within table levels for '$table_name'.'$name'\n";
    }
    # create line item
    if (($name =~ /^include/i) &&
	(scalar($tr->children('td')) < @$hdrs)) { # include macro
      my $xref = $tr->first_child('td')->first_descendant('xref');
      my $note = $tr->first_child('td')->next_sibling;
      $item = ($xref ?
	       {
		 link => $xref->att('linkend'),
		 $note ?
		 (note => $note->text) : ()
	       } :
	       {
		 spec => $tr->first_child('td')->text,
		   $note ?
		   (note => $note->text) : ()
		 }
	      );
    }
    else { # regular attribute
      @td = $tr->children('td');
      # look for variablelist in last column
      my $vl = $td[-1]->first_child('variablelist');
      if ($vl) {
	$vl->cut;
      }
      my @dta = map {
	my $txt = $_->text;
	$txt =~ s/\N{ZERO WIDTH SPACE}//g;
	$txt =~ s/^>*//g;
	$txt; } @td;
      @{$item}{@$hdrs} = @dta;
      if ($vl) {
	my $vldata;
	for $ent ($vl->children('varlistentry')) {
	  push @$vldata, {
	    term => $ent->first_child('term')->text,
	    desc => $ent->first_child('listitem') && $ent->first_child('listitem')->text,
	  }
	}
	$item->{valueset} = $vldata;
      }
    }
    # organize line item
    push(@$data, $item) if $lvl == 0;
    while (@stack && ($stack[-1][1] >= $lvl)) {
      pop @stack;
    }
    if (@stack) {
      push @{$stack[-1][0]{contains}}, $item
    }
    push @stack, [$item, $lvl];
  }
  $tbl->purge;
  1;
}

sub ptwig {
  $_ = shift;
  return $ptwigs{$_} if $ptwigs{$_};
  print STDERR "slurping $_";
  m/^PS3\.([0-9]+)/;
  my $s = sprintf("part%02d",$1);
  my $f = join('/',$srcdir,$s,"$s.xml");
  return unless -e $f;
  my $t = XML::Twig->new(
#    twig_roots => { 'section' => 1 },

  );
  $t->parsefile($f);
  $ptwigs{$_} = $t;
  return $t;
}

