#!/usr/bin/perl
# file: example
# example author display

use strict;
use Ace::Browser::AceSubs;
use ElegansSubs qw(:DEFAULT GetEvidence DisplayMoreLink FetchGene);
use CGI qw(:standard *table *iframe);
use vars qw/@PHENOTYPES $DB $phenotype $name/;
use lib '../lib';
# require 'OntologySubs.pl';
use constant TOO_MANY_DISPLAY_LIMIT => 25;

BEGIN {
    undef $phenotype;
    undef @PHENOTYPES;
    undef $name;
}

$DB = OpenDatabase() || AceError("Couldn't open database.");
$name = param('name');

@PHENOTYPES = fetch_phenotypes() if param('name');
if (@PHENOTYPES) {
    $phenotype = (@PHENOTYPES == 1) ? $PHENOTYPES[0] : undef;  # : would be > 1
}

# All
if ($name eq '*') {
    PrintTop($phenotype,'Phenotype',"All Phenotypes");
    # display_prompt();
    print "<a href=#full_search>[Search Ontologies]</a>";
    display_table();
    
# Details list
} elsif (param('details')) {
    my $clean_name = best_phenotype_name($phenotype);    
    PrintTop($phenotype,'Phenotype',$name 
	     ? "Phenotype: $clean_name" : 'Phenotype Search');
    #display_prompt();
    print "<a href=#full_search>[Search All Ontologies]</a>";
    print_details();
    
# Multiple results list
} elsif (@PHENOTYPES > 1) {
    PrintTop(undef,'Phenotype',"Phenotype Search: $name");
    #display_prompt();
    print "<a href=#full_search>[Search All Ontologies]</a>";
    print h3("Your search had ", scalar @PHENOTYPES," hits.  Please choose one:");
    
    print "<ol>";
    foreach (@PHENOTYPES)  {
	my $name = $_->Primary_name;    
	my @synonyms = map { $_ =~ s/_/ /g } $_->Synonym;
	print li(ObjectLink($_,$name) . " (" . join(",",@synonyms) . ")");
    }
    print "</ol>";
    # print ol(li([
#		 map {
#		     ObjectLink($_,$_ 
##				. ($_->Primary_name ? ': ' . $_->Primary_name : ''))
#		     } @PHENOTYPES]));
    PrintBottom();
    
# Query
} elsif ($name) {
    PrintTop(undef,'Phenotype',    
	     "Phenotype Search: $name");

    #display_prompt();
    print "<a href=#full_search>[Search All Ontologies]</a>";
    if ($phenotype) {
	display_report();
    } else {
	print h3({-class=>'warning'},"No phenotypes corresponding to $name were found.");
    }
} else {
    PrintTop(undef,'Phenotype','Phenotype Search');
    #display_prompt();
}

#print "<br><br><b>Search ontologies:</b>";
print "<a name=full_search></a>";
my $cgi = new CGI;

print_search_form($cgi,'phenotype');

PrintBottom();

exit 0;

########################################
# END MAIN 
########################################

sub print_ontology {

    my ($object) = @_;
    my $object_id = $object->name;
my %ontology2ace = (
		    'GO_term' => 'go',
		    'Phenotype' => 'po',
		    'Anatomy_term' => 'ao');
    my $class = $ontology2ace{$object->class};
    my $scr = '/db/ontology/browse_tree?query='.$object_id.';query_type=term_id;ontology='.$class.';details=on;children=on;expand=1';
    my $frame = div({-class => 'white'},iframe({-name => 'browser', 
						-src=> $scr, 
						-width => 950, 
						-height => 300}));
    my $end_frame = "\<\/iframe\>";

    return ($frame,$end_frame);

}


