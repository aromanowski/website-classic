#!/usr/bin/perl -w

use strict;
use Text::ParseWords 'quotewords';
use Getopt::Long;
use Data::Dumper;

use lib '/home/lstein/projects/bioperl-live';

# This URL corresponds to sofa.ontology file of SOFA Release 2 (the release 2 file is labeled as revision 1.32, 
# but is identical to 1.28, revision 1.32 is inaccessible through the public CVS)
# use constant SOFA => "GET 'http://song.cvs.sourceforge.net/*checkout*/song/ontology/sofa.ontology?revision=1.28' |";

# SOFA Release 2.1 is available. Also switching to sofa.obo (instead of sofa.ontology)
use constant SOFA => "GET 'http://song.cvs.sourceforge.net/*checkout*/song/ontology/sofa.obo?revision=1.14' |";

our $MAX_ALIGNMENT_GAP = 100000; # Max allowed gap between alignment features that share the same id

my %GENE_PART = map {$_=>1} qw(Transcript protein_coding_primary_transcript CDS intron exon coding_exon five_prime_UTR three_prime_UTR);

my %SOFA_TERM = (
		 Pseudogene                => 'pseudogene',
		 Sequence                  => 'region',
		 snoRNA_primary_transcript => 'snoRNA',
		 tRNA_primary_transcript   => 'tRNA',
		 miRNA_primary_transcript  => 'miRNA',
		 snRNA_primary_transcript  => 'snRNA',
		 rRNA_primary_transcript   => 'rRNA',
		 scRNA_primary_transcript  => 'scRNA',
		 SL1_acceptor_site         => 'trans_splice_acceptor_site',
		 SL2_acceptor_site         => 'trans_splice_acceptor_site',
		 ALLELE                    => 'sequence_variant',
		 Clone_left_end            => 'clone_insert_start',
		 Clone_right_end           => 'clone_insert_end',
		 complex_change_in_nucleotide_sequence => 'complex_substitution',
         'Deletion_and_insertion allele'       => 'complex_substitution', # Note the space between insertion and allele
         Substitution_and_insertion_allele     => 'complex_substitution',
		);

# my @SOFA_TYPES = qw(
#                     is_a
#                     non_functional_homolog_of
#                     part_of
#                     derives_from
#                     inverse_of
#                     homologous_to
#                     orthologous_to
#                     disjoint_from
#                     paralogous_to
#                     adjacent_to
#                     member_of
#                     similar_to
#                     );

# List of classes (name and class come from attributes) for which
# an ID should not be generated

my %CLASSES_NO_IDS = map {$_=>1} qw(Allele
                                    CDS
                                    Clone
                                    Gene
                                    intron
                                    Oligo_set
                                    Pseudogene
                                    SAGE_transcript
                                    Sequence
                                    Transcript
                                    Confirmed_EST
                                    Confirmed_false
                                    Confirmed_UTR
                                    Confirmed_cDNA
                                    Confirmed_inconsistent
                                    ncRNA
                                    Transposon
                                    );

# List of reserved tags

our %TAG_ORDER =  ( 'ID'            => 10, 
                    'Name'          => 9, 
                    'Alias'         => 8, 
                    'Parent'        => 7, 
                    'Target'        => 6, 
                    'Gap'           => 5, 
                    'Derives_from'  => 4, 
                    'Note'          => 3, 
                    'Dbxref'        => 2, 
                    'Ontology_term' => 1,
                    ); 


# List of feature types that will not have names

our %NO_NAME_TYPES = ( 
                       );

# List of feature types that will have an Indexed=1 attribute

our %INDEXED_TYPES = ( mRNA       => 1,
                       );

# List of chromosome names

our %CHROMOSOME_NAMES = ( I      => 1,
                          II     => 2, 
                          III    => 3, 
                          IV     => 4, 
                          V      => 5, 
                          X      => 6, 
                          MtDNA  => 7,
                          );

# List of reference sequences (seq_ids) and their last position 
# (to be used by sequence-region directive)

our %SEQUENCE_REGION_ENDS = ();

# Keep header components here

our @HEADER;

