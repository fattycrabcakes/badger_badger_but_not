package Badger;

use strict;
use Modern::Perl;
use Image::Magick;
use FFmpeg::Command;
use Term::ProgressBar;
use YAML;
use Moo;
use Data::Dumper;

has config=>(is=>'rw');
has configuration=>(is=>'lazy');
has filemask=>(is=>'lazy');

has tempfiles=>(is=>'rw',default=>sub {[];});
has format =>(is=>'rw',default => sub {"mp4";});


sub progress {
	my ($self,%args) = @_;

	return Term::ProgressBar->new({term_width=>80,name=>$args{name},count=>$args{count},remove=>0});
}

sub render_video {
    my ($self,%args) = @_;

    say STDERR "\nRendering video for $args{sequence}";
    my $output_filename = sprintf("%s/%s.%s",$self->conf("tmpdir"),$args{sequence},$self->format);

    my $ff = FFmpeg::Command->new();
    $ff->input_file($self->filemask);
    $ff->output_file($output_filename);
    $ff->options(
        '-framerate'=>$self->conf("fps"),
        '-crf' => 20,
        '-profile:v'=>'high',
        '-pix_fmt' => 'yuv420p',
        '-an',
        '-y',
    );
    $ff->exec();

	my @cleanup = @{$self->tempfiles};

    my $cp = $self->progress(name=>"Cleaning Up",count=>scalar(@{$self->tempfiles}));
    my $cpc = 0;
    foreach my $file (@cleanup) {
        unlink($file);
        $cp->update(++$cpc);
    }
    say "";
	$self->tempfiles([]);
    return $output_filename;
}


sub render_final {
    my ($self,%args) = @_;

    say STDERR "Rendering $args{config}->{out}";

    my $cfile = sprintf("%s/concat_files.txt",$self->conf("tmpdir"));


    open(FO,">",$cfile);
    foreach my $scene (@{$self->conf("scenes")}) {
        say FO sprintf("file '%s'",concat_filename($args{segments}->{$scene})) if (-f $args{segments}->{$scene});
    }
    close(FO);

    # apparently FFMpeg::COmmand goofs up the order of args
    my $res = `ffmpeg -f concat -safe 0 -y -i $cfile -c copy $self->{configuration}->{out}`;

    #unlink($cfile);
    unless($self->conf("preserve_tempfiles")) {
        foreach my $file (values %{$args{segments}}) {
            #unlink($file);
        }
    }
}


sub load_img {
    my ($self,%opt) = @_;

    my $img = Image::Magick->new();
    $img->Read($opt{img});

    my $height = $img->Get("height");
    my $width = 0;

    if (!$width) {
        my @pixels = $img->GetPixels(width=>int($img->Get("width")/2)+16,height=>1,x=>0,y=>$height/2,map=>"RGBA");
        $width=0;
        for (my $i=0;$i<scalar(@pixels);$i+=4) {
            my $pixel = (($pixels[$i]&0xff)<<24)|(($pixels[$i+1]&0xff)<<16)|(($pixels[$i+2]&0xff<<8))|($pixels[$i+3]&0xff);
            if ($pixel==0xB0FADEE5) {
                $width=int($i/4);
                last;
            }
        }
        if ($width==0) {
            return $img;
        }
    }

    my $frames = int($img->Get("width")/$width);
    my $ret = Image::Magick->new();
    for (my $i=0;$i<$frames;$i++) {
        my $frame = $img->Clone();
        $frame->Crop(width=>$width,height=>$height,x=>($i*$width)+$i,y=>0);
        push(@$ret,$frame);
    }
    return $ret;
}

sub writefile {
	my ($self,$img,$index) = @_;

	my $filename = sprintf($self->filemask,$index);
    $img->Write($filename);
	$self->tempfile($filename);
	undef $img;
}

sub tempfile {
	my ($self,$path) = @_;

	push (@{$self->tempfiles},$path);
}

sub concat_filename {
    my ($file) = @_;

    unless ($file=~/^\//) {
        $file= substr($file,rindex($file,"/")+1);
    }
    return $file;
}

sub conf {
	my ($self,$key) = @_;

	return $self->configuration->{$key};
}

sub asset {
	my ($self,$name) = @_;

	return $self->conf("assets")->{$name};
}

sub consume {
	my ($self,%args) = @_;

	my $conf = $self->configuration;
	foreach my $k (keys %args) { $conf->{$k} = $args{$k}; }
}


sub _build_configuration {
	my ($self) = shift;
	my $conf = YAML::LoadFile($self->config);
}

sub _build_filemask {
	my ($self) = shift;

	return join("/",$self->conf("tmpdir"),"frame-%02d.png");
}


no Moo;
1;