sub display_prompt {
    my $url = url(-absolute=>1);
    print
	start_form,
	p({-class=>'caption'},'<b>Run a specialized phenotype search.</b> Specify a phenotype such as '
	. a({-href=>$url . '?name=WBPhenotype0000643'},'uncoordinated')
	  . ', ' 
	  . a({-href=>$url . '?name=WBPhenotype0000062'},'lethal') . ' or '
	  . a({-href=>$url . '?name=WBPhenotype0000039'},'WBPhenotype0000039') . '.&nbsp;&nbsp;'
	  . 'You may also search using '
	  . a({-href=>$url . '?name=C17E4.5'},'genes')
	  . ', '
	  . a({-href=>$url . '?name=ra612'},'variations')
	  . ', '
	  . a({-href=>$url . '?name=WBRNAi00001701'},'RNAi experiments')      
	  . ', or '
	  . a({-href=>$url . '?name=GO:0040010'},'GO terms')
	  . '.'
	  . br . 'Enter a ' 
	  . a({-href=>url(-absolute=>1) . '?name=*'},'*')
	  . ' to browse all phenotypes: '
	  . textfield(-name=>'name')),
	  end_form;
}

sub extract_name {
    my $clean_name = ($phenotype =~ /WBPheno.*/) ? $phenotype->Primary_name : $phenotype;
    $clean_name =~ s/_/ /g;
    return $clean_name;
}


sub print_details {
    print start_table({-border=>0});
    my $tag = param('details');

    my ($byline,$formatted) = fetch_tags($phenotype,$tag);
    my $subtitle = get_subtitle($tag,$phenotype);
    print p(i("Displaying all " . (scalar @$formatted) . " $subtitle"));
    StartDataTable();
    StartSection($tag); 
    SubSection('',@$formatted);
    EndSection();
    EndDataTable();
    print end_table();
}

sub display_report {
    StartDataTable();
    StartSection('Details');

    
    # This should display counts of Evidence with a link to popup window
    # New window
    # Observation: unc-26 is synaptojanin
    #
    # Table of :
    # Evidence type   Source (linked)
    # To generate - requires object be passed to count references
    # Split Evidence hash parsing into two subroutines
    #     parsing and formatting

    my @synonyms = $phenotype->Synonym;
    SubSection('Primary name' => extract_name());
    SubSection('Short name'   => GetEvidence(-obj=>$phenotype->Short_name || '',-dont_link=>1));;
    SubSection('Synonym   ',join(',',@synonyms));
#GetEvidence(-obj=>$phenotype->Synonym || '',-dont_link=>1));;
    SubSection('Description'  => GetEvidence(-obj=>$phenotype->Description || '',-dont_link=>1));

    SubSection('Assay'        => GetEvidence(-obj=>$phenotype->Assay || '',-dont_link=>1));
    SubSection('Remark'       => GetEvidence(-obj=>$phenotype->Remark || '',-dont_link=>1));
    SubSection('WormBase ID' => $phenotype);

    # This phenotype is dead.  It may have been replaced by another.
    if ($phenotype->Dead(0)) {
	my $alternate = eval  {$phenotype->Dead->right };
	SubSection('Note',$alternate ? i("$phenotype has been retired and replaced by " . ObjectLink($alternate))
		   : i("$phenotype has been retired."));
	EndSection();
	return;	
    }


		StartSection('Ontology Browser');
		#my ($frame,$end_frame) = print_ontology2($term);
		my ($frame,$end_frame) = print_ontology($phenotype);
		SubSection('',$frame,$end_frame);
		EndSection();
	print "<a name=asc>";
    if ($phenotype->Related_phenotypes(0)) {
	StartSection('Related Phenotypes');
	foreach my $tag (qw/Specialisation_of Generalisation_of/) {
	    my @entries = map { ObjectLink($_,best_phenotype_name($_)) } $phenotype->$tag;
	    (my $label = $tag) =~ s/_/ /g;
	    SubSection($label => join(br,@entries)) if @entries;
	}
    }
    EndSection();

    foreach my $tag (qw/RNAi Variation Transgene GO_term/) {
	if ($phenotype->$tag) {
	    StartSection($tag);    
	    my ($byline,$formatted) = fetch_tags($phenotype,$tag);
	    SubSection('' => $byline,hr,$tag eq 'RNAi' || $tag eq 'Variation' ? @$formatted : Tableize($formatted));
	    EndSection();
	}
    }
		my $anatomy_fn = $phenotype->Anatomy_function;
		my $anatomy_fn_name = $anatomy_fn->Involved if $anatomy_fn;
		my $anatomy_term = $anatomy_fn_name->Term if $anatomy_fn_name;
		my $anatomy_term_id = $anatomy_term->Name_for_anatomy_term if $anatomy_term;
		my $anatomy_term_name = $anatomy_term_id->Term if $anatomy_term_id;
	if($anatomy_term_name){
		StartSection('Anatomy Ontology');    
		print "<i>Anatomy Ontology term associated with this Phenotype</i><br><hr>";
		SubSection('' => $anatomy_term_id);
	    # SubSection('',ObjectLink($anatomy_term_id));
	    EndSection();
	}
    EndDataTable();
}