# Track alignments and their id numbers
my %ALIGNMENT_IDENTIFIERS; # Generated by concatenating method, target, strand
my $MAX_ALIGNMENT_ID_NUMBER;

# Track gene names for SO mrnas (WB transcripts)
our %MRNA2GENE;

my ($SOFA);
GetOptions("sofa=s" => \$SOFA) or die <<USAGE;
Usage: $0 [options] <gff file> <gff file>...

Options: --sofa=<path>   Path or pipe to sofa.ontology file

By default the sofa ontology file will be checked out from sourceforge CVS
using this pipe:

  ${\SOFA}

USAGE

# $SORT ||= 0;
$SOFA ||= SOFA;

# parse_sofa($SOFA,\%SOFA_TERM, \@SOFA_TYPES);
parse_sofa($SOFA,\%SOFA_TERM);

my(%GENE,%CDS_HOLDER,%EXON,%mRNA);
my %MEMO;
my $previous_ref = '';

foreach (@ARGV) { $_ = "gunzip -c $_|" if /\.gz/ }

my $out = open_out();

push @HEADER, "##gff-version 3\n";
push @HEADER, "##Index-subfeatures 0\n";

while (<>) {

  chomp;
  my ($ref,$source,$method,$start,$end,$score,$strand,$phase,$mysterious_last_column) = split "\t";

  # Add special formatting/rules
  if (!$ref) {
    warn ("Discarding invalid line [$_]!");
    next;
  }  
  $mysterious_last_column =~ s/(RNAz-\d+)\s+Note/ncRNA "$1"; Note/ if $source eq 'ncRNA'; # ncRNAs
  $mysterious_last_column =~ s/Note\s+\"([^;\"]+);([^;\"]+)\"/Note "$1%3B$2"/ if $source eq 'Coding_transcript' and $method eq 'Transcript'; # unescaped semi-colon
  if ($source eq 'mSplicer_orf' or $source eq 'mSplicer_transcript') { # redundancy in mSplicer_transcript and mSplicer_orf
    $mysterious_last_column =~ s/CDS\s\"([^\"]+)\";/CDS "$source:$1"; Alias "$1";/;
  }  

  if ($method eq 'CDS' and $phase eq '.') { 
    $phase = '0';
    warn ("Converted phase: $_\n");
  }  

  # Some features' attribute column does not start with /\w "name"/
  # In these cases, move the attribuite to the end
  my @last_column_pairs; # e.g. /\w name/
  my @last_column_switches; # e.g. /something/
  
  my @mysterious_last_column = split(";", $mysterious_last_column);
  
  foreach my $attribute_value (@mysterious_last_column) {
    $attribute_value =~ s/^\s+//;
    $attribute_value =~ s/\s+$//;
    if ($attribute_value eq ".") {
      push @last_column_switches, $attribute_value;
    }
    elsif ($attribute_value =~ /\S+ /) {
      push @last_column_pairs, $attribute_value;
    }
    else {
      push @last_column_switches, "$attribute_value 1";
    }
  }
  
  if (!@last_column_pairs && @last_column_switches == 1 && $last_column_switches[0] ne ".") {
    @last_column_pairs = (qq[$method "$method"]);
    }
  
  $mysterious_last_column = join(";", @last_column_pairs, @last_column_switches);

  my $attributes = parse_attributes($mysterious_last_column);

#  # this bizarre bit ensures that the chromosomes are dumped one at a time rather than
#  # after the entire gff file is read.
  if ($ref ne $previous_ref) {
    dump_genes();
#    close $out unless $out eq \*STDOUT;
#    $out = open_out($SORT);
    $previous_ref = $ref;
  }

  # get rid of leftover curated genes
  next if $GENE_PART{$method} && $source eq 'curated';
  next if $method eq 'gene' && $source eq 'curated';

  if ($method eq 'misc_feature') {
    if ($source eq 'Deletion_and_insertion allele') { $source =~ s/\s/_/g; $method = 'complex_substitution'; }
    elsif ($source eq 'Substitution_and_insertion_allele') { $method = 'complex_substitution'; }
    else { $method = $source; }
  }

  #################################
  # this part handles genes
  #################################
  if ($GENE_PART{$method} and $source !~ /trna/i) {

    my $continue;

    # sort out genes
    if ($method eq 'Transcript' or $method eq 'protein_coding_primary_transcript') {
      my $transcript_name = $attributes->{Transcript}[0] or die "Transcript is missing for $_";  # always one of these
      my $gene            = $attributes->{Gene}[0]       || '';
      my $wormpep         = $attributes->{WormPep}[0]    || '';
      my $cds             = $attributes->{CDS}[0]        || '';
      my @locus           = grep {/^\w{3,4}-\d+$/} @{$attributes->{Note}};
      my @notes           = grep {!/^\w{3,4}-\d+$/} @{$attributes->{Note}};
      (my $name = $transcript_name) =~ s/^\w+://;
      my $other_attributes= format_attributes($attributes,qw(Transcript Gene WormPep Note CDS Name));
      my $transcript_attributes = "ID=$transcript_name";
      $transcript_attributes .= ";Name=$name" if $name;
      $transcript_attributes .= ";Parent=Gene:$gene;Alias=$gene" if $gene;
      $transcript_attributes .= ";Alias=$cds"              if $cds and $cds ne $name;
      $transcript_attributes .= ";Note=$_"                 foreach @locus;
      $transcript_attributes .= ";Dbxref=WormPep:$wormpep" if $wormpep;
      $transcript_attributes .= ";Dbxref=CDS:$cds"         if $cds;
      $transcript_attributes .= ";$other_attributes"       if $other_attributes;
      $transcript_attributes .= ';Note='.escape($_) foreach @notes;
      print $out join("\t",$ref,$source,'mRNA',$start,$end,$score,$strand,$phase,combine($transcript_attributes, $method)),"\n";
      store_region_end($ref, $end);
      
      $MRNA2GENE{$transcript_name} = $gene;

      $GENE{$gene}{start}    = $start if !exists $GENE{$gene}{start} or $GENE{$gene}{start} > $start;
      $GENE{$gene}{end}      = $end   if !exists $GENE{$gene}{end}   or $GENE{$gene}{end}   < $end;
      my $gene_attributes = "ID=Gene:$gene;Name=$gene";
      $gene_attributes   .= ";Alias=$_;Dbxref=CGC:$_" foreach @locus;
      $GENE{$gene}{ref}    ||= $ref;
      $GENE{$gene}{source} ||= $source;
      $GENE{$gene}{method} ||= 'gene';
      $GENE{$gene}{strand} ||= $strand;
      $GENE{$gene}{phase}  ||= $phase;
      $GENE{$gene}{score}  ||= $score;
      $GENE{$gene}{attributes}  ||= $gene_attributes;
      $GENE{$gene}{mRNAs}->{$name} = 1; # Track all transcripts associated with a gene
    }

    # *** Even though the name of the variable is %EXON, it is now being used for both introns and exons ***
    # *** Make sure you check for the method ***
    if ($method eq 'exon' or $method eq 'intron') {  # this is a SO exon/intron
      my $parent = $attributes->{Transcript}[0];   # always one of these
      if ($parent) {
	my $key = join $;,$source,$ref,$start,$end,$strand;
	my $attributes = format_attributes($attributes,'Transcript');
	$EXON{$key}{parent}{$parent}++;
	$EXON{$key}{ref}    ||= $ref;
	$EXON{$key}{source} ||= $source;
	$EXON{$key}{method} ||= $method;
	$EXON{$key}{start}  ||= $start;
	$EXON{$key}{end}    ||= $end;
	$EXON{$key}{strand} ||= $strand;
	$EXON{$key}{phase}  ||= $phase;
	$EXON{$key}{score}  ||= $score;
	$EXON{$key}{attributes} ||= $attributes;
      } else {
	$continue++;
      }
    }

    if ($method =~ /(five|three)_prime_UTR/ && $source eq 'Coding_transcript') {  # this is a SO UTR
      my $parent = $attributes->{Transcript}[0] or die "No Transcript for $_";   # always one of these
      my $other_attributes = format_attributes($attributes,'Transcript','CDS');
      my $attributes = "Parent=$parent";
      $attributes   .= ";$other_attributes" if $other_attributes;
      print $out join("\t",$ref,$source,$method,$start,$end,$score,$strand,$phase,combine($attributes, $method)),"\n";
      store_region_end($ref, $end);
    }

    if ($method eq 'coding_exon' && $source eq 'Coding_transcript') { # this is a SO CDS
      my $parent = $attributes->{Transcript}[0] or die "No Transcript for $_";   # always one of these
      my $other_attributes = format_attributes($attributes,'Transcript','CDS');
      my $attributes = "ID=CDS:$parent;Parent=$parent";
      $attributes   .= ";$other_attributes" if $other_attributes;
      print $out join("\t",$ref,$source,'CDS',$start,$end,$score,$strand,$phase,combine($attributes, $method)),"\n";
      store_region_end($ref, $end);    
    } 

    elsif ($method eq 'coding_exon') { # a historical CDS or a "curated" CDS - we generate an mRNA object automatically
      my $parent = $attributes->{CDS}[0] or die "No CDS for $_";     # always one of these
      $CDS_HOLDER{$parent}{start} = $start if !exists $CDS_HOLDER{$parent}{start} or $CDS_HOLDER{$parent}{start} > $start;
      $CDS_HOLDER{$parent}{end}   = $end   if !exists $CDS_HOLDER{$parent}{end}   or $CDS_HOLDER{$parent}{end}   < $end;
      $CDS_HOLDER{$parent}{ref}    ||= $ref;
      $CDS_HOLDER{$parent}{source} ||= $source;
      $CDS_HOLDER{$parent}{method} ||= 'mRNA';
      $CDS_HOLDER{$parent}{score}  ||= $score;
      $CDS_HOLDER{$parent}{strand} ||= $strand;
      $CDS_HOLDER{$parent}{phase}  ||= $phase;
      $CDS_HOLDER{$parent}{attributes} ||= format_attributes($attributes,'CDS');
      print $out join("\t",$ref,$source,'CDS',$start,$end,$score,$strand,$phase,"Parent=".escape($parent)),"\n";
      store_region_end($ref, $end);    
    }

    next unless $continue;
  }

  #################################
  # this part handles sofa terms
  #################################
  my $sofa_method = $SOFA_TERM{$method} || $SOFA_TERM{$source} or warn "$method is not a valid SOFA TERM, converting to region; line=\n\t$_\n";
  if (!$sofa_method) { $sofa_method = "region"; }
  my @formatted_attributes;

  my $discard;
  
  if ($mysterious_last_column =~ /^Target/) {
    $mysterious_last_column =~ s/Target "([^\"]+)" ([\d-]+) ([\d-]+)\s*\;*\s*//;
    my ($target_sequence,$target_start,$target_end) = ($1,$2,$3);
    my $target_strand = '+';
    if ($target_start < 0 or $target_end < 0) {
      $discard = "Negative start/end values, discarding!";  
    }
    if ($target_end < $target_start) {
      $target_strand = '-';
      ($target_start,$target_end) = ($target_end,$target_start);
    }
    
    $target_sequence =~ s/^[^:]+://; # Clean name from type
    
    # Assign an id
    my $alignment_identifier = join("", $ref, $source, $method, $target_sequence, $strand, $target_strand); # Use feature strand and target strand

    my $id_number; # If features are more than $MAX_ALIGNMENT_GAP apart, generate new id's
    
    if ($ALIGNMENT_IDENTIFIERS{$alignment_identifier}) {
      my @id_packs = @{$ALIGNMENT_IDENTIFIERS{$alignment_identifier}};
      
      foreach my $id_pack (@id_packs) {
        if ( abs($start - $id_pack->{start}) <= $MAX_ALIGNMENT_GAP  # If so, this is a feature that can be added in
             ||
             abs($start - $id_pack->{end})   <= $MAX_ALIGNMENT_GAP
             ||
             abs($end   - $id_pack->{start}) <= $MAX_ALIGNMENT_GAP
             ||
             abs($end   - $id_pack->{end})   <= $MAX_ALIGNMENT_GAP
             ) {
          if ($start < $id_pack->{start}) {
            $id_pack->{start} = $start;
            }
          if ($end > $id_pack->{end}) {
            $id_pack->{end} = $end;
            }
          $id_number = $id_pack->{id_number};
        }
       }      
      
      # If we couldn't assign an id number, that means, this is a far apart id number 
      # We generate a new id pack
      # This is the same case as when there is no same alignment identifier
      # *** Implemented in next step ***
    }

    if (!$id_number) {
      $MAX_ALIGNMENT_ID_NUMBER++;
      
      $id_number = $MAX_ALIGNMENT_ID_NUMBER;
      
      my %id_pack = (
                      start     => $start,
                      end       => $end,
                      id_number => $id_number,
                      );
      
      push @{$ALIGNMENT_IDENTIFIERS{$alignment_identifier}}, \%id_pack;
    }
    # At this point we have an $id_number
    
    my $formatted_id = sprintf('%.6u', $id_number);
    
    push @formatted_attributes, "ID=match_${method}_${formatted_id}";
#    push @formatted_attributes, "Name=$target_sequence";
    push @formatted_attributes, "Target=$target_sequence $target_start $target_end $target_strand";
    my $other_attributes = format_attributes(parse_attributes($mysterious_last_column),'Target','gene','Name');
    push @formatted_attributes, "$other_attributes" if $other_attributes;
  } 
  else {
    my $separator = ";";
    my ($class,$name) = $mysterious_last_column =~ /^(\w+) \"?([^\"\s]+)\"?/;
    
    # Handle Chromosomes separately
    if ($class && $class eq "Sequence" && $CHROMOSOME_NAMES{$name}) {
      $sofa_method = "chromosome";
      }
      
    # Handle Expr_profile separately
    if ($class && $class eq "Expr_profile") {
      foreach (@{$attributes->{ID}}) {
        $_ .= ".expr"; 
      }  
      foreach (@{$attributes->{Name}}) {
        $_ .= ".expr"; 
      }  
    }

    my $other_attributes = format_attributes($attributes,$class,'gene');

    if ($class && $class eq 'Note') {
	push @formatted_attributes, join ';',map {"Note=".escape($_)} @{$attributes->{Note}};
    } else {
	  push @formatted_attributes, "ID=${class}:${name}" if ($name && $class && !$CLASSES_NO_IDS{$class});

      # Handle trna's separately
      if ($method =~/tRNA/i && $attributes->{Name}->[0]) {
        push @formatted_attributes, "ID=Transcript:".$attributes->{Name}->[0];
      }
      elsif ($source =~/tRNA/i && $method eq 'exon') {
        push @formatted_attributes, "Parent=${class}:${name}";
      }
    }
#     $formatted_attributes   .= ";Alias=$attributes->{gene}" if $attributes->{gene};
#     $formatted_attributes   .= ";$other_attributes"         if $other_attributes;

      push @formatted_attributes, "Alias=$attributes->{gene}" if $attributes->{gene};
      push @formatted_attributes, "$other_attributes"         if $other_attributes;
  }

  my $formatted_attributes = join(";", @formatted_attributes);
  
  $formatted_attributes = qq[.] unless $formatted_attributes; # Some fetaures do not have attributes, dot is mandatory
  
  my $formatted_line = join("\t",$ref,$source,$sofa_method,$start,$end,$score,$strand,$phase,combine($formatted_attributes, $method));
  
  if ($discard) {
    warn "$discard $formatted_line\n";
  }
  else {
    print $out $formatted_line . "\n";
    store_region_end($ref, $end);  
  }
}

