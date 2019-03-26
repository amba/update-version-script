#!/usr/bin/env perl
use 5.020;
use warnings;
use strict;
use experimental 'signatures';
use JSON::XS;
use File::Slurper 'read_binary';
use File::Find;
use autodie qw/:all/;
use Getopt::Long;

verbose_system(qw/perl Makefile.PL/);

my $meta_json = decode_json(read_binary('MYMETA.json'));

my $new_version;
my $dry_run;
my $print_help;
my $changes_ok;

GetOptions(
    "version|v=s" => \$new_version,
    "dry-run|d"   => \$dry_run,
    "help|h"      => \$print_help,
    "changes-ok" => \$changes_ok,
    )
    or die "GetOptions";

if ($print_help) {
    print <<"EOF";
update-version [OPTIONS]

Options:
  -v, --version=VERSION             Set new version to VERSION. Default is
                                    to increment the last version.
  -d, --dry-run                     Do nothing. Only print status messages.
  -h, --help                        Print this help.
      --changes-ok
EOF
    exit;
}

if (not defined $changes_ok) {
    die "did you update the CHANGES file? if yes, set --changes-ok";
}

if ($dry_run) {
    say "Doing dry run";
}

my $version = $meta_json->{version};

if ($version !~ /^(?<major>[0-9])\.(?<minor>[0-9]{2})$/) {
    die "version $version is invalid";
}


my $major = $+{major};
my $minor = $+{minor};

printf("current version number: %d.%02d\n", $major, $minor);

if (not defined $new_version) {
    # increment version
    if ($minor == 99) {
        $minor = 0;
        ++$major;
    }
    else {
        ++$minor;
    }

    $new_version = sprintf("%d.%02d", $major, $minor);
}


say "new version number: $new_version";

# Replace 'our $VERSION = ...' in .pm files

for my $module (find_modules()) {
    my $source = read_binary($module);
    $source =~ s/^our \$VERSION = \K'$version'/'${new_version}'/m;
    write_file($module, $source);
}


# Git tag & commit
verbose_system('git', 'commit', '-am', "update version $version -> $new_version");
verbose_system('git', 'tag', '-a', "v$new_version", '-m', "version $new_version");

verbose_system(qw/git push/);
verbose_system(qw/git push --tags/);

# Rerun Makefile.PL to get the new version
verbose_system(qw/perl Makefile.PL/);



sub write_file ($filename, $content) {
    say "updating file $filename";
    if (not $dry_run) {
        open my $fh, ">", $filename;
        print {$fh} $content;
        close $fh;
    }
}

sub find_modules {
    my @files;
    File::Find::find(
    {
        wanted => sub { -f $_ && /\.pm$/ and push @files, $_ },
        no_chdir => 1
    },
    'lib'
        );
    say "modules: @files";
    return @files;
}


sub verbose_system(@command) {
    say "running command: @command";
    if (not $dry_run) {
        system(@command);
    }
}