sub fetch_tags {
    my ($phenotype,$tag) = @_;
    my @objects = $phenotype->$tag;
    my @results;

    my $subtitle = get_subtitle($tag,$phenotype);
    my @formatted = format_objects(\@objects,$tag,'inline',$phenotype);
    my $byline = i((scalar @objects) . " $subtitle");
    
    # Too many to display, we haven't requested display, or we aren't downloading
    if (@objects > TOO_MANY_DISPLAY_LIMIT && !param('details')) {
	my $link = DisplayMoreLink(\@objects,$tag,undef,'View all entries',1);
	$link =~ s/[\[\]]//g;
	$byline .= br .
	    i('Displaying the first ' . TOO_MANY_DISPLAY_LIMIT . " entries. $link.");
    }	   
    return($byline,\@formatted);
}


sub get_subtitle {
    my ($tag,$phenotype) = @_;
    my $blurb;
    if ($tag eq 'RNAi') {
	$blurb = 'RNAi experiments annotated';
    } elsif ($tag eq 'GO_term') {
	$blurb = 'gene ontology terms associated';
    } elsif ($tag eq 'Variation') {
	$blurb = 'variations annotated';
    } elsif ($tag eq 'Transgene') {
     	$blurb = 'transgenes annotated';
    }
    
    return "$blurb with the phenotype description "
	. b(best_phenotype_name($phenotype));
}
    


# Provide some basic formatting of different objects
# for either inline or downloadable format
sub format_objects  {
    my ($objects,$tag,$param,$phenotype) = @_;
    
    my ($count,@rows);
    my ($observed,$not_observed);
    foreach (@$objects) {
	$count++;
	if ($count > TOO_MANY_DISPLAY_LIMIT && !param('details')) {
	    last;
	}
	
	# Format the objects as appropriate for their type
	if ($tag eq 'RNAi') {
	    my $cds  = $_->Predicted_gene;
	    my $gene = $_->Gene;
	    
	    my $cgc  = eval{$gene->CGC_name};
	    my $str  = $cgc ? "$cds ($cgc)" : $cds;
	    my $is_not = is_not($_,$phenotype);
	    push @rows,[ObjectLink($_,$str . " [$_]") . (($is_not) ? " (phenotype not observed in this experiment)" : ''),$str];
#	    push @not_observed,[ObjectLink($_,$str . " [$_]"),$str] if $is_not;
#	    push @observed,[ObjectLink($_,$str . " [$_]"),$str] if !$is_not;
	   
	} elsif ($tag eq 'GO_term') {
	    my @evidence = go_evidence_code($_);
	    my $joined_evidence;
	    foreach (@evidence) {
		my ($ty,$evi) = @$_;
		my $tyy = a({-href=>'http://www.geneontology.org/GO.evidence.html',-target=>'_blank'},$ty);
		
		my $evidence = ($ty) ? "($tyy) $evi" : '';
		$joined_evidence = ($joined_evidence) ? ($joined_evidence . br . $evidence) : $evidence;
	    }
	    my $desc = $_->Term || $_->Definition;
	    my $href = 
		$_
		. (($desc) ? ": $desc" : '')
		. (($joined_evidence) ? "; $joined_evidence" : '');
	    push @rows,[ObjectLink($_,$href),$_];
	} elsif ($tag eq 'Variation') {
		my $is_not = is_not($_,$phenotype);
		push @rows,[ObjectLink($_,$_).(($is_not) ? " (phenotype not observed in this experiment)" : ''),$_];
	} 
	 else {
	    push @rows,[ObjectLink($_),$_];
	}
    }

#    if ($tag eq 'RNAi') {
#	my @sorted_not = map { $_->[0] } sort { $a->[1] cmp $b->[1] } @not_observed;
#	my @sorted = map { $_->[0] } sort { $a->[1] cmp $b->[1] } @observed;
#	return (\@sorted_not,\@sorted);
#    } else {
	my @sorted = map { $_->[0] } sort { $a->[1] cmp $b->[1] } @rows;
	return @sorted;
#    }
}