dump_genes();
close $out unless $out eq \*STDOUT;

foreach my $ref (sort {$CHROMOSOME_NAMES{$a} <=> $CHROMOSOME_NAMES{$b}}
                 keys %SEQUENCE_REGION_ENDS) {
  push @HEADER, qq[##sequence-region $ref 1 $SEQUENCE_REGION_ENDS{$ref}\n];
}      

foreach my $ref (sort {$CHROMOSOME_NAMES{$a} <=> $CHROMOSOME_NAMES{$b}}
                 keys %SEQUENCE_REGION_ENDS) {
  push @HEADER, join("\t", $ref, 'Reference', 'chromosome', 1, $SEQUENCE_REGION_ENDS{$ref}, '.', '+', '.', qq[ID=$ref;Name=$ref]) . "\n";
}      

print join('', @HEADER);

system("cat /tmp/wormbasegff2gff3.tmp | sort -k1 -k3 -k4n -T /tmp");

unlink 'tmp/wormbasegff2gff3.tmp';

exit 0;

##########################################################

sub open_out {
#  my $sort = shift;
#  return \*STDOUT if !$sort;
  open T,">/tmp/wormbasegff2gff3.tmp" or die "$!";
#  open T,"|sort -k9,50 -k1,2 -k4,10n -T /tmp" or die "sort: $!";
  return \*T;
}

sub store_region_end {
  my ($ref, $end) = @_;
  
  if (!$SEQUENCE_REGION_ENDS{$ref}) {
    $SEQUENCE_REGION_ENDS{$ref} = 1;
  }  
  
  elsif ($end > $SEQUENCE_REGION_ENDS{$ref}) {
    $SEQUENCE_REGION_ENDS{$ref} = $end;
  }  
  
  return 1;
}  

sub dump_genes {
  my ($ref) = @_;
  
  # fix up the genes again
  for my $gene (sort keys %GENE) {
    next if (!$gene); # Skip gene features that are created from gene parts and do not have a gene assignment
    # Construct Alias from associated mRNAs
    my %mrnas = map { my $name = $_; $name =~ s/^(\w+\.\d+).*/$1/; $name => 1; } keys %{$GENE{$gene}{mRNAs}};
    if (keys %mrnas == 0) { 
      warn("No mRNA assignment for gene ($gene)!");
    }
    if (keys %mrnas > 1) { 
      warn("Multiple mRNA assignments for gene ($gene); " . join(",", sort keys %mrnas));
    }
    my $alias = qq[Alias=] . join(",", sort keys %mrnas) if %mrnas;
    $GENE{$gene}{attributes} = $alias ? join(";", $GENE{$gene}{attributes}, $alias)
                                      : $GENE{$gene}{attributes};
                                      
    print $out join("\t",@{$GENE{$gene}}{qw(ref source method start end score strand phase)}, combine($GENE{$gene}{attributes}, $GENE{$gene}{method})),"\n";
    store_region_end(@{$GENE{$gene}}{qw(ref end)});  
  }

  # *** Even though the name of the variable is %EXON, it is now being used for both introns and exons ***
  # *** Make sure you check for the method ***
  for my $key (sort keys %EXON) {
    my @parents    = sort keys %{$EXON{$key}{parent}};
    
    foreach (@parents) {
      warn "Cannot find gene for mrna ($_)!" unless $MRNA2GENE{$_};
    }
    
    my @parent_genes = map {escape($MRNA2GENE{$_})} @parents;
    my @valid_parent_genes;
    foreach (@parent_genes) { 
      push @valid_parent_genes, "Gene:$_" if $_;
      }
    my %unique_parent_genes = map {$_=>1} @valid_parent_genes;
    
    warn "Cannot find any gene for exon set ($key)!" unless %unique_parent_genes;
    
    my @attributes;
    @attributes = ("Parent=".join ',',sort keys %unique_parent_genes) if %unique_parent_genes;

    push @attributes, "$EXON{$key}{attributes}" if $EXON{$key}{attributes};

    my $attributes = join(";", @attributes);
    if ($attributes =~ /Parent/) {
      $attributes =~ s/;*Name=[^;]*;*//; # Remove Name attribute, (has a parent, but no children)
    }
    print $out join("\t",@{$EXON{$key}}{qw(ref source method start end score strand phase)},combine($attributes, $EXON{$key}{method})),"\n";
    store_region_end(@{$EXON{$key}}{qw(ref end)});  
  }

  for my $cds (sort keys %CDS_HOLDER) {
    my $attributes = "ID=".escape($cds);
    $attributes   .= ";$CDS_HOLDER{$cds}{attributes}" if $CDS_HOLDER{$cds}{attributes};
    if ($attributes =~ /Parent/) {
      $attributes =~ s/;*Name=[^;]*;*//; # Remove Name attribute, (has a parent, but no children)
    }  
    print $out join("\t",@{$CDS_HOLDER{$cds}}{qw(ref source method start end score strand phase)},combine($attributes, $CDS_HOLDER{$cds}{method})),"\n";
    store_region_end(@{$CDS_HOLDER{$cds}}{qw(ref end)});
  }

  undef %GENE;
  undef %EXON;
  undef %CDS_HOLDER;
  undef %MRNA2GENE;
}


sub parse_attributes {
  my $text = shift;
  my @tokens = quotewords('\s*;\s*|\s+',0,$text);
  my $first_one;
  my %result;
  while (@tokens) {
    my $tag   = shift @tokens;
    my $value = shift @tokens;
    next unless defined $tag;     # fix empty semicolon sections in sanger gff
    $value = 1 unless defined $value;
    if (!$first_one++ && $tag ne 'Note') {
      push @{$result{Name}},$value;
      $value = "$tag:$value";
    }
    push @{$result{$tag}},$value;
  }

  return \%result;
}

sub format_attributes {
  my $attribute_hash = shift;
  return '' unless keys %$attribute_hash;
  my @exclude        = @_;
  my $exclude        = $MEMO{"@_"} ||= {map {$_=>1} @_};
  my $result         = join ';',map { my @p;
				      my $key = $_;
				      foreach (@{$attribute_hash->{$key}}) {
					push @p,escape(($key eq 'Name' or $key eq 'Alias') ? $key : lc $key).'='.escape($_);
				      }
				      @p
				    } grep {!$exclude->{$_}} keys %{$attribute_hash};
  $result;
}

sub parse_sofa {
  my $sofa  = shift;
  my $terms = shift;
  my $types = shift;
  
  my $mode = 'Placeholder';
  
  open F,$sofa or die "Couldn't open $sofa: $!";
  while (my $line = <F>) {
    chomp $line;
    next unless $line;

    if ($line =~ /^\[([^\[\]]+)\]/) {
      $mode = $1;
      if ($mode ne 'Term' and $mode ne 'Typedef' and $mode ne 'Placeholder') {
        die "Cannot parse sofa file ($line)";
      }
    }
    
    if ($mode eq 'Term' and $line =~ /^name:\s+(.+)/) {
        $terms->{$1} = $1;
    }        
  }
  if (scalar(keys %$terms) < 30) { # Something *most likely* went wrong in acquiring/processing sofa
    die "Cannot retrieve/parse SOFA file!";
  }                                 

}

sub escape {
  my $toencode = shift;
  return $toencode unless defined $toencode;
  $toencode = unescape($toencode); # Make safe
  $toencode=~s/([^a-zA-Z0-9_. :+-])/uc sprintf("%%%02x",ord($1))/eg;
  $toencode;
}

sub unescape {
  my $string = shift;
  return $string unless defined $string;
  $string =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
  return $string;
}

# Re-format formatted_attributes to eliminate multiple tag names of the same type
sub combine {
  my ($attributes, $method) = @_;
  
  if ($attributes eq ".") {
    return ".";
  }
    
  my %reformatted_attributes;
  my @attributes = split(";", $attributes);
  foreach my $tag_value_pair (@attributes) {
    my ($tag, @value) = split("=", $tag_value_pair);
    my $value = join("", @value);
    
    if (!defined $value or $value eq "" or $value eq " ") {
      $value = 1;
    }

    # tag corrections
    if ($tag eq 'note') {
      $tag = "Note";
    }  
    if (!$TAG_ORDER{$tag}) {
      $tag = lc($tag);
    }
    if ($NO_NAME_TYPES{$method} and $tag eq 'Name') { # Skip name
      next;
    }  
    
    $reformatted_attributes{$tag}{$value} = 1;
  }

  # tag additions
  if ($INDEXED_TYPES{$method}) {
    $reformatted_attributes{Indexed}{1} = 1;  
  }
  
  my @reformatted_attributes;
  {
    no warnings;
    foreach my $reformatted_tag (sort { $TAG_ORDER{$b} <=> $TAG_ORDER{$a} } keys %reformatted_attributes) {
      push @reformatted_attributes, $reformatted_tag . "=" . join(",", sort keys %{$reformatted_attributes{$reformatted_tag}});
    }
  }
  my $reformatted_attributes = join(";", @reformatted_attributes);
  
  return $reformatted_attributes;
  }
  
