#!/usr/bin/env perl

use strict;
use feature qw(say);
use YAML;
use Image::Magick;
use FFmpeg::Command;
use Data::Dumper;
use Getopt::Long;
use Term::ReadKey;
use Term::ProgressBar;


my %opt;

GetOptions(\%opt,"config=s","out=s","gif","scale=s",'report','overwrite');
die "Usage: $0 --config <file> --out <file> [--gif] [--overwrite] [--scale <float>]" if (!-f $opt{config} || !exists $opt{out});

my $config = YAML::LoadFile($opt{config});
my @timeline = @{$config->{timeline}};

foreach my $asset (keys %{$config->{assets}}) {
	die "$config->{assets}->{$asset} not found" if (!-f $config->{assets}->{$asset});
}

if (-f $opt{out} && !$opt{overwrite} && !$opt{report}) {
	print STDERR "$opt{out} already exists. Overwrite? (Y/N) ";
	ReadMode 1;
	my $ow = lc(ReadKey(0));
	ReadMode(1);
	if($ow ne "y") {
		exit;
	}
}

my $background = Image::Magick->new();
my $sprite = Image::Magick->new();
my $mushroom = Image::Magick->new();

my $has_gifsicle = length(qx(which gifsicle));
if (!$has_gifsicle && $opt{gif}) {
	say STDERR "\n\nYou should probably install gifsicle for optimizing the huge GIF that Imagemagick produces.";
	say STDERR "Seriously. They're giant.\n\n";
}

$background->Read(filename=>$config->{assets}->{background});
$sprite->Read($config->{assets}->{sprite});
$mushroom->Read($config->{assets}->{mushroom});

$sprite = split_frames(img=>$sprite);
$mushroom = split_frames(img=>$mushroom);

my ($sprites,$mushrooms,$timeline_length) = (scalar(@$sprite),scalar(@$mushroom),scalar(@timeline));
my ($bgw,$bgh) = $background->Get("width","height");
my ($sprite_width,$sprite_height) = $sprite->[0]->Get("width","height");

my $sprite_scaled = {'1'=>$sprite};
my $scp = Term::ProgressBar->new({term_width=>80,name=>"Scaling Sprites",count=>$timeline_length,remove=>0});
foreach my $spr (@timeline[1..$timeline_length]) {
	if (!defined $sprite_scaled->{$$spr[2]}) {
		$sprite_scaled->{$$spr[2]} = [
			map {$_->Resize(width=>$sprite_width*$$spr[2],height=>$sprite_height*$$spr[2]);$_} @{$sprite->Clone()}
		];
	}
}

#my $total_frames = $config->{badger_every}*$timeline_length;

my $bd = 4.5;
my $total_frames = $config->{fps}*$bd;
$config->{badger_every} = int($total_frames/$timeline_length);
#$total_frames += ($total_frames % $sprites);

say STDERR sprintf("\nGenerating %d frames (%d seconds)",$total_frames,$total_frames/$config->{fps});
if ($opt{report}) {
	exit;
}

my $output = Image::Magick->new();
my @cleanup = ();
my $badgers_in_play = [];


my $frame_pattern = "/tmp/frame-%04d.png";
my $current_frame=0;
my $frame_delay = int((1/$config->{fps})*100);
my $fps_diff = $config->{badgerfps}/$config->{fps};
my $bp = Term::ProgressBar->new({term_width=>80,name=>"Rendering Badgers",count=>$total_frames-1,remove=>0});


for (my $i=0;$i<$total_frames;$i++) {
	# new badger every half second

	if ($i % $config->{badger_every}==0) {
		if ($#timeline) {
			push(@$badgers_in_play,shift(@timeline));
		}
	}

	my $frame_to_render = int(($i*$fps_diff) % $sprites);
	my $frame = render_frame($background,$sprite_scaled,$badgers_in_play,$frame_to_render);

	#ImageMagick dows _not_ like it when stuff sticks over the edge
	$frame->Crop(width=>$bgw,height=>$bgh,x=>0,y=>0);

	if (!$opt{gif}) {
		my $opf = sprintf($frame_pattern,++$current_frame);
		$frame->Write($opf);
		push(@cleanup,$opf);
		#undef $frame;
	} else {
		$frame->Set(delay=>$frame_delay);
		$frame->Set(dispose=>"Background");
		push(@$output,$frame);
	} 
	$bp->update($i);
}

my $mushroom_duration = 1.5;

my $mtr = int($config->{fps}*$mushroom_duration);# $mushrooms**($mushroom_duration);
my $frame_delay = 1/($mtr);

say "Rendering $mtr mushroom frames";

