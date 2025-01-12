#!/usr/bin/perl
### ontology search ###

use strict;
use lib '../lib';
use ElegansSubs qw/:DEFAULT Bestname/;
use Ace::Browser::AceSubs;
use CGI qw(:standard *table *TR *td escape);
use WormBase;
use vars qw/$WORMBASE $db $query $db_ar $data_file_name/;
use Data::Dumper;
# use OntSubs;
# my @sections2filter = qw(t d);

$query = param('query');
$query=~ s/\+/ /g;
my $cgi = new CGI;


#print "$query<br>";
#print $cgi->start_html(-title=>'Ontology Search');

END {
  undef $WORMBASE;
  undef $db;
}

our %search_results_hash;

my $ontology_list;
my @ontology_list;
my $with_annotations_only = 0;
my $return_flag;
my $string_modification;
my $annotation_flag;
my $sort_results_by;
my $special_search;
my %string_search_results_hash;
my @sections2filter;


#my $db = Ace->connect(-host=>'localhost',-port=>2005); 
#my $dbx = undef; #OpenPageGetObject('Ontology Search','Ontology Search',1);
#$db = shift @{$db_ar};
$string_modification = param('string_modifications');

@ontology_list = param('ontologies');
$annotation_flag = param('with_annotations_only');
$sort_results_by = param('sort');
$special_search = param('special_search');
@sections2filter = param('filters');
push @sections2filter, 't';
push @sections2filter, 'i';
push @sections2filter, 'n';

#my $classtofetch = param('class');
ElegansSubs::PrintTop(undef,'Ontology Search', $query ? "Search Result for $query" : "Ontology Search");
# StartCache();
my $db = OpenDatabase() || AceError("Couldn't open database.");
$WORMBASE = WormBase->new($db);
autoload($cgi) if $cgi->param("autoload");
#PrintTop();

if ($annotation_flag eq 'ON'){
    $with_annotations_only = 1;
}

$ontology_list = join '&', @ontology_list;

#my $data_directory = './'; 
my $version = $db->version;
#print "$version<br>";
our $data_directory = "/usr/local/wormbase/databases/$version/ontology/";

$data_file_name = $data_directory . "search_data.txt";

### specialized search off URL not via form! ####

#print "$query<br>";

if ($special_search){
	%search_results_hash = &ontology_survey($special_search);
	$query = 1;
	# print "OK\n";
}
else{
		%string_search_results_hash = &run_search ($data_file_name,$query,$ontology_list,$with_annotations_only,$string_modification);

}

#print Dumper %search_results_hash;

my %filtered_data = filter_sections(\%string_search_results_hash,\@sections2filter,$query);
#print Dumper %filtered_data;

foreach my $filtered_data_key (keys %filtered_data) {
	
	$search_results_hash{$filtered_data_key}{'string'} = $filtered_data{$filtered_data_key};

}
### run anotation searches here, incorporate data into $search_results hash ###

run_annotation_searches($ontology_list,$query);
 
#### end annotation data search #####


my @fd_keys = keys %filtered_data;
#print "\<pre\>@fd_keys\<\/pre\>\n";


$return_flag = check_for_results(\%search_results_hash);

my @srh_keys = keys %search_results_hash;
#print "\<pre\>@srh_keys\<\/pre\>\n";
#print "\<pre\>@sections2filter\<\/pre\>\n";
#print "\<pre\>$return_flag\<\/pre\>\n";


#$return_flag = 2;

#print "$return_flag<br>"; 


if(!($query)){
    # Do nothing;
}
elsif($return_flag == 0){

    print "<br><br>Your search for <i>$query</i> did not return any terms. Please check the spelling and try again<br><br>\n";
}
else{
     print_ontology_search_results(\%search_results_hash,$sort_results_by); ## \%filtered_data
}

print_search_form($cgi);
ClosePage;

exit 0;


#######################################
#
# Subroutines
#
#######################################



