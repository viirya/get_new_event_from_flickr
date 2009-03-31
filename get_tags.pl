use Data::Dumper;
use Flickr::API;
use Flickr::API::Request;
use Graph;
use Graph::TransitiveClosure::Matrix;
use DateTime;
use Date::Parse;
use Benchmark;

binmode STDOUT, ':utf8';

my @photos;
my $dt_min = DateTime->new( year   => 2009,
                        month  => 2,
                        day    => 1,
                        hour   => 0,
                        minute => 0,
                        second => 0,
                        nanosecond => 0,
                        time_zone => 'Asia/Taipei',
                      );
my $dt_max = DateTime->new( year   => 2009,
                        month  => 2,
                        day    => 28,
                        hour   => 23,
                        minute => 59,
                        second => 59,
                        nanosecond => 0,
                        time_zone => 'Asia/Taipei',
                      );


my $min_taken_date = $dt_min->ymd;
my $max_taken_date = $dt_max->ymd;

my $api = new Flickr::API({'key' => ''});

foreach $page (1..20) {
  print "fetching photos of page: $page\n";

  my $request = new Flickr::API::Request({
              'method' => 'flickr.photos.search',
              'args' => {'per_page' => '250', 'accuracy ' => '15,16', 'tags ' => 'eatbrains', 'page' => $page, 'min_taken_date' => $min_taken_date, 'max_taken_date' => $max_taken_date, 'bbox ' => '-122.522278,37.675415,-65.654297,48.290990', 'extras' => 'date_upload, date_taken, geo, tags, views', 'sort ' => 'date-taken-desc'},
      });

  my $response = $api->execute_request($request);

  foreach $response_item (@{$response->{'tree'}{'children'}[1]{'children'}}) {
    if (defined $response_item->{'name'} && $response_item->{'name'} == 'photo') {
      push @photos, $response_item;
      #print Dumper($response_item);
    }
  }
}

print "There are " . $#photos . " photos.\n";

my $alpha = 1.6;
my @scale;

foreach $k (1..1) {
  push @scale, $alpha ** $k;   
}

my %tags_time_dist;
my %tags_user_dist;
my %tags_usage_times;

foreach $response_item (@photos) {
  if (defined $response_item->{'name'} && $response_item->{'name'} == 'photo') {
    my $owner = $response_item->{'attributes'}->{'owner'};
   
    $tags_string = $response_item->{'attributes'}->{'tags'};
    @tags = split(/ /, $tags_string);

    my $datetime_upload = $response_item->{'attributes'}->{'dateupload'};
      
    my $datetime_string = $response_item->{'attributes'}->{'datetaken'};
    my $datetime = str2time($datetime_string);

    if ($datetime_upload < $datetime) {
      next;
    }
 
    foreach $tag (@tags) {
      if (defined $tags_time_dist{$tag}) {
        push @{$tags_time_dist{$tag}}, $datetime;
        #push @{$tags_time_dist{$tag}}, $datetime_upload;
      }
      else {
        $tags_time_dist{$tag} = [];
        push @{$tags_time_dist{$tag}}, $datetime;
        #push @{$tags_time_dist{$tag}}, $datetime_upload;
      }

      if (defined $tags_usage_times{$tag}) {
        $tags_usage_times{$tag}++;
      }
      else {
        $tags_usage_times{$tag} = 1;
      }
 
      if (!defined $tags_user_dist{$tag}) {
        $tags_user_dist{$tag} = {};
      }
      if (!defined $tags_user_dist{$tag}->{$owner}) {
        $tags_user_dist{$tag}->{$owner} = 1;
      }

    }
  }
}

my %tags_siginicant;
my %tags_entropy;

my $tag_count = 0;
foreach $tag (keys %tags_usage_times) {
  if ($tags_usage_times{$tag} > 25) {
    print "$tag appears " . $tags_usage_times{$tag} . " times.\n";
    $tag_count++;
  }
}
print "There are $tag_count tags.\n";

#exit;

