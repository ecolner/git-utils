#!/usr/bin/perl -w
 use strict;
 use warnings;
 use CPAN;
 use Encoding;
 use File::Basename;
 CPAN::install("JSON");
 eval "use JSON";
 CPAN::install("IO::CaptureOutput");
 eval "use IO::CaptureOutput";
 
# MAIN
my $ced = dirname(__FILE__);
my $package = "NPMT";
my $iteration = "tools sprint 13.6 (08/22 - 09/04)";
my $rally_username = "your.name\@yourcompany.com";
my $rally_password = "your_secret_password";

print STDOUT "\n\n";
print STDOUT "Working on iteration: $iteration\n\n";

# parse parent branch using Rally's iteration name to XX.X_master
my $parent_branch = $iteration;
$parent_branch =~ s/[^\d+\.\d+]+//;
$parent_branch = (split(" ", $parent_branch))[0];
$parent_branch .= "_master";

# fetch current branch checked out from Git
my $current_branch = run_cmd ("git rev-parse --abbrev-ref HEAD");
chomp ($current_branch);

# compare --- they should be the same
if ($current_branch ne $parent_branch) {
   print STDOUT "'$current_branch' does not match '$parent_branch' generated from this Rally iteration\n";
   print STDOUT "Do you want to use $current_branch as the parent branch? (y/n): ";
   my $ans = <>;
   chomp ($ans);
   if (!$ans) {
       print STDOUT "ERROR: We cannot create branches.\n\n";
       print STDOUT "Please checkout $parent_branch before running again.\n";
       print STDOUT "Aborted.  Goodbye!";
       exit;
   }
}

my $url_encoded_iteration = $iteration;
$url_encoded_iteration =~ s/\s+/%20/g;
my $endpoint = "https://rally1.rallydev.com/slm/webservice/v2.0/hierarchicalrequirement.js?query=((Project.Name%20=%20\"NPMT%20Scrum%20Team\")%20and%20(Iteration.Name%20=%20\"$url_encoded_iteration\"))&fetch=true&start=1&pagesize=100";

my $response = run_cmd ("curl -u $rally_username:$rally_password $endpoint");
my %result = %{ decode_json ($response) };

if ($result{'QueryResult'}{'TotalResultCount'} == 0) {
    print STDOUT "Found 0 $package $iteration stories in DEFINED schedule state\n\n";
    print STDOUT "Goodbye!\n";
    exit;
}

my @stories = @{ $result{'QueryResult'}{'Results'} };

print STDOUT "Found $package $iteration stories in DEFINED schedule state\n\n";
my $bullet = 0;
foreach my $story (@stories) {
    if (editable ($story, $package)) {
        ++$bullet;
        my %s = %{ $story };
        binmode STDOUT, ':encoding(UTF-8)';
        print STDOUT "\t$bullet. $s{'Name'}\n";
    }
}
print STDOUT "\n\t----------------------------------------\n";
print STDOUT "\n\t$bullet stories are in 'add-branch' mode\n";
print STDOUT "\n\t----------------------------------------\n";

if ($bullet == 0) {
    print STDOUT "\nNothing to create.  Goodbye!\n";
    exit;
}

my $cont = "";
while (!$cont) {
    print STDOUT "\nAre these stories correct?  Continue (y/n): ";
    $cont = <>;
    chomp ($cont);
}
print STDOUT "\n";

if ($cont ne "y" && $cont ne "Y" && $cont ne "yes" && $cont ne "YES") {
    print STDOUT "Aborted.  Goodbye!\n";
    exit;
}

run_cmd ("git config credential.helper cache");

my $pull_current_branch = run_cmd ("git pull origin $current_branch");
if (index ($pull_current_branch, "CONFLICT") != -1) {
    print STDOUT "ERROR: Your local $current_branch has merge conflicts with remote branch\n";
    print STDOUT "\tResolve all conflicts\n";
    print STDOUT "Aborted.  Goodbye!";
    exit;
}
print STDOUT "\n";

my $session_cookie = "./rally-cookie.txt";

# request secure token to update story titles
# NOTE: using wget because of curl utf-8 encoding issues with curl ...
$response = run_cmd ("wget -O- -q --http-user=$rally_username --http-password=$rally_password --no-check-certificate --keep-session-cookies --save-cookies $session_cookie https://rally1.rallydev.com/slm/webservice/v2.0/security/authorize");
%result = %{ decode_json ($response) };
my $token = $result{'OperationResult'}{'SecurityToken'};
if (!$token) {
    print STDOUT "Couldn't fetch authorization token from Rally.  Can't continue.\n";
    print STDOUT "Aborted.  Goodbye!\n";
    exit;
}