sub association_links {
	
	my ($id,$ontology,$associations_count,$association_urls_hr) = @_;
	my $assc_url;
	my $wga_url;
	
	if($associations_count == 0){
		#print "Hello Associations!\n";
		return 0;
	}
	else { 
	## get urls
	$assc_url = ${$association_urls_hr}{$ontology};
	# $wga_url = ${$wm_gene_annotation_urls_hr}{$ontology}{'gene'};
	$assc_url =~ s/\$\$\$\$/$id/;
	# $wga_url =~ s/\$\$\$\$/$id/;
	return $assc_url;
	}		
}

sub wormmart_links {
		my ($id,$ontology,$wm_object_ontology_urls_hr) = @_;
		my %ontology_wm_objects = ('biological_process' => [qw(gene)],
			       'cellular_component' => [qw(gene)],
			       'molecular_function' => [qw(gene)],
			       'anatomy' => [qw(expr_pattern gene )],
			       'phenotype' => [qw(gene rnai variation)]
	    );
		
		my $objects_ar = $ontology_wm_objects{$ontology};
		my %wm_urls;
		foreach my $object (@{$objects_ar}){
			my $wga_url = ${$wm_object_ontology_urls_hr}{$ontology}{$object};
			$wga_url =~ s/\$\$\$\$/$id/;
			$wm_urls{$object} = $wga_url;
		}
		
		return %wm_urls;
}


sub filter_sections {
	my($results_hash_ref,$sections2filter_array_ref,$query) = @_;
	my %return_hash;

	foreach my $result_key (keys %{$results_hash_ref}){
		
		my $filtered_line = "";
		my $term_lines = ${$results_hash_ref}{$result_key};
		my @term_lines = split(/\n/,$term_lines);
		
		foreach my $term_line (@term_lines){	
			#print "\n\ncheck\:$term_line";
			my $checked_line = check_section($sections2filter_array_ref,$query,$term_line);
			#print "\nchecked_line\:$checked_line";
			$filtered_line = $filtered_line.$checked_line."\n";
		}
		$return_hash{$result_key} = $filtered_line;
	}
	return %return_hash;
}

sub check_section {
	my ($sections_array_ref,$query,$line) = @_;
	
	#$line =~ s/\<.*\>//g;
	## split line
	my %sections;
	($sections{'i'},$sections{'t'},$sections{'d'},$sections{'s'},$sections{'n'},$sections{'a'}) = split /\|/,$line;
	
	$sections{'n'} =~ s/\_/ /g;
	
	my $return_data = 0;
	#print "$query\n";
	foreach my $check_section (@{$sections_array_ref}){
		
		# print "$check_section => $sections{$check_section}\n";
		if($sections{$check_section} =~ m/$query/i){   #i			
			$return_data = $line;
		}
		else{
			next;
		}
	}
	return $return_data;
}

sub ontology_survey {
	my %search_results;
	my ($ontology,$data_file_name) = @_;
	my $search_data = `grep \'\|$ontology\|\' \./$data_file_name`;
	$search_results{$ontology} = $search_data;
	return %search_results;
	
}

