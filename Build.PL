use strict;
use warnings FATAL => 'all';
use Module::Build;



my $builder = Module::Build->new(
	module_name    => 'BadgerBadgerGoatse',
   	license        => 'perl',
   	dist_author    => ['Fatty Crabcakes'],
   	needs_compiler => 1,
   	configure_requires => {
   		'Module::Build'      => '0.3603',
   	},
	requires=>{
		YAML=>0,
        'FFmpeg::Command'=>0,
        'Term::ReadKey'=>0,  
        'Term::ProgressBar'=>0,
        'Image::Magick'=>0,
	},
	dist_version=>"6.6.6",
	dist_abstract=>"The Opposite of Concrete",
);
$builder->create_build_script;

