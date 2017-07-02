#!/usr/bin/env perl

use strict;
use lib("./lib");
use feature qw(say);
use YAML;
use Badger;
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
	my $frames = Badger->split_frames(img=>$img,width=>$opt{width});
	my $count = 0;
	foreach my $frame (@$frames) {
		$frame->Write(sprintf($opt{out},++$count));
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
