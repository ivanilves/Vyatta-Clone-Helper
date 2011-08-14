#!/usr/bin/perl
#
# Vyatta Cloning Helper: Interface Re-Map
#
use strict;
use POSIX qw(strftime);
use File::Copy;
use lib "/opt/vyatta/share/perl5/";
use XorpConfigParser;

use constant TRUE	=> 1;
use constant FALSE	=> 0;

my $config_file 	= "/opt/vyatta/etc/config/config.boot";
$config_file            = $ARGV[0] if defined($ARGV[0]);
my $backup_config_file  = $config_file . ".interface-remap." . strftime("%Y%m%d%H%M%S",localtime) . "." . int(rand(10000));

my $xcp 		= new XorpConfigParser();
$xcp->parse($config_file);

my @if_names		= ();
my %if_presense_state 	= ();
my %if_config_state	= ();

#
# Step 1: Collect information about interfaces
#
my $root_node 	= $xcp->get_node(['interfaces']);
my $nodes 	= $root_node->{'children'};
foreach my $node (@$nodes) {
  if ($node->{'name'} =~ m/^ethernet eth[0-9]{1,}$/) {
    my $if_name 			= $node->{'name'}; $if_name =~ s/^ethernet //;
    @if_names 				= (@if_names, $if_name);
    $if_presense_state{$if_name} 	= FALSE;
    $if_config_state{$if_name}   	= FALSE;
    if (`/sbin/ifconfig $if_name 2>/dev/null`) { $if_presense_state{$if_name} = TRUE; }
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
# Step 2: Examine collected information and abort cloning if needed
#
my $new_if_number 	= length(@if_names) + 1;
if ($new_if_number % 2 != 0) { die("Odd interface number: $new_if_number\n"); }
my $old_if_number 	= $new_if_number / 2;
my $if_c		= 1;
foreach my $if_name (@if_names) {
  if ($if_c <= $old_if_number) {
    if (($if_presense_state{$if_name} == FALSE) && ($if_config_state{$if_name} == TRUE))  { } else { die("Old interface present or not configured: $if_name\n"); }
  } else {
    if (($if_presense_state{$if_name} == TRUE)  && ($if_config_state{$if_name} == FALSE)) { } else { die("New interface absent or configured: $if_name\n"); }
  }
  $if_c++;
}

#
# Step 3: Perform actual cloning
#
$if_c = 1;
foreach my $if_name (@if_names) {
  if ($if_c <= $old_if_number) {
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
  } else {
    my $node = $xcp->get_node(['interfaces']);
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
