#!/usr/bin/env perl

use strict;
use feature qw(say);
use YAML;
use Image::Magick;
use Data::Dumper;
use Getopt::Long;

my %opt;
GetOptions(\%opt,"join","split","gif",'out=s',"width=i");
$opt{input} = [@ARGV];

die "Usage: $0 --out <file> --join||split||gif [--nosort] <files>" if (!$opt{out} || !scalar(@{$opt{input}}));

if ($opt{split} && $opt{out}!~/%(?:\d{1,})?d/) {
	die "split: out should be sprintf-conpatible. Ex: filename-%02.png";
}

my $img = Image::Magick->new();

my @files;
if ($opt{nosort}) {
	@files = @{$opt{input}};
} else {
 	@files = sort {($a=~/(\d+)/)[0] <=> ($b=~/(\d+)/)[0] } @{$opt{input}};
}

if ($opt{split}) {
	$img->ReadImage($files[0]);
	my $frames = split_frames(img=>$img,width=>$opt{width});
	my $count = 0;
	foreach my $frame (@$frames) {
		$frame->Write(sprintf($opt{out},++$count));
	}
} elsif ($opt{gif}) {
	
	my $output = Image::Magick->new();
	my @imglist;
	
	if ($#files==0) {
		my $tmp = Image::Magick->new();
		$tmp->Read($files[0]);
		@imglist  = @{split_frames(img=>$tmp)};
	} else {
		foreach my $file (@files) {
			my $tmp = Image::Magick->new();
			$tmp->Read($file);
			push(@imglist,$tmp);
		}
	}
	#$output->Set(size=>join("x",$imglist[0]->Get("width","height")));
	#$output->Read("xc:transparent");

	foreach my $img (@imglist) {
		my $tmp = Image::Magick->new();
		$tmp->Set(size=>join("x",$imglist[0]->Get("width","height")));
		$tmp->Read("xc:transparent");
		$tmp->Composite(image=>$img,x=>0,y=>0,gravity=>"Northwest");
		$tmp->Set(delay=>0.10);

		push(@$output,$tmp);
	}

	$output->Animate(delay=>0.10,magick=>"gif");
	if ($opt{out}) {
		$output->Write($opt{out});
	}

} elsif ($opt{join}) {

	my $first = Image::Magick->new();
	$first->Read(shift @files);


	my $frames = scalar(@files);
	my ($width,$height) = $first->Get("width","height");
	my $sprite = Image::Magick->new();

	$sprite->Set(size=>join("x",($width*($frames+1))+$frames,$height));
	$sprite->Read("xc:transparent");
	$sprite->Composite(image=>$first,x=>0,y=>0,gravity=>"Northwest");


	# I hate this, but otherwise alpa weirdness occurs
	my $line = Image::Magick->new();
	$line->Set(size=>"1x$height");
	$line->Read("xc:#B0FADEE5");
	$sprite->Composite(image=>$line,x=>$width,y=>0,gravity=>"Northwest");

	for (my $i=1;$i<=$frames;$i++) {
		my $ti = Image::Magick->new();
		$ti->Read($files[$i-1]);
		my $xp = ($i*$width);
		$sprite->Composite(image=>$ti,x=>$xp+$i,y=>0,gravity=>"Northwest");
		#$sprite->Draw(primitive=>"line",fill=>"#000000",points=>"$xp,0,$xp,$height");
	}
	
	$sprite->Write($opt{out});
	
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
			die "Unable to find registration mark 0xDACACA on sprite $opt{file}";
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
