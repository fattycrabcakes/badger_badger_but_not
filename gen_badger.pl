#!/usr/bin/env perl

use strict;
use lib("./lib");
use feature qw(say);
use YAML;
use Badger;
use Image::Magick;
use FFmpeg::Command;
use Data::Dumper;
use Getopt::Long;
use Term::ReadKey;
use Term::ProgressBar;


my %opt;
GetOptions(\%opt,"config=s","out=s",'overwrite','tmpdir=s');
die "Usage: $0 --config <file> --out <file> [--overwrite]" if (!-f $opt{config} || !exists $opt{out});

$opt{tmpdir}||="/tmp";

our $badger = Badger->new(config=>$opt{config});
$badger->consume(%opt);


foreach my $asset (keys %{$badger->conf("assets")}) {
	die "file fo $asset not found" if (!-f $badger->asset($asset)->{src});
}

if (-f $opt{out} && !$opt{overwrite}) {
	print STDERR "$opt{out} already exists. Overwrite? (Y/N) ";
	my $ow = lc(ReadKey(0));
	if(lc($ow) ne "y") {
		exit;
	}
}

my ($background,$sprites,$mushrooms,$snakes) = map {$badger->load_img(img=>$badger->asset($_)->{src})} qw(background badger mushroom snake);
my ($bgw,$bgh) = $background->Get("width","height");


my $rendered = {
	badgers=>render_badgers(sprites=>$sprites,bg=>$background),
	mushrooms=>render_mushrooms(sprites=>$mushrooms,bg=>$background),
	snake=>render_snake(sprites=>$snakes,bg=>$background)
};
$badger->render_final(segments=>$rendered);



sub render_badgers {
	my (%args) = @_;


	my $sprites = $args{sprites};
	my $conf = $badger->asset("badger");
	my ($sprite_width,$sprite_height) = $sprites->[0]->Get("width","height");
	
	my $total_frames = $badger->conf("fps")*$conf->{duration};

	my @timeline = @{$badger->conf("timeline")};
	my $timeline_length = scalar(@timeline);

	my $badger_every = int($total_frames/$timeline_length+1);
	my $fps_diff = $conf->{fps}/$badger->conf("fps");

	my $scale_progress = $badger->progress(name=>"Scaling Sprites",count=>$timeline_length-1);
	my $scale_i=0;

	my $sprite_scaled = {
		'1'=>$sprites,
	};
	foreach my $spr (@timeline) {
    	if (!defined $sprite_scaled->{$$spr[2]}) {
        	$sprite_scaled->{$$spr[2]} = [
            	map {$_->Resize(width=>$sprite_width*$$spr[2],height=>$sprite_height*$$spr[2]);$_} @{$sprites->Clone()},
			];
    	}
		$scale_progress->update(++$scale_i);
	}

	my $progress = $badger->progress(name=>"Rendering Badgers",count=>$total_frames-1);
	my @badgers_visible = ();
	my @files;

	for (my $i=0;$i<$total_frames;$i++) {
    	if ($i % $badger_every==0) {
        	if (scalar(@timeline)) {
            	push(@badgers_visible,shift(@timeline));
        	}
    	}
    	my $frame_to_render = int(($i*$fps_diff) % scalar(@$sprites));

		my $frame = $args{bg}->Clone();
    	foreach my $badger (reverse @badgers_visible) {
        	my $st = $sprite_scaled->{$badger->[2]}->[$frame_to_render];
        	$frame->Composite(image=>$st,gravity=>"NorthWest",x=>$badger->[0],y=>$badger->[1]);
    	}
		$badger->writefile($frame,$i);
    	$progress->update($i);
	}
	my $ret = $badger->render_video(sequence=>"badger");
}

sub render_mushrooms {
    my (%args) = @_;

	my $conf = $badger->asset("mushroom");
    my $total_frames = int($badger->conf("fps")*$conf->{duration});
    my $fps_diff = $conf->{fps}/$total_frames;
	my $sprites = $args{sprites};
    my $progress = $badger->progress(name=>"Rendering Mushrooms",count=>$total_frames-1);
	
    for (my $i=0;$i<$total_frames;$i++) {
        my $frame_to_render = int(($i*$fps_diff) % scalar(@$sprites));
		$badger->writefile($sprites->[$frame_to_render],$i);
    	$progress->update($i);
	}
	return $badger->render_video(sequence=>"mushroom");
}

sub render_snake {
	my (%args) = @_;

	my $sprites = $args{sprites};
	my $conf = $badger->asset("snake");
	my $total_frames = $badger->conf("fps")*$conf->{"duration"};
    my $fps_diff = $conf->{fps}/$badger->conf("fps");
	my $x= -$sprites->[0]->Get("width");
	my $inc = ($args{bg}->Get("Width")+$sprites->[0]->Get("width"))/$total_frames;

	my $progress = $badger->progress(name=>"Rendering snake",count=>scalar($total_frames)-1);


	for (my $i=0;$i<$total_frames;$i++) {
    	my $frame_to_render = int(($i*$fps_diff) % scalar(@$sprites));

    	my $frame = $args{bg}->Clone();
    	my $st = $sprites->[$frame_to_render];
    	$frame->Composite(
			image=>$st,compose=>"Over",gravity=>"NorthWest",
			x=>$x,y=>$conf->{y},
		);
		$badger->writefile($frame,$i);
    	$x+=$inc;
    	$progress->update($i);
	}
	return $badger->render_video(sequence=>"snake");
}

