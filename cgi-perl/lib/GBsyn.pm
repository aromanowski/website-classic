package GBsyn;

# temporary package awaits completion of gbrowse re-architecture

# a package of shared drawing and HTML rendering methods
# for gbrowse and related applications

# $Id: GBsyn.pm,v 1.1.1.1 2010-01-25 15:36:06 tharris Exp $

use strict;

use lib '/home/smckay/lib/stable2';

use Bio::Graphics::Browser;
use Bio::Graphics::Browser::Util;
use Bio::Root::RootI;
use CGI qw/:standard escape/;
use CGI::Toggle;
use CGI::Carp 'fatalsToBrowser';
use GD;
use Text::Shellwords;
use vars qw/$VERSION @ISA/;
@ISA = ('Bio::Graphics::Browser');

use Data::Dumper;

$VERSION = 0.01;

use constant DEFAULT_FINE_ZOOM => '20%';
use constant BUTTONSDIR        => '/gbrowse/images/buttons';
use constant OVERVIEW_RATIO    => 0.9;
use constant DEBUG             => 0;
use constant RULER_INTERVALS   => 50;

sub new {
  my $class = shift;
  my $self = {};
  return bless $self;
}

sub current_config {
  die "current_config not implemented";
}


*segment = \&current_segment;

sub current_segment {
  my ( $self, $segment ) = @_;
  $self->{current_segment} = $segment if $segment;
  $self->{current_segment} ||= $self->{segment};
  return $self->{current_segment};
}

sub get_source {
  my $self = shift;
  my $source;
  my $new_source = param('source') || param('src') || path_info();
  $new_source =~ s!^/+!!;
  $new_source =~ s!/+$!!;
  # gbrowse_syn expects a list
  if ( wantarray ) {
    my $old_source = cookie('sbrowse_source')
	unless $new_source && param('.cgifields');
    $source = $new_source || $old_source;
    $source ||= $self->source;
    
    # the default, whatever it is    $self->source($source);
    return ( $source, $old_source );
  } 
  # otherwise just the source
  else {
    $self->source($new_source) if defined $new_source;
    return $new_source;
  }
}

# species-specific landmark examples
sub show_examples {
  my $self     = shift;
  my $params   = join ';', '', @_;
  $params ||= '';
  my $examples = $self->setting('examples') or return;
  my @examples = shellwords($examples);
  my $source   = $self->source || $self->get_source;
  my @urls = map { a( { -href => "?name=" . escape($_) . $params }, $_ ) } @examples;
  return b( $self->tr('Examples') ) . ': ' . join( ', ', @urls ) . ". ";
}

sub toggle {
  my $self = shift;
  my ($state,$title,@contents) = @_;
  toggle_section( {on=>$state},
                        "${title}_panel",
                        b($title),
		  @contents);
}

sub source_menu {
  my $self         = shift;
  my @sources      = $self->sources;
  my $show_sources = $self->setting('show sources');
  $show_sources ||= 1;

  # default to true  
  my $sources = $show_sources && @sources > 1;
  my $popup = popup_menu(
			 -name     => 'source',
			 -values   => \@sources,
			 -labels   => { map { $_ => $self->description($_) } $self->sources },
			 -default  => $self->source,
			 -onChange => 'document.mainform.submit()'
			 );
  return b( $self->tr('DATA_SOURCE') ) . br
      . ( $sources ? $popup : $self->description( $self->source ) );
}