# Display whether the phenotype is obsjerved or not
# for RNAi experiments.  Sadly not trivial.
sub is_not {
    my ($obj,$phene) = @_;
    my @phenes = $obj->Phenotype;
    foreach (@phenes)  {
	next unless $_ eq $phene;
	my %keys = map { $_ => 1 } $_->col;
	return 1 if $keys{Not};
	return 0;
    }
    

}


sub go_evidence_code {
    my $term = shift;
    my @type      = $term->col;
    my @evidence  = $term->right->col if $term->right;
    
    my @results;
    foreach my $type (@type) {
	my $evidence = '';
	for my $ev (@evidence) {
	    next unless $ev =~ /evidence$/;
	    (my $desc = $ev) =~ s/_evidence$//;
	    my @supporting_data = $ev->col;
	    $evidence .= ($evidence ? ' and ' : '') . "via $desc ".join '; ',
	    map {
		if ($_->class eq 'Paper') {  # a paper
		    ObjectLink($_,build_citation(-paper=>$_,-format=>'short'));
		} elsif ($_->class eq 'Text' && $ev =~ /Protein/) {  # a protein
		    a({-href=>sprintf(Configuration->Protein_links->{NCBI},$_),-target=>'_blank'},$_);
		} else {
		    ObjectLink($_);
		}
	    } @supporting_data;
	}
	
	push @results,[$type,($type eq 'IEA') ? 'via InterPro' : $evidence];
    }
    #my @proteins = $term->at('Protein_id_evidence');
    return @results;
    
    ##  return ("IEA", "via InterPro");  # Off, (for now) WS142
    #return "$GO_CODES{$type} $evidence" if $type;
    #return "$GO_CODES{IEA} via InterPro";
}

sub fetch_phenotypes {
    # Get them all if requested
    return $DB->fetch(-class=>'Phenotype',-name=>'*') if $name eq '*';
        
    # 1. Simplest case: assume a WBPhene ID
    my @phenes = $DB->fetch(-class=>'Phenotype',-name => $name,-fill=>1) if 
	$name =~ /WBPhen.*/;
    
    # 2. Try text searching the Phenotype class
    unless (@phenes) {
	my @obj = $DB->fetch(-class=>'Phenotype_name',-name=>$name,-fill=>1);
	@phenes = map { $_->Primary_name_for || $_->Synonym_for || $_->Short_name_for } @obj;
	push @phenes,$DB->fetch(-query=>qq{find Phenotype where Description=*$name*});	

    }
    
    # 3. Perhaps we searched with one of the main classes
    # Variation, Transgene, or RNAi
    unless (@phenes) {
	foreach my $class (qw/Variation Transgene RNAi GO_term/) {
	    if (my @objects = $DB->fetch($class => $name)) {
		# Try fetching phenotype objects from these
		push @phenes, map { $_->Phenotype } @objects;
	    }
	}
    }
    
    # 4. Okay, maybe user entered a gene or sequence
    unless (@phenes) {
	my ($gene,$bestname) = FetchGene($DB,$name);
	if ($gene) {
	    my (@objects,$query_class);

	    # Fetch all RNAi objects that map to this gene
	    push @objects,
	    $DB->fetch(-query=>qq{find RNAi where Gene=$gene});

	    # ...or attached to transgenes
	    push @objects,
	    $DB->fetch(-query=>qq{find Transgene where Driven_by_gene=$gene});
				      
	    # ...or perhaps even variations
	    push @objects,
	    $DB->fetch(-query=>qq{find Transgene where Gene=$gene});

	    my %seen;
	    @phenes = grep { !$seen{$_}++ } map { $_->Phenotype } @objects;
	}
    }
    return @phenes if @phenes;
    return '';
}


