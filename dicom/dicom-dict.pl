use XML::Twig;
use JSON::ize;
use v5.10;
use utf8::all;

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

$p->parsefile('part06.xml');

open my $outf, ">dicom-tables.json";
print $outf J(\%tables);


# for $tbl_name (keys %tables) {
#   my $tbl = $tables{$tbl_name};
#   my $fnm = lc $tbl_name;
#   $fnm =~ s/\s/_/g;
#   open my $fh, ">$fnm.tsv" or die $!;
#   say $fh join("\t", @{$tbl->{hdrs}});
#   for $row (@{$tbl->{data}}) {
#     say $fh join("\t",@$row);
#   }
#   close $fh;
# }
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
    $txt = XML::Twig::Elt->new( "#PCDATA" => $txt );
    $txt->replace($elt);
    1;
  }
}
sub parse_table {
  my $tbl = $_;
  
  $tbl_name = $tbl->first_child('caption')->text;
  $tables{$tbl_name}{hdrs} = [
    map { $_->text } $_->first_child('thead')->first_child('tr')->children('th')
   ];
  $data = $tables{$tbl_name}{data} = [];
  for $tr ($_->first_child('tbody')->children('tr')) {
    push @$data, [ map {$_->text} $tr->children('td') ];
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
};