sub slidertable {
  my $self       = shift;
  my $small_pan  = shift;    
  my $buttons    = $self->setting('buttons') || BUTTONSDIR;
  my $segment    = $self->current_segment or fatal_error("No segment defined");
  my $span       = $small_pan ? int $segment->length/2 : $segment->length;
  my $half_title = $self->unit_label( int $span / 2 );
  my $full_title = $self->unit_label($span);
  my $half       = int $span / 2;
  my $full       = $span;
  my $fine_zoom  = $self->get_zoomincrement();
  Delete($_) foreach qw(ref start stop);
  my @lines;
  push @lines,
  hidden( -name => 'start', -value => $segment->start, -override => 1 );
  push @lines,
  hidden( -name => 'stop', -value => $segment->end, -override => 1 );
  push @lines,
  hidden( -name => 'ref', -value => $segment->seq_id, -override => 1 );
  push @lines, (
		image_button(
			     -src    => "$buttons/green_l2.gif",
			     -name   => "left $full",
			     -border => 0,
			     -title  => "left $full_title"
			     ),
		image_button(
			     -src    => "$buttons/green_l1.gif",
			     -name   => "left $half",
			     -border => 0,
			     -title  => "left $half_title"
			     ),
		'&nbsp;',
		image_button(
			     -src    => "$buttons/minus.gif",
			     -name   => "zoom out $fine_zoom",
			     -border => 0,
			     -title  => "zoom out $fine_zoom"
			     ),
		'&nbsp;', $self->zoomBar, '&nbsp;',
		image_button(
			     -src    => "$buttons/plus.gif",
			     -name   => "zoom in $fine_zoom",
			     -border => 0,
			     -title  => "zoom in $fine_zoom"
			     ),
		'&nbsp;',
		image_button(
			     -src    => "$buttons/green_r1.gif",
			     -name   => "right $half",
			     -border => 0,
			     -title  => "right $half_title"
			     ),
		image_button(
			     -src    => "$buttons/green_r2.gif",
			     -name   => "right $full",
			     -border => 0,
			     -title  => "right $full_title"
			     ),
		);
  return join( '', @lines );
}

sub unit_label {
  my ( $self, $value ) = @_;
  my $unit    = $self->setting('units')        || 'bp';
  my $divider = $self->setting('unit_divider') || 1;
  $value /= $divider;
  my $abs = abs($value);
  my $label;
        $label = $abs >= 1e9 ? sprintf( "%.4g G%s", $value / 1e9, $unit )
      : $abs >= 1e6  ? sprintf( "%.4g M%s", $value / 1e6, $unit )
      : $abs >= 1e3  ? sprintf( "%.4g k%s", $value / 1e3, $unit )
      : $abs >= 1    ? sprintf( "%.4g %s",  $value,       $unit )
      : $abs >= 1e-2 ? sprintf( "%.4g c%s", $value * 100, $unit )
      : $abs >= 1e-3 ? sprintf( "%.4g m%s", $value * 1e3, $unit )
      : $abs >= 1e-6 ? sprintf( "%.4g u%s", $value * 1e6, $unit )
      : $abs >= 1e-9 ? sprintf( "%.4g n%s", $value * 1e9, $unit )
      : sprintf( "%.4g p%s", $value * 1e12, $unit );
  if (wantarray) {
    return split ' ', $label;
  }
  else {
    return $label;
  }
}

sub get_zoomincrement {
  my $self = shift;
  my $zoom = $self->setting('fine zoom') || DEFAULT_FINE_ZOOM;
  $zoom;
}

sub zoomBar {
  my $self    = shift;
  my $segment = $self->current_segment;
  my ($show)  = $self->tr('Show');
  my %seen;
  my @ranges = grep { !$seen{$_}++ } sort { $b <=> $a } ($segment->length, $self->get_ranges());
  my %labels = map { $_ => $show . ' ' . $self->unit_label($_) } @ranges;
  return popup_menu(
    -class    => 'searchtitle',
    -name     => 'span',
    -values   => \@ranges,
    -labels   => \%labels,
    -default  => $segment->length,
    -force    => 1,
    -onChange => 'document.mainform.submit()',
  );
}

sub page_settings {
  my $self   = shift;
  my $source = $self->get_source;
  my $session
      = Bio::Graphics::Browser::PageSettings->new( $self, param('id') );
  $source ||= $session->source;
  redirect_legacy_url($source);

  # may cause a redirect and exit!!!  
  my $old_source    = $session->source($source);
  $self->source($source);

  # do not change the page settings when the user is changing from one
  # database source to another
  my $settings = $self->get_settings($session);
  $self->adjust_settings($settings);
  return wantarray ? ( $settings, $session ) : $settings;
}