sub display_table {
  my @rows;

  foreach my $phene (@PHENOTYPES) {
      my @rnai       = $phene->RNAi;
      my @variations = $phene->Variation;
      my @transgene  = $phene->Transgene;
      push @rows,[$phene,
		  $phene->Primary_name,
		  $phene->Description || '',,
		  scalar @rnai,
		  scalar @variations,
		  scalar @transgene,
		  ];
  }
  
  # Corresponds to position in the @rows array
  my %cols = (
	      0 => ['phenotype',    10  ],
	      1 => ['primary name', 10  ],
	      2 => ['description',  10  ],
	      3 => ['RNAi',         5   ],
	      4 => ['Variations',   5   ],
	      5 => ['Transgenes',   5   ],
	      );

  my $sort_by    = url_param('sort');
  $sort_by = ($sort_by eq '') ? 0 : $sort_by; # Have to do it this way because of 0
  my $sort_order = (param('order') eq 'ascending') ? 'descending' : 'ascending';
  my @sorted;
  if ($sort_by =~ /[012]/) {   # Alphanumeric sort columns
    if ($sort_order eq 'ascending') {
      @sorted = sort { lc ($a->[$sort_by]) cmp lc ($b->[$sort_by]) } @rows;
    } else {
      @sorted = sort { lc ($b->[$sort_by]) cmp lc ($a->[$sort_by]) } @rows;
    }
  } else {
    if ($sort_order eq 'ascending') {
      @sorted = sort { $a->[$sort_by] <=> $b->[$sort_by] } @rows;
    } else {
      @sorted = sort { $b->[$sort_by] <=> $a->[$sort_by] } @rows;
    }
  }

  # Create column headers linked with the sort options
  print hr;
  print start_table();
  my $url = url(-absolute=>1,-query=>1);
  $url .= "?name=$name;sort=";
  print TR(
	   map {
	     my ($header,$width) = @{$cols{$_}};
	     th({-class=>'dataheader',-width=>$width},
		a({-href=>$url . $_ . ";order=$sort_order"},
		  $header
		  . img({-width=>17,-src=>'/images/sort.gif'})
		  ))}
	   sort {$a <=> $b} keys %cols);
  
  foreach (@sorted) {
      my ($phenotype,$primary,$description,$rnai,$variation,$transgene) = @$_;
      next if $phenotype eq '=';  # kludge for sloppy data entry
      print TR(td({-class=>'datacell'},ObjectLink($phenotype)),
	       td({-class=>'datacell'},$primary),
	       td({-class=>'datacell'},$description),
	       td({-class=>'datacell'},$rnai),
	       td({-class=>'datacell'},$variation),
	       td({-class=>'datacell'},$transgene));
  }
  print end_table;
}

#### cut and pasted onto ontology/gene, ontology/anatomy/ and misc/phenotype as kludge around 
### troubles with the use *.pm file commands