my $mp = Term::ProgressBar->new({term_width=>80,name=>"Rendering Mushrooms",count=>$mtr-1,remove=>0});
my $fps_diff = 16/$mtr;

for (my $i=0;$i<$mtr;$i++) {
	 my $frame_to_render = int(($i*$fps_diff) % $mushrooms);
	if (!$opt{gif}) {
		my $opf = sprintf($frame_pattern,++$current_frame);
		$mushroom->[$frame_to_render]->Write($opf);
		push(@cleanup,$opf);
	} else {
		my $delay = 1/($mtr*2);
		my $frame = $background->Clone();

		my $m = $mushroom->[$i % $mushrooms]->Clone();
		$frame->Set(delay=>$delay);
		$frame->Set(dispose=>"Background");
		$frame->Composite(image=>$m,compose=>"Over",gravity=>"NorthWest");

		#$frame->Quantize(colors=>256,colorspace=>"RGB");
		undef $m;
		push(@$output,$frame);
	}
	$mp->update();
}


if (!$opt{gif}) {
	say STDERR "\nGenerating Video....";

	my $ff = FFmpeg::Command->new();
	$ff->input_file("/tmp/frame-%04d.png");
	$ff->output_file($opt{out});

	$ff->options(
		'-framerate'=>$config->{fps},
		'-crf' => 20,
		'-profile:v'=>'high',
		'-pix_fmt' => 'yuv420p',
		'-an',
		'-y',
	);
	$ff->exec();
	
	my $cp = Term::ProgressBar->new({term_width=>80,name=>"Cleaning Up",count=>$#cleanup-1,remove=>0});
	my $cpc = 0;
	foreach my $file (@cleanup) {
		unlink($file);
		$cp->update(++$cpc);
	}
	say "";
} else {
	if ($opt{scale}) {
		my $sp = Term::ProgressBar->new({term_width=>80,name=>"Scaling",count=>scalar(@$output)-1,remove=>0});
		my $spc=0;
		foreach my $frame (@$output) {
			$frame->Resize(width=>$bgw*$opt{scale},height=>$opt{scale}*$bgh);
			$sp->update(++$spc);
		}
	}
	say "";
	say STDERR "Writing JIF";
    $output->write($opt{out});

	if ($has_gifsicle) {
		my $tmpfile = "$opt{out}.tmp";

		my $size = (stat($opt{out}))[7];
		
		say STDERR "Optimizing....";
		rename($opt{out},$tmpfile);
		system("gifsicle $tmpfile --colors=256  --optimize=3 -o $opt{out}");
		my $reduction = $size-(stat($opt{out}))[7];
		my $reduction_scale = "K";
		if ($reduction>=2**20) {
			$reduction_scale="M";
			$reduction/=2**20;
		} else {
			$reduction/=2**10;
		}
		
		say STDERR sprintf("Reduced file by %0.2f%s",$reduction,$reduction_scale);
		unlink($tmpfile);
	}
}

sub render_frame {
	my ($bg,$sprite,$all,$current_frame) = @_;

	my $nbg = $bg->Clone();
	foreach my $badger (reverse @$all) {
		my $st = $sprite->{$badger->[2]}->[$current_frame];
		$nbg->Composite(image=>$st,compose=>"Over",gravity=>"NorthWest",x=>$badger->[0],y=>$badger->[1]);
		undef $st;
		
	}
	return $nbg;
}

sub split_frames {
    my (%opt) = @_;

    my $height = $opt{img}->Get("height");
    my $width = $opt{width};
    my $frames =0;

    if (!$width) {
        my @pixels = $opt{img}->GetPixels(width=>int($opt{img}->Get("width")/2)+16,height=>1,x=>0,y=>$height/2,map=>"RGBA");
        $width=0;
        for (my $i=0;$i<scalar(@pixels);$i+=4) {
            my $pixel = (($pixels[$i]&0xff)<<24)|(($pixels[$i+1]&0xff)<<16)|(($pixels[$i+2]&0xff<<8))|($pixels[$i+3]&0xff);
            if ($pixel==0xB0FADEE5) {
                $width=int($i/4);
                last;
            }
        }
        if ($width==0) {
            die "Unable to find registration mark 0xB0FADEE5 on sprite $opt{file}";
        }
    }

    my $frames = int($opt{img}->Get("width")/$width);
    my $ret = Image::Magick->new();
    for (my $i=0;$i<$frames;$i++) {
        my $frame = $opt{img}->Clone();
        $frame->Crop(width=>$width,height=>$height,x=>($i*$width)+$i,y=>0);
        push(@$ret,$frame);
    }
    return $ret;
}