sub get_settings {
  my ( $self, $session ) = @_;
  my $hash = $session->page_settings;
  delete $hash->{flip};

  # obnoxious for this to persist
  $self->default_settings($hash) if param('reset') or !%$hash;
  $hash->{id} = $session->id;
  $hash;
}

sub default_settings {
  my ( $self, $settings ) = @_;
  warn "Setting default settings" if DEBUG;
  $settings ||= {};
  %$settings = ();
  @$settings{ 'name', 'ref', 'start', 'stop', 'flip', 'version' }
      = ( '', '', '', '', '', 100 );
  $settings->{width}       = $self->setting('default width') || $self->width;
  $settings->{source}      = $self->source;
  $settings->{region_size} = $self->setting('region segment');
  $settings->{v}           = $VERSION;
  $settings->{stp}         = 1;
  $settings->{ins}         = 1;
  $settings->{head}        = 1;
  $settings->{ks}          = 'between';
  $settings->{grid}        = 1;
  $settings->{sk} = $self->setting("default varying") ? "unsorted" : "sorted";
  $self->set_default_tracks($settings);
}

sub set_default_tracks {
  my ( $self, $settings ) = @_;
  my @labels = $self->labels;
  $settings->{tracks} = \@labels;
  warn "order = @labels" if DEBUG;
  foreach (@labels) {
    $settings->{features}{$_} = { visible => 0, options => 0, limit => 0 };
  }
  foreach ( $self->default_labels ) {
    $settings->{features}{$_}{visible} = 1;
  }
}

sub adjust_settings {
  my ( $self, $settings ) = @_;
  $settings->{grid} = 1 unless exists $settings->{grid};

  # to upgrade from older settings  
  if (param('width') || param('label')) {
    # just looking to see if the settings form was submitted
    my @selected = $self->split_labels( param('label') );
    $settings->{features}{$_}{visible} = 0
	foreach keys %{ $settings->{features} };
    $settings->{features}{$_}{visible} = 1 foreach @selected;
    $settings->{flip} = param('flip');
    $settings->{grid} = param('grid');
  }
  if ( my @selected = $self->split_labels( param('enable') ) ) {
    $settings->{features}{$_}{visible} = 1 foreach @selected;
  }
  if ( my @selected = $self->split_labels( param('disable') ) ) {
    $settings->{features}{$_}{visible} = 0 foreach @selected;
  }
  $settings->{width} = param('width') if param('width');
  my $divider = $self->setting('unit_divider') || 1;
  
  # Update coordinates.
  local $^W = 0; # kill uninitialized variable warning
  $settings->{ref}   = param('ref');
  $settings->{start} = param('start')
      if defined param('start') && param('start') =~ /^[\d-]+/;
  $settings->{stop} = param('stop')
      if defined param('stop') && param('stop') =~ /^[\d-]+/;
  $settings->{stop} = param('end')
      if defined param('end') && param('end') =~ /^[\d-]+/;
  $settings->{version} ||= param('version') || '';
  if (
      ( request_method() eq 'GET' && param('ref') )
      || ( param('span')
	   && $divider * $settings->{stop} - $divider * $settings->{start} + 1
	   != param('span') )
      || grep {/left|right|zoom|nav|regionview\.[xy]|overview\.[xy]/} param()
      ) {
    $self->zoomnav($settings);
    $settings->{name} = "$settings->{ref}:$settings->{start}..$settings->{stop}";
    param( name => $settings->{name} );
  }
  
  foreach (qw(name source plugin stp ins head ks sk version)) {
    $settings->{$_} = param($_) if defined param($_);
  }
  
  $settings->{name} =~ s/^\s+//;

  # strip leading  
  $settings->{name} =~ s/\s+$//; # and trailing whitespace
  if (my @features = shellwords(param('h_feat'))) {
    $settings->{h_feat} = {};
    for my $hilight (@features) {
      last if $hilight eq '_clear_';
      my ( $featname, $color ) = split '@', $hilight;
      $settings->{h_feat}{$featname} = $color || 'yellow';
    }
  }
  if ( my @regions = shellwords( param('h_region') ) ) {
    $settings->{h_region} = [];
    foreach (@regions) {
      last if $_ eq '_clear_';
      $_ = "$settings->{ref}:$_" if /^\d+/;

      # add reference if not there
      push @{
	$settings->{h_region};
      }, $_;
    }
  }
  if ( $self->setting('region segment') ) {
    $settings->{region_size} = param('region_size')
        if defined param('region_size');
    $settings->{region_size} = $self->setting('region segment')
        unless defined $settings->{region_size};
  }
  else {
    delete $settings->{region_size};
  }
  
  if ( my @external = param('eurl') ) {
    my %external = map { $_ => 1 } @external;
    foreach (@external) {
      warn "eurl = $_" if $self->setting('DEBUG_EXTERNAL');
      next             if exists $settings->{features}{$_};
      $settings->{features}{$_} = { visible => 1, options => 0, limit => 0 };
      push @{ $settings->{tracks} }, $_;
    } 
    # remove any URLs that aren't on the list
    foreach (keys %{$settings->{features}}) {      next unless /^(http|ftp):/;
						   delete $settings->{features}{$_} unless exists $external{$_};
						 }
  } # the "q" request overrides name, ref, and h_feat
  if (my @q = param('q')) {
    delete $settings->{$_} foreach qw(name ref h_feat h_region);
    $settings->{q} = [ map { split /[+-]/ } @q ];
  }
  
  if ( param('revert') ) {
    warn "resetting defaults..." if DEBUG;
    $self->set_default_tracks($settings);
  }
  elsif ( param('reset') ) {
    %$settings = ();
    
    #    Delete_all();
    $self->default_settings($settings);
  }
  elsif ( param( $self->tr('Adjust_Order') )
	  && !param( $self->tr('Cancel') ) ) {
    $self->adjust_track_options($settings);
    $self->adjust_track_order($settings);
  }
}