foreach $scale_value (@scale) {
  foreach $tag (keys %tags_time_dist) {
   
    #next if ($tags_usage_times{$tag} <= 10);

    my @users_of_tag = keys %{$tags_user_dist{$tag}};
    #next if ($#users_of_tag + 1 <= 1);

    my $g = Graph->new(undirected => 1);

    my @time_nodes = @{$tags_time_dist{$tag}};

    foreach $source_node (@time_nodes) {
      foreach $target_node (@time_nodes) {
        next if ($source_node == $target_node);
        if (abs($source_node - $target_node) <= $scale_value * 10) {
          $g->add_edge($source_node, $target_node);
        }
      }
    }

    my $nodes_number = $g->vertices;

    my @nodes = $g->vertices;

    my $transitivity = 0;
    my $triangles = 0;
    my $triples = 0;

    foreach $source_node (@nodes) {
      my $paths = 0;

      foreach $target_node (@nodes) {
        next if ($source_node == $target_node);

        foreach $second_target_node (@nodes) {
          next if ($source_node == $target_node);
          next if ($source_node == $second_target_node);
          next if ($target_node == $second_target_node);

          if ($g->has_cycle($source_node, $target_node, $second_target_node)) {
            $triangles++;
          }
        }

        if ($g->has_path($source_node, $target_node)) {
          $paths++;
        }
      }
      $triples += ($paths * ($paths - 1) / 2);
     
    } 

    if ($triples > 0) {
      $transitivity = $triangles / $triples;
    }

    if ($nodes_number > 0) {
      $tags_siginicant{$tag} += $transitivity;
    }

    #my $tcm = Graph::TransitiveClosure::Matrix->new($g, reflexive => 0);
    #my $transitivity = 0;

    #foreach $source_node (@nodes) {
    #  foreach $target_node (@nodes) {
    #    next if ($source_node == $target_node);
    #   
    #    if ($tcm->is_transitive($source_node, $target_node)) {
    #      $transitivity++;
    #    }
    #  }
    #}
    #if ($nodes_number > 0) {
    #  if ($transitivity == 0) {
    #    $transitivity = 1;
    #  }
    #  $transitivity = ($transitivity) / ($nodes_number * ($nodes_number - 1)) * $nodes_number;
    #  $transitivity = log($transitivity) / log(2); 
    #  $tags_siginicant{$tag} += $transitivity; # * ($#ccs);
    #}

  }
}

foreach $tag (sort {$tags_siginicant{$a} <=> $tags_siginicant{$b}} keys %tags_siginicant) {
  $probability = $tags_siginicant{$tag};
  print "$tag is an event with probability: $probability.\n";
}

print "\n\n";

print "<hr class=\"clear-contentunit\" />\n";
print "<h1 class=\"block\">Hotest events on Flickr.</h1>\n";
print "<h1></h1>\n";
print "<div class=\"column1-unit\">\n";
print "<p>\n";

foreach $tag (sort {$tags_siginicant{$a} <=> $tags_siginicant{$b}} keys %tags_siginicant) {
  $probability = $tags_siginicant{$tag};
  if ($probability >= 1) {
    my $font_size = $tags_usage_times{$tag};
    my $tag_parameter = rtrim($tag);
    my $font_percentage = 100 + log($font_size) * 20;
    my $margin = log($font_size) * 5;
    my $margin_top_bottom = $margin * 2;

    print "<a style=\"text-decoration: none;\"><font style=\"font-size:$font_percentage%;margin: $margin_top_bottom" . "px $margin" . "px $margin_top_bottom" . "px $margin" . "px\" onclick=\"selectTag('$tag_parameter');\">$tag </font></a>";
  }
}

print "</p>\n";

print "</div>\n";
print "<hr class=\"clear-contentunit\" />\n\n";

# Perl trim function to remove whitespace from the start and end of the string
sub trim($) {
	my $string = shift;
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	return $string;
}
# Left trim function to remove leading whitespace
sub ltrim($) {
	my $string = shift;
	$string =~ s/^\s+//;
	return $string;
}
# Right trim function to remove trailing whitespace
sub rtrim($) {
	my $string = shift;
	$string =~ s/\s+$//;
	return $string;
}

exit;