sub print_ontology {

my ($object) = @_;
my $object_id = $object->name;
my %ontology2ace = (
		'GO_term' => 'go',
		'Phenotype' => 'po',
		'Anatomy_term' => 'ao');
my $class = $ontology2ace{$object->class};
# my $scr = '/db/ontology/browse_tree?query='.$object_id.';query_type=term_id;ontology='.$class.';details=on;children=on;expand=1';
my $scr = '/db/ontology/tree_lister?name='.$object_id;
my $frame = div({-class => 'white'},iframe({-name => 'browser', 
											-src=> $scr, 
											-width => 950, 
											-height => 300}));
my $end_frame = "\<\/iframe\>";

return ($frame,$end_frame);

}



### search form subs ####

sub print_search_form {
    
    my $cgi = shift @_;
    my $form_type = shift @_;
    
    print $cgi->startform(-method=>'GET', 
			  -action=>'search');   

	print "<table>";

	if ($form_type=~ m/multi/) {
	
		print "<tr><td>";
		print_ontology_choices($cgi,$form_type);
		print "</td></tr>";
		
		print "<tr><td>";
		print_entry_items($cgi,$form_type);
		print "</td></tr>";		
	}

	else {
	
		print "<tr><td>";
		print_entry_items($cgi,$form_type);
		print "</td></tr>";	

		print "<tr><td>";
		print_ontology_choices($cgi,$form_type);
		print "</td></tr>";		
	}
	
	print "<tr><td>";
	print_return_choices($cgi);
	print "</td></tr>";
	
	print "</table>";

	print "<br><br>\n";

    print $cgi->submit('Submit');
    print "\&nbsp\;\&nbsp\;";
    print $cgi->defaults('  Reset  ');

	print $cgi->endform;
}

sub print_ontology_choices {

	my $cgi = shift;
	my $form_type = shift;
	

    my %ontologies = ('biological_process'=>'GO:Biological Process',
                      'cellular_component'=>'GO:Cellular Component',
                      'molecular_function'=>'GO:Molecular Function',
		      			'anatomy'=>'Anatomy',
		      			'phenotype'=>'Phenotype'
		      			);

	if ($form_type=~ m/multi/) {
	
		print "<h3>Select ontologies you wish to search.</h3>"; 
    	print $cgi->checkbox_group({
    				-name=>'ontologies',  -values=>['biological_process','cellular_component','molecular_function',
    				'anatomy','phenotype'], 
			       	-multiple=>'true', 
			       	-labels=>\%ontologies,
			       	-linebreak=>1
			       	});	
	}
	elsif ($form_type=~ m/go/) {
	
		print "<br><br>Other ontologies can be included in this search, see table below for complete annotated information<br><br>";
		
		print $cgi->checkbox_group({
    				-name=>'ontologies',       
    				-values=>['biological_process','cellular_component','molecular_function',
    				'anatomy','phenotype'], 
			       	-default=>['biological_process','cellular_component','molecular_function'], ## 
			       	-multiple=>'true', 
			       	-labels=>\%ontologies,
			       	-linebreak=>1
			       	});	
	
	}
	
	elsif ($form_type=~ m/phenotype/) {
	
		print "<br><br>Other ontologies can be included in this search, see table below for complete annotated information<br><br>";
		print $cgi->checkbox_group({
    				-name=>'ontologies',       -values=>['biological_process','cellular_component','molecular_function',
    				'anatomy','phenotype'], 
			       	-default=>'phenotype', ## 
			       	-multiple=>'true', 
			       	-labels=>\%ontologies,
			       	-linebreak=>1
			       	});	
	}
	elsif ($form_type=~ m/anatomy/) {
	
		print "<br><br>Other ontologies can be included in this search, see table below for complete annotated information<br><br>";		
	
		print $cgi->checkbox_group({
    				-name=>'ontologies',       -values=>['biological_process','cellular_component','molecular_function',
    				'anatomy','phenotype'], 
			       	-default=>'anatomy', ## 
			       	-multiple=>'true', 
			       	-labels=>\%ontologies,
			       	-linebreak=>1
			       	});	
	}
	else {
			print $cgi->checkbox_group({
    				-name=>'ontologies',       -values=>['biological_process','cellular_component','molecular_function',
    				'anatomy','phenotype'], 
			       	-multiple=>'true', 
			       	-labels=>\%ontologies,
			       	-linebreak=>1
			       	});	
	}			       	
}