sub split_labels {
  my $self = shift;
  map { /^(http|ftp|das)/ ? $_ : split /[+-]/ } @_;
}

sub click_bar {
  my $self  = shift;
  my $width = $self->width;
  my @rgb   = $_[0] ? @_ : qw/255 255 255/;
  @rgb == 3 or fatal_error("usage: \$browser->click_bar(\$width,\$R,\$G,\$B)");
  my $gd = GD::Image->new( $width, 20 );
  my $bg = $gd->colorAllocate(@rgb);
  $gd->fill( 1, 1, $gd );
  my $image = $self->generate_image($gd);
}


#sub image_link {
#  my ( $self, $settings ) = @_;
#  return "?help=link_image;
#  flip=" . ( $settings->{flip} || 0 );
#}

sub zoomnav {
  my ( $self, $settings ) = @_;
  return unless $settings->{ref};
  my $start   = $settings->{start};
  my $stop    = $settings->{stop};
  my $span    = $stop - $start + 1;
  my $divisor = $self->setting( general => 'unit_divider' ) || 1;
  warn "before adjusting, start = $start, stop = $stop, span=$span" if DEBUG;
  my $flip = $settings->{flip} ? -1 : 1;

  # get zoom parameters
  my $selected_span  = param('span');
  my ($zoom) = grep {/^zoom (out|in) \S+/} param();
  my ($nav)  = grep {/^(left|right) \S+/} param();
  my $overview_x      = param('overview.x');
  my $regionview_x    = param('regionview.x');
  my $regionview_size = $settings->{region_size};
  my $seg_min         = param('seg_min');
  my $seg_max         = param('seg_max');
  my $segment_length  = $seg_max - $seg_min + 1
      if defined $seg_min && defined $seg_max;
  my $zoomlevel = $self->unit_to_value($1)
      if $zoom && $zoom =~ /((?:out|in) .+)\.[xy]/;
  my $navlevel = $self->unit_to_value($1)
      if $nav && $nav =~ /((?:left|right) .+)/;

  if ( defined $zoomlevel ) {
    warn "zoom = $zoom, zoomlevel = $zoomlevel" if DEBUG;
    my $center = int( $span / 2 ) + $start;
    my $range = int( $span * ( 1 - $zoomlevel ) / 2 );
    $range = 1 if $range < 1;
    ( $start, $stop ) = ( $center - $range, $center + $range - 1 );
  }
  elsif ( defined $navlevel ) {
    $start += $flip * $navlevel;
    $stop  += $flip * $navlevel;
  }
  elsif ( defined $overview_x && defined $segment_length ) {
    my @overview_tracks = grep { $settings->{features}{$_}{visible} }
        $self->config->overview_tracks;
    my ( $padl, $padr ) = $self->overview_pad( \@overview_tracks );
    $settings->{width} ||= 800;
    my $overview_width = ( $settings->{width} * OVERVIEW_RATIO );

    # adjust for padding in pre 1.6 versions of bioperl
    $overview_width -= ($padl+$padr) unless Bio::Graphics::Panel->can('auto_pad');
    my $click_position = $seg_min + $segment_length * ( $overview_x - $padl )
        / $overview_width;
    $span = $self->setting('DEFAULT_SEGMENT')
        if $span > $self->setting('MAX_SEGMENT');
    $start = int( $click_position - $span / 2 );
    $stop  = $start + $span - 1;
  }
  elsif ( defined $regionview_x ) {
    my ( $regionview_start, $regionview_end )
        = get_regionview_seg( $settings, $start, $stop );
    my @regionview_tracks = grep { $settings->{features}{$_}{visible} }
        $self->self->regionview_tracks;
    my ( $padl, $padr ) = $self->overview_pad( \@regionview_tracks );
    my $regionview_width
        = ( $settings->{width} * OVERVIEW_RATIO );

    # adjust for padding in pre 1.6 versions of bioperl
    $regionview_width -= ($padl+$padr) unless Bio::Graphics::Panel->can('auto_pad');
    my $click_position
        = $regionview_size * ( $regionview_x - $padl ) / $regionview_width;
    $span = $self->setting('DEFAULT_SEGMENT')
        if $span > $self->setting('MAX_SEGMENT');
    $start = int( $click_position - $span / 2 + $regionview_start );
    $stop  = $start + $span - 1;
  }
  elsif ($selected_span) {
    warn "selected_span = $selected_span" if DEBUG;
    my $center = int( ( $span / 2 ) ) + $start;
    my $range  = int( ($selected_span) / 2 );
    $start = $center - $range;
    $stop  = $start + $selected_span - 1;
  }
  warn
      "after adjusting for navlevel, start = $start, stop = $stop, span=$span"
      if DEBUG;

  # to prevent from going off left end
  if (defined $seg_min && $start < $seg_min) {
    warn "adjusting left because $start < $seg_min" if DEBUG;
    ( $start, $stop ) = ( $seg_min, $seg_min + $stop - $start );
  } 
  # to prevent from going off right end
  if (defined $seg_max && $stop > $seg_max) {
    warn "adjusting right because $stop > $seg_max" if DEBUG;
    ( $start, $stop ) = ( $seg_max - ( $stop - $start ), $seg_max );
  } 
  # to prevent divide-by-zero errors when zoomed down to a region < 2 bp  
  $stop  = $start + ($span > 4 ? $span - 1 : 4) if $stop <= $start+2;
  warn "start = $start, stop = $stop\n" if DEBUG;
  $divisor = 1 if $divisor =~ /[^0-9]/;;
  $settings->{start} = $start / $divisor;
  $settings->{stop}  = $stop / $divisor;
}

