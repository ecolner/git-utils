#!/usr/bin/perl -w
 use CPAN;
 use strict;
 use warnings;
 
 CPAN::install("IO::CaptureOutput");
 eval "use IO::CaptureOutput";

# MAIN
my $new_branch;
my $batch_mode = 0;

foreach my $arg (@ARGV) {
    if ($arg eq "--batch-mode") {
        $batch_mode = 1;
    } else {
        $new_branch = $arg;
    }
}

if ($batch_mode && !$new_branch) {
    print STDOUT "ERROR: Cannot continue.  The name of your new branch is required in batch mode.\n";
    abort ();
}

my $current_branch = run ("git rev-parse --abbrev-ref HEAD");
chomp ($current_branch);

if (!$batch_mode) {
    print STDOUT "\nCreating new branch from $current_branch.  Continue? [y]: ";
    my $continue = <>;
    chomp ($continue);
    if ($continue ne ""    &&
        $continue ne "y"   &&
        $continue ne "Y"   &&
        $continue ne "yes" &&
        $continue ne "YES") {
        abort ();
    }
    print STDOUT "\n";
}

print STDOUT "Stash changes to $current_branch...\n";
run ("git stash");

print STDOUT "Pull latest from $current_branch...\n";
run ("git pull origin $current_branch");

my $storyId = "";
if (!$batch_mode) {
    print STDOUT "\n";
    my $is_valid_branchname = 0;
    do {
        print STDOUT "Name of the new branch: ";
        $new_branch = <>;
        chomp($new_branch);
        $new_branch =~ s/\s/_/g;
        my @groups = $new_branch =~ /((US|DE|TA)\d+)([^\d].+)*/i;
	if (scalar(@groups) != 0) {
	    $storyId = $groups[0];
            $is_valid_branchname = 1;
            print STDOUT "\n";
        } else {
            print STDERR "Branch name invalid. Pattern: ((US|DE|TA)\\d+)([^\\d].+)*\n";
        }
    } while (!$is_valid_branchname);
} else {
    $new_branch =~ s/\s/_/g;
    my @groups = $new_branch =~ /((US|DE|TA)\d+)([^\d].+)*/i;
    if (scalar(@groups) != 0) {
        $storyId = $groups[0];
    } else {
        $storyId = $new_branch;
    }
}

# create local branch
print STDOUT "Create branch $new_branch...\n";
my $create_branch_result = run ("git branch $new_branch", "--continue-on-error");
if (index ($create_branch_result, "already exists") != -1) {
    print STDERR "SKIPPED: A branch named '$new_branch' already exists.\n";
    abort ();
}

print STDOUT "Checkout $new_branch...\n\n";
run ("git checkout $new_branch");

# allow future Git commands to authenticate using credentials stored in memory
run ("git config credential.helper cache");

foreach my $dir (<*>) {
    if (-d $dir) {
        print STDOUT "Updating $dir/pom.xml\n";
        # update child poms with <US1234>-SNAPSHOT
        run ("mvn versions:set -DnewVersion=$storyId-SNAPSHOT -DprocessParent=false -f $dir");
        # removes pom.xml.versionsBackup
        run ("mvn versions:commit -f $dir");
    }
}
if (!$batch_mode) {
    for my $dir (<*>) {
        if (-d $dir) {
            my $packaging = run ("mvn org.apache.maven.plugins:maven-help-plugin:2.1.1:evaluate -Dexpression=project.packaging -f $dir");
            $packaging =~ s/(\[INFO\]|\[WARNING\]|\[ERROR\]|Download)[^\n]+//g;
            if (index ($packaging, "jar") != -1) {
                print STDOUT "Building $dir jar...\n";
    	        run ("mvn clean install -DskipTests=true -q -f $dir");
            }
        }
    }
}
run ("git commit -am Snapshotted");
print STDOUT "\n\t----------------------------------------\n";
print STDOUT "\n\tProject branch POM at $storyId-SNAPSHOT \n";
print STDOUT "\n\t----------------------------------------\n";

my $push_remote = "y";
if (!$batch_mode) {
    print STDOUT "\nPush $new_branch branch to remote repo now? [y]: ";
    $push_remote = <>;
    chomp($push_remote);
}
print STDOUT "\n";
if ($push_remote eq ""    ||
    $push_remote eq "y"   ||
    $push_remote eq "Y"   ||
    $push_remote eq "yes" ||
    $push_remote eq "YES") {
   print STDOUT "Pushing $new_branch...\n";
   run ("git push origin $new_branch");
}

if ($batch_mode) {
    run ("git checkout $current_branch");
    run ("git stash pop");
} else {
    $current_branch = run ("git rev-parse --abbrev-ref HEAD");
    chomp ($current_branch);
    print STDOUT "You are currently on $current_branch";
    done ();
}

# SUBS
sub run {
   if (scalar (@_) == 2 && $_[1] eq "-p") {
      print STDOUT "$_[0]\n";
   }
   my @args = split (" ", "$_[0]");
   my ( $stdout, $stderr, $success, $exit_code ) = IO::CaptureOutput::capture_exec(@args);
   if ($exit_code != 0) {
      if (scalar (@_) < 2 || $_[1] ne "--continue-on-error") {
         die "ERROR: run (\"@args\") failed: $stderr";
      } else {
         return $stderr;
      }
   }
   chomp($stdout);
   if (scalar (@_) == 2 && $_[1] eq "-p") {
      print STDOUT "$stdout\n";
   }
   return $stdout;
}

sub done {
   print STDOUT "\n\nDone.  Goodbye!\n";
   exit;
}

sub abort {
   print STDOUT "\n\nAborted.  Goodbye!\n";
   exit (1);
}