sub print_search_form {
    
    my $cgi = shift @_;
    
    print $cgi->startform(-method=>'GET', 
			  -action=>'search');   

    print "<br><hr><br>Search for term, phrase, or term ID that \&nbsp\;\&nbsp;";
    my %string_choices = (#'before'=>'Starts with', 
			  #'after'=>'Followed by', 
			  'middle'=>'Contains',
			  'stand_alone'=>'Stands Alone'
			  );

    print $cgi->popup_menu(-name=>'string_modifications', 
			   -values=>[
				     #'before',
				     #'after',
				     'middle',
				     'stand_alone'], 
			   -default=>'middle', 
			   -labels=>\%string_choices);
 
    
    print "<br><br>\n";

    print $cgi->textfield(-name=>'query', 
			  -size=>50, 
			  -maxlength=>80);
    
    print "<br><br>In the following ontologies\:<br><br>\n";

    my %ontologies = ('biological_process'=>'GO: Biological Process',
                      'cellular_component'=>'GO: Cellular Component',
                      'molecular_function'=>'GO: Molecular Function',
		      'anatomy'=>'Anatomy',
		      'phenotype'=>'Phenotype'
		      );

    print $cgi->scrolling_list(-name=>'ontologies', 
			       -values=>['biological_process','cellular_component','molecular_function','anatomy','phenotype'], 
			       -default=>['biological_process','cellular_component','molecular_function'], 
			       -multiple=>'true', -labels=>\%ontologies);
	print "<br><br>";

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


 my %filter_choices = ('d'=>'definition',
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

    print "<br><br>\n";

    print $cgi->submit('Submit');
    print "\&nbsp\;\&nbsp\;";
    print $cgi->defaults('  Reset  ');

	print $cgi->endform;
}

sub run_search {

    my %search_results;
    my ($data_file_name, $query,$ontology_list,$annotations_only,$string_modification) = @_;
    my $search_data;
	
	#$data_file_name = "/usr/local/wormbase/databases/WS205/ontology/search_data.txt";
	
    my @ontologies = split '&',$ontology_list;
    sort @ontologies;
	#print "$data_file_name<br>";
    if ($annotations_only == 1) {
    
		if ($string_modification eq 'stand_alone'){
	    	$search_data = `grep -iw \'$query\' \.\/$data_file_name \| grep \-v \'\|0\'`;
		}
		else{
	    
	    $search_data = `grep -i \'$query\' \.\/$data_file_name \| grep \-v \'\|0\'`;
		}
    }
    else {

		if ($string_modification eq 'stand_alone'){
	  		$search_data = `grep -iw \'$query\' \.\/$data_file_name`;
		}
		else{
	    	$search_data = `grep -i \'$query\' \.\/$data_file_name`;
		}
   	}

	if(!($query=~ /WBbt/ || $query=~ /WBPhenotype/ || $query=~ /GO:/ )) {
	
	    $search_data =~ s/$query/\<font color\=\'red\'\>$query\<\/font\>/g;
	}
    

    
    my @search_data_lines = split '\n', $search_data;
   
    foreach my $ontology (@ontologies){
        my $ontology_specific_line = '';
        foreach my $search_data_line (@search_data_lines){
            my @split_data = split(/\|/, $search_data_line);
            if($ontology eq $split_data[3]){
                $ontology_specific_line = $ontology_specific_line."$search_data_line\n";
            }
            else {
                next;
            }
        }
        if ($ontology_specific_line =~ m/\|/){
            $search_results{$ontology} = $ontology_specific_line;
        }
        else
        {
            $search_results{$ontology} = 0;
        }
    }
    return %search_results;
}

sub check_for_results {

    my $search_results_hash_ref;
    my $key;
    my $data;
    my $results_returned_flag = 0;
	my $break_out = 0;	

    ($search_results_hash_ref) = @_; 


    foreach $key (keys %{$search_results_hash_ref}){
    	if($break_out) {
    		last;
    	}
    	else {
    		my $aspects = $search_results_hash_ref->{$key};
    	   	foreach my $aspect (keys %$aspects) {
   
        		$data = $search_results_hash_ref->{$key}->{$aspect};
        	
        		if($data =~ m/\|/) { ### 
					$results_returned_flag = 1;
					$break_out = 1;
					last;
				}
				else {
					next;
				}
   			}
    	}
    	
        

    return $results_returned_flag;
	}
}
sub print_ontology_search_results {

	my $query = param('query');
    my $search_results_hash_ref;
    my $key;
    my $data;
    my $sort_results_by;

    ($search_results_hash_ref,$sort_results_by) = @_;

    my %ontology_names = ('biological_process', 'GO Biological Process',
		       'cellular_component', 'GO Cellular Component',
		       'molecular_function', 'GO Molecular Function',
		       'anatomy', 'Anatomy Ontology',
		       'phenotype', 'Phenotype Ontology'
    );

	my %aspects = ('phenotype' => {
									'pheno2gene_names' => "Associated Genes",
									'pheno2gene_names_not' =>  'Genes NOT associated',
									'pheno2rnais_not' => 'RNAis NOT associated',
									'pheno2vars_not' => 'Variants NOT associated',
									'pheno2xgenes' =>  'Associated Transgenes',
									'pheno2rnais' => 'Associated RNAis',
									'pheno2vars' => 'Associated Variants',
									'string' => 'Contains query in various info'
									},
									
				'biological_process' => {
									'bp2gene_name' => 'Associated Genes',
									'string' => 'Contains query in various info'
									},
		       'cellular_component' => {
		       						'cc2gene_name' => 'Associated Genes',
		       						'string' => 'Contains query in various info'
		       						},
		       'molecular_function'=>{
		       						'mf2gene_name' => 'Associated Genes',
		       						'string' => 'Contains query in various info'
		       						},
		       'anatomy'=>{
		       						'anatomy2gene_names' => 'Associated Genes via Expression Pattern',
		       						'string' => 'Contains query in various info'
		       }
			);	


    my @ontology_names = sort {lc($a) cmp lc($b)} keys %ontology_names;

    my %ontology_directory = ('biological_process', 'ontology/gene',
                       'cellular_component', 'ontology/gene',
                       'molecular_function', 'ontology/gene',
                       'anatomy', 'ontology/anatomy',
                       'phenotype', 'misc/phenotype'
			  );
			
			my %association_urls = ('biological_process', '/db/ontology/gene?name=$$$$#asc',
			                   'cellular_component', '/db/ontology/gene?name=$$$$#asc',
			                   'molecular_function', '/db/ontology/gene?name=$$$$#asc',
			                   'anatomy', '/db/ontology/anatomy?name=$$$$#asc',
			                   'phenotype', '/db/misc/phenotype?name=$$$$#asc'
				);

			my $server = '/'; ## kludge for localhost:9006

### wormmart links for gene data
	my %wm_gene_annotation_urls; ### vestigial declaration
			
	my %wm_object_ontology_urls;
	
	$wm_object_ontology_urls{'biological_process'}{'gene'} =  $server.'biomart/martview?VIRTUALSCHEMANAME=default&ATTRIBUTES=wormbase_gene.default.attributes.gene|wormbase_gene.default.attributes.public_name|wormbase_go_term.default.attributes.go_term|wormbase_go_term.default.attributes.term&FILTERS=wormbase_go_term.default.filters.go_term_ancestor."$$$$"';

	$wm_object_ontology_urls{'cellular_component'}{'gene'} = $server.'biomart/martview?VIRTUALSCHEMANAME=default&ATTRIBUTES=wormbase_gene.default.attributes.gene|wormbase_gene.default.attributes.public_name|wormbase_go_term.default.attributes.go_term|wormbase_go_term.default.attributes.term&FILTERS=wormbase_go_term.default.filters.go_term_ancestor."$$$$"';

	$wm_object_ontology_urls{'molecular_function'}{'gene'} = $server.'biomart/martview?VIRTUALSCHEMANAME=default&ATTRIBUTES=wormbase_gene.default.attributes.gene|wormbase_gene.default.attributes.public_name|wormbase_go_term.default.attributes.go_term|wormbase_go_term.default.attributes.term&FILTERS=wormbase_go_term.default.filters.go_term_ancestor."$$$$"';

	$wm_object_ontology_urls{'anatomy'}{'gene'} = $server.'biomart/martview?VIRTUALSCHEMANAME=default&ATTRIBUTES=wormbase_expr_pattern.default.attributes.gene|wormbase_expr_pattern.default.attributes.gene_public_name|wormbase_anatomy_term.default.attributes.anatomy_term|wormbase_anatomy_term.default.attributes.term_anatomy_name&FILTERS=wormbase_anatomy_term.default.filters.anatomy_term."$$$$"',

	$wm_object_ontology_urls{'phenotype'}{'gene'} =
$server.'biomart/martview?VIRTUALSCHEMANAME=default&ATTRIBUTES=wormbase_gene.default.attributes.gene|wormbase_gene.default.attributes.public_name|wormbase_phenotype.default.attributes.phenotype|wormbase_phenotype.default.attributes.name_primaryname_phenotypename&FILTERS=wormbase_gene.default.filters.rnai_observed_count."only"|wormbase_phenotype.default.filters.phenotype."$$$$"';
	
	$wm_object_ontology_urls{'anatomy'}{'expr_pattern'} =
	
$server.'biomart/martview?VIRTUALSCHEMANAME=default&ATTRIBUTES=wormbase_expr_pattern.default.attributes.expr_pattern|wormbase_expr_pattern.default.attributes.gene|wormbase_expr_pattern.default.attributes.gene_public_name|wormbase_anatomy_term.default.attributes.anatomy_term|wormbase_anatomy_term.default.attributes.term_anatomy_name&FILTERS=wormbase_anatomy_term.default.filters.anatomy_term."$$$$"';

	$wm_object_ontology_urls{'phenotype'}{'rnai'} = $server.'biomart/martview?VIRTUALSCHEMANAME=default&ATTRIBUTES=wormbase_rnai.default.attributes.rnai|wormbase_rnai.default.attributes.gene|wormbase_phenotype.default.attributes.phenotype|wormbase_phenotype.default.attributes.name_primaryname_phenotypename&FILTERS=wormbase_phenotype.default.filters.phenotype."$$$$"';
	
	$wm_object_ontology_urls{'phenotype'}{'variation'} = $server.'biomart/martview?VIRTUALSCHEMANAME=default&ATTRIBUTES=wormbase_variation.default.attributes.variation|wormbase_phenotype.default.attributes.phenotype|wormbase_phenotype.default.attributes.name_primaryname_phenotypename&FILTERS=wormbase_variation.default.filters.species_selection."Caenorhabditis elegans"|wormbase_phenotype.default.filters.phenotype."$$$$"';
	
	

	print "<div align=right><b>NB: * $query \(also\) found in synonym\(s\)\<\/b></div><br\>";
    ## Start table
    StartDataTable;

    ## loop through ontology data hash
    #foreach $key (keys %{$search_results_hash_ref}){
    
    foreach $key (@ontology_names){
    	
    	my $aspects = $search_results_hash_ref->{$key} ;    
		foreach my $aspect (keys %$aspects) {
			#print "$aspect<br>";
			#next unless ($aspect=~ m/string/);
			
			my %terms;
			my %defs;
			my %annotation_counts;
			my @sorted_ids;
			
			$data = $search_results_hash_ref->{$key}->{$aspect};
			
			#print "$data<br>";
			
			if($data =~ m/\|/){  ## data available
				## start row for ontology
				StartSection($ontology_names{$key} . ":<br>" . $aspects{$key}{$aspect});
				my @data = split (/\n/,$data);
		
				foreach my $data_line (@data){
						if($data_line =~ 'OBSOLETE') {
							next;
						}
						else{
							my ($id,$term,$definition,$ontology,$synonyms,$annotation_count) = split (/\|/,$data_line);
					$term =~ s/\_/ /g;
					if($synonyms =~ m/$query/){
						$term = "$term"."\*";
					}
					$terms{$id} = $term;
					$defs{$id} = $definition;
					$annotation_counts{$id} = $annotation_count;
						}
					}
		
				if ($sort_results_by eq 'annotation_count'){		
				@sorted_ids = reverse sort { $annotation_counts{$a} <=> $annotation_counts{$b} } keys %annotation_counts; 
				}
				else{
				@sorted_ids = sort { lc($terms{$a}) cmp lc($terms{$b}) } keys %terms;
				}
		##
				print start_table({border => 0,width=> '100%'});
				my $term_width = '20%';
				my $def_width = '50%';
				my $annotation_count_width = '10%';
				my $wm_link_width = '20%';
		
				print TR({},
					 th({-align=>'left',-width=>$term_width,-class=>'databody'},'Term'),
					 th({-align=>'left',-width=>$def_width,-class=>'databody'},'Definition'),
					 th({-align=>'center',-width=>$annotation_count_width,-class=>'databody'},'Annotations'),
					 th({-align=>'center',-width=>$wm_link_width,-class=>'databody'},'WormMart data')
					 );
		
				foreach my $sorted_id (@sorted_ids){
				
				my $anchor = a({-href=>"/db/$ontology_directory{$key}\?name=$sorted_id"},$terms{$sorted_id});
		
				my $association_url = &association_links($sorted_id,$key,$annotation_counts{$sorted_id},\%association_urls);
				my %wm_urls = &wormmart_links($sorted_id,$key,\%wm_object_ontology_urls);
				my @wm_links;
				# my $wm_url;
				my $association_anchor;
				my $wm_anchor;
				if($association_url){
					$association_anchor = a({-href=>$association_url},$annotation_counts{$sorted_id});
					foreach my $object (keys %wm_urls){
						
						$wm_anchor = a({-href=>$wm_urls{$object}},$object);
						push @wm_links, $wm_anchor;
					}
				}
				else {
					$association_anchor = $annotation_counts{$sorted_id};
					@wm_links = ('');
				}
				
				my $wm_link_line = join " | ", @wm_links;
				
				print TR({},
					 td({-align=>'left',-width=>$term_width,-class=>'databody'},$anchor),
					 td({-align=>'left',-width=>$def_width,-class=>'databody'},$defs{$sorted_id}),
					 td({-align=>'center',-width=>$annotation_count_width,-class=>'databody'},$association_anchor),
					 td({-align=>'center',-width=>$wm_link_width,-class=>'databody'},$wm_link_line)
					 );
		# 
				}
			} # end if($data =~ m/\|/){
			else {
				next; ## skip creation of row
			} # end else
			print end_section;    
			
			}
	}
    
	

    
    
    ## end table
EndDataTable;

} # end sub print_ontology_search_results

sub run_annotation_search {

	my $query = shift @_;
	my $filename = shift @_;	
	
	
	my $datafile = $data_directory . $filename;
	my $full_search_data = $data_directory . "search_data.txt";
	
	my $search_results = `grep \'$query\' $datafile`;
	
	my @search_results = split /\n/,$search_results;
	
	my @object_id_search_results;
	
	foreach my $search_result (@search_results) {
		
			my ($object_id,$discard) = split "=>", $search_result;
			push @object_id_search_results, $object_id;
	}
	
	my $object2term_search_results = "";
    
    foreach my $obj_id (@object_id_search_results) {
    
    	my $term_data = `grep \^$obj_id \.\/$full_search_data`;
    	$object2term_search_results.= "$term_data\n";
    	
    }
	
	
	return $object2term_search_results;

}  ### end run annotation search



sub run_annotation_searches {

my @ontologies = shift @_;
my $query = shift @_;

my %data_files = ('phenotype' => {
									'pheno2gene_names' => 'pheno2gene_names.txt',
									'pheno2gene_names_not' =>  'pheno2gene_names_not.txt',
									'pheno2rnais_not' => 'pheno2rnais_not.txt',
									'pheno2vars_not' => 'pheno2vars_not.txt',
									'pheno2xgenes' =>  'pheno2xgenes.txt',
									'pheno2rnais' => 'pheno2rnais.txt',
									'pheno2vars' => 'pheno2vars.txt'
								},				
								
			'biological_process' => {
									'bp2gene_name' => 'go_bp_id2gene_id.txt',
									'string' => 'Contains query in various info'
									},
		       'cellular_component' => {
		       						'cc2gene_name' => 'go_cc_id2gene_id.txt',
		       						'string' => 'Contains query in various info'
		       						},
		       'molecular_function'=>{
		       						'mf2gene_name' => 'go_mf_id2gene_id.txt',
		       						'string' => 'Contains query in various info'
		       						},
									
					'anatomy'	=> {
									'anatomy2gene_names' => 'ao_2gene_via_ep.txt'
									}
					);									
									
									
					





foreach my $ontology (@ontologies) {

	my $pheno_data = $data_files{$ontology};
	
	foreach my $pheno_relation (keys %$pheno_data) {
		
		$search_results_hash{$ontology}{$pheno_relation} = run_annotation_search($query,$data_files{$ontology}{$pheno_relation});
	
	}

}

}