sub unit_to_value {
  my ( $self, $string ) = @_;
  my $sign = $string =~ /out|left/ ? '-' : '+';
  my ( $value, $units ) = $string =~ /([\d.]+) ?(\S+)/;

  return unless defined $value;

  $value /= 100 if $units eq '%';

  # percentage;
  $value *= 1000 if $units =~ /kb/i;
  $value *= 1e6  if $units =~ /mb/i;
  $value *= 1e9  if $units =~ /gb/i;
  return "$sign$value";
}

sub make_overview {
  my ( $self, $settings, $feature_files ) = @_;
  my $segment       = $self->current_segment || return;
  my $whole_segment = $self->whole_segment;

  $self->width( $settings->{width} * OVERVIEW_RATIO );

  my ( $image, $length )
      = $self->overview( $whole_segment, $segment, $settings->{features},
			 $feature_files )
      or return;

  # restore the original width!
  my $restored_width = $self->width/OVERVIEW_RATIO;
  $self->width($restored_width);

  my ( $width, $height ) = $image->getBounds;
  my $url = $self->generate_image($image);

  return image_button(
		      -name   => 'overview',
		      -src    => $url,
		      -width  => $width,
		      -height => $height,
		      -border => 0,
		      -align  => 'middle'
		      )
      . hidden(
	       -name     => 'seg_min',
	       -value    => $whole_segment->start,
	       -override => 1
	       )
      . hidden(
	       -name     => 'seg_max',
	       -value    => $whole_segment->end,
	       -override => 1
	       );
}