foreach my $story (@stories) {
    if (editable ($story, $package)) {
        
        my %s = %{ $story };
        
        # [NPMT+] US1234 Super Story ====> US1234_Super_Story
        my $new_branch = $s{'Name'};
        my $offset = lastindexof ($new_branch, "]") + 1;
        if ($offset != -1) {
            $new_branch = substr($new_branch, $offset);
        }
        $new_branch =~ s/^\s+//;            # trim leading spaces
        $new_branch =~ s/[^a-zA-Z0-9\s]//g; # replace non-alphanumerics
        $new_branch =~ s/\s+|\.+/_/g;       # replace remaining spaces with underscore
        $new_branch = "$s{'FormattedID'}_$new_branch";
            
        print STDOUT "Creating branch: $new_branch\n\n";
        
        # create branch
        my $cmd = "$ced/create_branch.pl --batch-mode $new_branch";
        $response = run_cmd ($cmd, "--continue-on-error");
        print STDOUT "$response\n";
            
        my $branched_story_name = $s{'Name'};
        $branched_story_name =~ s/NPMT\+/NPMT~/g;   # replace 'NPMT+' with 'NPMT~'
        
        my $json = encode_json ({ "hierarchicalrequirement" => { "Name" => $branched_story_name }});
	$json =~ s/\"/\\"/g;  # replace " with slash quos for command
	
        my $update_url = "https://rally1.rallydev.com/slm/webservice/v2.0/hierarchicalrequirement/$s{'ObjectID'}?key=$token";

        # NOTE: using wget because of curl utf-8 encoding issues with curl ...
        $response = update_rally ("wget -O- -q --http-user=$rally_username --http-password=$rally_password --keep-session-cookies --no-check-certificate --header=\"Content-Type: text/javascript;charset=utf-8\" --load-cookies $session_cookie --post-data=\"$json\" $update_url");
                 
        %result = %{ decode_json ($response) };
        
        my @errors = @{ $result{'OperationResult'}{'Errors'} };
        foreach my $error (@errors) {
            binmode STDERR, ':encoding(UTF-8)';
            print STDERR "ERROR: $error\n";
        }
        my @warnings = @{ $result{'OperationResult'}{'Warnings'} };
        foreach my $warning (@warnings) {
            binmode STDERR, ':encoding(UTF-8)';
	    print STDERR "WARNING: $warning\n";
        }
    }
}
if (-e "$session_cookie") {
    run_cmd ("rm $session_cookie");
}

print STDOUT "\nDone.  Goodbye!\n";

# SUBS
sub editable {
    my %story = %{ $_[0] };
    my $package = $_[1];
    return ($story{'ScheduleState'} eq "Defined") &&   # is in Defined state
           ($story{'Package'} eq $package) &&          # belongs to correct package
           (index($story{'Name'}, "$package+") != -1); # is in Git 'add mode'
}

sub run_cmd {
    my $continue_on_error = 0;
    if (scalar (@_) == 2 && $_[1] eq "--continue-on-error") {
        $continue_on_error = 1;
    }
    my @args = split (" ", "$_[0]");
    my ( $stdout, $stderr, $success, $exit_code ) = IO::CaptureOutput::capture_exec(@args);
    if (!$success) {
        if (!$continue_on_error) {
            die "ERROR: run_cmd (\"@args\") failed [$exit_code]: $stderr";
        } else {
            return $stderr;
        }
    }
    return $stdout;
}

# same as run_cmd() but doesn't split on spaces due to the story name field
sub update_rally {
    my ( $stdout, $stderr, $success, $exit_code ) = IO::CaptureOutput::capture_exec(@_);
    if (!$success) {
        die "ERROR: run_cmd (\"@_\") failed [$exit_code]: $stderr";
    }
    return $stdout;
}

# UTIL
sub trim {
    chomp ($_[0]);
    return $_[0] =~ s/^\s+|\s+$//rg;
}

sub lastindexof {
    my @parts = split ($_[1], $_[0]);
    my $num_parts = scalar(@parts);
    if ($num_parts > 1) {
        # found match
        return length ($_[0]) - length ($parts[$num_parts - 1]) - 1;
    }
    return -1;
}