sub print_return_choices {

	my $cgi = shift;
	
	print "<br>";
	
	print start_table({-border=>1, -cell_spacing=>1, -cellpadding=>1});
	
	print TR({},
			th({},'Ontology'),
			th({},'Annotated objects that can be entered into search (<i>example</i>).')
	);
	print TR({},
			td({},'GO'),
			td({},'genes(<i>unc-26</i>)')
	);
	print TR({},
			td({},'Anatomy'),
			td({},'genes(<i>unc-26</i>)')
	);
		print TR({},
			td({},'Phenotype'),
			td({},'genes(<i>unc-26</i>), transgenes(<i>bcEx757</i>), rnais(<i>WBRNAi00077478</i>), variations(<i>n422</i>)')
	);
	
	print end_table();
	
	print "<br><br>";
	
	print $cgi->checkbox(-name=>'string_modifications', 
			 #-checked=>'checked', 
			 -value=>'ON', 
			 -label=>'Query Stands Alone');
	
	print "<br>";
    print $cgi->checkbox(-name=>'with_annotations_only', 
			 #-checked=>'checked', 
			 -value=>'ON', 
			 -label=>'Return Only Terms with Annotations');

    print "<br><br>Sort Annotations \&nbsp\;\&nbsp\;";
    
    my %sorting_choices = ('alpha'=>'Alphabetically',
			   'annotation_count'=>'By number of annotations'
			   );

    print $cgi->popup_menu(-name=>'sort',
                           -values=>[
                                     'alpha',
                                     'annotation_count'],
                           -default=>'alpha',
		       -labels=>\%sorting_choices);

    print "<br><br>";

    print "Include the following areas in the search\:<br><br>\n";

 my %filter_choices = (
 				'd'=>'definition',
			   	's'=>'synonyms'
			   	);

    print $cgi->scrolling_list(-name=>'filters',
                           -values=>[
                                     'd',
                                     's'],
						   -default=>[
						         'd',
                                 's'],
		      				-multiple=>'true',
		      				-labels=>\%filter_choices);
}

sub print_entry_items {

	my $cgi = shift;
	my $form_type = shift;

    my %string_choices = (#'before'=>'Starts with', 
			  #'after'=>'Followed by', 
			  'middle'=>'Contains',
			  'stand_alone'=>'Stands Alone'
			  );

	if ($form_type=~ m/multi/) {

		print "<h3>Enter a term (<i>egg</i>), phrase (<i>larval development</i>), term ID, or annotated object. See table below for available information</h3>";
		#print "Annotated objects can also be used to look up terms. .<br><br>";
	}
	elsif($form_type=~ m/go/) {
	
		print "<h3>Enter a term (<i>egg</i>), phrase(<i>larval development</i>), term ID (<i>GO:0009790</i>), or gene(<i>unc-26</i>) </h3>";
	}
	elsif($form_type=~ m/anatomy/) {
	
		print "<h3>Enter a term(<i>egg</i>), phrase(<i>germ line</i>), term ID(<i>WBbt:0005784</i>), or gene(<i>unc-26</i>) </h3>";
	}
	elsif($form_type=~ m/phenotype/) {
	
		print "<h3>Enter a term(<i>egg</i>), phrase(<i>embryonic lethal</i>), term ID, gene(<i>unc-26</i>), variation(<i>n422</i>), transgene(<i>bcEx757</i>), or rnai(<i>WBRNAi00077478</i>)</h3>";
	}
	else {
	
	print "<h3>Enter a term, phrase, or term ID</h3>";
	}
	
    print $cgi->textfield(-name=>'query', 
			  -size=>50, 
			  -maxlength=>80);
 
 	 print "<br>\n";
 

}

### end search form subs ###