sub overview_panel {
  my ( $self, $page_settings, $feature_files ) = @_;
  my $segment = $self->current_segment || return;
  return '' if $self->section_setting('overview') eq 'hide';

  my $image = $self->make_overview( $page_settings, $feature_files );
  return $self->toggle( 1,
		       'Overview',
		       table(
			     { -border => 0, -width => '100%', },
			     TR( { -class => 'databody' }, td( { -align => 'center' }, $image ) )
			     )
		       );
}

sub whole_segment {
  my $self = shift;
  die ('No Segment') unless $self->current_segment;
  return $self->{whole_segment} if $self->{whole_segment};
  my $segment = $self->current_segment;
  my $factory = $segment->factory;

  # the segment class has been deprecated, but we still must support it
  my $class   = eval {$segment->seq_id->class} || eval{$factory->refclass};
  ( $self->{whole_segment} ) = $factory->segment(
						 -class => $class,
						 -name  => $segment->seq_id
						 );
  $self->{whole_segment} ||= $segment;
  
  # just paranoia
  return $self->{whole_segment};
}

sub resize {
  my $self          = shift;
  my $segment       = $self->current_segment;
  my $whole_segment = $self->whole_segment;
  my $divider       = $self->setting('unit_divider') || 1;
  my $min_seg_size  = $self->setting('min segment')
      || $self->setting('MIN_SEG_SIZE');
  $min_seg_size /= $divider;

  my ( $new_start, $new_stop, $fix ) = ( $segment->start, $segment->end, 0 );

  if ( $segment->length < $min_seg_size ) {
    my $resize = $min_seg_size;
    my $middle = int( ( $segment->start + $segment->end ) / 2 );
    $new_start = $middle - int( $resize / 2 );
    $new_stop  = $middle + int( $resize / 2 );
    $fix++;
  }

  if ( $segment->start < $whole_segment->start ) {
    $new_start = $whole_segment->start;
    $fix++;
  }
  elsif ( $segment->start > $whole_segment->end ) {
    $new_start = $whole_segment->end - $min_seg_size;
    $fix++;
  }

  if ( $segment->end > $whole_segment->end ) {
    $new_stop = $whole_segment->end;
    $fix++;
  }
  elsif ( $segment->end < $whole_segment->start ) {
    $new_stop = $whole_segment->start + $min_seg_size;
    $fix++;
  }    
  # error($self->tr('Small_interval',$resize));
  # error message  return unless $fix;
  
  $new_start = $whole_segment->start if $new_start < $whole_segment->start;
  $new_stop  = $whole_segment->end   if $new_stop > $whole_segment->end;
  my $new_seg = $segment->factory->segment(
    -name     => $segment->seq_id,
    -start    => $new_start,
    -end      => $new_stop,
    -absolute => 1
  );
  $self->current_segment($new_seg);
}

sub is_search {
  my ( $self, $page_settings ) = @_;
  return 1 if param();
  return 1 if $self->setting('initial landmark') && !$page_settings->{name};
  return 1 unless $self->setting('no autosearch');
  return undef;
}

sub features2segments {
  my ( $self, $features, $db ) = @_;
  my $refclass = $self->setting('reference class') || 'Sequence';
  $db ||= open_database();
  my @segments = map {
    my $version = eval { $_->isa('Bio::SeqFeatureI') ? undef: $_->version };
    $db->segment(
      -class    => $refclass,
      -name     => $_->ref,
      -start    => $_->start,
      -stop     => $_->end,
      -absolute => 1,
      defined $version ? ( -version => $version ) : ()
        )
  } @$features;
  warn "segments = @segments\n" if DEBUG;
  \@segments;
}

