#!/usr/bin/perl
#
# Vyatta Clone Helper: Clear NIC hw-id [on boot]
#
use strict;
use POSIX qw(strftime);
use File::Copy;
use lib "/opt/vyatta/share/perl5/";
use XorpConfigParser;

use constant TRUE	=> 1;
use constant FALSE	=> 0;
use constant REMAP	=> 1;
use constant CLEAR      => 2;

my $config_file 	= "/opt/vyatta/etc/config/config.boot";
$config_file            = $ARGV[0] if defined($ARGV[0]);
my $backup_config_file  = $config_file . ".clear-nic-hw-id." . strftime("%Y%m%d%H%M%S",localtime) . "." . int(rand(10000));

my $xcp 		= new XorpConfigParser();
$xcp->parse($config_file);

my @if_names		= ();
my %if_presense_state 	= ();
my %if_config_state	= ();
my $present_if_number	= 0;

#
# Step 1: Collect information about [ethernet] interfaces
#
my $root_node 	= $xcp->get_node(['interfaces']);
my $nodes 	= $root_node->{'children'};
foreach my $node (@$nodes) {
  if ($node->{'name'} =~ m/^ethernet eth[0-9]{1,}$/) {
    my $if_name 			= $node->{'name'}; $if_name =~ s/^ethernet //;
    @if_names 				= (@if_names, $if_name);
    $if_presense_state{$if_name} 	= FALSE;
    $if_config_state{$if_name}   	= FALSE;
    if (`/sbin/ip link show $if_name 2>/dev/null`) {
      $if_presense_state{$if_name} = TRUE;
      $present_if_number++;
    }
    my $child_nodes 			= $node->{'children'};
    foreach my $child_node (@$child_nodes) {
      if ($child_node->{'name'} !~ m/^hw-id .*/) {
        $if_config_state{$if_name} = TRUE;
        last;
      }
    }
  }
}

#
# Step 2: Examine collected information and abort script execution if needed
#
my $mode_of_operation	= REMAP; # Yeap, default mode is remap
my $new_if_number 	= scalar(@if_names);
my $old_if_number       = $new_if_number;
if (($new_if_number == $present_if_number) or ($present_if_number == 0)) { $mode_of_operation = CLEAR; } # All interfaces present, no remap needed, we just clear hw-id from every [ethernet] interface
if (($new_if_number % 2 != 0) and ($mode_of_operation == REMAP)) { die("Odd interface number: $new_if_number\n"); }
# Additional sanity check for remap mode
if ($mode_of_operation == REMAP) {
  $old_if_number = $new_if_number / 2;
  my $if_c 	 = 1;
  foreach my $if_name (@if_names) {
    if ($if_c <= $old_if_number) {
      if ($if_presense_state{$if_name} == FALSE) { } else { die("Old interface present: $if_name\n"); }
    } else {
      if (($if_presense_state{$if_name} == TRUE) && ($if_config_state{$if_name} == FALSE)) { } else { die("New interface absent or configured: $if_name\n"); }
    }
    $if_c++;
  }
}

#
# Step 3: Perform actual remap/clear
#
my $if_c = 1;
foreach my $if_name (@if_names) {
  if ($if_c <= $old_if_number) { # For these interfaces we just clear hw-id
    my $node 		= $xcp->get_node(['interfaces', 'ethernet ' . $if_name]);
    my $child_nodes 	= $node->{'children'};
    my $hw_id 		= '';
    foreach my $child_node (@$child_nodes) {
      if ($child_node->{'name'} =~ /hw-id .*/) {
        $hw_id = $child_node->{'name'};
        last;
      }
    }
    $xcp->delete_child($node->{'children'}, $hw_id);
    } else { # Delete excess interfaces (NB! In clear mode we never get here!)
      my $node 		= $xcp->get_node(['interfaces']);
      my $sub_node 	= $xcp->get_node(['interfaces', 'ethernet ' . $if_name]);
      $xcp->delete_child($node->{'children'}, 'ethernet ' . $if_name);
    }
  $if_c++;
}

# Backup original config file
copy($config_file, $backup_config_file) or die("Can't copy(backup) $config_file to $backup_config_file: $!\n");
# Overwrite original config file
open(my $config, '>', $config_file) or die ("Can't open $config_file: $!");
select $config;
$xcp->output(0);
select STDOUT;
close $config;
# Bye Bye Kansas!
exit(0);