sub get_features {
  my ( $self, $settings, $db ) = @_;
  $db ||= open_database();
  unless ($db) {
    fatal_error(
      "ERROR: Unable to open database",
      $self->setting('description'),
      pre($@)
    );
  }
  eval { $db->biosql->version( $settings->{version} ) };

  # if no name is specified but there is a "initial landmark" defined in the
  # config file, then we default to that.  
  $settings->{name} ||= $self->setting('initial landmark')
      if defined $self->setting('initial landmark') && !defined $settings->{q};

  my @features = $self->lookup_features_from_db( $db, $settings );

  # sort of hacky way to force keyword search on wildcards  
  if (defined $settings->{name} && $settings->{name} =~ /[*?]/ ){ 
    my $searchterm = $settings->{name};
        push @features, do_keyword_search($searchterm)
        if length $searchterm > 0;
    } 
   
  # h'mmm.  Couldn't find the feature.  See if it is in an uploaded file.
  @features    = $self->lookup_features_from_external_sources($settings,$settings->{name}, undef ) 
      unless @features;

  return \@features;
}

sub lookup_features_from_external_sources {
  my ( $self, $settings, $searchterm ) = @_;
  return unless my $uploads = $self->setting('UPLOADED_SOURCES');

  my @uploaded_files = map { $uploads->feature_file($_) }
  grep { $settings->{features}{$_}{visible} } $uploads->files;

  for my $file (@uploaded_files) {
    next unless $file->can('get_feature_by_name');
    my @features = $file->get_feature_by_name($searchterm);
    return @features if @features;
  }
  # No exact match.  Try inexact match.                                                                                                                                       
  my $max_keywords = $self->setting('keyword search max')|| $self->setting('MAX_KEYWORD_RESULTS');

  for my $file (@uploaded_files) {
    next unless $file->can('search_notes');
    my @matches = $file->search_notes( $searchterm, $max_keywords );
    return map {
      my ( $feature, $description, $score ) = @$_;
    Bio::Graphics::Feature->new(
                                  -name  => $feature->display_name,
                                  -type  => $description,
                                  -score => $score,
                                  -ref   => $feature->ref,
                                  -start => $feature->start,
                                  -end   => $feature->end
                                  )
      } @matches if @matches;
  }
  return;
}

sub lookup_features_from_db {
  my ( $self, $db, $settings ) = @_;
  my @segments;
  warn
      "lookup_features_from_db: name = $settings->{name}, ref = $settings->{ref}, start = $settings->{start}, "
      . "stop = $settings->{stop}, version = $settings->{version} db = $db"
      if DEBUG;

  my $divisor  = $self->setting( general => 'unit_divider' )     || 1;
  my $padding  = $self->setting( general => 'landmark_padding' ) || 0;
  my $too_many = $self->setting('TOO_MANY_SEGMENTS');

  if ( my $name = $settings->{name} ) {
    @segments = $self->name2segments( $name, $db, $too_many );
  }
  elsif ( ( my $names = $settings->{q} ) && ref $settings->{q} ) {
    warn "looking up by query: q = $names" if DEBUG;
    my $max = $too_many / @$names;
    @segments = map { $self->name2segments( $_, $db, $max ) } @$names;
  }
  elsif ( my $ref = $settings->{ref} ) {
    my @argv = ( -name => $ref );
    push @argv, ( -start => $settings->{start} * $divisor )
        if defined $settings->{start};
    push @argv, ( -end => $settings->{stop} * $divisor )
        if defined $settings->{stop};
    warn "looking up by @argv" if DEBUG;
    @segments = $db->segment(@argv);
  } 
  # expand by a bit if padding is requested
  # THIS CURRENTLY ISN'T WORKING PROPERLY
  if (@segments == 1 && $padding > 0 && !$settings->{name} ){ 
    $segments[0] = $segments[0]->subseq( -$padding, $segments[0]->length + $padding );
  } 
  # some segments are not going to support the absolute() method
  # if they come out of BioPerl  
  eval {$_->absolute(1)} foreach @segments;
  return unless @segments;

  # Filter out redundant segments; this can happen when the same basic feature
  # ia present under several names, such as "genes" and "frameworks"
  my %seenit;
  my $version = eval { $_->isa('Bio::SeqFeatureI') ? undef: $_->version };
  $version ||= 0;
  @segments = grep { !$seenit{ $_->seq_id, $_->start, $_->end, $version }++ }
  @segments;
  return @segments if @segments > 1;

  # this prevents any confusion over (ref,start,stop) and (name) addressing.  $settings->{ref}   = $segments[0]->seq_id;
  $settings->{start} = $segments[0]->start / $divisor;
  $settings->{stop}  = $segments[0]->end / $divisor;
 
  return $segments[0];
}

sub do_keyword_search {
  my ( $self, $searchterm, $db ) = @_;
  $db ||= open_database();

  # if they wanted something specific, don't give them non-specific results.
  return if $searchterm =~ /^[\w._-]+:/;

  # Need to untaint the searchterm.  We are very lenient about
  # what is accepted here because we wil be quote-metaing it later.
  $searchterm =~ /([\w .,~!@\#$%^&*()-+=<>?\/]+)/;
  $searchterm = $1;
  my $max_keywords = $self->setting('keyword search max')
      || $self->setting('MAX_KEYWORD_RESULTS');
  my @matches = $db->search_notes( $searchterm, $max_keywords );
  my @results;

  for my $r (@matches) {
    my ( $name, $description, $score ) = @$r;
    my ($seg) = $db->segment($name) or next;
    push @results,
    Bio::Graphics::Feature->new(
				-name    => $name,
				-class   => eval { $name->class } || undef,
				-type    => $description,
				-score   => $score,
				-ref     => $seg->abs_ref,
				-start   => $seg->abs_start,
				-end     => $seg->abs_end,
				-factory => $db
				);
  }

  return @results;
}

sub make_cookie {
  my $self = shift;
  my ( $name, $val ) = @_;
  my $cookie = cookie(
    -name  => $name,
    -value => $val
  );
  return $cookie;
}

sub make_centering_map {
  my $self   = shift;
  my ($ruler,$flip,$label,$scale_map_type)  = @_;
  my @map = $label ? ($label) : ();

  return if $ruler->[3]-$ruler->[1] == 0;

  my $segment = $self->current_segment;
  my $length = $segment->length;
  my $offset = $segment->start;
  my $end    = $segment->end;
  my $scale  = $length/($ruler->[3]-$ruler->[1]);
  my $pl     = $ruler->[-1]->panel->pad_left;
  my $ruler_intervals = RULER_INTERVALS;

  # divide into intervals
  my $portion = ($ruler->[3]-$ruler->[1])/$ruler_intervals;
  my $ref    = $ruler->[0]->seq_id;
  my $source = $self->setting('search_src');

  for my $i (0..$ruler_intervals-1) {
    my $x1 = int($portion * $i+0.5);
    my $x2 = int($portion * ($i+1)+0.5);

    my ($start,$stop);
    if ($scale_map_type eq 'centering_map') {
      # put the middle of the sequence range into the middle of the picture
      my $middle = $flip ? $end - $scale * ($x1+$x2)/2 : $offset + $scale * ($x1+$x2)/2;
      $start  = int($middle - $length/2);
      $stop   = int($start  + $length - 1);
    }
    elsif ($scale_map_type eq 'interval_map') {
      # center on the interval
      $start = int($flip ? $end - $scale * $x1 : $offset + $scale * $x1);
      $stop  = int($start + $portion * $scale);
    }

    $x1 += $pl;
    $x2 += $pl;

    my $url = "?ref=$ref;start=$start;stop=$stop;search_src=$source";
    $url .= ";flip=1" if $flip;
    
    push @map, join("\t",'ruler',$x1, $ruler->[2], $x2, $ruler->[4], 
		    href  => $url, title => 'recenter', alt   => 'recenter');
  }
  
  return $label ? \@map : @map;
}


1;
